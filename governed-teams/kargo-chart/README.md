# governed-kargo Helm chart

Renders a Kargo project for one governed tenant. See [`../README.md`](../README.md)
for the whole picture.

| File | What it renders or holds |
| --- | --- |
| `platform-controls.yaml` | **The prod policy.** Which checks run, the change gate, break glass, groups, allowlists. Read by the templates with `.Files.Get`, so tenants can't override it. |
| `values.yaml` | Defaults, with the settings tenants may change marked TENANT |
| `templates/_governed.tpl` | Guardrails (no resources) |
| `templates/_prod-controls.tpl` | The evidence checks, rendered into prod-controls |
| `templates/_deploy.tpl` | Deploy helpers for GitHub Actions tenants |
| `templates/kargo/guardrails.yaml` | Runs the guardrails before anything renders |
| `templates/kargo/stages.yaml` | `dev`, `staging` (tenant steps, source set by `pipeline.staging.after`) and the locked `prod` Stage; Argo CD or GitHub Actions deploys |
| `templates/kargo/extra-stages.yaml` | Tenant stages from `pipeline.extraStages`: environments (`deploy: true`) and test stages |
| `templates/kargo/prod-controls.yaml` | The `prod-controls` PromotionTask every prod Stage runs |
| `templates/kargo/project.yaml` | Project, plus auto-promotion for dev and tenant stages with `autoPromote: true` |
| `templates/kargo/app-roles.yaml` | Developers: dev and their own stages |
| `templates/kargo/qa-roles.yaml`, `sre-roles.yaml` | QA: staging. SRE: everything (unchanged) |
| `templates/kargo/break-glass-roles.yaml` | Break glass: can start prod promotions; authorizes emergencies |
| `templates/kargo/warehouse.yaml`, `analysis.yaml`, `notifications.yaml` | Unchanged from templated-teams |
