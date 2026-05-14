# Team Daniel

Comprehensive demo pipeline showcasing advanced Kargo features: multiple warehouses (image, git config, feature flags), OPA policy enforcement, Trivy scanning, GitHub Actions integration, canary rollout, and Teams notifications.

## Pipeline

```
Warehouse: guestbook (image)  ──┐
Warehouse: features (git)     ──┤→ dev (auto)
Warehouse: config-dev (git)   ──┘       → staging-security (auto)
                                              → staging (manual)
                                                   → prod-canary (manual, PR gate)
```

Each stage has its own config warehouse (`config-{stage}`) tracking per-environment config changes independently.

## Stages

| Stage | Color | Auto-promote | Key capabilities |
|-------|-------|-------------|-----------------|
| `dev` | gray | yes | OPA policy check, Teams notification |
| `staging-security` | amber | yes | OPA policy, Trivy CVE scan, GitHub Actions dispatch (integration tests), Teams notification |
| `staging` | blue | no | Kargo verification analysis |
| `prod-canary` | green | no | PR gate, canary rollout (20% → 100% over 1 min), Teams notification |

## Key Concepts

### Multiple warehouse subscriptions
Image changes, feature flag changes, and per-environment config changes are tracked as separate freight sources. A promotion can be triggered by any one of them independently.

### OPA policy enforcement
`policy/kubernetes.rego` runs at dev and staging-security, blocking promotions that violate policy before anything is committed to git.

### Trivy scanning
staging-security runs a Trivy CVE scan against the candidate image. A high/critical finding fails the promotion.

### GitHub Actions dispatch
staging-security triggers an integration test workflow in GitHub Actions and waits for the result before proceeding.

### Canary rollout
prod-canary uses Argo Rollouts with a 20% canary weight, soaking for 1 minute before promoting to 100%. Requires a PR gate approval before the rollout starts.

## Namespaces

| Stage | Namespace |
|-------|-----------|
| dev | `team-daniel-dev` |
| staging-security | `team-daniel-staging-security` |
| staging | `team-daniel-staging` |
| prod-canary | `team-daniel-prod-canary` |

## Storytelling Points

- Trigger a promotion from a feature flag change (git freight) — show that Kargo tracks more than just images
- Show the Trivy scan blocking a promotion for a vulnerable image at staging-security
- Show the OPA policy check rejecting a misconfigured manifest before it ever reaches git
- Open the PR gate at prod-canary and watch the canary rollout progress to 100%
- Show Teams notifications firing at each stage with dynamic freight metadata
