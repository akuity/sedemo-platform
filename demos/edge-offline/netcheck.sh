#!/usr/bin/env bash
# What can this site reach right now? Akuity control plane, GitHub, in-site Gitea.
set -uo pipefail
SITE="${1:?site}"
chk() {
  local code
  code=$(kubectl --context "k3d-${SITE}" exec netcheck -- curl -s -o /dev/null -m 4 -w '%{http_code}' "$2" 2>/dev/null)
  if [[ "${code}" =~ ^[1-5][0-9][0-9]$ && "${code}" != "000" ]]; then printf '  %-22s reachable (%s)\n' "$1" "${code}"; else printf '  %-22s UNREACHABLE\n' "$1"; fi
}
echo "${SITE}:"
chk "Akuity control plane" "https://e96rrp7fide5qg83-agentsvr.cdsvcs.akuity.cloud"
chk "GitHub" "https://github.com"
chk "in-site Gitea" "http://gitea.gitea.svc:3000/api/healthz"
