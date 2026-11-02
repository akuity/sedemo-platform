# Governed Teams: self-service below prod, locked controls at prod

A copy of [`templated-teams/`](../templated-teams/) built for the governance
story: **tenants run their own pipeline before prod, and every prod release
passes the same platform-owned controls, whatever the tenant's pipeline looks
like, with evidence attached.**

- **[DEMO.md](DEMO.md)** is the runbook: scene by scene, what to show and say.
- This README is how it works and how to run it.

It's separate from `templated-teams/` so nothing here changes an existing
demo: its own ApplicationSet, its own monorepo folder (`governed/*`), and every
generated name is prefixed `gov-` / `governed-`.

## The layers

| Layer | Where | Stops |
| --- | --- | --- |
| **Prod controls** (the paved road) | `kargo-chart/platform-controls.yaml` + `templates/kargo/prod-controls.yaml` | Releases without evidence or change approval |
| **Guardrails** | `kargo-chart/templates/_governed.tpl` | Tenant values that try to weaken prod (gauntlet 4a–4b4, 4g) |
| **Kargo RBAC** | `kargo-chart/templates/kargo/*-roles.yaml` | Tenants editing prod or approving their own release (4c, 4d) |
| **GitHub ruleset** | `github/` | Pushing straight to a prod branch (4e) |
| **Kyverno backstop** | `cluster-policies/` | Writing to prod without Argo CD: kubectl, a rogue workflow (4f, 4g); unsigned images |
| **Break glass** | `prod-controls.yaml` + `break-glass-roles.yaml` | Nothing, on purpose: emergencies go through, authorized and recorded for review |

The first three ship with this folder. The ruleset and the backstop are
written here but applied outside it (a repo admin, `sedemo-infra-iac`).

## How it fits together

![Shipping a change from a team's point of view: edit your settings file, the platform checks it, promote through your own pipeline, prod runs the same checklist for every team, then you're live with a full record](docs/how-it-fits.svg)

## What a tenant can change

All in their own `platform/app-values.yaml`. See [`kargo-chart/values.yaml`](kargo-chart/values.yaml).

| Tier | What | Example |
| --- | --- | --- |
| 1. Settings | Image, Rollouts on/off, ingress prefix, labels, replicas, S3, Slack | `rollouts.enabled: false` |
| 1. How they deploy | Argo CD (default), or their own GitHub Actions workflow | `deploy.method: github-actions` |
| 2. Extra steps | Steps in dev or staging, from the allowlist | a Grype scan in staging |
| 3. Their own stages | Up to 5, after dev, staging or each other. `deploy: true` makes one a real environment; `autoPromote: true` promotes automatically | a `qa` environment, a `smoke-test` stage |
| 3. Staging's source | Put their dev-side stages in front of staging | `pipeline.staging.after: [qa]` |

```
payments:  dev ──► staging ──► prod
checkout:  dev ──► qa ──► staging ──► prod        (+ smoke-test after staging)
reports:   dev ──► staging ──► prod               (each stage runs the team's GitHub Actions workflow)
                                └── prod is the same for all three
```

## What a tenant can't change: prod

Every prod Stage runs [`prod-controls`](kargo-chart/templates/kargo/prod-controls.yaml),
built from [`platform-controls.yaml`](kargo-chart/platform-controls.yaml).
Tenants can't touch either: they ship with the platform's chart, and tenant
roles can't edit Stages or PromotionTasks. Nothing is written to the prod
branch until the task finishes.

| Step | What it does | Set in `platform-controls.yaml` |
| --- | --- | --- |
| **release-type** | The person releasing (only `groups.releasers` or `groups.breakGlass`) picks normal or emergency and writes a note | `breakGlass.enabled` |
| **image-scan** | Trivy blocks CRITICAL CVEs (stand-in for Snyk) | `checks.imageScan` |
| **policy-check** | Kyverno CLI runs `policies/prod-policies.yaml` on the rendered manifests (skipped for GitHub Actions tenants) | `checks.policyCheck` |
| **ci-evidence** | Every GitHub check run on the image's source commit succeeded; none at all blocks | `checks.ciEvidence` |
| **secret-scan** | gitleaks on the source the image was built from | `checks.secretScan` |
| **signature** | cosign keyless signature from CI (off until CI signs images) | `checks.signature` |
| **change gate** | Approval by `sedemo-approver`, or a ServiceNow change that must reach Implement | `changeGate` |
| **evidence** | Audit event, plus who/what/which checks recorded on the Freight | always |
| **break glass** | Emergency: checks report but don't block, `sedemo-breakglass` authorizes, audit event + Freight record (+ ServiceNow incident) | `breakGlass` |

Change a line in `platform-controls.yaml`, merge, and every tenant picks it up
on the next sync.

## Guardrails

[`_governed.tpl`](kargo-chart/templates/_governed.tpl) checks the tenant's
values before anything renders. A failure shows on the tenant's
`gov-<name>-kargo` Application in Argo CD as `GUARDRAIL [rule]: reason`, and
nothing reaches Kargo.

| Rule | Rejects |
| --- | --- |
| `locked-setting` | Unknown top-level keys (e.g. `prodControls:`), or `environments.staging: false` |
| `prod-locked` | Anything under `pipeline.prod` |
| `step-allowlist` | Tenant steps not on `allowedTenantSteps` (e.g. `git-push`), tasks, or platform step aliases |
| `registry-allowlist` | `image.repository` outside `approvedRegistries` |
| `deploy-allowlist` | Unknown deploy methods, or GitHub Actions workflows outside `approvedDeployRepos` |
| `prod-source-fixed` | Tenant stages named like platform stages, or with fields like `feeds:` that would change what feeds prod |
| `shared-secrets` | Tenant steps that read a platform `sharedSecret()` |
| `pipeline-shape` | Malformed pipelines: unknown sources, loops, more than 5 stages |

Each rule has a matching file in [`example-tenants/rejected/`](example-tenants/rejected/).

## Add a tenant

A tenant is one folder with one file: `<name>/platform/app-values.yaml`.
Locally it lives in `example-tenants/`; live, it lives in
`akuity/sedemo-monorepo` under `governed/`.

1. **Pick a name.** Lowercase letters, numbers and dashes, e.g. `orders`. It
   becomes the Kargo project `gov-orders`, the Argo CD apps
   `gov-orders-dev`/`-staging`/`-prod`, and the namespaces with the same names.
2. **Copy an example.** `payments` for the plain pipeline, `checkout` for one
   with its own stages and steps, `reports` for a GitHub Actions team:
   ```
   cp -r governed-teams/example-tenants/payments governed-teams/example-tenants/orders
   ```
3. **Edit `example-tenants/orders/platform/app-values.yaml`:**

   | Setting | Required | What to put |
   | --- | --- | --- |
   | `image.repository` | yes | An image from `ghcr.io/akuity/` (registry-allowlist). Keep `ghcr.io/akuity/sedemo-monorepo-rollouts-app` for the demo. |
   | `ingress.custom_prefix` | Argo CD tenants | Unique per tenant, e.g. `orders-gov`. URLs become `dev.orders-gov.akpdemoapps.link`. |
   | `labels.purpose` | Argo CD tenants | Any value, e.g. `orders-api`. Prod's policy check blocks without it. |
   | `deploy` | no | Leave out for Argo CD. For GitHub Actions: `method: github-actions` plus `githubActions.repo`, `.workflow`, `.ref`. |
   | `rollouts.enabled` | no | `false` deploys a plain Deployment instead of a canary Rollout. |
   | `pipeline.dev.extraSteps` / `pipeline.staging.extraSteps` | no | The team's own checks, from the step allowlist. |
   | `pipeline.extraStages` | no | Up to 5 of the team's own stages or environments. See the comments in `kargo-chart/values.yaml`. |
   | `pipeline.staging.after` | no | Which of those stages staging waits for, e.g. `[qa]`. |

   Anything else at the top level (or anything under `pipeline.prod`) is rejected.
4. **Preview it:** `governed-teams/tests/render.sh orders` lists the Argo CD
   apps and Kargo Stages the file creates and where each Stage gets its
   Freight from. If the file breaks a rule, it prints the same
   `GUARDRAIL [rule]` error Argo CD would. Add `--full` to see every object.
5. **Check it:** `governed-teams/tests/verify.sh` picks up `orders`
   automatically: it must render, its `prod-controls` must match every other
   tenant's, and (for Argo CD tenants) its whole prod Stage too.
6. **Go live:** copy the folder into `akuity/sedemo-monorepo` as
   `governed/orders/` and open a PR there (`demo/reset-tenants.sh` copies all
   example tenants for you). Once merged, the ApplicationSet creates
   everything within a few minutes. If nothing shows up in Kargo, look at the
   `gov-orders-kargo` app in Argo CD: a guardrail error shows there.

## Test it locally

```
governed-teams/tests/verify.sh          # every tenant, every rejected file, the controls
governed-teams/tests/render.sh checkout # what one tenant file turns into
governed-teams/demo/gauntlet.sh         # the gauntlet's config attempts, as the demo shows them
```

All three need Helm 3 (`brew install helm`).

## Getting it live

1. **Merge the shared steps.** `kargo-shared/governed-gitleaks-scan.yaml` and
   `kargo-shared/governed-cosign-verify.yaml` define the `gitleaks-scan` and
   `cosign-verify` steps. They deploy with the existing `kargo-shared` app.
   They're new names, so they don't change any other demo.
2. **Groups.** `sedemo-approver` exists. `sedemo-breakglass` probably doesn't:
   ask for it, or point `groups.breakGlass` in `platform-controls.yaml` at an
   existing group for the demo.
3. **Register the ApplicationSet.** `templated-teams/appset.yaml` isn't applied
   from this repo (probably from `sedemo-infra-iac`). Either ask Daniel to add
   `governed-teams/appset.yaml` the same way, apply it with
   `argocd appset create governed-teams/appset.yaml`, or move it to
   `apps/governed-teams/argocd/appset.yaml`, where `bootstrap/argocd-apps.yaml`
   picks it up automatically. Post in #project-monster-demo and #sce first.
4. **Add the tenants** to `akuity/sedemo-monorepo` under `governed/`
   (`demo/reset-tenants.sh <your clone>`, then commit and push or open a PR).
5. **Testing from a branch first:** `demo/use-branch.sh <your fork URL> <branch>`
   points the ApplicationSet at it. Run `demo/use-branch.sh --reset` before merging.
6. **Optional layers:** the ruleset (`github/README.md`), the Kyverno backstop
   (`cluster-policies/README.md`) and signed images (`ci/README.md`).

## Check on the first live run

Everything here renders and passes `verify.sh`, but none of it has run
against Kargo yet. Watch these:

- **Image scan:** if the demo image has a CRITICAL CVE, every normal prod
  release stops at `image-scan`. Use break glass, a newer image, or turn the
  check off while you sort it out.
- **CI evidence:** relies on the image's `org.opencontainers.image.revision`
  label (the Warehouse already uses it) and on check runs existing for that
  commit in `sedemo-monorepo`. The `github-pr-token` shared secret needs read
  access to checks (`checks:read`, or `repo` on a classic token); otherwise
  GitHub returns 403 and every normal release blocks. In the monorepo, any
  team's failing workflow on the same commit blocks too: set
  `checks.ciEvidence.checkName` to the image build job.
- **Secret scan:** if gitleaks finds something in `rollouts-app/`, every
  release blocks. Change `checks.secretScan.path` or add a `.gitleaksignore`.
- **`kyverno-policy-apply`** must exit non-zero on a violation for
  `policy-check` to block.
- **Inside the task:** `get-user-input`, `wait-for-approval` and
  `task.outputs[...]` (all used elsewhere in this repo, but not yet together
  in one task).
- **Custom steps** (`trivy-image`, `kyverno-policy-apply`, `gitleaks-scan`,
  `cosign-verify`) run without `shard:`, like templated-teams' staging does today.
- **GitHub Actions tenants:** Kargo needs credentials to dispatch workflows
  in the deploy repo (it already does for `sedemo-platform`, for team-daniel).
- **Tenant environments:** a test-only stage should pass Freight on once its
  steps succeed; new URLs like `qa.checkout-gov.akpdemoapps.link` need DNS and
  a certificate like the others.
- **New Freight:** the Warehouse only creates Freight when the image's source
  commit matches the latest commit to the tenant's folder, so the image build
  in sedemo-monorepo has to run for commits that touch `governed/**` (check
  its path filter). Otherwise, assemble Freight by hand in the Kargo UI.
- **`ctx.meta.promotion.actor`** should show who started the promotion
  (`prod-promoted-by` on the Freight).
- **Requester ≠ approver** (spike S2) is still open: someone in both
  `sedemo-admin` and `sedemo-approver` could approve their own release.

## Folder map

| Path | What it is |
| --- | --- |
| `DEMO.md` | Scene-by-scene runbook |
| `appset.yaml` | Finds tenant folders in `sedemo-monorepo/governed/*` and starts everything |
| `project-templates/` | Each tenant's Argo CD project and apps; labels namespaces with their tier |
| `kargo-chart/` | Each tenant's Kargo pipeline, guardrails and prod controls ([README](kargo-chart/README.md)) |
| `apps-chart/` | The app itself (unchanged from templated-teams) |
| `policies/` | Kyverno policies the prod and staging checks run (as files, not installed) |
| `cluster-policies/` | Kyverno backstop for the prod cluster and Kargo control plane ([README](cluster-policies/README.md)) |
| `github/` | Ruleset that makes Kargo the only writer to prod branches ([README](github/README.md)) |
| `ci/` | Signing step for the image build in sedemo-monorepo ([README](ci/README.md)) |
| `example-tenants/` | `payments`, `checkout`, `reports`, and `rejected/` bypass attempts ([README](example-tenants/README.md)) |
| `demo/` | `gauntlet.sh`, `try-rejected.sh`, `reset-tenants.sh`, `use-branch.sh` |
| `tests/` | `verify.sh`, `render.sh` |
| `../kargo-shared/governed-*.yaml` | The `gitleaks-scan` and `cosign-verify` steps |
