#!/usr/bin/env bash
# Both views of each site: what the Akuity control plane reports, and what is
# actually running inside the site.  `state.sh --brief` prints one line per site.
set -uo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
if [[ "${1:-}" == "--brief" ]]; then
  shift; sites=("$@"); [[ ${#sites[@]} -gt 0 ]] || sites=(edge-sr-off edge-sr-on)
  for site in "${sites[@]}"; do site_brief "${site}"; done; exit 0
fi
SITES=("${@:-edge-sr-off edge-sr-on}"); read -r -a SITES <<< "${SITES[*]}"

for site in "${SITES[@]}"; do
  short="${site#edge-}"
  printf '\n\033[1m== %s ==\033[0m  ' "${site}"
  docker exec "$(knode "${site}")" iptables -t raw -S EDGE-OUTAGE >/dev/null 2>&1 \
    && { docker exec "$(knode "${site}")" iptables -t raw -S EDGE-OUTAGE | grep -q -- '-j RETURN' && echo "[OFFLINE]" || echo "[CLOUD LINK DOWN]"; } \
    || echo "[online]"
  echo "  Akuity says:"
  akuity argocd cluster get "${CD[@]}" "${site}" -o json 2>/dev/null \
    | jq -r '"    cluster: \(.healthStatus.code | sub("STATUS_CODE_"; "")) - \(.healthStatus.message) (status observed \(.agentState.observeTime[11:19])Z)"'
  for app in "${short}-github" "${short}-local"; do
    argocd --argocd-context "${ARGOCD_CONTEXT}" app get "${app}" -o json 2>/dev/null \
      | jq -r '"    \(.metadata.name): \(.status.sync.status)/\(.status.health.status) rev=\(.status.sync.revision[0:7]) last-op=\(.status.operationState.finishedAt // "-")"'
  done
  echo "  Site reality:"
  k() { kubectl --context "$(kctx "${site}")" --request-timeout=8s "$@"; }
  printf '    guestbook-ui replicas=%s  edge-app replicas=%s  edge-config.message=%s\n' \
    "$(k -n guestbook get deploy guestbook-ui -o jsonpath='{.spec.replicas}' 2>/dev/null)" \
    "$(k -n edge-app get deploy edge-app -o jsonpath='{.spec.replicas}' 2>/dev/null)" \
    "$(k -n edge-app get cm edge-config -o jsonpath='{.data.message}' 2>/dev/null)"
  printf '    app controller: %s\n' "$(k -n akuity get pods -l app.kubernetes.io/name=argocd-application-controller --no-headers 2>/dev/null | awk '{print $1" "$2" "$3" restarts="$4" age="$5}')"
  if k get crd applications.argoproj.io >/dev/null 2>&1; then
    k -n akuity get applications -o json 2>/dev/null \
      | jq -r '.items[] | "    local copy \(.metadata.name): \(.status.sync.status)/\(.status.health.status) rev=\(.status.sync.revision[0:7])"'
  fi
done
