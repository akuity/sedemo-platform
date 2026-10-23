#!/usr/bin/env bash
# Simulate a site outage inside one kind cluster's node, without touching the host.
#
#   outage.sh <site> link-down   drop traffic to the Akuity control planes (Argo CD + Kargo) only;
#                                Git, registries and in-site services stay reachable
#   outage.sh <site> offline     drop everything leaving the site (internet gone; in-site traffic still works)
#   outage.sh <site> restore     remove all outage rules
#   outage.sh <site> status
#
# Rules live in an EDGE-OUTAGE chain in the raw table (IPv4 and IPv6), hooked
# first into PREROUTING (pod traffic) and OUTPUT (node: kubelet, containerd).
# The raw table is used because CNI/NetworkPolicy controllers rewrite the filter
# table: on k3s, kube-router re-inserted its FORWARD jump above ours and ACCEPTed
# traffic for policy-selected pods (all Akuity/Kargo agent pods), silently ending
# outages. kubectl from the laptop keeps working throughout.
set -euo pipefail
SITE="${1:?site, e.g. edge-sr-on}"; MODE="${2:?link-down|offline|restore|status}"
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
NODE="$(knode "${SITE}")"
POD_CIDR=10.244.0.0/16   # kind defaults
SVC_CIDR=10.96.0.0/12

ipt()  { docker exec "${NODE}" iptables  -t raw "$@"; }
ip6t() { docker exec "${NODE}" ip6tables -t raw "$@"; }
reset_chain() {  # <ipt|ip6t>
  "$1" -N EDGE-OUTAGE 2>/dev/null || "$1" -F EDGE-OUTAGE
  for c in PREROUTING OUTPUT; do
    "$1" -C "$c" -j EDGE-OUTAGE 2>/dev/null || "$1" -I "$c" 1 -j EDGE-OUTAGE
  done
}
remove_chain() {  # <ipt|ip6t>
  for c in PREROUTING OUTPUT; do "$1" -D "$c" -j EDGE-OUTAGE 2>/dev/null || true; done
  "$1" -F EDGE-OUTAGE 2>/dev/null || true; "$1" -X EDGE-OUTAGE 2>/dev/null || true
}
# kind puts every cluster on the shared "kind" network (dual-stack).
kind_subnet() {  # <4|6>
  docker network inspect kind -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}' | tr ' ' '\n' \
    | if [[ "$1" == 6 ]]; then grep ':'; else grep -v ':'; fi | grep -v '^$' | head -1
}

case "${MODE}" in
  link-down)
    # shellcheck disable=SC2086 # AKUITY_HOSTS is a space-separated list
    ips=$(for h in ${AKUITY_HOSTS}; do dig +short "$h" | grep -E '^[0-9.]+$'; done | sort -u)
    [[ -n "${ips}" ]] || { echo "could not resolve any of: ${AKUITY_HOSTS}" >&2; exit 1; }
    remove_chain ip6t
    reset_chain ipt
    for ip in ${ips}; do
      ipt -A EDGE-OUTAGE -d "${ip}" -j DROP
    done
    ;;
  offline)
    reset_chain ipt
    for cidr in 127.0.0.0/8 "${POD_CIDR}" "${SVC_CIDR}" "$(kind_subnet 4)"; do
      ipt -A EDGE-OUTAGE -d "${cidr}" -j RETURN
    done
    # API server replies to the laptop (port-forwarded connections can arrive
    # from outside the kind subnet), so kubectl keeps working.
    ipt -A EDGE-OUTAGE -p tcp --sport 6443 -j RETURN
    ipt -A EDGE-OUTAGE -j DROP
    reset_chain ip6t
    for cidr in ::1/128 fe80::/10 "$(kind_subnet 6)"; do
      [[ -n "${cidr}" ]] && ip6t -A EDGE-OUTAGE -d "${cidr}" -j RETURN
    done
    ip6t -A EDGE-OUTAGE -p tcp --sport 6443 -j RETURN
    ip6t -A EDGE-OUTAGE -j DROP
    ;;
  restore)
    remove_chain ipt; remove_chain ip6t
    ;;
  status) ;;
  *) echo "unknown mode ${MODE}" >&2; exit 2 ;;
esac

if ipt -S EDGE-OUTAGE >/dev/null 2>&1; then
  echo "${SITE}: outage rules active"; ipt -S EDGE-OUTAGE | sed 1d | sed 's/^/  /'
  ip6t -S EDGE-OUTAGE 2>/dev/null | sed 1d | sed 's/^/  (v6) /'
  for c in PREROUTING OUTPUT; do
    [[ "$(ipt -S "$c" | sed -n 2p)" == "-A $c -j EDGE-OUTAGE" ]] \
      || echo "  WARNING: EDGE-OUTAGE is not the first rule in raw/$c; the outage may leak" >&2
  done
else
  echo "${SITE}: online (no outage rules)"
fi
