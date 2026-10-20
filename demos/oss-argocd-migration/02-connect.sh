#!/usr/bin/env bash
# Register the cluster with the Akuity instance and install the agent.
# Outbound-only: the agent dials the control plane; nothing is exposed.
set -euo pipefail
source "$(dirname "$0")/env.sh"

say "Register this site with the hosted control plane"
# STATE_REPLICATION=1: lets the site keep core Argo CD features while cut off
# from the platform. Install-time only; it cannot be turned on later.
SR_FLAG=""
if [[ "${STATE_REPLICATION:-0}" == "1" ]]; then SR_FLAG=" --state-replication=true"; fi
step "akuity argocd cluster create ${CLUSTER_NAME} ${AK_FLAGS[*]} --upsert --label migration-demo=true${SR_FLAG}"
say "The agent install is one manifest, applied to the site cluster"
step "akuity argocd cluster get-agent-manifests ${AK_FLAGS[*]} ${CLUSTER_NAME} > ${OUT_DIR}/agent.yaml"
step "k apply -f ${OUT_DIR}/agent.yaml"
say "Agent runs in its own namespace, alongside the existing Argo CD"
step "k -n akuity rollout status deploy/akuity-agent --timeout=300s"
step "k get ns argocd akuity"

echo "Waiting for the instance to report the cluster healthy..."
for _ in $(seq 1 60); do
  status=$(akuity argocd cluster get "${AK_FLAGS[@]}" "${CLUSTER_NAME}" -o json 2>/dev/null | jq -r '.healthStatus.code // empty' || true)
  [[ "${status}" == "STATUS_CODE_HEALTHY" ]] && { echo "  ${CLUSTER_NAME}: ${status}"; exit 0; }
  sleep 10
done
echo "Cluster not healthy yet (last: ${status:-unknown}); check the Akuity UI." >&2
exit 1
