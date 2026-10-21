#!/usr/bin/env bash
# Commit a new edge-config message and push it to one site's in-site Gitea.
# Goes through the Kubernetes API (port-forward), so it works while the site is
# offline. Exits non-zero if nothing was pushed.
set -euo pipefail
SITE="${1:?site}"; MSG="${2:?message, e.g. v2}"
DIR="$(cd "$(dirname "$0")" && pwd)"; R="${DIR}/out/edge-app-repo-${SITE}"
# shellcheck source=lib.sh
source "${DIR}/lib.sh"

gitea_open "${SITE}"
trap gitea_close EXIT
rm -rf "${R}"; git clone -q "${GITEA_URL}" "${R}"
yq -i "(select(.kind == \"ConfigMap\") | .data.message) = \"${MSG}\"" "${R}/app.yaml"
if git -C "${R}" diff --quiet; then
  echo "${SITE}: message is already ${MSG}; nothing to push" >&2; exit 1
fi
git -C "${R}" -c user.name=demo -c user.email=demo@example.com commit -q -am "edge-config: ${MSG}"
git -C "${R}" push -q origin main
echo "${SITE}: pushed message=${MSG} as $(git -C "${R}" rev-parse --short HEAD) at $(date -u +%H:%M:%S)Z"
