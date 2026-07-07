# Demo Ephemeral — PR Preview + Traditional Pipeline

> **To trigger a preview environment:** open a pull request against `main` in [akuity/sedemo-monorepo](https://github.com/akuity/sedemo-monorepo) that touches any file under `rollouts-app/`, then add the `preview` label to the PR.

Demonstrates two complementary GitOps delivery patterns in a single Kargo project:

1. **PR Preview pipeline** — every open PR gets an isolated, auto-promoted preview environment with its own Warehouse, Stage, namespace, and PR comment. Tears down automatically on PR close.
2. **Traditional pipeline** — `dev → staging → prod` promotion driven by `kustomize-set-image` on the main branch, showing the graduation path from a validated PR preview to production.

## Architecture

### PR Preview Pipeline

```
GitHub PR opened / updated + labeled "preview"
  → ApplicationSet PR generator (polls every 3 min, instant with ArgoCD webhook; filtered to PRs with "preview" label)
      → ArgoCD: demo-ephemeral-stage-pr-<N>
          → deploys stage-template Helm chart to kargo cluster
              → Warehouse: demo-ephemeral-pr-<N>  (scoped to ^pr-<N>-.+$ only)
              → Stage:     preview-pr-<N>          (auto-promote)
                  → git-clone sedemo-platform (for preview-chart)
                  → helm-template preview-chart → ConfigMap + Deployment (replicas: 0)
                  → git-push to env-ephemeral/pr-<N> in sedemo-monorepo
                  → argocd-update + http (posts PR comment)
      → ArgoCD: demo-ephemeral-pr-<N>
          → syncs env-ephemeral/pr-<N> branch → demo-ephemeral-pr-<N> namespace
            (retries until Kargo creates the branch on first promotion)

GitHub PR closed
  → ApplicationSet prunes both Applications
      → Stage + Warehouse deleted from kargo cluster
      → namespace demo-ephemeral-pr-<N> pruned by ArgoCD
```

### Traditional Pipeline

```
PR merged → CI builds release image (e.g. 42-blue)
  → Warehouse: demo-ephemeral-release  (allowTagsRegexes: ^\d+-[a-z]+$)
      → Stage: dev     (manual) → kustomize-set-image → main branch → demo-ephemeral-dev
          → Stage: staging (manual) → kustomize-set-image → main branch → demo-ephemeral-staging
              → Stage: prod (manual) → kustomize-set-image → main branch → demo-ephemeral-prod
```

All three stages require a manual promotion click. No auto-promote on the traditional pipeline.

## Why Per-PR Warehouses?

Each PR gets its own Warehouse scoped to `^pr-<N>-.+$`. A single shared Warehouse would cause `preview-pr-42` to pick up the newest image across all PRs — meaning PR #67's image could auto-promote into PR #42's environment. Per-PR Warehouses make that impossible.

## Image Tag Conventions

| Pipeline | Tag pattern | Example | Trigger |
|----------|-------------|---------|---------|
| PR Preview | `pr-<N>-<color>` | `pr-42-blue` | `pull_request` event; color = PR# % 6 |
| Traditional | `<build>-<color>` | `42-blue` | push to `main` after merge; color = run# % 6 |

The two patterns are mutually exclusive — `^pr-\d+-.+$` and `^\d+-[a-z]+$` never overlap.

## Key Files

| File | Purpose |
|------|---------|
| `stage-template/templates/warehouse.yaml` | Per-PR Warehouse scoped to that PR's image tags |
| `stage-template/templates/stage.yaml` | Per-PR Stage: renders preview-chart, pushes manifests, posts PR comment |
| `preview-chart/` | Minimal Helm chart: ConfigMap (`environment`, `image-tag`) + Deployment (`replicas: 0`) |
| `kargo/tasks-kustomize.yaml` | `deploy-app` PromotionTask using `kustomize-set-image` (traditional pipeline) |
| `kargo/warehouse-release.yaml` | Release Warehouse — watches `^\d+-[a-z]+$` tagged images |
| `kargo/stages-traditional.yaml` | `dev`, `staging`, `prod` Stages |
| `kargo/project.yaml` | Project + auto-promote policy for `regex:preview.*` only |
| `argocd/application-set.yaml` | Two PR-generator ApplicationSets (app deployments + Stage/Warehouse CRs) |
| `argocd/traditional-apps.yaml` | List ApplicationSet for `demo-ephemeral-dev/staging/prod` ArgoCD apps |
| `env/base/` | Base Deployment (`replicas: 0`) + ConfigMap |
| `env/dev/`, `env/staging/`, `env/prod/` | Kustomize overlays updated by `kustomize-set-image` on promotion |

## Secrets

| Secret | How provisioned | Used by |
|--------|----------------|---------|
| `application-set-secret` | Already exists via ESO (`eddies-gh-pat`) | ApplicationSet PR generator — lists open PRs |
| `github-pr-token` | ESO (`eddies-gh-pat`) via `kargo-sync-secrets.yaml` | Kargo `sharedSecret()` — posts PR comments |

Both backed by `eddies-gh-pat` in AWS Secrets Manager (`kargo-pats`). Token needs `pull_requests: read+write` on `akuity/sedemo-monorepo`.

## Warehouse Refresh

By default Kargo polls for new images on its own schedule. To trigger immediate discovery after CI pushes a PR image, add a `WebhookReceiver` to the `stage-template` alongside the Warehouse and call it from `preview-rollouts-app.yml` after the image push step. Each receiver is scoped to its PR's Warehouse by PR number.

## Storytelling Points

### PR Preview
- Open two PRs and add the `preview` label to each — two independent `preview-pr-N` stages appear in Kargo UI with separate Warehouses
- Each PR gets a different color (PR# % 6) — visually proves isolation
- PR comment appears automatically on each PR with the preview URL
- Highlight `allowTagsRegexes` scoping in the Warehouse — neither stage can pick up the other's image
- Close one PR — its Stage, Warehouse, namespace, and ArgoCD apps disappear automatically

### Traditional Pipeline (graduation story)
- Merge a PR → CI builds a release image (`42-blue`) → `demo-ephemeral-release` Warehouse detects it
- Click Promote to `dev` in Kargo — `kustomize-set-image` writes the tag into `env/dev/kustomization.yaml` on main
- ArgoCD syncs `demo-ephemeral-dev` — same image just validated in the preview
- Click Promote to `staging`, then `prod`
- Show the git commit history in `sedemo-platform` — every promotion is a real, traceable commit
