#!/usr/bin/env bash
# Renders the governed-teams charts and checks the claims the demo makes:
#   1. every tenant in example-tenants/ renders (Kargo and Argo CD side)
#   2. every tenant gets exactly the same prod-controls task, and every Argo CD
#      tenant exactly the same prod Stage (tenant name aside)
#   3. checkout's own steps, qa environment and smoke-test stage, and reports'
#      GitHub Actions deploys, show up as designed
#   4. platform-controls.yaml switches checks, the change gate and break glass
#      for everyone at once
#   5. every file in example-tenants/rejected/ fails for the reason in its header
#
# Usage (from anywhere):  governed-teams/tests/verify.sh
# Needs helm 3. Set HELM=/path/to/helm to use a different binary.
set -u
HELM="${HELM:-helm}"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHART="$DIR/kargo-chart"
PLATFORM="$DIR/tests/platform-values.yaml"
OUT="$(mktemp -d)"
pass=0; fail=0

ok()  { echo "  PASS  $1"; pass=$((pass+1)); }
bad() { echo "  FAIL  $1"; fail=$((fail+1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }  # description, shell test

render() { # name values-file [chart] -> $OUT/name.yaml, $OUT/name.err
  "$HELM" template "gov-$1" "${3:-$CHART}" \
    -f "$2" -f "$PLATFORM" \
    --set "application.name=gov-$1,project.name=governed-$1,project.path=governed/$1" \
    >"$OUT/$1.yaml" 2>"$OUT/$1.err"
}
render_apps() { # name values-file -> $OUT/name-apps.yaml
  "$HELM" template "gov-$1" "$DIR/project-templates" -f "$2" -f "$PLATFORM" \
    --set "application.name=gov-$1,project.name=governed-$1,project.path=governed/$1" \
    >"$OUT/$1-apps.yaml" 2>"$OUT/$1-apps.err"
}
doc() { # tenant kind name -> that document, tenant name blanked out
  awk -v kind="kind: $2" -v want="  name: $3" '
    function flush() { if (index(doc, "\n" kind "\n") && index(doc, "\n" want "\n")) printf "%s", doc; doc = "\n" }
    BEGIN { doc = "\n" }
    /^---/ { flush(); next }
    { doc = doc $0 "\n" }
    END { flush() }
  ' "$OUT/$1.yaml" | sed -e "s#gov-$1#TENANT#g" -e "s#governed/$1/#governed/TENANT/#g"
}
is_gha() { grep -q "method: github-actions" "$DIR/example-tenants/$1/platform/app-values.yaml"; }

TENANTS=""
for f in "$DIR"/example-tenants/*/platform/app-values.yaml; do
  TENANTS="$TENANTS $(basename "$(dirname "$(dirname "$f")")")"
done

echo "1. Every tenant renders"
for t in $TENANTS; do
  f="$DIR/example-tenants/$t/platform/app-values.yaml"
  if render "$t" "$f"; then ok "$t renders"; else bad "$t renders: $(cat "$OUT/$t.err")"; continue; fi
  check "$t has the prod-controls task" 'doc "$t" PromotionTask prod-controls | grep -q "release-type"'
  check "$t prod Stage is labeled tier: prod and runs prod-controls" 'doc "$t" Stage prod | grep -q "tier: prod" && doc "$t" Stage prod | grep -q "name: prod-controls"'
  if render_apps "$t" "$f"; then ok "$t Argo CD apps render"; else bad "$t Argo CD apps render: $(cat "$OUT/$t-apps.err")"; fi
done

echo "2. Prod is the same for everyone"
if [ -s "$OUT/payments.yaml" ]; then
  for t in $TENANTS; do
    [ "$t" = payments ] || [ ! -s "$OUT/$t.yaml" ] && continue
    if diff <(doc payments PromotionTask prod-controls) <(doc "$t" PromotionTask prod-controls) >"$OUT/task-$t.diff"; then
      ok "$t has the same prod-controls task as payments"
    else
      bad "$t has the same prod-controls task as payments:"; cat "$OUT/task-$t.diff"
    fi
    is_gha "$t" && continue
    if diff <(doc payments Stage prod) <(doc "$t" Stage prod) >"$OUT/prod-$t.diff"; then
      ok "$t has the same prod Stage as payments"
    else
      bad "$t has the same prod Stage as payments:"; cat "$OUT/prod-$t.diff"
    fi
  done
fi

echo "3. Example tenants work as designed"
if [ -s "$OUT/payments.yaml" ]; then
  T="$(doc payments PromotionTask prod-controls)"
  for step in release-type image-scan policy-check ci-evidence secret-scan change-approval audit-approved evidence \
              image-scan-bg break-glass-approval audit-break-glass break-glass-record audit-blocked; do
    check "prod-controls has $step" 'printf "%s" "$T" | grep -q "as: $step$"'
  done
  check "signature check is off by default" '! printf "%s" "$T" | grep -q "as: signature$"'
  check "every conditional step also requires success() (except audit-blocked)" \
    '[ "$(printf "%s" "$T" | grep "^    if:" | grep -v "failure()" | grep -vc "success()")" = 0 ]'
  check "audit-blocked records any failure or rejection" 'printf "%s" "$T" | grep -A2 "as: audit-blocked" | grep -q "if: \"\${{ failure() }}\""'
  check "only releasers and break glass answer the release-type form" 'printf "%s" "$T" | grep -A8 "as: release-type" | grep -q "value: sedemo-breakglass"'
  check "recorded checks leave out the policy check when there are no manifests" 'printf "%s" "$T" | grep -q "prod-checks-passed: \"\${{ vars.manifests != '"'"''"'"' ?"'
  check "nothing is written to the prod branch before prod-controls" \
    'doc payments Stage prod | awk "/name: prod-controls/{c=1} /uses: git-push/{print c; exit}" | grep -q 1'
  check "payments has a break-glass role" 'doc payments ServiceAccount break-glass | grep -q sedemo-breakglass'
  check "payments has no tenant steps" '! grep -q "tenant steps" "$OUT/payments.yaml"'
  check "payments staging still waits for dev" 'doc payments Stage staging | grep -A2 "stages:" | grep -q -- "- dev"'
  check "payments prod namespace is labeled tier: prod" 'grep -A12 "namespace: gov-payments-prod" "$OUT/payments-apps.yaml" | grep -q "tier: prod"'
  check "staging skips the PR review when the promotion changes nothing" 'doc payments Stage staging | grep -A3 "as: wait-for-pr" | grep -qF "?.pr != nil"'
  check "prod skips the merge when the promotion changes nothing" 'doc payments Stage prod | grep -A3 "uses: git-merge-pr" | grep -qF "?.pr != nil"'
fi
if [ -s "$OUT/checkout.yaml" ]; then
  for s in manifest-check second-scan check-staging "name: smoke-test"; do
    check "checkout has $s" 'grep -q "$s" "$OUT/checkout.yaml"'
  done
  check "checkout qa deploys its own Argo CD app" 'doc checkout Stage qa | grep -q "name: TENANT-qa"'
  check "checkout qa runs its smoke test" 'doc checkout Stage qa | grep -q "qa-smoke-test"'
  check "checkout staging waits for qa" 'doc checkout Stage staging | grep -A2 "stages:" | grep -q -- "- qa"'
  check "checkout staging no longer takes Freight from dev" '! doc checkout Stage staging | grep -A2 "stages:" | grep -q -- "- dev"'
  check "checkout qa auto-promotes" 'grep -A1 "tenant stage with autoPromote" "$OUT/checkout.yaml" | grep -q "stageSelector"'
  check "project-templates creates gov-checkout-qa" 'grep -q "name: '"'"'gov-checkout-qa'"'"'" "$OUT/checkout-apps.yaml"'
  check "no Argo CD app for the smoke-test stage" '! grep -q "gov-checkout-smoke-test" "$OUT/checkout-apps.yaml"'
fi
if [ -s "$OUT/reports.yaml" ]; then
  for st in dev staging prod; do
    check "reports $st deploys with its GitHub Actions workflow" 'doc reports Stage $st | grep -q "uses: gha-dispatch-workflow"'
  done
  check "reports never renders manifests or touches Argo CD" '! grep -qE "uses: (argocd-update|helm-template)" "$OUT/reports.yaml"'
  check "reports prod runs prod-controls with no manifests (no policy check)" 'doc reports Stage prod | grep -A1 "name: manifests" | grep -q "value: \"\""'
  check "reports gets no Argo CD environment apps" '! grep -q "name: '"'"'gov-reports-dev'"'"'" "$OUT/reports-apps.yaml"'
fi

echo "4. platform-controls.yaml switches everyone at once"
ALT="$OUT/alt-chart"
cp -R "$CHART" "$ALT"
sed -e 's/^changeGate: approval/changeGate: servicenow/' \
    -e 's/^  incident: audit/  incident: servicenow/' \
    -e '/^  signature:/,/^    enabled:/s/enabled: false/enabled: true/' \
    "$CHART/platform-controls.yaml" > "$ALT/platform-controls.yaml"
if render alt "$DIR/example-tenants/payments/platform/app-values.yaml" "$ALT"; then
  A="$(doc alt PromotionTask prod-controls)"
  check "servicenow change gate raises a change request" 'printf "%s" "$A" | grep -q "as: change-request$"'
  check "servicenow change gate waits for Implement" 'printf "%s" "$A" | grep -q "condition: state=-1"'
  check "break glass raises a ServiceNow incident" 'printf "%s" "$A" | grep -q "tableName: incident"'
  check "signature check turns on" 'printf "%s" "$A" | grep -q "as: signature$"'
else
  bad "renders with servicenow and signature on: $(cat "$OUT/alt.err")"
fi
sed -e '/^breakGlass:/,/^  enabled:/s/enabled: true/enabled: false/' "$CHART/platform-controls.yaml" > "$ALT/platform-controls.yaml"
if render alt "$DIR/example-tenants/payments/platform/app-values.yaml" "$ALT"; then
  A="$(doc alt PromotionTask prod-controls)"
  check "break glass off: no release-type form and no emergency path" '! printf "%s" "$A" | grep -qE "as: (release-type|break-glass-approval)$"'
  check "break glass off: no break-glass role" '! grep -q "name: break-glass$" "$OUT/alt.yaml"'
else
  bad "renders with break glass off: $(cat "$OUT/alt.err")"
fi

echo "5. Rejected tenants"
for f in "$DIR"/example-tenants/rejected/*.yaml; do
  n="$(basename "$f" .yaml)"
  rule="$(sed -n 's/^# REJECTED (\([a-z-]*\)).*/\1/p' "$f" | head -1)"
  if render "rej-$n" "$f"; then
    bad "$n should be rejected by [$rule] but rendered"
  elif grep -q "GUARDRAIL \[$rule\]" "$OUT/rej-$n.err"; then
    ok "$n rejected by [$rule]"
  else
    bad "$n rejected for the wrong reason: $(cat "$OUT/rej-$n.err")"
  fi
done
if render_apps rej-skip-staging "$DIR/example-tenants/rejected/skip-staging.yaml"; then
  check "a rejected file that turns staging off doesn't remove the staging app" \
    'grep -q "name: '"'"'gov-rej-skip-staging-staging'"'"'" "$OUT/rej-skip-staging-apps.yaml"'
else
  bad "Argo CD apps render for skip-staging: $(cat "$OUT/rej-skip-staging-apps.err")"
fi

echo
echo "$pass passed, $fail failed. Rendered output: $OUT"
[ "$fail" -eq 0 ]
