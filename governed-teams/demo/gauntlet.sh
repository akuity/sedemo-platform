#!/usr/bin/env bash
# The circumvention gauntlet (demo scene 4), as a script.
#
#   governed-teams/demo/gauntlet.sh                  # config attempts (4a-4b4, 4g): no cluster needed
#   governed-teams/demo/gauntlet.sh --live <context> # also try to write to a prod namespace with
#                                                    # kubectl server-side dry run (4f, 4g)
#
# Config attempts render each file in example-tenants/rejected/ the way Argo
# CD would and show the guardrail that stops it. Live attempts use
# `kubectl apply --dry-run=server`: the request goes through admission
# (Kyverno) but nothing is created, so it's safe to run against the real
# cluster. Needs helm 3 (and kubectl for --live). Set HELM to override.
set -u
HELM="${HELM:-helm}"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
live=""; ctx=""
if [ "${1:-}" = "--live" ]; then live=1; ctx="${2:?usage: gauntlet.sh --live <kube-context> [prod-namespace]}"; fi
ns="${3:-gov-payments-prod}"
blocked=0; open=0

scene() { # file -> gauntlet scene number
  case "$(basename "$1" .yaml)" in
    remove-prod-check|add-prod-step) echo 4a ;;
    git-push-in-staging) echo 4b ;;
    unapproved-registry) echo 4b2 ;;
    skip-staging) echo 4b3 ;;
    side-stage-to-prod|stage-feeds-prod) echo 4b4 ;;
    unapproved-deploy-repo) echo 4g ;;
    *) echo "  " ;;
  esac
}

echo "Config attempts: a tenant changes its app-values.yaml (or opens a PR that a teammate approves)"
echo
# Scene order first, then any other rejected examples.
ORDER="remove-prod-check add-prod-step git-push-in-staging unapproved-registry skip-staging side-stage-to-prod stage-feeds-prod unapproved-deploy-repo borrow-platform-secret staging-after-loop"
FILES=""
for n in $ORDER; do [ -f "$DIR/example-tenants/rejected/$n.yaml" ] && FILES="$FILES $DIR/example-tenants/rejected/$n.yaml"; done
for f in "$DIR"/example-tenants/rejected/*.yaml; do
  case " $ORDER " in *" $(basename "$f" .yaml) "*) ;; *) FILES="$FILES $f" ;; esac
done
for f in $FILES; do
  what="$(sed -n 's/^# REJECTED ([a-z-]*): //p' "$f" | head -1 | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"
  printf '%-4s %s\n' "$(scene "$f")" "$what"
  if "$HELM" template gov-demo "$DIR/kargo-chart" -f "$f" -f "$DIR/tests/platform-values.yaml" \
       --set "application.name=gov-demo,project.name=governed-demo,project.path=governed/demo" >/dev/null 2>/tmp/gauntlet.$$; then
    echo "     NOT BLOCKED"; open=$((open+1))
  else
    echo "     Blocked: $(sed 's/.*GUARDRAIL/GUARDRAIL/' /tmp/gauntlet.$$ | head -1)"; blocked=$((blocked+1))
  fi
  echo
done
rm -f /tmp/gauntlet.$$

cat <<'TXT'
4c   Create or edit a prod Stage in the Kargo UI or CLI
     Show live: log in as a tenant developer (group sedemo-team) and try. Kargo
     RBAC denies it: the developer role can only promote to dev and the team's
     own stages, and has no write access to Stages or PromotionTasks.

4d   Approve their own prod promotion
     Show live: start a prod promotion, then try to approve it as the tenant
     developer. wait-for-approval only accepts the approvers group.

4e   Push straight to the prod branch (rendered/gov-<tenant>/prod)
     Show live, only once github/prod-branch-ruleset.json is active:
       git push origin HEAD:rendered/gov-payments/prod
     GitHub rejects it and names the ruleset.

TXT

if [ -n "$live" ]; then
  echo "Live attempts against context '$ctx', namespace '$ns' (server-side dry run: nothing is created)"
  echo
  try() { # scene, description, manifest
    printf '%-4s %s\n' "$1" "$2"
    if out="$(printf '%s\n' "$3" | kubectl --context "$ctx" apply --dry-run=server -n "$ns" -f - 2>&1)"; then
      echo "     NOT BLOCKED: is cluster-policies/prod-only-argocd.yaml applied, and is $ns labeled tier=prod?"; open=$((open+1))
    else
      echo "     Blocked: $(printf '%s' "$out" | tr '\n' ' ' | sed 's/  */ /g' | cut -c1-220)"; blocked=$((blocked+1))
    fi
    echo
  }
  try 4f "kubectl apply an unsigned image straight into prod" "apiVersion: v1
kind: Pod
metadata: {name: gauntlet-sneaky-pod, labels: {purpose: demo}}
spec: {containers: [{name: app, image: docker.io/library/nginx:1.27}]}"
  try 4g "A GitHub Actions job deploys to prod with its own credentials, skipping Kargo" "apiVersion: apps/v1
kind: Deployment
metadata: {name: gauntlet-direct-deploy}
spec:
  replicas: 1
  selector: {matchLabels: {app: gauntlet}}
  template:
    metadata: {labels: {app: gauntlet, purpose: demo}}
    spec: {containers: [{name: app, image: ghcr.io/akuity/sedemo-monorepo-rollouts-app:latest}]}"
else
  echo "4f/4g  Writing to a prod namespace directly: run with --live <kube-context> to try it"
  echo "       against the cluster (needs cluster-policies/prod-only-argocd.yaml applied)."
  echo
fi

echo "What's left, said plainly: a cluster-admin, a GitHub org owner and a Kargo admin"
echo "can still change the rules themselves. Those changes go through the platform repo"
echo "and its own review, and break glass covers real emergencies with an audit trail."
echo
echo "$blocked blocked, $open not blocked."
[ "$open" -eq 0 ]
