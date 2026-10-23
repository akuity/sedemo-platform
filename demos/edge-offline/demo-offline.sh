#!/usr/bin/env bash
# Live part of the offline demo. Run after stage-offline.sh (both sites offline).
# Prints each step and a one-line-per-site view so the presenter can narrate.
#   PAUSE=1 ./demo-offline.sh   wait for Enter before each step
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; cd "${DIR}" || exit 1
# shellcheck source=lib.sh
source "${DIR}/lib.sh"
SITES=(edge-sr-off edge-sr-on)
TAG="offline-$(date +%H%M%S)"

k()   { kubectl --context "$(kctx "$1")" --request-timeout=8s "${@:2}"; }
reps() { k "$1" -n edge-app get deploy edge-app -o jsonpath='{.spec.replicas}' 2>/dev/null; }
msg()  { k "$1" -n edge-app get cm edge-config -o jsonpath='{.data.message}' 2>/dev/null; }
ctrl() { k "$1" -n akuity get pods -l app.kubernetes.io/name=argocd-application-controller --no-headers 2>/dev/null | awk '{print $2; exit}'; }
health() { akuity argocd cluster get "${CD[@]}" "$1" -o json 2>/dev/null | jq -r '.healthStatus.code // "?" | sub("STATUS_CODE_"; "")'; }

step() {
  printf '\n\033[1;36m━━ %s\033[0m\n' "$1"
  [[ -n "${2:-}" ]] && printf '\033[2m   %s\033[0m\n' "$2"
  if [[ "${PAUSE:-0}" == "1" ]]; then read -r -p "   [enter] " _; fi
}
show() { echo; for s in "${SITES[@]}"; do site_brief "${s}"; done; }
# wait_for <max-seconds> <label> <test-command...>: progress line until the test passes
wait_for() {
  local max="$1" label="$2" t=0; shift 2
  until "$@"; do
    (( t >= max )) && { printf '\r   %s: not yet after %ss\n' "${label}" "${t}"; return 1; }
    printf '\r   %s ... %ss' "${label}" "${t}"; sleep 5; t=$((t + 5))
  done
  printf '\r   %s: done after %ss      \n' "${label}" "${t}"
}

for s in "${SITES[@]}"; do
  docker exec "$(knode "${s}")" iptables -t raw -S EDGE-OUTAGE 2>/dev/null | grep -q -- '-j RETURN' \
    || { echo "${s} is not offline; run ./stage-offline.sh first." >&2; exit 1; }
done
since=$(cat out/outage-start 2>/dev/null || echo "?")

step "Where we are: both sites lost their uplink (since ${since})" \
  "Same agent, one install-time switch: State Replication off (top) vs on (bottom). Akuity can't reach either."
show

step "1. Someone changes the app by hand at the site (scale to 3)" \
  "SR off: nothing enforces Git. SR on: the site reverts it on its own."
for s in "${SITES[@]}"; do k "${s}" -n edge-app scale deploy edge-app --replicas=3 >/dev/null; done
sr_on_reverted() { [[ "$(reps edge-sr-on)" == 1 ]]; }
wait_for 60 "waiting for edge-sr-on to self-heal" sr_on_reverted
show

step "2. A new release lands in the site's local Git (message=${TAG})" \
  "Argo CD polls Git every few minutes; to save time we ask each site to check now, locally."
for s in "${SITES[@]}"; do ./push.sh "${s}" "${TAG}" 2>/dev/null | sed 's/^/   /'; done
echo "   edge-sr-on:  refresh the local copy of the app (no control plane involved)"
k edge-sr-on -n akuity annotate application sr-on-local argocd.argoproj.io/refresh=hard --overwrite | sed 's/^/     /'
echo "   edge-sr-off: same request..."
k edge-sr-off -n akuity annotate application sr-off-local argocd.argoproj.io/refresh=hard --overwrite 2>&1 \
  | sed 's/^/     /'
echo "     -> no local copy of the app exists without State Replication; only the control plane could do this."
sr_on_deployed() { [[ "$(msg edge-sr-on)" == "${TAG}" ]]; }
wait_for 90 "waiting for edge-sr-on to deploy it" sr_on_deployed
show

step "3. The site's node reboots mid-outage (restart the app controllers)" \
  "SR off: the controller can't load its config from the control plane. SR on: starts from its local copy."
for s in "${SITES[@]}"; do k "${s}" -n akuity delete pod -l app.kubernetes.io/name=argocd-application-controller --wait=false >/dev/null; done
sleep 5
sr_on_ready() { [[ "$(ctrl edge-sr-on)" == 3/3 ]]; }
wait_for 120 "waiting for edge-sr-on's controller" sr_on_ready
sleep 10
show

step "4. The uplink comes back" \
  "SR off catches up: drift reverted, release deployed. SR on was already right. Then the dashboard turns green."
for s in "${SITES[@]}"; do ./outage.sh "${s}" restore | sed 's/^/   /'; done
sr_off_caught_up() { [[ "$(reps edge-sr-off)" == 1 && "$(msg edge-sr-off)" == "${TAG}" && "$(ctrl edge-sr-off)" == 3/3 ]]; }
wait_for 240 "waiting for edge-sr-off to catch up" sr_off_caught_up
both_healthy() { [[ "$(health edge-sr-off)" == HEALTHY && "$(health edge-sr-on)" == HEALTHY ]]; }
wait_for 240 "waiting for the Akuity dashboard" both_healthy
show
echo
