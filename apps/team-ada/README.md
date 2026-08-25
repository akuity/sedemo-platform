# Team Ada — Akkoma

Deploys [akkoma-helm](https://github.com/adamancini/akkoma-helm)'s
published chart (`oci://ghcr.io/adamancini/charts/akkoma`) directly to
`sedemo-primary` — nothing is vendored into this repo. Each environment's
`env/<stage>/release.yaml` pins the chart version and stage values; Argo
CD's `files` generator reads it to build a multi-source Application (chart
+ this repo's own path for the stage's `ExternalSecret`s).

Ported from a personal instance in
[`adamancini/argo-fleet`](https://github.com/adamancini/argo-fleet)
(`apps/akkoma/`), which keeps running independently on its own cluster —
this is a second, separate deployment, not a migration/cutover.

## Pipeline

```
Warehouse: akkoma (chart + image)  →  dev (auto)  →  staging (manual)  →  prod (manual)
```

## Stages

| Stage | Namespace | Auto-promote |
|-------|-----------|--------------|
| `dev` | `team-ada-dev` | yes |
| `staging` | `team-ada-staging` | no |
| `prod` | `team-ada-prod` | no |

## Why not vendor the chart

`akkoma-helm` is an independently maintained, versioned chart — copying it
in means manually re-syncing on every upstream release, which defeats the
point of it being published. The Warehouse's `chart:` subscription tracks
real chart SemVer releases directly.

## Secrets

See [`SECRETS.md`](./SECRETS.md) — `ExternalSecret`s pull the Postgres
password and Phoenix secret-key-base/signing-salt/release-cookie from AWS
Secrets Manager via the repo's existing `aws-secretsmanager`
`ClusterSecretStore`.

## Things to know

- The Warehouse is chart-only for chart-version discovery, plus an image
  subscription — no digest pinning needed; the chart's own default
  `image.tag`/`appVersion` tracks the akkoma app version already.
- Storage defaults (bundled Postgres StatefulSet), and TLS/ingress
  (disabled, placeholder domains) are deferred — see
  `argo-fleet`'s `docs/superpowers/specs/2026-08-25-akkoma-sedemo-platform-migration-design.md`
  for full design rationale and what's explicitly out of scope.
