#!/usr/bin/env bash
# The bulk path: every remaining Application and AppProject on this OSS
# instance, exported, rewritten, diffed, and applied in one shot.
set -euo pipefail
source "$(dirname "$0")/env.sh"
B="${OUT_DIR}/bulk.yaml"
# Apps already handed off (their OSS copy has auto-sync off now). Export BEFORE
# disabling: whatever the OSS spec says at export time is what Akuity gets.
: "${EXCLUDE:=${APP}}"

say "1. Export all AppProjects and Applications from OSS (sync policy kept as-is)"
step "k -n argocd get appprojects -o yaml | yq '.items[] | select(.metadata.name != \"default\") | split_doc' | to_akuity > ${B}"
step "echo --- >> ${B}"
step "k -n argocd get applications -o yaml | EXCLUDE=\"${EXCLUDE}\" yq '.items[] | select(.metadata.name as \$n | strenv(EXCLUDE) | split(\" \") | contains([\$n]) | not) | split_doc' | to_akuity >> ${B}"
step "yq '[.kind, .metadata.name, (.spec.destination.name // \"\")] | join(\"  \")' ${B}"
# Repo credentials live in Secrets labeled argocd.argoproj.io/secret-type;
# export those too for private repos (they contain secrets: keep out/ local).

say "2. Preview what this changes on the Akuity instance"
step "akuity argocd diff ${AKUITY_INSTANCE} --organization-name ${AKUITY_ORG} -f ${B}"

say "3. Old Argo CD: auto-sync and self-heal off for every app"
for app in $(yq -N 'select(.kind == "Application") | .metadata.name' "${B}"); do
  step "k -n argocd patch app ${app} --type merge -p '{\"spec\":{\"syncPolicy\":{\"automated\":null}}}'"
done

say "4. Apply to Akuity (NEVER add --prune here: it would delete every app not in this file)"
step "akuity argocd apply ${AK_FLAGS[*]/--instance-name/--name} -f ${B}"
say "Retire the OSS apps later, non-cascade: ./03b-retire.sh \$(kubectl --context ${KCTX} -n argocd get app -o name | cut -d/ -f2)"
