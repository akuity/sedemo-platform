# App ↔ IaC Coupled Promotion (Kargo monorepo demo)

Demonstrates how Kargo orchestrates an Application pipeline that has hard
version dependencies on an Infrastructure pipeline, both living in the same
monorepo. Designed for a 30-minute customer walkthrough.

## What this demo answers

| Customer question | Mechanism in this demo |
|---|---|
| **Q1** — How does Kargo distinguish IaC vs App changes in a monorepo? | Two Warehouses with different subscriptions; the Cassandra Warehouse uses `git.includePaths` to scope to `iac/cassandra/**` |
| **Q2** — How do we block App promotion when IaC isn't at the required version? | App Stages list **two sources** in `requestedFreight` and use `availabilityStrategy: All` on the IaC source; a pre-deploy `http` step in `deploy-app` fails the promotion if the App's `-cassN` tag suffix doesn't match the IaC's `major` |
| **Q3** — How do we guarantee v6 → v7 → v8 with no skipping? | Downstream IaC Stages use `selectionPolicy: MatchUpstream` so they promote the Freight *currently in the upstream Stage*, not the newest in the Warehouse |
| **Q4** — Can we run agentless (only Git + VictoriaMetrics + GitHub API)? | `vm-smoke` AnalysisTemplate uses the Prometheus provider against VictoriaMetrics and the Web provider against the GitHub Deployments API. Delete the `argocd-update` step in `deploy-app` to go fully agentless |
| **Q5** — Can multiple component groups live under one "Product" view? | All five Stages and both Warehouses share a single Kargo `Project` (`app-iac-coupled`); the UI renders them as one graph |

## Pipeline shape

```
cassandra-iac-warehouse  (git, includePaths: iac/cassandra/**)
  iac-dev ──► iac-staging ──► iac-prod        [MatchUpstream]
                                  │
app-warehouse  (image, tag ^X.Y.Z-cassN$)     │
  app-dev ◄─── couples to iac-dev ◄───────────┘
   │
   └─► app-prod ◄─── couples to iac-prod
```

## Walkthrough

### Q1: path filtering (≈1 min)

Show `kargo/warehouses.yaml`. Two Warehouses, two scopes:
- `app-warehouse` watches an image registry; tag regex `^\d+\.\d+\.\d+-cass\d+$`
- `cassandra-iac-warehouse` watches `apps/demo-app-iac-coupled/iac/cassandra/**`

Trigger: a commit touching `iac/cassandra/version.yaml` produces **only** a
Cassandra Freight. A new App image push produces **only** an App Freight.

### Q2: cross-Freight dependency (≈3 min)

Open `kargo/stages.yaml` and point at `app-dev`. Two entries in
`requestedFreight` — one per Warehouse. The IaC entry uses
`availabilityStrategy: All` referencing `iac-dev`, so `app-dev` cannot promote
until Cassandra has cleared its dev stage.

Then open `deploy-app` in `kargo/promotion-tasks.yaml` — the `compat-check`
step parses `env/<env>/cassandra/version.yaml` and compares the `major` to the
suffix of the App image tag. If they diverge (`1.4.2-cass7` against IaC major
`8`), the step fails and the promotion log shows exactly why.

> **Alternative pattern:** a verification-based gate. Move the compat check
> into an AnalysisTemplate (similar shape to `cassandra-smoke`) and reference
> it from `app-dev.spec.verification`. Visible in the Kargo UI as a verification
> result rather than a promotion failure. Pick whichever the customer's SREs
> are likelier to act on.

### Q3: sequential catch-up (≈3 min)

Two layers of enforcement — present them as defense in depth.

**Layer 1 — declarative selection (`selectionPolicy: MatchUpstream`).** Show
`iac-staging` and `iac-prod` in `kargo/stages.yaml`:

```yaml
sources:
  stages: [iac-dev]
  selectionPolicy: MatchUpstream
```

`MatchUpstream` means the Stage promotes whatever Freight is **currently in**
the upstream Stage. If `iac-dev` is at v7 while v8 and v9 already exist in the
Warehouse, `iac-staging` will only see v7. As `iac-dev` advances to v8,
`iac-staging` becomes eligible for v8. No skipping during auto-promotion.

**Layer 2 — imperative deploy-time gate (semver step).** Show the
`semver-guard` step in `deploy-iac` (`kargo/promotion-tasks.yaml`). Two
`yaml-parse` steps extract the currently-deployed and incoming Freight
versions as semver strings; an `http` step's `successExpression` uses
Kargo's built-in [`semverDiff`](https://docs.kargo.io/user-guide/reference-docs/expressions#semverdiffversion1-version2)
and `semverParse(...).IncMajor()` to enforce "allow same-major or exactly +1
major; block downgrades and major skips":

```
semverDiff(incoming, current) != 'Major'
  || semverParse(incoming).Major() == semverParse(current).IncMajor().Major()
```

Worth knowing the function semantics: `semverDiff` returns the *magnitude* of
the change (`"None"` | `"Patch"` | `"Minor"` | `"Major"` | `"Metadata"` |
`"Incomparable"`) but not the direction — a v6→v8 jump and a v8→v6 downgrade
both return `"Major"`. The `semverParse(...).IncMajor()` half of the
expression is what pins the direction to "exactly the next major".

Why have both: `MatchUpstream` controls **selection** (which Freight gets
picked), the semver step controls **deploy** (whether the picked Freight
actually lands). The semver step catches the cases `MatchUpstream` can't:

- A manual promotion that hand-picks an out-of-order Freight
- Multi-upstream sources (where `MatchUpstream` is not applicable)
- Downgrade attempts (v8 → v6)

Demo move: in the Kargo UI, manually trigger a promotion of v9 against an env
sitting at v7. The Stage picks it up (no auto-promotion ordering applies to a
manual run), `semver-guard` fails with `9 - 7 = 2`, and the promotion log
shows exactly why it was blocked.

> **Honest caveat:** there is no first-class "FIFO at the Warehouse" knob in
> Kargo. The two-layer pattern above is how you compose strict ordering
> today. If a customer needs strict per-Warehouse arrival order independent
> of Stage state, surface it as a feature request.

### Q4: agentless feedback loop (≈4 min)

Two switches:

1. **Verification.** Open `kargo/analysis-templates.yaml`. `vm-smoke` has two
   metrics — a Prometheus provider against the VictoriaMetrics read endpoint,
   and a Web provider against the GitHub Deployments API. Neither needs an
   in-cluster agent on the target side; the AnalysisRun runs in Kargo's
   cluster and reaches out.

2. **Deploy.** In `deploy-app`, delete the trailing `argocd-update` step. Now
   Kargo's only deploy action is the git commit. An external CD (Flux running
   in the disconnected cluster, an out-of-band Terraform apply, etc.) picks
   it up. Kargo verifies the rollout entirely via external telemetry.

> **Honest framing:** "agentless" here means *no Akuity Agent in the target
> cluster*. Kargo itself still runs on Kubernetes and needs network reach to
> the VM endpoint and `api.github.com`. The customer's "Zero-Trust" goal is
> achievable, but it's a network/identity discussion, not a "feature toggle".

### Q5: component grouping (≈2 min)

One `Project: app-iac-coupled`, two Warehouses, five Stages. The Kargo UI
renders the whole pipeline as a single graph — that *is* the Product view.
For a comparison point, open `apps/demo-microservices` after this to show the
same pattern at higher cardinality (3 Warehouses, 12 Stages, still one graph).

If sub-grouping inside a Project becomes important to the customer, point at
Stage labels and the `kargo.akuity.io/color` annotation as the current
visual-grouping affordances.

## Files

```
apps/demo-app-iac-coupled/
├── argocd/
│   ├── appproject.yaml
│   └── application-set.yaml          # app-dev, app-prod Argo CD Applications
├── kargo/
│   ├── project.yaml                  # Project + ProjectConfig (auto-promotion)
│   ├── warehouses.yaml               # app + cassandra-iac Warehouses
│   ├── stages.yaml                   # 5 Stages with multi-source + MatchUpstream
│   ├── promotion-tasks.yaml          # deploy-iac, deploy-app (with compat-check)
│   └── analysis-templates.yaml       # cassandra-smoke, vm-smoke (agentless)
├── iac/cassandra/
│   └── version.yaml                  # source — cassandra-iac-warehouse watches this
├── env/                              # promotion targets
│   ├── dev/{app,cassandra}/
│   ├── staging/cassandra/
│   └── prod/{app,cassandra}/
├── kustomize/base/                   # minimal app Deployment
└── README.md
```

## Doc references

- Warehouses, path filters, `freightCreationPolicy`: https://docs.kargo.io/user-guide/how-to-guides/working-with-warehouses
- Stages, `requestedFreight`, `availabilityStrategy`, `selectionPolicy`: https://docs.kargo.io/user-guide/how-to-guides/working-with-stages
- Verification (AnalysisTemplate integration): https://docs.kargo.io/user-guide/how-to-guides/verification
- Promotion step reference:
  - `http`: https://docs.kargo.io/user-guide/reference-docs/promotion-steps/http
  - `git-commit`: https://docs.kargo.io/user-guide/reference-docs/promotion-steps/git-commit
  - `argocd-update`: https://docs.kargo.io/user-guide/reference-docs/promotion-steps/argocd-update
- Argo Rollouts analysis providers (for `prometheus` + `web`): https://argo-rollouts.readthedocs.io/en/stable/features/analysis/
