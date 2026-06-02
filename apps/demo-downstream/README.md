# Downstream — Multi-Tenant Release Train Demo

**Use case:** A SaaS platform vendor (trading platforms, fintech) deploys single-tenant apps per customer namespace in shared clusters. They need to ship coordinated releases across a growing fleet of customers × regions × environments without a config file explosion.

---

## The Problem

Every combination of (customer × region × env) produces a folder with slightly different config. Adding a single new parameter means editing hundreds of files. The cartesian product is materialized in Git and grows with every new customer.

## The Solution: Two Axes, Never Multiplied

| Axis | What changes | Who manages it |
|---|---|---|
| **Version (the train)** | Which image versions make up a release | Kargo Warehouse + Stages |
| **Config (composition)** | base ← region ← customer ← env values | Layered Helm values + ApplicationSet |

A new parameter touches `config/base/values.yaml` once — O(1) forever. A new customer adds one file to `config/instances/`. These two axes never multiply each other.

Both axes flow through the same Kargo pipeline. The Warehouse subscribes to the image registry **and** the config directory — a change to either creates new Freight.

---

## Customers (5)

| Customer | Tier | ID | Notes |
|---|---|---|---|
| customer-a | standard | crd-0001 | Always on main train |
| customer-b | premium | crd-0002 | Change-freeze in US east (end-of-quarter) |
| customer-c | enterprise | crd-0003 | UAT sign-off + change-freeze in EU west (GDPR window) |
| customer-d | standard | crd-0004 | Change-freeze in US east |
| customer-e | premium | crd-0005 | Main train, EU west |

## Instances (16 total across 4 namespaces)

| Instance | Namespace | Stage | Compliance |
|---|---|---|---|
| customer-a / us-east / dev | demo-downstream-dev | dev-us | standard |
| customer-b / us-east / dev | demo-downstream-dev | dev-us | standard |
| customer-d / us-east / dev | demo-downstream-dev | dev-us | standard |
| customer-a / eu-west / dev | demo-downstream-dev | dev-eu | gdpr |
| customer-b / eu-west / dev | demo-downstream-dev | dev-eu | gdpr |
| customer-c / eu-west / dev | demo-downstream-dev | dev-eu | gdpr |
| customer-e / eu-west / dev | demo-downstream-dev | dev-eu | gdpr |
| customer-a / us-east / staging | demo-downstream-staging | staging | standard |
| customer-a / eu-west / staging | demo-downstream-staging | staging | gdpr |
| customer-c / eu-west / uat | demo-downstream-uat | uat-customer-c | gdpr |
| customer-a / us-east / prod | demo-downstream-prod | prod-us-east | standard |
| customer-b / us-east / prod | demo-downstream-prod | prod-us-east-customer-b ⚠️ | standard |
| customer-d / us-east / prod | demo-downstream-prod | prod-us-east-customer-d ⚠️ | standard |
| customer-a / eu-west / prod | demo-downstream-prod | prod-eu-west | gdpr |
| customer-e / eu-west / prod | demo-downstream-prod | prod-eu-west | gdpr |
| customer-c / eu-west / prod | demo-downstream-prod | prod-eu-west-customer-c ⚠️ | gdpr |

---

## Config Hierarchy

```
config/
├── base/values.yaml          ← schema + defaults; new params land here once
├── regions/
│   ├── us-east.yaml          ← datacenter: nyc
│   └── eu-west.yaml          ← datacenter: lon, complianceMode: gdpr
├── customers/
│   ├── customer-a.yaml       ← standard, crd-0001, 200 max connections
│   ├── customer-b.yaml       ← premium, crd-0002, advancedAnalytics: true
│   ├── customer-c.yaml       ← enterprise, crd-0003, riskEngine: v2
│   ├── customer-d.yaml       ← standard, crd-0004, 300 max connections
│   └── customer-e.yaml       ← premium, crd-0005, advancedAnalytics: true
├── envs/
│   ├── dev.yaml              ← replicas: 0, logLevel: debug
│   ├── staging.yaml          ← replicas: 0, logLevel: info
│   ├── uat.yaml              ← replicas: 0, logLevel: info
│   └── prod.yaml             ← replicas: 0, logLevel: warn
└── instances/
    └── customer-*.yaml       ← one file per instance; drives the AppSet
```

Merge order (last wins): `base ← region ← customer ← env`

---

## Kargo Pipeline (11 stages)

```
Warehouse  (image: ghcr.io/akuity/guestbook  +  git: config/)
    │  Freight = image tag + config commit
    │
    ├─► dev-us (auto) ──► a, b, d  /  us-east  /  dev
    └─► dev-eu (auto) ──► a, b, c, e  /  eu-west  /  dev

    both pass ──► staging (auto, convergence) ──► customer-a / us-east + eu-west / staging
                             │
                        qa (manual)
                             │
              ┌──────────────┼─────────────────────────┐
              ▼              ▼                          ▼
    prod-us-east (auto)   prod-eu-west (auto, 2m soak)  uat-customer-c (auto)
    customer-a/us-east    customer-a, e / eu-west         customer-c / eu-west / uat
         │                        │                              │
         ├─ customer-b ⚠️          └─ customer-c ⚠️               └─► prod-eu-west-customer-c ⚠️
         └─ customer-d ⚠️
```

⚠️ = change-freeze lane. Freight is queued; a human promotes when the maintenance window opens.

`uat-customer-c` auto-promotes from qa so customer-c always has a validated build ready. Their prod approval is a separate manual step.

Each promotion renders from the **exact config commit captured in Freight** (`commitFrom()`).

---

## Demo Moments

### Act 1 — O(1) config change

```bash
# Touch one file — all 16 instances get the new param
echo "  newRiskEngine: false" >> config/base/values.yaml
git commit -am "feat: add newRiskEngine feature flag"
git push
```

The Warehouse detects the new commit on `apps/demo-downstream/config/`, creates new Freight, and auto-promotes to `dev-us` and `dev-eu` in parallel. The git commit to `rendered/` shows the new key appearing in every `manifests.yaml` — that diff is the blast radius, visible in git before it reaches prod.

### Act 2 — Release train promotion

New image detected → Freight created → `dev-us` and `dev-eu` fire in parallel → both pass → `staging` auto-promotes (convergence gate, renders US + EU staging instances) → `qa` manual gate → `prod-us-east` auto-promotes → 2m soak → `prod-eu-west` fires. Meanwhile `uat-customer-c` auto-promotes from `qa` so customer-c can start UAT validation while prod waves are in flight.

One Freight. One approval. 16 instances across two regions.

### Act 3 — Add a new customer

```bash
cat > config/instances/customer-f-us-east-dev.yaml <<EOF
customer: customer-f
region: us-east
env: dev
stage: dev-us
EOF
git commit -am "onboard customer-f"
git push
```

ArgoCD Application appears within ~30s. The next Kargo promotion includes it automatically.

### Act 4 — Change-freeze lanes

`customer-b`, `customer-c`, and `customer-d` are already on dedicated Stage lanes — amber nodes in the Kargo UI with freight queued and waiting. When a maintenance window opens, click **Promote**. That's it.

To freeze any other customer: change one field in their `config/instances/` file to point at a holdback Stage.

---

## Key Talking Points

- **O(1) parameter changes:** touch `base/values.yaml` once. Any key added under `featureFlags:` appears automatically in every instance's ConfigMap — the template ranges over the map dynamically. The rendered diff shows blast radius across all 16 instances before anything hits prod.
- **No CI needed for config changes:** the Warehouse git subscription means config changes flow through the same Kargo pipeline as image promotions.
- **4 namespaces, not 16:** all dev instances share `demo-downstream-dev`, all prod share `demo-downstream-prod`. Resources are distinguished by `customer-region` prefix from the Helm release name.
- **Rendered manifests = real diffs:** every promotion is a real git commit. Rollback is `git revert`.
- **Scale doesn't change the model:** 16 instances today, 300 next year. The hierarchy, pipeline, and task stay the same — only `config/instances/` grows.
- **Holdbacks are exceptions:** dedicated Stage lanes for change-freeze customers are an escape hatch, not the default. Each lane is a one-line instance file change.

---

## File Layout

```
apps/demo-downstream/
├── argocd/
│   ├── appproject.yaml       ← AppProject: demo-downstream
│   └── appset.yaml           ← Git file generator → 16 Applications
├── kargo/
│   ├── project.yaml          ← Project + auto-promote policies
│   ├── warehouse.yaml        ← image + git config/ subscriptions
│   ├── tasks.yaml            ← render-instance PromotionTask (reused by all stages)
│   └── stages.yaml           ← 11 stages
├── chart/                    ← Helm chart; Release.Name drives resource names
├── config/
│   ├── base/                 ← schema + defaults
│   ├── regions/              ← us-east, eu-west
│   ├── customers/            ← a, b, c, d, e
│   ├── envs/                 ← dev, staging, uat, prod
│   └── instances/            ← one file per instance; AppSet reads these
└── rendered/                 ← Kargo writes here; ArgoCD reads from here
    └── <customer>/<region>/<env>/manifests.yaml
```
