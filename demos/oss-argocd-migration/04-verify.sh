#!/usr/bin/env bash
# Prove nothing was redeployed and the service never went down.
set -euo pipefail
source "$(dirname "$0")/env.sh"

say "Pods now, compared to before the cutover"
snapshot | tee "${OUT_DIR}/after.txt"
if diff -u "${OUT_DIR}/before.txt" "${OUT_DIR}/after.txt"; then
  echo ">>> Identical: same pods, same UIDs, zero restarts. Adopted, not redeployed."
else
  echo ">>> Pods differ (see diff above)."
fi

say "Uptime probe: requests to the app since the demo started"
t0=$(cat "${OUT_DIR}/t0" 2>/dev/null || echo 00:00:00)
k -n probe logs probe | awk -v t0="$t0" '$1 >= t0 {n++; if ($2 == "200") ok++; else bad++} END {printf "  %d requests, %d OK, %d failed\n", n, ok, bad+0}'

say "Who is in control now? OSS self-heal is off, so if drift snaps back, Akuity did it."
step "k -n ${APP_NS} scale deploy guestbook-ui --replicas=2"
for i in $(seq 1 20); do
  sleep 3
  r=$(k -n "${APP_NS}" get deploy guestbook-ui -o jsonpath='{.spec.replicas}')
  echo "  t+$((i * 3))s replicas=${r}"
  [[ "${r}" == "1" ]] && break
done
step "k -n argocd get app ${APP} -o jsonpath='OSS last sync: {.status.operationState.finishedAt}{\"\\n\"}'"
say "Compare with the Akuity UI: ${APP} shows a fresh self-heal sync just now."
