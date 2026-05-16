# App ↔ IaC Coupled Promotion (Kargo monorepo demo)

Demonstrates how Kargo orchestrates an Application pipeline that has hard
version dependencies on an Infrastructure pipeline, both living in the same
monorepo. Designed for a 30-minute customer walkthrough.

The stateful infra in this demo is **PostgreSQL** (via the Bitnami chart),
chosen because `pg_upgrade` literally only supports adjacent-major upgrades
— a real-world version of the customer's "must go v6 → v7 → v8, no skipping"
constraint. The App uses `ghcr.io/akuity/sedemo-monorepo-rollouts-app`, the
same image the `demo-rollouts` pipeline ships.

## What this demo answers

| Customer question | Mechanism in this demo |
|---|---|
| **Q1** — How does Kargo distinguish IaC vs App changes in a monorepo? | Two Warehouses with disjoint subscriptions. `postgres-iac-warehouse` uses `git.includePaths: iac/postgres/**`; `app-warehouse` subscribes to the app image AND `app/**` |
| **Q2** — How do we block App promotion when IaC isn't at the required version? | App Stages list **two sources** in `requestedFreight` with `availabilityStrategy: All` on the IaC source; the App declares `requiredPostgresMajor` in `app/spec.yaml`; a pre-deploy `compat-check` step fails the promotion when it doesn't match the IaC-deployed PG major |
| **Q3** — How do we guarantee v14 → v15 → v16 with no skipping? | Two layers: declarative `selectionPolicy: MatchUpstream` on downstream Stages, plus an imperative `semver-guard` step using `semverDiff` + `semverParse(...).IncMajor()` |
| **Q4** — Can we run agentless (only Git + VictoriaMetrics + GitHub API)? | `vm-smoke` AnalysisTemplate uses the Prometheus provider against VictoriaMetrics and the Web provider against the GitHub Deployments API. Delete the `argocd-update` step in `deploy-app` to go fully agentless |
| **Q5** — Can multiple component groups live under one "Product" view? | All five Stages and both Warehouses share a single Kargo `Project` (`app-iac-coupled`); the UI renders them as one graph |

## Pipeline shape

```
postgres-iac-warehouse  (git, includePaths: iac/postgres/**)
  iac-dev ──► iac-staging ──► iac-prod        [MatchUpstream + semver-guard]
                                  │
app-warehouse  (image + git, includePaths: app/**)
  app-dev ◄─── couples to iac-dev ◄───────────┘
   │
   └─► app-prod ◄─── couples to iac-prod
```

## Walkthrough

### Q1: path filtering (≈1 min)

Show `kargo/warehouses.yaml`. Two Warehouses, three subscriptions, three scopes:
- `app-warehouse` watches the rollouts-app image (tags like `43-green`) **and**
  `apps/demo-app-iac-coupled/app/**`
- `postgres-iac-warehouse` watches `apps/demo-app-iac-coupled/iac/postgres/**`

Trigger: a commit touching `iac/postgres/version.yaml` produces **only** a
Postgres-IaC Freight. A new App image push, or a change to `app/spec.yaml`,
produces **only** an App Freight.

### Q2: cross-Freight dependency (≈3 min)

Open `kargo/stages.yaml` and point at `app-dev`. Two entries in
`requestedFreight` — one per Warehouse. The IaC entry uses
`availabilityStrategy: All` referencing `iac-dev`, so `app-dev` cannot promote
until Postgres has cleared its dev stage.

Then open `deploy-app` in `kargo/promotion-tasks.yaml` — the `compat-check`
step does:

```
int(outputs.appSpec.requiredMajor) == semverParse(outputs.iac.version).Major()
```

The App's `spec.yaml` says `requiredPostgresMajor: 16`; the IaC's
`env/<env>/postgres/version.yaml` is at chart `16.4.0`. They match, so the
promotion proceeds. Bump the App's required to `17` while IaC stays at `16`
and the promotion fails with the math visible in the log.

> **Alternative pattern:** a verification-based gate. Move the compat check
> into an AnalysisTemplate referenced from `app-dev.spec.verification`.
> Visible in the Kargo UI as a verification result rather than a promotion
> failure. Pick whichever the customer's SREs are likelier to act on.

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
the upstream Stage. If `iac-dev` is at PG 15 while 16 and 17 already exist in
the Warehouse, `iac-staging` will only see 15. As `iac-dev` advances to 16,
`iac-staging` becomes eligible for 16. No skipping during auto-promotion.

**Layer 2 — imperative deploy-time gate (semver step).** Show the
`semver-guard` step in `deploy-iac` (`kargo/promotion-tasks.yaml`). Two
`yaml-parse` steps extract the currently-deployed and incoming versions; an
`http` step's `successExpression` uses Kargo's built-in
[`semverDiff`](https://docs.kargo.io/user-guide/reference-docs/expressions#semverdiffversion1-version2)
and `semverParse(...).IncMajor()`:

```
semverDiff(incoming, current) != 'Major'
  || semverParse(incoming).Major() == semverParse(current).IncMajor().Major()
```

Worth knowing the function semantics: `semverDiff` returns the *magnitude* of
the change (`"None"` | `"Patch"` | `"Minor"` | `"Major"` | `"Metadata"` |
`"Incomparable"`) but not the direction — a 14→16 jump and a 16→14 downgrade
both return `"Major"`. The `semverParse(...).IncMajor()` half of the
expression is what pins the direction to "exactly the next major".

Why have both: `MatchUpstream` controls **selection** (which Freight gets
picked), the semver step controls **deploy** (whether the picked Freight
actually lands). The semver step catches the cases `MatchUpstream` can't:

- A manual promotion that hand-picks an out-of-order Freight
- Multi-upstream sources (where `MatchUpstream` is not applicable)
- Downgrade attempts (16 → 14)

Demo move: in the Kargo UI, manually trigger a promotion of `17.0.0` against
an env sitting at `15.x`. The Stage picks it up (no auto-promotion ordering
applies to a manual run), `semver-guard` fails because `17 != 15+1`, and the
promotion log shows exactly why it was blocked. Real-world parallel:
`pg_upgrade` would refuse the same jump.

> **Honest caveat:** there is no first-class "FIFO at the Warehouse" knob in
> Kargo. The two-layer pattern above is how you compose strict ordering today.
> If a customer needs strict per-Warehouse arrival order independent of Stage
> state, surface it as a feature request.

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
│   ├── warehouses.yaml               # app-warehouse (image + git) + postgres-iac-warehouse (git)
│   ├── stages.yaml                   # 5 Stages with multi-source + MatchUpstream
│   ├── promotion-tasks.yaml          # deploy-iac (with semver-guard) + deploy-app (with compat-check)
│   └── analysis-templates.yaml       # postgres-smoke + vm-smoke (agentless)
├── app/
│   └── spec.yaml                     # App's declared dependency: requiredPostgresMajor
├── iac/postgres/
│   └── version.yaml                  # source — postgres-iac-warehouse watches this
├── env/                              # promotion targets (rewritten on each promotion)
│   ├── dev/{app,postgres}/
│   ├── staging/postgres/
│   └── prod/{app,postgres}/
├── kustomize/base/                   # minimal app Deployment
└── README.md
```

## Doc references

- Expressions reference (semverDiff, semverParse, imageFrom): https://docs.kargo.io/user-guide/reference-docs/expressions
- Working with Warehouses (path filters, `freightCreationPolicy`): https://docs.kargo.io/user-guide/how-to-guides/working-with-warehouses
- Working with Stages (`requestedFreight`, `availabilityStrategy`, `selectionPolicy`): https://docs.kargo.io/user-guide/how-to-guides/working-with-stages
- Verification (AnalysisTemplate integration): https://docs.kargo.io/user-guide/how-to-guides/verification
- Promotion step reference:
  - `http`: https://docs.kargo.io/user-guide/reference-docs/promotion-steps/http
  - `yaml-parse`: https://docs.kargo.io/user-guide/reference-docs/promotion-steps/yaml-parse
  - `git-commit`: https://docs.kargo.io/user-guide/reference-docs/promotion-steps/git-commit
  - `argocd-update`: https://docs.kargo.io/user-guide/reference-docs/promotion-steps/argocd-update
- Argo Rollouts analysis providers (for `prometheus` + `web`): https://argo-rollouts.readthedocs.io/en/stable/features/analysis/
