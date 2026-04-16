# team-daniel — Kargo Pipeline

Multi-warehouse, multi-microservice progressive delivery pipeline.

## Topology

```
warehouse-frontend ─────────────────────────► staging-frontend ─┐
                   ╲                                               ├──► integration ──► prod-us ─┐
                    ╲──► dev (both) ────────► staging-backend  ─┘                    prod-eu ─┴─► prod-global
                   ╱
warehouse-backend ─
```

## Stages

| Stage | Task | Auto? | Pattern |
|-------|------|-------|---------|
| `dev` | `promote-all` | ✅ | Both warehouses, kyverno policy gate |
| `staging-frontend` | `promote-frontend` | ✅ | Frontend only, 5 min soak from dev |
| `staging-backend` | `promote-backend` | ✅ | API + worker only, 5 min soak from dev |
| `integration` | `promote-all` + `slack-notify` | ✅ | Fan-in: both staging lanes must converge |
| `prod-us` | `promote-with-pr` | ❌ | PR gate, fan-out from integration |
| `prod-eu` | `promote-with-pr` | ❌ | PR gate, fan-out from integration |
| `prod-global` | `promote-with-github-action` | ❌ | GHA dispatch, fan-in: both prod regions |

## Warehouses

| Warehouse | Subscriptions | Triggers |
|-----------|--------------|---------|
| `warehouse-frontend` | `ghcr.io/dhpup/guestbook` image + git `services/frontend/` | New frontend tag or config change |
| `warehouse-backend` | `guestbook-api` image + `guestbook-worker` image + git `services/api/` + `services/worker/` | New API or worker tag, or backend config change |

## Files

- [warehouse.yaml](warehouse.yaml) — 2 warehouses with multiple subscriptions
- [stages.yaml](stages.yaml) — 7-stage pipeline
- [tasks.yaml](tasks.yaml) — 5 promotion tasks (per service tier + prod gates)
- [project.yaml](project.yaml) — Auto-promotion policies
- [analysis.yaml](analysis.yaml) — PokeAPI verification gates

## Shared Custom Steps

- `kyverno-policy-check` — Policy gate before any deployment (from `kargo-shared/`)
- `trivy-image` — Vulnerability scan on each image; blocks promotion if critical CVEs found (runs at `dev` for all 3 images)
- `teams-notify` — Posts a MessageCard to Microsoft Teams when integration promotes (from `kargo-shared/`)
  - Requires Kargo project secret `teams-webhook` with key `url`
