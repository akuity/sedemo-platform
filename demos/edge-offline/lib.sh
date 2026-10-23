# shellcheck shell=bash
# shellcheck disable=SC2034 # variables here are used by the scripts that source this file
# Shared settings and helpers for the edge-offline demo scripts.

# Sites are kind clusters on OrbStack. Pin the engine (kind only sees the active
# Docker context) and the host architecture (an inherited
# DOCKER_DEFAULT_PLATFORM=linux/amd64 on Apple Silicon pulls an emulated
# kindest/node that times out in kubeadm).
: "${DOCKER_CONTEXT:=orbstack}"; export DOCKER_CONTEXT
DOCKER_DEFAULT_PLATFORM="linux/$(uname -m | sed 's/x86_64/amd64/; s/aarch64/arm64/')"; export DOCKER_DEFAULT_PLATFORM
kctx()  { echo "kind-$1"; }            # kube context of a site
knode() { echo "$1-control-plane"; }   # node container of a site

CD=(--organization-name demo --instance-name se-demo-iac)
KG=(--organization-name demo --instance-name se-demo-iac-kargo)
: "${ARGOCD_CONTEXT:=argo.akpdemoapps.link}"
# Control-plane endpoints the site agents dial (Argo CD agent server + API, Kargo API).
: "${ARGOCD_INSTANCE_ID:=e96rrp7fide5qg83}"
: "${KARGO_INSTANCE_ID:=yz0qxt8l0dixl8rc}"
AGENT_HOST="${ARGOCD_INSTANCE_ID}-agentsvr.cdsvcs.akuity.cloud"
: "${AKUITY_HOSTS:=${AGENT_HOST} ${ARGOCD_INSTANCE_ID}-cplane.cdsvcs.akuity.cloud ${KARGO_INSTANCE_ID}-cplane.kargosvcs.akuity.cloud}"
GITEA_AUTH="demo:demo-pass-123"   # throwaway in-site Gitea, see README

# retry <attempts> <command...>: re-run a command that can hit transient API errors.
retry() {
  local n="$1" i; shift
  for i in $(seq 1 "${n}"); do
    "$@" && return 0
    [[ "${i}" -lt "${n}" ]] && { echo "  retrying in 10s ($i/${n})" >&2; sleep 10; }
  done
  return 1
}

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
  kubectl --context "$(kctx "${site}")" -n gitea port-forward svc/gitea "${port}:3000" >/dev/null 2>&1 &
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

# site_brief <site>: one line per site, what's running vs what Git says.
# Git is read from the site's own Gitea via the in-site netcheck pod, so this
# works while the site is offline.
site_brief() {
  local site="$1" k net akuity reps msg gmsg ctrl ok bad
  k=(kubectl --context "$(kctx "${site}")" --request-timeout=8s)
  if docker exec "$(knode "${site}")" iptables -t raw -S EDGE-OUTAGE >/dev/null 2>&1; then
    docker exec "$(knode "${site}")" iptables -t raw -S EDGE-OUTAGE | grep -q -- '-j RETURN' && net="OFFLINE  " || net="LINK DOWN"
  else net="online   "; fi
  akuity=$(akuity argocd cluster get "${CD[@]}" "${site}" -o json 2>/dev/null | jq -r '.healthStatus.code // "?" | sub("STATUS_CODE_"; "")')
  reps=$("${k[@]}" -n edge-app get deploy edge-app -o jsonpath='{.spec.replicas}' 2>/dev/null)
  msg=$("${k[@]}" -n edge-app get cm edge-config -o jsonpath='{.data.message}' 2>/dev/null)
  gmsg=$("${k[@]}" exec netcheck -- curl -s -m 4 http://gitea.gitea.svc:3000/demo/edge-app/raw/branch/main/app.yaml 2>/dev/null \
    | awk '/message:/ {gsub(/"/, "", $2); print $2; exit}')
  ctrl=$("${k[@]}" -n akuity get pods -l app.kubernetes.io/name=argocd-application-controller --no-headers 2>/dev/null | awk '{print $2; exit}')
  ok=$'\033[32m'; bad=$'\033[31m'
  printf '  %-12s %s  akuity: %-11s  replicas %s%s\033[0m (git 1)  message %s%s\033[0m (git %s)  controller %s%s\033[0m\n' \
    "${site}" "${net}" "${akuity}" \
    "$([[ "${reps}" == 1 ]] && echo "${ok}" || echo "${bad}")" "${reps:-?}" \
    "$([[ "${msg}" == "${gmsg}" ]] && echo "${ok}" || echo "${bad}")" "${msg:-?}" "${gmsg:-?}" \
    "$([[ "${ctrl}" == 3/3 ]] && echo "${ok}" || echo "${bad}")" "${ctrl:-?}"
}
