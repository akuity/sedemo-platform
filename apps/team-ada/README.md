# Team Ada — Akkoma

Deploys [akkoma-helm](https://github.com/adamancini/akkoma-helm)'s
published chart (`oci://ghcr.io/adamancini/charts/akkoma`) directly to
`sedemo-primary` — nothing is vendored into this repo. Each environment's
`env/<stage>/release.yaml` pins what the stage runs -- the chart version and
the image tag, both set by Kargo -- and the other Helm values live in
[`env/values.yaml`](./env/values.yaml) (shared) and `env/<stage>/values.yaml`
(domain, secret names). Argo CD's `files` generator reads `release.yaml` to
build a multi-source Application: the chart with those two value files and
the image tag as a Helm parameter, plus this repo's own path for the stage's
`ExternalSecret`s. Chart version and image tag deliberately share that one
path, so a promotion is a single rollout.

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

## Verification

After every promotion, Kargo runs [`akkoma-smoke-test`](./kargo/analysis-templates.yaml)
against the stage's public URL:

- `/api/v1/instance` answers and reports the stage's own host;
- nodeinfo reports software `akkoma`;
- on staging and prod, nodeinfo's version matches the Freight's `vX.Y.Z`
  image. Dev's `main-<ts>-<sha8>` tag doesn't carry the version, so dev skips
  this check.

A Freight that fails it isn't verified in that stage, so it can't move on:
dev → `release`, staging → prod. Chart lint, render and install tests run in
akkoma-helm's CI on every PR.

## Cutting a release

1. In Kargo, promote the dev-verified Freight you want to release to
   **`release`**.
2. The promotion pauses on a **get-user-input** form asking for the release
   version (`X.Y.Z` or `vX.Y.Z`; the form rejects anything else). Open the
   promotion in the Kargo UI and submit it. Any signed-in user who can see the
   promotion can respond. The promotion then:
   - dispatches akkoma-helm's `release.yml` with the Freight's commit and that
     version, and waits for the run to succeed;
   - records `releasedAs`, `releasedBy` (whoever submitted the form) and the
     run URL in the Freight's metadata, and links to the GitHub release;
   - sets the Freight's **alias** to `vX.Y.Z`, so the release is easy to spot
     in the `akkoma-main` lane. Aliases are unique per project: if another
     Freight already has it, this step fails without failing the promotion
     (the release is already out), and you rename the aliases by hand.

   `release.yml` refuses versions that aren't newer than the last release, and
   commits without a dev chart. It re-tags the exact image dev ran and
   repackages the exact chart dev ran.
3. A few minutes later `akkoma-release` picks up chart `X.Y.Z`, and staging
   auto-promotes it, opening the release's Jira ticket.

A promotion waiting on the form holds the `release` Stage like any other
waiting step; abort it to back out.

Without Kargo, run the release by hand in akkoma-helm:
`gh workflow run release.yml -f sha=<commit> -f version=0.7.0`. The result
reaches staging the same way.

`get-user-input` is an Akuity Platform step (Kargo ≥ v1.12).

## URLs

Each stage is served at `https://akkoma-<stage>.akpdemoapps.link/`:
[dev](https://akkoma-dev.akpdemoapps.link/) ·
[staging](https://akkoma-staging.akpdemoapps.link/) ·
[prod](https://akkoma-prod.akpdemoapps.link/). The host comes from
`akkoma.domain` in `env/<stage>/values.yaml`. The `*.akpdemoapps.link`
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

### When verification runs

The ApplicationSet, not Kargo, writes `release.yaml` into each Application
(it polls every 30s), so Kargo's own sync can happen before the new chart
version arrives. The promote task's `argocd-update` therefore sets a
`desiredRevision` on the chart source: the step keeps re-syncing (up to 10
minutes) until the Application is synced to this release's chart version,
then the Stage's health check waits for that rollout to be Healthy before
the smoke test starts. Akkoma's DB migrations run in the `db-migrate` init
container, so Healthy (pods Ready) implies migrated. A promotion that seems
stuck at `argocd-update` with "sync result revisions ... do not match
desired revisions" is waiting on the ApplicationSet refresh.

### What reviewers see

- **Dev/QA, before UAT:** once staging opens the release ticket, it renders
  the release exactly as Argo CD will deploy it (the release chart with
  [`env/values.yaml`](./env/values.yaml) + `env/staging/values.yaml` and the
  image tag from `env/staging/release.yaml`) to the
  `rendered/team-ada/staging` branch, and comments a GitHub compare link on
  the ticket: every manifest and value that changes, from what's running in
  staging to this release. (The very first render has no deployed baseline
  yet, so its link shows the whole render.) The same link is on the staging promotion in
  Kargo. Review it, then Approve for Testing.
- **VP, before prod:** the prod promotion first posts the chart's GitHub
  release notes (the PRs merged since the last release), with links to the
  chart release and the upstream Akkoma release, then waits for Approved.

The rendered branch is for review only; nothing deploys from it. The diff
baseline is the render recorded when staging last deployed (Stage metadata
`renderedCommit`), so an aborted promotion's render never becomes the
baseline. The render uses `main` as of the moment staging's promotion
started: if `env/values.yaml` or `env/staging/values.yaml` change while the
ticket waits for UAT, what deploys will include those changes too --
re-promote to get a fresh diff.

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
