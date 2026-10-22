#!/usr/bin/env bash
# Remove the offline demo: Kargo project + agent, Argo CD apps + clusters, k3d.
# Needs `argocd login argo.akpdemoapps.link --sso --grpc-web` and
# `kargo login https://kargo.akpdemoapps.link --sso`. If your default kargo
# login is for another instance, log in with a separate home and pass it:
#   HOME=/some/dir kargo login https://kargo.akpdemoapps.link --sso
#   KARGO_HOME=/some/dir ./99-teardown.sh
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "${DIR}/lib.sh"

kg() { HOME="${KARGO_HOME:-${HOME}}" kargo "$@"; }

# The kargo CLI must point at the demo instance: against another instance the
# project looks "not found", the delete below is skipped, and removing the edge
# agent then strands the project in Terminating on the shared instance.
kargo_addr=$(kg config view 2>/dev/null | awk '/apiAddress/ {print $2}')
if [[ "${kargo_addr}" != "https://kargo.akpdemoapps.link" ]]; then
  echo "kargo CLI points at '${kargo_addr:-nothing}', not the demo instance." >&2
  echo "Run: kargo login https://kargo.akpdemoapps.link --sso (or see KARGO_HOME above)" >&2
  exit 1
fi

for site in edge-sr-off edge-sr-on; do "${DIR}/outage.sh" "${site}" restore >/dev/null 2>&1; done

# Kargo: delete only this demo's project (never `akuity kargo apply --prune`), and
# wait until it is gone: the edge-sr-on agent clears the finalizers on the sharded
# Warehouse/Stage, so it must still be running while the project terminates.
if kg get project edge-offline >/dev/null 2>&1; then
  kg delete project edge-offline
  for _ in $(seq 1 60); do
    kg get project edge-offline >/dev/null 2>&1 || break
    sleep 5
  done
  if kg get project edge-offline >/dev/null 2>&1; then
    echo "Kargo project edge-offline is still terminating after 5 min; leaving the" >&2
    echo "edge-sr-on agent and clusters in place. Check the Kargo UI, then re-run." >&2
    exit 1
  fi
fi
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
