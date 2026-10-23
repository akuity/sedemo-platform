#!/usr/bin/env bash
# Two edge sites, identical except for Argo CD State Replication, each running
# the same two apps (one from GitHub, one from an in-site Gitea), plus a Kargo
# project with central-agent stages and a self-hosted Kargo agent on edge-sr-on.
# Safe to re-run: existing clusters, agents and the seeded repo are kept.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; OUT="${DIR}/out"; mkdir -p "${OUT}"
# shellcheck source=lib.sh
source "${DIR}/lib.sh"

for site in edge-sr-off edge-sr-on; do
  kind get clusters 2>/dev/null | grep -qx "${site}" \
    || kind create cluster --name "${site}" --wait 120s
done

echo "== Register sites with Argo CD (State Replication is install-time only)"
akuity argocd cluster create edge-sr-off "${CD[@]}" --upsert --label offline-demo=true
akuity argocd cluster create edge-sr-on "${CD[@]}" --upsert --label offline-demo=true --state-replication=true
for site in edge-sr-off edge-sr-on; do
  akuity argocd cluster get-agent-manifests "${CD[@]}" "${site}" > "${OUT}/agent-${site}.yaml"
  kubectl --context "$(kctx "${site}")" apply -f "${OUT}/agent-${site}.yaml" >/dev/null
done

echo "== In-site Gitea + netcheck pod (images must be pulled while online)"
for site in edge-sr-off edge-sr-on; do
  k() { kubectl --context "$(kctx "${site}")" "$@"; }
  k apply -f "${DIR}/manifests/gitea.yaml" -f "${DIR}/manifests/netcheck.yaml" >/dev/null
  k -n gitea rollout status deploy/gitea --timeout=300s
  k -n gitea exec deploy/gitea -- su git -c "gitea admin user list" | grep -qw demo \
    || k -n gitea exec deploy/gitea -- su git -c "gitea admin user create --username demo \
         --password ${GITEA_AUTH#demo:} --email demo@example.com --admin --must-change-password=false"
  k wait --for=condition=Ready pod/netcheck --timeout=180s
done

echo "== Seed edge-app repo in each Gitea (skipped if it already exists)"
for site in edge-sr-off edge-sr-on; do
  gitea_open "${site}"
  if curl -sf -o /dev/null "${GITEA_API}/repos/demo/edge-app"; then
    echo "  ${site}: repo exists"
  else
    R="${OUT}/edge-app-seed-${site}"; rm -rf "${R}"; mkdir -p "${R}"
    cp "${DIR}/edge-app/app.yaml" "${R}/"
    git -C "${R}" init -q -b main && git -C "${R}" add . \
      && git -C "${R}" -c user.name=demo -c user.email=demo@example.com commit -q -m "edge-app v1"
    git -C "${R}" push -q "${GITEA_URL}" main
    echo "  ${site}: repo seeded"
  fi
  gitea_close
done

echo "== Wait for both Argo CD agents"
for site in edge-sr-off edge-sr-on; do
  wait_healthy "argocd agent ${site}" akuity argocd cluster get "${CD[@]}" "${site}"
done

echo "== Self-hosted Kargo agent on edge-sr-on"
akuity kargo agent create edge-sr-on "${KG[@]}" --upsert --self-hosted=true \
  --akuity-argocd-name se-demo-iac --label offline-demo=true
akuity kargo agent get-manifests "${KG[@]}" edge-sr-on > "${OUT}/kargo-agent-edge-sr-on.yaml"
kubectl --context "$(kctx edge-sr-on)" apply -f "${OUT}/kargo-agent-edge-sr-on.yaml" >/dev/null
wait_healthy "kargo agent edge-sr-on" akuity kargo agent get "${KG[@]}" edge-sr-on

echo "== Apps and Kargo resources"
# Applies occasionally fail with a transient "internal error" from the API.
retry 3 akuity argocd apply --organization-name demo --name se-demo-iac -f "${DIR}/manifests/apps.yaml"
retry 3 akuity kargo apply --organization-name demo --name se-demo-iac-kargo -f "${DIR}/manifests/kargo.yaml"

echo; echo "Setup done. Check with ./state.sh (apps take ~1 min to go Synced/Healthy)."
