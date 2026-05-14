# Active-Active Demo

Demonstrates a multi-region high-availability deployment pipeline using Kargo. The same version of the app runs simultaneously in geographically distributed regions (modeled as separate namespaces/clusters).

## Pipeline

```
Warehouse (image + git)
  → dev-east ──┐
  → dev-west ──┘ ← convergence gate (both must pass before staging)
  → staging        manual gate; deploys east + west simultaneously
  → approve        creates ServiceNow CR, waits for "Implement" state (1m soak)
  → prod-east      auto-promote
  → prod-west      auto-promote (2m soak after prod-east)
  → close          closes the ServiceNow CR (2m soak after prod-west)
```

## Key Concepts

### Parallel dev + convergence gate
`dev-east` and `dev-west` both source directly from the warehouse and promote in parallel. The `staging` stage uses `availabilityStrategy: All`, meaning freight must have successfully passed through **both** dev regions before it can advance. A version that only works in one region cannot reach staging.

### Simultaneous multi-region staging
The `staging` stage renders Helm manifests for both `-east` and `-west` in a single promotion and triggers both Argo CD apps. This keeps the two regions in lockstep through staging.

### Sequential prod rollout with soak
`prod-east` deploys first (auto-promoted from `approve`). `prod-west` only auto-promotes after a **2-minute soak** on `prod-east`, giving time to catch region-specific issues before rolling the second region.

### ServiceNow change management lifecycle
- `approve` creates a change request via `snow-create` and blocks on `snow-wait-for-condition` until the ticket reaches `state=-1` (Implement). The ticket's `sys_id` is stored on the freight using `set-metadata`.
- `close` retrieves the `sys_id` via `freightMetadata()` and updates the ticket through Review → Closed after both prod regions are healthy.

### Policy enforcement at promotion time
Dev stages run `kyverno-policy-check` after rendering manifests, enforcing compliance before anything is committed to git.

### GitOps manifest layout
Each stage renders manifests via `helm-template` and commits them to `active-active/deploy/targets/{env}/manifests.yaml`. Argo CD syncs each environment from its own path in the repo.

## Argo CD Apps (via ApplicationSet)

| App | Kargo Stage | Git Path |
|-----|-------------|----------|
| `active-active-dev-east` | `dev-east` | `active-active/deploy/targets/dev-east` |
| `active-active-dev-west` | `dev-west` | `active-active/deploy/targets/dev-west` |
| `active-active-staging-east` | `staging` | `active-active/deploy/targets/staging-east` |
| `active-active-staging-west` | `staging` | `active-active/deploy/targets/staging-west` |
| `active-active-prod-east` | `prod-east` | `active-active/deploy/targets/prod-east` |
| `active-active-prod-west` | `prod-west` | `active-active/deploy/targets/prod-west` |

`approve` and `close` are pure Kargo orchestration stages with no corresponding Argo CD app.

## Auto-promotion Policy

Auto-promotion is enabled for all stages **except `staging`**, which is the sole manual gate in the pipeline:

| Stage pattern | Auto-promote |
|---------------|-------------|
| `dev.*` | yes |
| `approve.*` | yes |
| `prod.*` | yes |
| `close.*` | yes |
| `staging` | **no — manual gate** |

## Storytelling Points

- Show the convergence gate in action: promote a freight to `dev-east` but block `dev-west` and observe that `staging` stays locked
- Show the ServiceNow CR being created in `approve` and how the ticket `sys_id` travels downstream via freight metadata to `close`
- Show the sequential soak between `prod-east` → `prod-west` → `close`
- Point out the Kyverno policy check running at dev promotion time

## URLs

- App: `{stage}.ha.akpdemoapps.link` (e.g. `dev-east.ha.akpdemoapps.link`)
