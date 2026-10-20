#!/usr/bin/env bash
# Commit a new edge-config message and push it to one site's in-site Gitea.
# Goes through the Kubernetes API (port-forward), so it works while the site is offline.
set -euo pipefail
SITE="${1:?site}"; MSG="${2:?message, e.g. v2}"
DIR="$(cd "$(dirname "$0")" && pwd)"; R="${DIR}/out/edge-app-repo-${SITE}"
PORT=$((13000 + RANDOM % 1000))
kubectl --context "k3d-${SITE}" -n gitea port-forward svc/gitea "${PORT}:3000" >/dev/null 2>&1 & pf=$!
trap 'kill ${pf} 2>/dev/null' EXIT
sleep 3
URL="http://demo:demo-pass-123@localhost:${PORT}/demo/edge-app.git"
rm -rf "${R}"; git clone -q "${URL}" "${R}"
yq -i "(select(.kind == \"ConfigMap\") | .data.message) = \"${MSG}\"" "${R}/app.yaml"
git -C "${R}" -c user.name=demo -c user.email=demo@example.com commit -q -am "edge-config: ${MSG}"
git -C "${R}" push -q origin main 2>&1 | grep -v '^remote:' || true
echo "${SITE}: pushed message=${MSG} as $(git -C "${R}" rev-parse --short HEAD) at $(date -u +%H:%M:%S)Z"
