#!/usr/bin/env bash
# Simulate a site outage inside one k3d cluster's node, without touching the host.
#
#   outage.sh <site> link-down   drop traffic to the Akuity control plane only (Git, registries still reachable)
#   outage.sh <site> offline     drop everything leaving the site (internet gone; in-site traffic still works)
#   outage.sh <site> restore     remove all outage rules
#   outage.sh <site> status
#
# Rules live in an EDGE-OUTAGE chain in the raw table, hooked first into
# PREROUTING (pod traffic) and OUTPUT (node: kubelet, containerd). The raw table
# matters: kube-router periodically re-inserts its own FORWARD jump above any
# filter-table rule and ACCEPTs traffic for pods that have NetworkPolicies (all
# Akuity/Kargo agent pods), which silently ended earlier filter-table outages.
# kubectl from the laptop keeps working throughout.
set -euo pipefail
SITE="${1:?site, e.g. edge-sr-on}"; MODE="${2:?link-down|offline|restore|status}"
NODE="k3d-${SITE}-server-0"
: "${AKUITY_HOSTS:=e96rrp7fide5qg83-agentsvr.cdsvcs.akuity.cloud e96rrp7fide5qg83-cplane.cdsvcs.akuity.cloud}"

ipt() { docker exec "${NODE}" iptables -t raw "$@"; }
reset_chain() {
  ipt -N EDGE-OUTAGE 2>/dev/null || ipt -F EDGE-OUTAGE
  for c in PREROUTING OUTPUT; do
    ipt -C "$c" -j EDGE-OUTAGE 2>/dev/null || ipt -I "$c" 1 -j EDGE-OUTAGE
  done
}

case "${MODE}" in
  link-down)
    reset_chain
    for ip in $(for h in ${AKUITY_HOSTS}; do dig +short "$h" | grep -E '^[0-9.]+$'; done | sort -u); do
      ipt -A EDGE-OUTAGE -d "${ip}" -j DROP
    done
    ;;
  offline)
    reset_chain
    subnet=$(docker network inspect "k3d-${SITE}" -f '{{(index .IPAM.Config 0).Subnet}}')
    for cidr in 127.0.0.0/8 10.42.0.0/16 10.43.0.0/16 "${subnet}"; do
      ipt -A EDGE-OUTAGE -d "${cidr}" -j RETURN
    done
    # API server replies to the laptop (Docker Desktop delivers port-forwarded
    # connections from outside the k3d subnet), so kubectl keeps working.
    ipt -A EDGE-OUTAGE -p tcp --sport 6443 -j RETURN
    ipt -A EDGE-OUTAGE -j DROP
    ;;
  restore)
    for c in PREROUTING OUTPUT; do ipt -D "$c" -j EDGE-OUTAGE 2>/dev/null || true; done
    ipt -F EDGE-OUTAGE 2>/dev/null || true; ipt -X EDGE-OUTAGE 2>/dev/null || true
    ;;
  status) ;;
  *) echo "unknown mode ${MODE}" >&2; exit 2 ;;
esac

if ipt -S EDGE-OUTAGE >/dev/null 2>&1; then
  echo "${SITE}: outage rules active"; ipt -S EDGE-OUTAGE | sed 1d | sed 's/^/  /'
  for c in PREROUTING OUTPUT; do
    [[ "$(ipt -S "$c" | sed -n 2p)" == "-A $c -j EDGE-OUTAGE" ]] \
      || echo "  WARNING: EDGE-OUTAGE is not the first rule in raw/$c; the outage may leak" >&2
  done
else
  echo "${SITE}: online (no outage rules)"
fi
