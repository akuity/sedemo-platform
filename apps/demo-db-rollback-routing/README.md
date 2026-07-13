# demo-db-rollback-routing

One demo, three hard questions prospects actually ask:

1. How do database schema changes ride along with app promotions? (Flyway via an
   enterprise `CustomPromotionStep`)
2. What happens when a bad version reaches an environment? (Kargo 1.11
   `autoRollback` driven by Prometheus verification)
3. How do different artifacts get routed into different stages without polluting
   the main path? (separate Warehouses, tag-based PR previews, honest
   auto-promotion behavior)

The thesis tying them together: auto-rollback is only trustworthy when your
database strategy survives it. Rolling back re-promotes old Freight, which
re-runs the migration step against a newer schema. This demo shows why that is
safe here and what makes it safe.

## Architecture

```
preview lane (git tags only)
  PR + `deploy-preview` label -> GH Action tags head `preview-<PR#>`
  -> Warehouse `preview` (NewestTag, ^preview-) -> Stage preview (dead end)

main lane (image + migrations in one Freight)
  merge to main / new image tag
  -> Warehouse `main` -> dev -> staging -> prod
                          |       |          |
                       flyway  flyway     flyway      (EE custom step)
                               +verify    +verify     (error-rate, Prometheus)
                               +autoRollback          (ProjectConfig, Kargo 1.11)
```

Each stage namespace on `sedemo-primary` runs: the rollouts demo app (its UI can
dial in an error rate), a throwaway Postgres, pgweb for browsing
`flyway_schema_history`, and a load generator that keeps traffic flowing through
the ingress so verification always has samples.

**URLs:** `dbr-{stage}.akpdemoapps.link` (app) and
`dbr-{stage}-schema.akpdemoapps.link` (schema viewer).

Every promotion runs: `git-clone` (Freight commit to `./src`, main to `./out`)
-> `flyway-migrate` -> update `env/<stage>/image.yaml` -> commit/push ->
`argocd-update`. Migrations always come from the Freight commit, never branch
head. That detail is what makes rollbacks correct.

## Why rollback does not break the database

- Migrations are forward-only and expand/contract: additive, backward compatible
  with the previous app version. Community Flyway has no down-migrations, and
  that is fine.
- The shared `flyway-migrate` step (in `kargo-shared/`) passes
  `-ignoreMigrationPatterns=*:missing,*:future`, so promoting old Freight (whose
  checkout lacks already-applied migrations) validates cleanly and no-ops
  instead of failing.
- It also runs `flyway repair` first, clearing any failed-history row left by a
  non-transactional migration, and Flyway's advisory lock serializes concurrent
  runs.
- Reverting a bad schema change is a new forward migration promoted through the
  same pipeline, not a rollback.

## Demo script

1. **Main lane baseline.** Copy `db/demo-assets/V3__add_loyalty_tier.sql` into
   `db/migrations/` and merge to main. New Freight appears, dev auto-promotes,
   and the loyalty_tier column shows up in the dev schema viewer. Promote to
   staging and prod and watch the schema land env by env.
2. **Rapid freight honesty.** Push three quick commits. Auto-promotion creates a
   Promotion per Freight and walks the queue in order. Intermediates are NOT
   skipped; converging on newest is the end state, not the mechanism.
   Hard-cancel of queued promotions is unshipped (kargo issue #3108). The
   Warehouse `interval: 2m` coalesces commits only because this project has no
   webhook receivers; a webhook would mint one Freight per push.
3. **Preview routing.** Open a PR touching this app and add the `deploy-preview`
   label. The Action tags the head, the `preview` Warehouse discovers it, and
   the preview stage deploys the PR's chart and migrations against its own
   database. Nothing sources from the preview stage, so preview Freight never
   enters the main lane. Caveats to state out loud: previews are git-only
   provenance (the image is whatever `env/preview/image.yaml` pins), and Kargo
   never saw the label, only the tag.
4. **Auto-rollback on bad code.** Promote to staging, open the app UI and dial
   errors up. The error-rate verification fails (5xx over 5% through the
   ingress) and the autoRollback policy re-promotes the last good Freight.
   Point at the Flyway step in the rollback Promotion logs: it no-ops.
5. **Auto-rollback on bad migration.** Copy `db/demo-assets/V4__bad_migration.sql`
   into `db/migrations/` and merge. The Flyway step itself fails in dev (no
   rollback there, promotion just fails; dev has no autoRollback policy), or
   let it reach staging where `autoRollback.onPromotion` bounces it. Two
   failure planes, same recovery. Clean up by reverting the commit.

## Notes and limits

- Requires Kargo 1.11+ for `autoRollback` in ProjectConfig, and the Akuity EE
  `CustomPromotionStep` CRD (`ee.kargo.akuity.io/v1alpha1`).
- Postgres uses emptyDir (the cluster has no CSI driver, and it keeps the
  footprint minimal). A db pod restart wipes the schema; re-promote the
  stage's current Freight and Flyway rebuilds it.
- The `preview` Warehouse reports a discovery error until at least one
  `preview-*` tag exists in the repo. Bootstrap it once with
  `git tag preview-0 && git push origin preview-0`, or just run the preview
  beat (label a PR) and let the Action create the first tag.
- Stages shard to `sedemo-primary`, so the Flyway container runs in that
  cluster and reaches each stage's Postgres over cluster DNS
  (`db.demo-db-rollback-routing-<stage>.svc.cluster.local`).
- The AnalysisTemplate queries in-cluster Prometheus
  (`prometheus-server.prometheus.svc.cluster.local`). If verification executes
  anywhere other than the shard, switch the address to
  `https://prometheus.akpdemoapps.link`.
- The Flyway DB credential comes from AWS Secrets Manager key `kargo-flyway-db`
  via ESO (`secrets/flyway-db-secret.yaml`), then reaches the project via the
  `kargo.akuity.io/secret-sync: demo-db-rollback-routing` label: the agent
  pushes it from the `akuity` namespace on sedemo-primary into the project
  namespace, which is the only place the `secret()` expression looks (and the
  admission webhook blocks writing it there via GitOps). Two gotchas: the
  `eso-secret-store-kargo` Application has no automated sync policy, so it
  needs a manual sync after changes; and syncing to `kargo-shared-resources`
  does NOT work for `secret()`, only for repo creds. The password must match
  `db.password` in chart values (still demo-grade plaintext there, since the
  chart also provisions the throwaway Postgres it protects).
- Verification error rate is measured at the nginx ingress per namespace, so it
  needs the loadgen (in the chart) or real traffic to be meaningful. No traffic
  evaluates as healthy (`or vector(0)`).
