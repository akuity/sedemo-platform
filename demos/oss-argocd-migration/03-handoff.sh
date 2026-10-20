#!/usr/bin/env bash
# Hand ONE app from OSS Argo CD to Akuity without redeploying it:
#   1. stop OSS writing (auto-sync + self-heal off)
#   2. same Application, same Git repo, on Akuity -> adopts the live resources
#   3. retire the OSS Application later, non-cascade (03b-retire.sh)
set -euo pipefail
source "$(dirname "$0")/env.sh"

say "1. Old Argo CD: turn off auto-sync and self-heal. It still compares, but never writes."
step "k -n argocd patch app ${APP} --type merge -p '{\"spec\":{\"syncPolicy\":{\"automated\":null}}}'"
step "k -n argocd get app ${APP} -o jsonpath='{.spec.syncPolicy}{\"\\n\"}'"

say "2. Same Application, same Git repo, on Akuity. Only the destination changes."
step "k -n argocd get appproject edge-site -o yaml | to_akuity > ${OUT_DIR}/${APP}.yaml"
step "echo --- >> ${OUT_DIR}/${APP}.yaml"
# The OSS app's sync policy was just removed; restore auto-sync on the Akuity copy.
step "k -n argocd get app ${APP} -o yaml | to_akuity | yq '.spec.syncPolicy.automated = {\"prune\": true, \"selfHeal\": true}' >> ${OUT_DIR}/${APP}.yaml"
step "yq 'select(.kind == \"Application\") | .spec' ${OUT_DIR}/${APP}.yaml"
step "akuity argocd apply ${AK_FLAGS[*]/--instance-name/--name} -f ${OUT_DIR}/${APP}.yaml"
say "Watch ${APP} in the Akuity UI: Synced/Healthy, nothing recreated. Then run 04-verify.sh"

say "3. (later) Retire the OSS app safely with 03b-retire.sh. Until then it is your rollback path."
