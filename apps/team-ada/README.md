# Team Ada — Akkoma

Deploys [akkoma-helm](https://github.com/adamancini/akkoma-helm)'s
published chart (`oci://ghcr.io/adamancini/charts/akkoma`) directly to
`sedemo-primary` — nothing is vendored into this repo. Each environment's
`env/<stage>/release.yaml` pins the chart version and stage values; Argo
CD's `files` generator reads it to build a multi-source Application (chart
+ this repo's own path for the stage's `ExternalSecret`s).

## Pipeline

```text
Warehouse: akkoma (chart + image)  →  dev (auto)  →  staging (manual)  →  prod (manual)
```

## Stages

| Stage | Namespace | Auto-promote |
| ------- | ----------- | -------------- |
| `dev` | `team-ada-dev` | yes |
| `staging` | `team-ada-staging` | no |
| `prod` | `team-ada-prod` | no |

## Secrets

See [`SECRETS.md`](./SECRETS.md) — `ExternalSecret`s pull the Postgres
password and Phoenix secret-key-base/signing-salt/release-cookie from AWS
Secrets Manager via the repo's existing `aws-secretsmanager`
`ClusterSecretStore`.
