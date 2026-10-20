#!/usr/bin/env bash
# Show the starting point and record pod identity before anything changes.
set -euo pipefail
source "$(dirname "$0")/env.sh"

say "Self-hosted Argo CD on this cluster, managing three apps"
step "k -n argocd get applications"
say "The running pods. Note the UIDs and start times."
snapshot | tee "${OUT_DIR}/before.txt"
say "How OSS Argo CD tracks what it owns (resource tracking annotation)"
step "k -n ${APP_NS} get deploy guestbook-ui -o jsonpath='{.metadata.annotations.argocd\.argoproj\.io/tracking-id}{\"\\n\"}'"
date -u +%H:%M:%S > "${OUT_DIR}/t0"
