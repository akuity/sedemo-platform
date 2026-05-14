# Utilities

Non-demo infrastructure components that support the demo environment. Managed by ArgoCD only — no Kargo pipeline.

## How It Works

A single ApplicationSet scans `utilities/*` directories in `akuity/sedemo-monorepo` and creates one ArgoCD app per subdirectory:

- App name: `{directory_basename}-app`
- Source path: `utilities/{directory_basename}/k8s`
- Namespace: `utilities`
- Cluster: `sedemo-primary`

Adding a new utility tool is as simple as creating a new directory under `utilities/` in sedemo-monorepo with a `k8s/` subfolder containing manifests. ArgoCD picks it up automatically.

## Notes

- Automated sync with prune enabled
- `CreateNamespace=true` — the `utilities` namespace is created automatically
