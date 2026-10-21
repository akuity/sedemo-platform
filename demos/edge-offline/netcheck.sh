#!/usr/bin/env bash
# What can this site reach right now? Akuity control plane, GitHub, in-site Gitea.
set -uo pipefail
SITE="${1:?site}"
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
chk() {
  local code
  code=$(kubectl --context "k3d-${SITE}" exec netcheck -- curl -s -o /dev/null -m 4 -w '%{http_code}' "$2" 2>/dev/null)
  if [[ "${code}" =~ ^[1-5][0-9][0-9]$ ]]; then printf '  %-22s reachable (%s)\n' "$1" "${code}"; else printf '  %-22s UNREACHABLE\n' "$1"; fi
}
echo "${SITE}:"
chk "Akuity control plane" "https://${AGENT_HOST}"
chk "GitHub" "https://github.com"
chk "in-site Gitea" "http://gitea.gitea.svc:3000/api/healthz"
