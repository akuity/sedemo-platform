#!/usr/bin/env bash
# Pre-demo: a k3d (k3s) cluster standing in for an on-prem site, running a
# self-hosted OSS Argo CD that manages three apps. Run this before the call.
set -euo pipefail
source "$(dirname "$0")/env.sh"

if ! k3d cluster get "${CLUSTER_NAME}" >/dev/null 2>&1; then
  k3d cluster create "${CLUSTER_NAME}" --no-lb --k3s-arg '--disable=traefik@server:0' --wait
fi

k create namespace argocd --dry-run=client -o yaml | k apply -f -
k apply -n argocd --server-side --force-conflicts \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${OSS_ARGOCD_VERSION}/manifests/install.yaml"
k -n argocd rollout status deploy/argocd-server --timeout=300s
k -n argocd rollout status statefulset/argocd-application-controller --timeout=300s
k -n argocd rollout status deploy/argocd-repo-server --timeout=300s

k apply -f "${DEMO_DIR}/oss/apps.yaml"

# Uptime probe: hits the app's Service twice a second for the whole demo and
# logs one line per request. Not managed by either Argo CD.
k create namespace probe --dry-run=client -o yaml | k apply -f -
k -n probe apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata: {name: probe}
spec:
  containers:
    - name: curl
      image: curlimages/curl:8.11.1
      command: [sh, -c]
      args:
        - |
          while true; do
            code=\$(curl -s -o /dev/null -m 2 -w '%{http_code}' http://guestbook-ui.${APP_NS}.svc || true)
            echo "\$(date -u +%H:%M:%S) \$code"
            sleep 0.5
          done
YAML

echo "Waiting for OSS apps to be Synced/Healthy..."
for app in edge-guestbook edge-helm-guestbook edge-kustomize-guestbook; do
  until [[ "$(k -n argocd get app "$app" -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null)" == "Synced/Healthy" ]]; do
    sleep 5
  done
  echo "  $app Synced/Healthy"
done
k -n probe wait --for=condition=Ready pod/probe --timeout=120s

echo
echo "OSS Argo CD admin password:"
k -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
echo "UI: kubectl --context ${KCTX} -n argocd port-forward svc/argocd-server 8080:443  ->  https://localhost:8080"
