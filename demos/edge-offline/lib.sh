# shellcheck shell=bash
# shellcheck disable=SC2034 # variables here are used by the scripts that source this file
# Shared settings and helpers for the edge-offline demo scripts.

CD=(--organization-name demo --instance-name se-demo-iac)
KG=(--organization-name demo --instance-name se-demo-iac-kargo)
: "${ARGOCD_CONTEXT:=argo.akpdemoapps.link}"
# Control-plane endpoints the site agents dial (Argo CD agent server + API, Kargo API).
: "${ARGOCD_INSTANCE_ID:=e96rrp7fide5qg83}"
: "${KARGO_INSTANCE_ID:=yz0qxt8l0dixl8rc}"
AGENT_HOST="${ARGOCD_INSTANCE_ID}-agentsvr.cdsvcs.akuity.cloud"
: "${AKUITY_HOSTS:=${AGENT_HOST} ${ARGOCD_INSTANCE_ID}-cplane.cdsvcs.akuity.cloud ${KARGO_INSTANCE_ID}-cplane.kargosvcs.akuity.cloud}"
GITEA_AUTH="demo:demo-pass-123"   # throwaway in-site Gitea, see README

# wait_healthy <label> <command...>: poll a `... get -o json` command until
# healthStatus is HEALTHY (10 min max); exit non-zero otherwise.
wait_healthy() {
  local label="$1" h=""; shift
  for _ in $(seq 1 60); do
    h=$("$@" -o json 2>/dev/null | jq -r '.healthStatus.code // empty' || true)
    if [[ "${h}" == "STATUS_CODE_HEALTHY" ]]; then echo "  ${label}: healthy"; return 0; fi
    sleep 10
  done
  echo "  ${label}: not healthy after 10 min (last: ${h:-unknown})" >&2
  return 1
}

# gitea_open <site>: port-forward to the site's Gitea (works while the site is
# offline) and set GITEA_URL / GITEA_API / GITEA_PF. Fails if Gitea doesn't answer in 10 s.
gitea_open() {
  local site="$1" port
  port=$((13000 + RANDOM % 1000))
  kubectl --context "k3d-${site}" -n gitea port-forward svc/gitea "${port}:3000" >/dev/null 2>&1 &
  GITEA_PF=$!
  GITEA_URL="http://${GITEA_AUTH}@localhost:${port}/demo/edge-app.git"
  GITEA_API="http://localhost:${port}/api/v1"
  for _ in $(seq 1 20); do
    curl -sf -o /dev/null "http://localhost:${port}/api/healthz" && return 0
    sleep 0.5
  done
  echo "Gitea on ${site} not reachable via port-forward" >&2
  gitea_close; return 1
}
gitea_close() { kill "${GITEA_PF:-}" 2>/dev/null || true; }
