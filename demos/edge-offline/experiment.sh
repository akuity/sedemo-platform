#!/usr/bin/env bash
# Scripted outage on both sites at once, logging one line per minute:
#   t+1m  drift: scale edge-app to 3        (does the site revert it?)
#   t+2m  push a new commit to in-site Git   (does the site deploy it?)
#   t+3m  restart the app controller         (does it come back working?)
#   t+4m  drift again after the restart
#   then restore and log the catch-up.
# Every line re-checks that the outage is still in force (netcheck + iptables
# hook position), so a leaking outage can't produce a false result.
#
#   experiment.sh [offline|link-down] [minutes]
#   RESTART=0 experiment.sh ...   skip the controller restart (isolates commit polling)
set -uo pipefail
MODE="${1:-offline}"; MINUTES="${2:-9}"
DIR="$(cd "$(dirname "$0")" && pwd)"; cd "${DIR}" || exit 1
# shellcheck source=lib.sh
source "${DIR}/lib.sh"
SITES=(edge-sr-off edge-sr-on)
TAG="x$(date +%H%M%S)"

k() { kubectl --context "k3d-$1" --request-timeout=8s "${@:2}"; }
line() {
  local out; out="$(date -u +%H:%M:%S)Z $1 |"
  for s in "${SITES[@]}"; do
    local ready akuity reach hook
    ready=$(k "$s" -n akuity get pods -l app.kubernetes.io/name=argocd-application-controller --no-headers 2>/dev/null | awk '{print $2}')
    akuity=$(akuity argocd cluster get "${CD[@]}" "$s" -o json 2>/dev/null | jq -r '.healthStatus.code // "?" | sub("STATUS_CODE_"; "")')
    reach=$(k "$s" exec netcheck -- curl -s -o /dev/null -m 3 -w '%{http_code}' https://${AGENT_HOST} 2>/dev/null)
    hook=$(docker exec "k3d-$s-server-0" iptables -t raw -S PREROUTING 2>/dev/null | sed -n 2p | grep -q EDGE-OUTAGE && echo first || echo none)
    out+=" ${s#edge-}: replicas=$(k "$s" -n edge-app get deploy edge-app -o jsonpath='{.spec.replicas}') msg=$(k "$s" -n edge-app get cm edge-config -o jsonpath='{.data.message}') ctrl=${ready:-?} akuity=${akuity} cplane=$([[ ${reach:-000} == 000 ]] && echo blocked || echo REACHABLE) hook=${hook} |"
  done
  echo "${out}"
}

line "baseline"
for s in "${SITES[@]}"; do ./outage.sh "$s" "${MODE}" >/dev/null; done
line "OUTAGE ${MODE} started"
for m in $(seq 1 "${MINUTES}"); do
  sleep 60
  case "$m" in
    1) for s in "${SITES[@]}"; do k "$s" -n edge-app scale deploy edge-app --replicas=3 >/dev/null; done
       sleep 20; line "t+1m drift: scaled edge-app to 3 (+20s)" ;;
    2) pushed=""
       for s in "${SITES[@]}"; do ./push.sh "$s" "${TAG}" >/dev/null && pushed+="${s#edge-} " || pushed+="${s#edge-}=FAILED "; done
       line "t+2m pushed msg=${TAG} to in-site Git (${pushed% })" ;;
    3) if [[ "${RESTART:-1}" == "1" ]]; then
         for s in "${SITES[@]}"; do k "$s" -n akuity delete pod -l app.kubernetes.io/name=argocd-application-controller --wait=false >/dev/null; done
         line "t+3m restarted app controllers"
       else line "t+3m (no restart)"; fi ;;
    4) for s in "${SITES[@]}"; do k "$s" -n edge-app scale deploy edge-app --replicas=2 >/dev/null; done
       sleep 20; line "t+4m drift after restart: scaled edge-app to 2 (+20s)" ;;
    *) line "t+${m}m" ;;
  esac
done
for s in "${SITES[@]}"; do ./outage.sh "$s" restore >/dev/null; done
line "RESTORED"
for _ in 1 2 3; do sleep 30; line "after restore"; done
