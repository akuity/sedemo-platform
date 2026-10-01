# Team Ada — Akkoma

Deploys [akkoma-helm](https://github.com/adamancini/akkoma-helm)'s
published chart (`oci://ghcr.io/adamancini/charts/akkoma`) directly to
`sedemo-primary` — nothing is vendored into this repo. Each environment's
`env/<stage>/release.yaml` pins the chart version and stage values; Argo
CD's `files` generator reads it to build a multi-source Application (chart
+ this repo's own path for the stage's `ExternalSecret`s).

## Pipeline

akkoma-helm's CI only builds and packages; Kargo decides what is released and
where it goes. There are two lanes, one per Warehouse:

```text
akkoma-main     →  dev (auto, every main commit)  →  release (manual: cuts chart X.Y.Z)
                                                           ┊ akkoma-helm release.yml
akkoma-release  →  staging (auto, Jira QA gate)   →  prod (manual, Jira VP gate)
```

- **`akkoma-main`** sees every commit on akkoma-helm `main`: a dev chart
  `0.0.0-main.<ts>.g<sha8>` and the image it pins, `main-<ts>-<sha8>`. Freight
  is only created when both come from the same commit.
- **`akkoma-release`** sees only chart releases `X.Y.Z` and the Akkoma-version
  image tag `vX.Y.Z` each one pins. That's the only Freight staging and prod
  can receive.

## Stages

| Stage | Namespace | Auto-promote | Freight from |
| ------- | ----------- | -------------- | -------------- |
| `dev` | `team-ada-dev` | yes | `akkoma-main` |
| `release` | none (deploys nothing) | no | `akkoma-main`, verified in `dev` |
| `staging` | `team-ada-staging` | yes (blocks until the Jira ticket reaches `UAT`) | `akkoma-release` |
| `prod` | `team-ada-prod` | no | `akkoma-release`, via `staging` |

## Cutting a release

1. In Kargo, pick the dev-verified Freight you want to release and set its
   **alias** to the release version, e.g. `v0.7.0`. In the UI that's
   *Change alias* on the Freight; with the CLI:
   `kargo update freight --project team-ada --name <freight> --new-alias v0.7.0`.
2. Promote that Freight to **`release`**. The promotion:
   - checks the alias is `X.Y.Z` / `vX.Y.Z`;
   - dispatches akkoma-helm's `release.yml` with the Freight's commit and that
     version, and waits for the run to succeed;
   - records `releasedAs`, `releasedBy` and the run URL in the Freight's
     metadata, and links to the GitHub release.

   `release.yml` refuses versions that aren't newer than the last release, and
   commits without a dev chart. It re-tags the exact image dev ran and
   repackages the exact chart dev ran.
3. A few minutes later `akkoma-release` picks up chart `X.Y.Z`, and staging
   auto-promotes it, opening the release's Jira ticket.

Without Kargo, run step 2 by hand in akkoma-helm:
`gh workflow run release.yml -f sha=<commit> -f version=0.7.0`. The result
reaches staging the same way.

The alias is a stand-in for a form: once the instance runs Kargo ≥ v1.12 on
the Akuity Platform, the `get-user-input` step can ask for the version during
the promotion instead.

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

One Jira ticket follows each **release** from staging to prod, using the
`CHANGE` project's workflow on `eddiewebb.atlassian.net`
(Open → UAT → Approved, with Declined from any status). Dev deploys every
commit, so it opens no tickets. A release cut through Kargo has already passed
dev (QA); one dispatched by hand in akkoma-helm has not.

1. **staging (UAT)** auto-promotes each new release. Its promotion first
   creates the ticket (status Open); the `jira` step stores the issue key in
   the Freight's metadata (`jira-issue-key`). It then waits until QA moves
   the ticket to `UAT` ("Approve for Testing"), deploys, and comments on the
   ticket.
2. **prod** is promoted manually. Its promotion waits until the same ticket
   is `Approved` (the VP sign-off), deploys, and comments on the ticket.

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
- **Mismatched release Freight fails fast.** `akkoma-release` discovers the
  chart and image separately, and a discovery in the middle of a release can
  pair the previous chart with the new image. Staging's first steps compare
  the chart's `appVersion` to the image tag and fail before opening a
  ticket; the matching Freight arrives on the next discovery.
- **The `release` card's Akkoma link goes nowhere.** `stageLinks` applies to
  every Stage, and `release` deploys nothing.
- **Re-promoting a release to staging reuses its ticket.** The ticket is only
  created when the Freight has no `jira-issue-key` yet, so aborting a waiting
  staging promotion and promoting again doesn't open a second one.

## Secrets

See [`SECRETS.md`](./SECRETS.md) — `ExternalSecret`s pull the Postgres
password and Phoenix secret-key-base/signing-salt/release-cookie from AWS
Secrets Manager via the repo's existing `aws-secretsmanager`
`ClusterSecretStore`. It also covers the GitHub PAT the `release` Stage uses
to dispatch akkoma-helm's `release.yml` (`team-ada-akkoma-helm-creds`).
