# Team Daniel Kargo Pipeline

This directory contains the Kargo configuration for Team Daniel's application, migrated from [dhpup/kargo](https://github.com/dhpup/kargo).

## Pipeline Overview

```
Warehouse (team-daniel)
       │
       ▼
    ┌──────┐
    │ test │ ← Auto-promote, promote-standard (red)
    └──┬───┘
       │
       ▼
    ┌──────┐
    │ uat  │ ← Auto-promote, promote-with-github-action, pokemon-xp verification (amber)
    └──┬───┘
       │
       ├────────────────┐
       ▼                ▼
┌───────────┐    ┌────────────┐
│prod-useast│    │prod-uswest │
│  (PR)     │    │ (auto)     │
│  (violet) │    │  (violet)  │
└───────────┘    └────────────┘
```

## Stages

| Stage | Source | Promotion Method | Verification |
|-------|--------|------------------|--------------|
| `test` | Warehouse (direct) | `promote-standard` | None |
| `uat` | `test` stage | `promote-with-github-action` | `pokemon-xp` AnalysisTemplate |
| `prod-useast` | `uat` stage | `promote-with-pr` (requires PR approval) | None |
| `prod-uswest` | `uat` stage | `promote-standard` (auto-promote enabled) | None |

## Promotion Tasks

1. **`promote-standard`** - Direct promotion with Kustomize rendering
2. **`promote-with-pr`** - Creates a PR for manual approval before merging
3. **`promote-with-github-action`** - Triggers GitHub Action workflow after promotion

## Subscriptions

- **Git**: `https://github.com/akuity/sedemo-platform` (main branch)
- **Image**: `ghcr.io/dhpup/guestbook`

## Branch Strategy

Rendered manifests are pushed to branches: `stage/team-daniel/{test,uat,prod-useast,prod-uswest}`

## Required Secrets

For the GitHub Action integration (`promote-with-github-action` task), you need a secret named `githubtoken` in the `team-daniel` namespace containing a GitHub token with workflow dispatch permissions.

## Files

- [project.yaml](project.yaml) - Project + ProjectConfig with auto-promotion policies
- [warehouse.yaml](warehouse.yaml) - Subscribes to Git repo and container image
- [stages.yaml](stages.yaml) - Defines the 4-stage pipeline
- [tasks.yaml](tasks.yaml) - PromotionTasks for different promotion strategies
- [analysis.yaml](analysis.yaml) - AnalysisTemplates for verification
