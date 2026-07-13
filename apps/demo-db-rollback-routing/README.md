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

## Demo script (repeatable; no resets between runs)

Every beat is driven by `db/demo-assets/new-migration.sh`, which generates a
fresh timestamp-versioned migration each time. Nothing needs reverting and no
database ever needs wiping; schema history and release notes just accumulate,
which is itself part of the story.

1. **Main lane baseline.** Run
   `./db/demo-assets/new-migration.sh "Shipped loyalty tiers"` and push to
   main. New Freight appears, dev auto-promotes, and the new release_notes row
   shows up in the dev schema viewer. Watch it land env by env as staging
   auto-promotes and you promote prod.
2. **Rapid freight honesty.** Generate and push three migrations as separate
   quick commits. Auto-promotion creates a Promotion per Freight and walks the
   queue in order. Intermediates are NOT skipped; converging on newest is the
   end state, not the mechanism. Hard-cancel of queued promotions is unshipped
   (kargo issue #3108). The Warehouse `interval: 2m` coalesces commits only
   because this project has no webhook receivers; a webhook would mint one
   Freight per push.
3. **Preview routing.** Open a PR touching this app and add the `deploy-preview`
   label. The Action tags the head, the `preview` Warehouse discovers it, and
   the preview stage deploys the PR's chart and migrations against its own
   database. Nothing sources from the preview stage, so preview Freight never
   enters the main lane. Caveats to state out loud: previews are git-only
   provenance (the image is whatever `env/preview/image.yaml` pins), and Kargo
   never saw the label, only the tag.
4. **Auto-rollback on bad code.** Generate a migration, push, and let the new
   Freight promote to staging. During the ~90 second verification window, open
   the staging app UI and dial errors up. The error-rate verification fails
   (5xx over 5% through the ingress) and the autoRollback policy re-promotes
   the last good Freight. Point at the Flyway step in the rollback Promotion
   logs: it no-ops. IMPORTANT: dial errors back to zero as soon as the
   rollback promotion appears, or its own verification fails too and rollback
   fires again (the error toggle lives in the app process, which the rollback
   does not restart when the image tag is unchanged).
5. **Failed migration.** Run `./new-migration.sh --bad`, push, and watch the
   Flyway step fail the dev promotion (dev has no autoRollback; the pipeline
   simply refuses the Freight, and staging never sees it because it only
   sources dev-verified Freight). Recover fix-forward: `./new-migration.sh
   --fix`, push, done. No revert: Flyway never recorded the failed migration,
   so editing its file is safe, and the step's built-in `flyway repair`
   clears the failed history row.

## Notes and limits

- Requires Kargo 1.11+ for `autoRollback` in ProjectConfig, and the Akuity EE
  `CustomPromotionStep` CRD (`ee.kargo.akuity.io/v1alpha1`).
- Postgres uses emptyDir (the cluster has no CSI driver, and it keeps the
  footprint minimal). A db pod restart wipes the schema; re-promote the
  stage's current Freight and Flyway rebuilds it.
- The `preview` Warehouse reports a discovery error whenever zero `preview-*`
  tags exist, including after the Action deletes a closed PR's tag. Push a
  permanent `git tag preview-0 && git push origin preview-0` once and leave it:
  the Warehouse then always has a fallback and stays healthy between demos.
- Stages shard to `sedemo-primary`, so the Flyway container runs in that
  cluster and reaches each stage's Postgres over cluster DNS
  (`db.demo-db-rollback-routing-<stage>.svc.cluster.local`).
- The AnalysisTemplate queries in-cluster Prometheus
  (`prometheus-server.prometheus.svc.cluster.local`). If verification executes
  anywhere other than the shard, switch the address to
  `https://prometheus.akpdemoapps.link`.
- The Flyway DB credential comes from AWS Secrets Manager key `kargo-flyway-db`
  via ESO (`secrets/flyway-db-secret.yaml`), synced by the agent into
  `kargo-shared-resources` and read in promotions with
  `sharedSecret("flyway-db")`. Do not use `secret()` for it: that function only
  reads the project's own namespace (which GitOps cannot write to; the
  admission webhook blocks it) and silently returns an empty map when nothing
  is there. Also note the `eso-secret-store-kargo` Application has no automated
  sync policy, so it needs a manual sync after changes. The password must match
  `db.password` in chart values (still demo-grade plaintext there, since the
  chart also provisions the throwaway Postgres it protects).
- Verification error rate is measured at the nginx ingress per namespace, so it
  needs the loadgen (in the chart) or real traffic to be meaningful. No traffic
  evaluates as healthy (`or vector(0)`).
