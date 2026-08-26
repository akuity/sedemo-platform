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
| `staging` | blue | no | External QE suite gate (http trigger + poll), Kargo verification analysis |
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

### External QE suite gate (beyond Kubernetes)
staging runs `qe-suite-gate` before anything is committed to git: a generic `http` step queues
a job on an external test runner, then a second `http` step polls until the run reports back.
While neither `successExpression` nor `failureExpression` matches, the step stays `Running` and
Kargo re-runs it — so the freight sits on the gate until QE actually answers. A failed run fails
the promotion and the freight never reaches `prod-canary`.

Nothing here is Kubernetes-specific or vendor-specific. Repointing `qeBaseURL` and `qeJob` in
`kargo/tasks.yaml` at a real Jenkins (`/job/<name>/buildWithParameters`, `/job/<name>/<n>/api/json`)
is the only change needed — no new Kargo step types, no wrapper service around Kargo.

The demo target is a mock runner in [`qe-mock/`](./qe-mock/) — a **stand-in, not a real Jenkins**.
It serves Jenkins-shaped endpoints and a small control page at
[qe.team-daniel.akpdemoapps.link](https://qe.team-daniel.akpdemoapps.link) where you can force the
next run to pass or fail and set how long it takes. It is fixed demo infrastructure, synced
straight from `main` by the `team-daniel-qe-mock` Application rather than promoted by Kargo.

### Canary rollout
prod-canary uses Argo Rollouts with a 20% canary weight, soaking for 1 minute before promoting to 100%. Requires a PR gate approval before the rollout starts.

## Namespaces

| Stage | Namespace |
|-------|-----------|
| dev | `team-daniel-dev` |
| staging-security | `team-daniel-staging-security` |
| staging | `team-daniel-staging` |
| qe-mock (support) | `team-daniel-qe` |
| prod-canary | `team-daniel-prod-canary` |

## Storytelling Points

- Trigger a promotion from a feature flag change (git freight) — show that Kargo tracks more than just images
- Open the QE control page, set the suite to **fail**, then promote to staging — watch the gate hold the freight and `prod-canary` stay unreachable. Flip it back to pass and re-promote.
- Point out that the gate is two plain `http` steps: Kargo orchestrates systems that have nothing to do with Kubernetes, so a Jenkins QE suite does not need a separate tool wrapped around Kargo
- Show the Trivy scan blocking a promotion for a vulnerable image at staging-security
- Show the OPA policy check rejecting a misconfigured manifest before it ever reaches git
- Open the PR gate at prod-canary and watch the canary rollout progress to 100%
- Show Teams notifications firing at each stage with dynamic freight metadata
