#!/usr/bin/env bash
# Remove the offline demo: Kargo project + agent, Argo CD apps + clusters, k3d.
# Needs `argocd login argo.akpdemoapps.link --sso --grpc-web` and
# `kargo login https://kargo.akpdemoapps.link --sso`.
set -uo pipefail
: "${ARGOCD_CONTEXT:=argo.akpdemoapps.link}"
DIR="$(cd "$(dirname "$0")" && pwd)"
CD=(--organization-name demo --instance-name se-demo-iac)
KG=(--organization-name demo --instance-name se-demo-iac-kargo)

for site in edge-sr-off edge-sr-on; do "${DIR}/outage.sh" "${site}" restore >/dev/null 2>&1; done

# Kargo: delete only this demo's project (never `akuity kargo apply --prune`).
kargo delete project edge-offline || echo "Delete Kargo project edge-offline in the UI if this failed."
akuity kargo agent delete "${KG[@]}" edge-sr-on || true

APPS=(sr-off-github sr-off-local sr-on-github sr-on-local)
for app in "${APPS[@]}"; do
  argocd --argocd-context "${ARGOCD_CONTEXT}" app delete "${app}" --cascade=false -y || true
done
for app in "${APPS[@]}"; do
  for _ in $(seq 1 40); do
    argocd --argocd-context "${ARGOCD_CONTEXT}" app get "${app}" -o json >/dev/null 2>&1 || break
    sleep 3
  done
done
# The edge-offline AppProject is left in place (see the migration demo README on RBAC).

for site in edge-sr-off edge-sr-on; do
  akuity argocd cluster delete "${CD[@]}" "${site}" || true
  k3d cluster delete "${site}"
done
rm -rf "${DIR}/out"
