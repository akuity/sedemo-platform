# Demo Snow

Demonstrates ServiceNow change management integration with a multi-region Kargo pipeline. A new image triggers automated deployments through dev and staging, then at prod a ServiceNow change request is created and must reach "Implement" state before the regional fan-out proceeds.

## Pipeline

```
Warehouse (image + git)
  → dev      Prometheus verification + hello-world custom step; auto-promote
  → staging  e2e verification; manual gate
  → prod     renders manifests for 3 regions; creates + waits on ServiceNow CR; fan-out
    → prod-amer-east  auto-promote
    → prod-amer-west  auto-promote
    → prod-emea       auto-promote
```

## Key Concepts

### Verification at every stage
- **dev**: Prometheus-based HTTP success rate check against `snow-demo-dev` namespace
- **staging**: End-to-end verification via `e2e-verification` AnalysisTemplate

### ServiceNow lifecycle in prod
The `prod` stage handles the full ITSM workflow in a single promotion:
1. Renders Helm manifests for all three regions and commits them to git
2. Creates a ServiceNow change request (`snow-create`) with impact/urgency metadata and a link to the Kargo promotion
3. Blocks on `snow-wait-for-condition` until the ticket reaches state `-1` (Implement)
4. Updates the ticket to "Review" after manifests are committed

Regional stages (`prod-amer-east`, `prod-amer-west`, `prod-emea`) auto-promote once `prod` completes, copying region-specific manifests to their own env branches and syncing the Argo CD apps.

### Slack notification for staging PR
When `push-manifests` runs with `asPR: "true"`, a Slack message is sent to `kargo-notification` with the PR link. Staging in this demo uses a direct push (not PR), so the notification fires on PR-based workflows when `asPR` is set by a caller.

### Reusable PromotionTasks
`prepare-workdir` and `push-manifests` are shared `PromotionTask` resources reused across all stages. The `push-manifests` task supports both direct-push and PR-based flows controlled by the `asPR` variable.

## Required Secrets

| Secret | Keys | Used by |
|--------|------|---------|
| `kargo-step-snow` | `api-token` | `snow-create`, `snow-wait-for-condition`, `snow-update` |

## URLs

- dev: `dev.akpdemoapps.link`
- staging: `staging.akpdemoapps.link`
- prod-amer-east: `snow-demo-prod-amer-east.akpdemoapps.link`
- prod-amer-west: `snow-demo-prod-amer-west.akpdemoapps.link`
- prod-emea: `snow-demo-prod-emea.akpdemoapps.link`

## Storytelling Points

- Show the ServiceNow CR being created automatically when prod promotion starts
- Open the SNOW ticket and approve it to "Implement" — watch Kargo unblock and the regional stages auto-promote
- Contrast with the active-active demo: here SNOW create/wait/update all happen in a single `prod` stage rather than being split across `approve` and `close`
