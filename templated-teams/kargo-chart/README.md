# kargo-template Helm Chart

Generates a full Kargo project for a templated app team. Platform team deploys one instance of this chart per team; app teams supply their Docker image and a `platform/app-values.yaml` file.

## What the Chart Creates

- **Kargo Project** with a `ProjectConfig` setting auto-promotion on dev
- **Two Warehouses**: one tracking the app image, one tracking the Helm chart
- **Stages**: `dev`, optionally `staging`, and `prod` (PR-based approval always required)
- **RBAC Roles**: separate roles for Dev, SRE, and QA teams
- **AnalysisTemplate** for optional post-promotion verification
- **Notifications** configuration

## Pipeline Shape

```
app-warehouse + chart-warehouse
  → dev      auto-promote; optional S3 Terraform provisioning
  → staging  (optional, controlled by environments.staging)
  → prod     always PR-based approval; optional Slack notification on PR open
```

Prod always opens a pull request and blocks on `git-wait-for-pr` before syncing Argo CD.

## Key values.yaml Fields

| Field | Default | Description |
|-------|---------|-------------|
| `application.name` | `template` | Used as the Kargo project name, namespace prefix, and Argo CD app name |
| `image.repository` | — | Container registry path for the app image |
| `image.tagRegex` | `^\d*-[a-z]*$` | Tag filter for the warehouse subscription |
| `image.selectionStrategy` | `NewestBuild` | How to select the next image version |
| `environments.staging` | `true` | Whether to include a staging stage |
| `rollouts.enabled` | `true` | Whether the Argo Rollout is enabled in the deployed chart |
| `services.s3.enabled` | `false` | When true, runs `tf-apply` in dev to provision an S3 bucket |
| `notifications.slack.enabled` | `false` | When true, sends a Slack message when the prod PR is opened |
| `project.path` | — | Path in `repoUrl` where `platform/app-values.yaml` lives |

## App Team Requirements

Each directory under `sedemo-monorepo/templated/` must contain:

```
platform/
  app-values.yaml   # Helm values passed to the base chart at promotion time
```

The `application.name` in `values.yaml` must match the directory name, which also becomes the Kargo project name.

## RBAC Roles

| Role | Kargo permissions |
|------|------------------|
| Dev | promote to dev; read all stages |
| SRE | promote to all stages; manage freight |
| QA  | approve PRs; read all stages |
