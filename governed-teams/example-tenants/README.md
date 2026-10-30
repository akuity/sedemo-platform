# Example tenants

Each folder is one tenant: `<name>/platform/app-values.yaml`. To add your
own, copy `payments` or `checkout`, edit the file, and preview it with
`../tests/render.sh <name>`. Step-by-step: "Add a tenant" in
[`../README.md`](../README.md#add-a-tenant).

To go live, copy the folder into `akuity/sedemo-monorepo` under
`governed/<name>/`. The `governed-team-projects` ApplicationSet picks it up and
creates Kargo project `gov-<name>`.

| Tenant | Pre-prod pipeline | Prod |
| --- | --- | --- |
| `payments` | Golden path only: dev, staging | Platform prod-controls |
| `checkout` | dev → **qa** (its own environment) → staging, plus a `smoke-test` stage after staging, a manifest check in dev and a second image scan in staging | Same platform prod-controls |
| `reports` | Doesn't use Argo CD: each stage runs the team's GitHub Actions workflow | Same platform prod-controls, then the workflow deploys |

`payments` and `checkout` get identical prod Stages, and all three get the
identical `prod-controls` task. That's the point of scenes 1 and 7.

## Rejected examples

Each file in `rejected/` is an `app-values.yaml` that tries to weaken prod.
The guardrails in `kargo-chart/templates/_governed.tpl` refuse to render it,
and Argo CD shows the reason on the tenant's `gov-<name>-kargo` Application.

| File | What the tenant tries | Guardrail | Gauntlet scene |
| --- | --- | --- | --- |
| `remove-prod-check.yaml` | Turn off the prod image scan | `locked-setting` | 4a |
| `add-prod-step.yaml` | Add a step to prod | `prod-locked` | 4a |
| `git-push-in-staging.yaml` | Push to the prod branch from staging | `step-allowlist` | 4b |
| `unapproved-registry.yaml` | Deploy an image from Docker Hub | `registry-allowlist` | 4b2 |
| `skip-staging.yaml` | Turn off staging | `locked-setting` | 4b3 |
| `side-stage-to-prod.yaml` | Add a stage named like prod | `prod-source-fixed` | 4b4 |
| `stage-feeds-prod.yaml` | Add a stage that feeds prod directly | `prod-source-fixed` | 4b4 |
| `staging-after-loop.yaml` | Make staging wait for a stage after staging | `pipeline-shape` | extra |
| `unapproved-deploy-repo.yaml` | Deploy with a workflow from outside the approved org | `deploy-allowlist` | 4g |
| `borrow-platform-secret.yaml` | Read a platform shared secret | `shared-secrets` | extra |

`../tests/verify.sh` renders all of these and checks each one fails for the
right reason.
