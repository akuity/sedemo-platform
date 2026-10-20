#!/usr/bin/env bash
# Retire OSS Applications once Akuity owns them. The finalizer is removed first
# so the delete does NOT cascade -- a default delete here would remove the live
# workloads Akuity is now managing.  Usage: 03b-retire.sh [app ...]
set -euo pipefail
source "$(dirname "$0")/env.sh"

for app in "${@:-${APP}}"; do
  step "k -n argocd patch app ${app} --type merge -p '{\"metadata\":{\"finalizers\":null}}'"
  step "k -n argocd delete app ${app}"
done
step "k -n ${APP_NS} get deploy,pods"
