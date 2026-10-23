#!/usr/bin/env bash
# Hand ONE app from OSS Argo CD to Akuity without redeploying it:
#   1. export the Application (and its project) as-is
#   2. stop OSS writing (auto-sync + self-heal off)
#   3. same Application, same Git repo, on Akuity -> adopts the live resources
#   later: retire the OSS Application non-cascade (03b-retire.sh)
set -euo pipefail
source "$(dirname "$0")/env.sh"

say "1. Export the app and its project from OSS. Only the destination changes."
step "k -n argocd get appproject edge-site -o yaml | to_akuity > ${OUT_DIR}/${APP}.yaml"
step "echo --- >> ${OUT_DIR}/${APP}.yaml"
step "k -n argocd get app ${APP} -o yaml | to_akuity >> ${OUT_DIR}/${APP}.yaml"
step "yq 'select(.kind == \"Application\") | .spec' ${OUT_DIR}/${APP}.yaml"

say "2. Old Argo CD: turn off auto-sync and self-heal. It still compares, but never writes."
step "k -n argocd patch app ${APP} --type merge -p '{\"spec\":{\"syncPolicy\":{\"automated\":null}}}'"
step "k -n argocd get app ${APP} -o jsonpath='{.spec.syncPolicy}{\"\\n\"}'"

say "3. Same Application, same Git repo, on Akuity."
step "akuity argocd apply ${AK_FLAGS[*]/--instance-name/--name} -f ${OUT_DIR}/${APP}.yaml"
say "Watch ${APP} in the Akuity UI: Synced/Healthy, nothing recreated. Then run 04-verify.sh"

say "Later: retire the OSS app safely with 03b-retire.sh. Until then it is your rollback path."
