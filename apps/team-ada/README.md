# Team Ada — Akkoma

Deploys [akkoma-helm](https://github.com/adamancini/akkoma-helm)'s
published chart (`oci://ghcr.io/adamancini/charts/akkoma`) directly to
`sedemo-primary` — nothing is vendored into this repo. Each environment's
`env/<stage>/release.yaml` pins the chart version and stage values; Argo
CD's `files` generator reads it to build a multi-source Application (chart
+ this repo's own path for the stage's `ExternalSecret`s).

## Pipeline

```text
Warehouse: akkoma (chart + image)  →  dev (auto)  →  staging (auto, Jira QA gate)  →  prod (manual, Jira VP gate)
```

## Stages

| Stage | Namespace | Auto-promote |
| ------- | ----------- | -------------- |
| `dev` | `team-ada-dev` | yes |
| `staging` | `team-ada-staging` | yes (blocks until the Jira ticket reaches `UAT`) |
| `prod` | `team-ada-prod` | no |

## URLs

Each stage is served at `https://akkoma-<stage>.akpdemoapps.link/`:
[dev](https://akkoma-dev.akpdemoapps.link/) ·
[staging](https://akkoma-staging.akpdemoapps.link/) ·
[prod](https://akkoma-prod.akpdemoapps.link/). The host comes from
`akkoma.domain` in `env/<stage>/release.yaml`. The `*.akpdemoapps.link`
wildcard record already points at `sedemo-primary`'s nginx ingress, and
cert-manager's `letsencrypt-prod` issuer provisions the TLS certificate.
Each Kargo stage card links to its instance via `stageLinks`.

## Jira approval gates

One Jira ticket follows each Freight from dev to prod, using the `CHANGE`
project's workflow on `eddiewebb.atlassian.net`
(Open → UAT → Approved, with Declined from any status):

1. **dev (QA)** deploys, then creates the ticket (status Open). The `jira`
   step stores the issue key in the Freight's metadata (`jira-issue-key`),
   so later stages reuse the same ticket.
2. **staging (UAT)** auto-promotes. Its promotion waits until QA moves the
   ticket to `UAT` ("Approve for Testing"), deploys, and comments on the
   ticket.
3. **prod** is promoted manually. Its promotion waits until the ticket is
   `Approved` (the VP sign-off), deploys, and comments on the ticket.

Kargo checks the ticket's status every 30s and does not check who changed
it. The Jira workflow's transition permissions decide who can approve.
The `jira-access-secret` credentials come from the shared,
git-managed `ExternalSecret` in
[`secrets/kargo-sync-secrets.yaml`](../../secrets/kargo-sync-secrets.yaml).
The project key and status names are stage `vars` in
[`kargo/stages.yaml`](./kargo/stages.yaml).

### Operating notes

- **Move tickets through `UAT` before approving.** `Approved` is a global
  transition, so a ticket approved straight from Open (or approved while its
  staging promotion is still queued) never shows `UAT`, and the staging
  promotion waits indefinitely.
- **A waiting promotion holds its stage.** Promotions run one at a time per
  stage, so newer Freight queues behind a gate that is never satisfied. If a
  ticket is Declined or abandoned, abort its promotion in Kargo.
- **Freight needs a ticket before it leaves dev.** Freight promoted to dev
  before these gates existed, or whose `createIssue` step failed, has no
  `jira-issue-key`, and its staging and prod promotions fail. Re-promote it
  to dev to create the ticket.
- **Re-promoting the same Freight to dev creates a new ticket** and replaces
  the key on the Freight; the earlier ticket is left behind.

## Secrets

See [`SECRETS.md`](./SECRETS.md) — `ExternalSecret`s pull the Postgres
password and Phoenix secret-key-base/signing-salt/release-cookie from AWS
Secrets Manager via the repo's existing `aws-secretsmanager`
`ClusterSecretStore`.
