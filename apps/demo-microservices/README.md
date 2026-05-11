# Kargo Microservices Demo

This example deploys the [GCP Microservices Demo](https://github.com/GoogleCloudPlatform/microservices-demo) using Kargo and Argo CD, demonstrating two promotion patterns across three independent pipelines.

## Patterns demonstrated

### Grouped services (backend pipeline)
Seven backend services share a single Warehouse and travel together as a unit. A single promotion deploys all seven services atomically — if one image is updated, the entire group promotes together.

### Ordered services (frontend pipeline)
Four frontend services each have their own Kargo Stage, promoting one at a time in a fixed sequence. Each stage gates on the previous one completing successfully, giving fine-grained visibility into which service is being promoted.

### Independent pipeline (loadgenerator)
The load generator runs its own isolated pipeline, independent of both the backend and frontend flows.

## Pipelines

```
backend-group warehouse
  backend-dev ──► backend-prod

frontend-group warehouse
  adservice-dev ──► recommendationservice-dev ──► shoppingassistantservice-dev ──► frontend-dev
                                                                                        │
  adservice-prod ──► recommendationservice-prod ──► shoppingassistantservice-prod ──► frontend-prod

loadgenerator warehouse
  loadgen-dev ──► loadgen-prod
```

## Kargo resources

| Resource | File | Purpose |
|---|---|---|
| 3 Warehouses | `kargo/warehouses.yaml` | Monitor image registries for `backend-group`, `frontend-group`, and `loadgenerator` |
| 12 Stages | `kargo/stages.yaml` | Represent each environment/service step in the promotion pipelines |
| 3 PromotionTasks | `kargo/promotion-tasks.yaml` | Reusable step sequences for `deploy-backend`, `deploy-frontend-service`, and `deploy-loadgenerator` |

## Argo CD resources

| Resource | File | Apps generated |
|---|---|---|
| ApplicationSet (backend) | `argocd/application-set-backend.yaml` | `backend-dev`, `backend-prod` |
| ApplicationSet (frontend) | `argocd/application-set-frontend.yaml` | `adservice-dev/prod`, `recommendationservice-dev/prod`, `shoppingassistantservice-dev/prod`, `frontend-dev/prod` |
| ApplicationSet (loadgenerator) | `argocd/application-set-loadgenerator.yaml` | `loadgenerator-dev`, `loadgenerator-prod` |

## Repository layout

```
apps/demo-microservices/
├── argocd/             # ApplicationSets and AppProject
├── kargo/              # Warehouses, Stages, PromotionTasks
├── kustomize/
│   └── base/           # Per-service kustomize bases
└── env/
    ├── dev/            # Per-service overlays for dev (image tags updated by Kargo)
    └── prod/           # Per-service overlays for prod (image tags updated by Kargo)
```

Each promotion writes updated image tags into the relevant `env/<stage>/<service>/kustomization.yaml` and triggers an Argo CD sync.
