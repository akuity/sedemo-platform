# shellcheck shell=bash
# Shared settings for the OSS Argo CD -> Akuity migration demo.
# Override any of these in the environment before running a script.

: "${CLUSTER_NAME:=edge-site-1}"                 # k3d cluster AND Akuity cluster name
: "${KCTX:=k3d-${CLUSTER_NAME}}"                # kube context for the k3d cluster
: "${OSS_ARGOCD_VERSION:=v3.5.5}"                # use a v2.x tag to rehearse label tracking
: "${AKUITY_ORG:=demo}"
: "${AKUITY_INSTANCE:=se-demo-iac}"
: "${ARGOCD_CONTEXT:=argo.akpdemoapps.link}"     # argocd CLI context for that instance
: "${APP:=edge-guestbook}"                       # the app migrated live, one at a time
: "${APP_NS:=guestbook}"

DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${DEMO_DIR}/out"
mkdir -p "${OUT_DIR}"

k() { kubectl --context "${KCTX}" "$@"; }

# Print a command, wait for Enter when PAUSE=1 (live demo), then run it.
step() {
  printf '\n\033[1;36m$ %s\033[0m\n' "$*"
  if [[ "${PAUSE:-0}" == "1" ]]; then read -r -p "  [enter to run] " _; fi
  eval "$@"
}

say() { printf '\n\033[1;33m# %s\033[0m\n' "$*"; }

AK_FLAGS=(--organization-name "${AKUITY_ORG}" --instance-name "${AKUITY_INSTANCE}")

# Rewrite OSS Argo CD manifests for the Akuity instance: drop server-side
# fields, and point "this cluster" destinations at the registered agent cluster.
# Everything else (name, project, source, sync policy) stays exactly as-is;
# the Application name is part of the resource tracking id, so it must not change.
to_akuity() {
  CLUSTER_NAME="${CLUSTER_NAME}" yq '
    del(.status, .operation,
        .metadata.uid, .metadata.resourceVersion, .metadata.generation,
        .metadata.creationTimestamp, .metadata.managedFields,
        .metadata.annotations."kubectl.kubernetes.io/last-applied-configuration")
    | .metadata.namespace = "argocd"
    | (select(.kind == "Application") | .spec.destination
        | select(.server == "https://kubernetes.default.svc" or .name == "in-cluster"))
        |= (del(.server) | .name = strenv(CLUSTER_NAME))
    | (select(.kind == "AppProject") | .spec.destinations[]
        | select(.server == "https://kubernetes.default.svc" or .name == "in-cluster"))
        |= (del(.server) | .name = strenv(CLUSTER_NAME))
  ' "$@"
}

# Pod identity for every demo namespace: if these UIDs/restarts are unchanged
# after cutover, nothing was redeployed.
snapshot() {
  k get pods -A -l 'app in (guestbook-ui,helm-guestbook)' --sort-by=.metadata.namespace \
    -o custom-columns='NAMESPACE:.metadata.namespace,POD:.metadata.name,UID:.metadata.uid,RESTARTS:.status.containerStatuses[0].restartCount,STARTED:.status.startTime' \
    2>/dev/null || true
}
