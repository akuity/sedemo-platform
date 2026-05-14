# Demo Ephemeral — PR Preview + Traditional Pipeline

Demonstrates two complementary GitOps delivery patterns in a single Kargo project:

1. **PR Preview pipeline** — every open PR gets an isolated, auto-promoted preview environment with its own Warehouse, Stage, namespace, and preview URL; environment tears down when the PR closes.
2. **Traditional pipeline** — `dev → staging → prod` promotion driven by `kustomize-set-image` on the main branch, showing the graduation path from validated PR previews to production.

## Architecture

### PR Preview Pipeline

```
GitHub PR opened / updated
  → ApplicationSet PR generator (polls every 3 min, instant with webhook)
      → ArgoCD: demo-ephemeral-stage-pr-<N>
          → deploys stage-template Helm chart to kargo cluster
              → Warehouse: demo-ephemeral-pr-<N>  (scoped to pr-<N>-* images only)
              → Stage:     preview-pr-<N>          (auto-promote)
                  → renders preview-chart (ConfigMap + Deployment replicas:0)
                  → pushes to env-ephemeral/pr-<N>, posts PR comment
      → ArgoCD: demo-ephemeral-pr-<N>
          → syncs env-ephemeral/pr-<N> branch → demo-ephemeral-pr-<N> namespace

GitHub PR closed
  → ApplicationSet prunes both Applications
      → Stage + Warehouse deleted from kargo cluster
      → namespace demo-ephemeral-pr-<N> pruned by ArgoCD
```

### Traditional Pipeline

```
PR merged → CI builds release image (e.g. 1-yellow)
  → Warehouse: demo-ephemeral-release  (allowTags: ^\d+-[a-z]+$)
      → Stage: dev    (auto-promote) → kustomize-set-image → main branch → demo-ephemeral-dev
          → Stage: staging (manual)  → kustomize-set-image → main branch → demo-ephemeral-staging
              → Stage: prod (manual) → kustomize-set-image → main branch → demo-ephemeral-prod
```

## Why Per-PR Warehouses?

Each PR gets its own Warehouse scoped to `^pr-<prNumber>-.+$`. This prevents `preview-pr-42` from ever picking up an image built for PR #67. Without this isolation, a single shared warehouse would cause the latest image (from any PR) to overwrite another developer's running preview on auto-promote.

## Image Tag Conventions

| Pipeline | Tag pattern | Example | Built by CI on |
|----------|-------------|---------|----------------|
| PR Preview | `pr-<N>-<variant>` | `pr-42-yellow` | `pull_request` event |
| Traditional | `<build>-<variant>` | `1-yellow` | push to `main` (after merge) |

The two patterns are mutually exclusive — the preview warehouse (`^pr-\d+-.+$`) and the release warehouse (`^\d+-[a-z]+$`) will never pick up each other's images.

## Key Files

| File | Purpose |
|------|---------|
| `stage-template/templates/warehouse.yaml` | Per-PR Warehouse scoped to that PR's image tags |
| `stage-template/templates/stage.yaml` | Per-PR Stage: renders preview-chart, pushes to git, posts PR comment |
| `preview-chart/` | Minimal Helm chart: ConfigMap (environment/image-tag) + Deployment (replicas: 0) |
| `kargo/tasks-kustomize.yaml` | `deploy-app` PromotionTask using `kustomize-set-image` (traditional pipeline) |
| `kargo/warehouse-release.yaml` | Release Warehouse — watches for `\d+-[a-z]+` tagged images |
| `kargo/stages-traditional.yaml` | `dev`, `staging`, `prod` Stages for the traditional pipeline |
| `kargo/project.yaml` | Project + auto-promote policies for `preview.*` and `dev` stages |
| `argocd/application-set.yaml` | Two ApplicationSets: one for app deployments, one for Stage/Warehouse CRs (PR preview) |
| `argocd/traditional-apps.yaml` | Static ApplicationSet (list) for `demo-ephemeral-dev/staging/prod` ArgoCD apps |
| `env/base/` | Base Kubernetes manifests (Deployment + ConfigMap) |
| `env/dev/`, `env/staging/`, `env/prod/` | Kustomize overlays; `kustomize-set-image` writes image tags here on main branch |

## Preview URLs

Each PR gets a unique URL: `https://pr-<number>.ephemeral.akpdemoapps.link`

## Required Secrets

| Secret | Namespace | Key | Used by |
|--------|-----------|-----|---------|
| `github-appset-token` | `argocd` | `token` | ApplicationSet PR generator — reads open PRs |
| `github-pr-token` | `demo-ephemeral` | `token` | `http` step in Stage — posts PR comments |

The `github-appset-token` needs `repo` read scope. The `github-pr-token` needs `pull_requests: write`.

## Storytelling Points

### PR Preview
- Open two PRs simultaneously — two independent `preview-pr-N` stages appear in Kargo UI, each with its own Warehouse
- Each preview URL shows a different image color, proving isolation
- PR comment appears automatically on each PR pointing to the preview URL
- Merge one PR — its Stage, Warehouse, namespace, and comment all disappear while the other preview keeps running
- Highlight the Warehouse `allowTags` scoping: neither stage can accidentally pick up the other's image

### Traditional Pipeline (graduation story)
- Merge a PR → CI tags a release image (`1-yellow`) → `demo-ephemeral-release` Warehouse detects it
- Kargo auto-promotes to `dev` — `kustomize-set-image` writes the new tag into `env/dev/kustomization.yaml` on main
- ArgoCD syncs `demo-ephemeral-dev` automatically — same image the team just validated in the preview
- Click "Promote" to `staging`, then manually approve `prod`
- Show the git commit history in `sedemo-platform` — every promotion is a traceable commit on main
