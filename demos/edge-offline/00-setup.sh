#!/usr/bin/env bash
# Two edge sites, identical except for Argo CD State Replication, each running
# the same two apps (one from GitHub, one from an in-site Gitea), plus a Kargo
# project with central-agent stages and a self-hosted Kargo agent on edge-sr-on.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; OUT="${DIR}/out"; mkdir -p "${OUT}"
CD=(--organization-name demo --instance-name se-demo-iac)
KG=(--organization-name demo --instance-name se-demo-iac-kargo)

for site in edge-sr-off edge-sr-on; do
  k3d cluster get "${site}" >/dev/null 2>&1 \
    || k3d cluster create "${site}" --no-lb --k3s-arg '--disable=traefik@server:0' --wait
done

echo "== Register sites with Argo CD (State Replication is install-time only)"
akuity argocd cluster create edge-sr-off "${CD[@]}" --upsert --label offline-demo=true
akuity argocd cluster create edge-sr-on "${CD[@]}" --upsert --label offline-demo=true --state-replication=true
for site in edge-sr-off edge-sr-on; do
  akuity argocd cluster get-agent-manifests "${CD[@]}" "${site}" > "${OUT}/agent-${site}.yaml"
  kubectl --context "k3d-${site}" apply -f "${OUT}/agent-${site}.yaml" >/dev/null
done

echo "== In-site Gitea + netcheck pod (images must be pulled while online)"
for site in edge-sr-off edge-sr-on; do
  k() { kubectl --context "k3d-${site}" "$@"; }
  k apply -f "${DIR}/manifests/gitea.yaml" -f "${DIR}/manifests/netcheck.yaml" >/dev/null
  k -n gitea rollout status deploy/gitea --timeout=300s
  k -n gitea exec deploy/gitea -- su git -c "gitea admin user create --username demo \
    --password demo-pass-123 --email demo@example.com --admin --must-change-password=false" 2>/dev/null || true
  k wait --for=condition=Ready pod/netcheck --timeout=180s
done

echo "== Seed edge-app repo in each Gitea"
for site in edge-sr-off edge-sr-on; do
  R="${OUT}/edge-app-repo-${site}"; rm -rf "${R}"; mkdir -p "${R}"
  cp "${DIR}/edge-app/app.yaml" "${R}/"
  git -C "${R}" init -q -b main && git -C "${R}" add . \
    && git -C "${R}" -c user.name=demo -c user.email=demo@example.com commit -q -m "edge-app v1"
  port=$((13000 + RANDOM % 1000))
  kubectl --context "k3d-${site}" -n gitea port-forward svc/gitea "${port}:3000" >/dev/null 2>&1 & pf=$!
  sleep 3
  git -C "${R}" push -q "http://demo:demo-pass-123@localhost:${port}/demo/edge-app.git" main 2>&1 | grep -v '^remote:' || true
  kill "${pf}"
done

echo "== Wait for both Argo CD agents"
for site in edge-sr-off edge-sr-on; do
  for _ in $(seq 1 60); do
    h=$(akuity argocd cluster get "${CD[@]}" "${site}" -o json 2>/dev/null | jq -r '.healthStatus.code // empty' || true)
    [[ "${h}" == "STATUS_CODE_HEALTHY" ]] && break
    sleep 10
  done
  echo "  ${site}: ${h:-unknown}"
done

echo "== Self-hosted Kargo agent on edge-sr-on"
akuity kargo agent create edge-sr-on "${KG[@]}" --upsert --self-hosted=true \
  --akuity-argocd-name se-demo-iac --label offline-demo=true
akuity kargo agent get-manifests "${KG[@]}" edge-sr-on > "${OUT}/kargo-agent-edge-sr-on.yaml"
kubectl --context k3d-edge-sr-on apply -f "${OUT}/kargo-agent-edge-sr-on.yaml" >/dev/null
for _ in $(seq 1 60); do
  h=$(akuity kargo agent get "${KG[@]}" edge-sr-on -o json 2>/dev/null | jq -r '.healthStatus.code // empty' || true)
  [[ "${h}" == "STATUS_CODE_HEALTHY" ]] && break
  sleep 10
done
echo "  kargo agent edge-sr-on: ${h:-unknown}"

echo "== Apps and Kargo resources"
akuity argocd apply --organization-name demo --name se-demo-iac -f "${DIR}/manifests/apps.yaml"
akuity kargo apply --organization-name demo --name se-demo-iac-kargo -f "${DIR}/manifests/kargo.yaml"

echo; echo "Setup done. Check with ./state.sh (apps take ~1 min to go Synced/Healthy)."
