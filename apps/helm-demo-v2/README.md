# Helm Demo V2

Multi-cluster, multi-environment deployment of the Kubernetes Dashboard using Kustomize with embedded Helm charts and synchronized sync waves. Demonstrates cluster-selector-based targeting and ordered multi-component rollout.

## Environments

| Env | Namespace | Cluster label |
|-----|-----------|---------------|
| dev | `kd-dev` | `dev: 'true'` |
| stage | `kd-stage` | `stage: 'true'` |
| prod | `kd-prod` | `prod: 'true'` |

Apps are named `kd-{env}-{cluster_name}` — one ArgoCD app per matching cluster per environment.

## Chart

`kubernetes-dashboard` v7.14.0 from `https://wenerme.github.io/charts`, rendered via Kustomize `helmCharts` directive.

## Sync Waves

Three-wave deployment ensures correct startup order:

| Wave | Components |
|------|------------|
| 1 | API server |
| 2 | Web UI |
| 3 | Kong gateway |

## Notes

- No Kargo configuration — ArgoCD-only, cluster selector drives targeting
- Each environment's `values.yaml` and wave patches live under `env/{dev,stage,prod}/`
- Automated sync with prune enabled
