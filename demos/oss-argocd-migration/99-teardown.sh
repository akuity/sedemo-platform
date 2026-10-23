#!/usr/bin/env bash
# Remove the demo apps and project from Akuity, unregister the cluster, delete the kind cluster.
# Needs an argocd CLI session on the instance: argocd login ${ARGOCD_CONTEXT} --sso --grpc-web
set -euo pipefail
source "$(dirname "$0")/env.sh"

APPS=(edge-guestbook edge-helm-guestbook edge-kustomize-guestbook)
for app in "${APPS[@]}"; do
  argocd --argocd-context "${ARGOCD_CONTEXT}" app delete "${app}" --cascade=false -y || true
done
# `app delete --wait` never returns over grpc-web, so poll until they are gone.
for app in "${APPS[@]}"; do
  for _ in $(seq 1 40); do
    argocd --argocd-context "${ARGOCD_CONTEXT}" app get "${app}" -o json >/dev/null 2>&1 || break
    sleep 3
  done
  if argocd --argocd-context "${ARGOCD_CONTEXT}" app get "${app}" -o json >/dev/null 2>&1; then
    echo "${app} still present on the instance after 2 min; delete it in the UI." >&2
  fi
done
# The edge-site AppProject is left in place (re-applied each run). Deleting it
# needs RBAC on `projects, delete, edge-site`; the instance's `*/*` object
# pattern covers apps (project/app) but not projects. Remove it in the UI if needed.
akuity argocd cluster delete "${AK_FLAGS[@]}" "${CLUSTER_NAME}" || true
kind delete cluster --name "${CLUSTER_NAME}"
rm -f "${OUT_DIR}"/*.yaml "${OUT_DIR}"/*.txt "${OUT_DIR}"/t0
