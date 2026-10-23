#!/usr/bin/env bash
# Before the call: take both sites offline and wait until the Akuity dashboard
# shows them as not healthy (took up to ~10 min in testing). Then run
# demo-offline.sh live. Leave this running in its own terminal tab.
#
#   stage-offline.sh            stage and watch the dashboard
#   stage-offline.sh --no-wait  stage only
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; mkdir -p "${DIR}/out"
# shellcheck source=lib.sh
source "${DIR}/lib.sh"
SITES=(edge-sr-off edge-sr-on)

# The local apps must follow Git HEAD for the "new release in local Git" step.
# A Kargo promotion to edge-sr-on-local pins sr-on-local to a commit, and an app
# can't be changed once its site is offline, so reset that first.
for app in sr-off-local sr-on-local; do
  argocd --argocd-context "${ARGOCD_CONTEXT}" app set "${app}" --revision HEAD
done
for _ in $(seq 1 24); do
  [[ "$(kubectl --context "$(kctx edge-sr-on)" -n akuity get application sr-on-local \
        -o jsonpath='{.spec.source.targetRevision}')" == HEAD ]] && break
  sleep 5
done
echo "Local apps track Git HEAD."

for s in "${SITES[@]}"; do "${DIR}/outage.sh" "${s}" offline | head -1; done
date -u +%Y-%m-%dT%H:%M:%SZ > "${DIR}/out/outage-start"
echo "Outage started $(date +%H:%M) local. Run demo-offline.sh once the dashboard shows the sites down."
[[ "${1:-}" == "--no-wait" ]] && exit 0

start=$(date +%s)
while :; do
  line="  $(date +%H:%M:%S) (+$(( ($(date +%s) - start) / 60 ))m)"; down=0
  for s in "${SITES[@]}"; do
    h=$(akuity argocd cluster get "${CD[@]}" "${s}" -o json 2>/dev/null | jq -r '.healthStatus.code // "?" | sub("STATUS_CODE_"; "")')
    line+="  ${s}: ${h}"; [[ "${h}" != HEALTHY && "${h}" != "?" ]] && down=$((down + 1))
  done
  echo "${line}"
  if [[ "${down}" == "${#SITES[@]}" ]]; then
    echo; echo "READY: the Akuity dashboard shows both sites as not healthy. Run ./demo-offline.sh"
    exit 0
  fi
  if (( $(date +%s) - start > 1500 )); then
    echo; echo "Still not flagged after 25 min; the sites are offline anyway, so you can run ./demo-offline.sh." >&2
    exit 0
  fi
  sleep 30
done
