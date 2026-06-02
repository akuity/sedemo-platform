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

---

## Instances (8 total)

| Instance | Stage | Tier | Region | Compliance |
|---|---|---|---|---|
| customer-a / us-east / dev | dev | standard | us-east | standard |
| customer-a / eu-west / dev | dev | standard | eu-west | **gdpr** |
| customer-b / us-east / dev | dev | premium | us-east | standard |
| customer-b / eu-west / dev | dev | premium | eu-west | **gdpr** |
| customer-a / us-east / prod | prod-us-east | standard | us-east | standard |
| customer-b / us-east / prod | prod-us-east | premium | us-east | standard |
| customer-a / eu-west / prod | prod-eu-west | standard | eu-west | **gdpr** |
| customer-c / eu-west / prod | prod-eu-west | **enterprise** | eu-west | **gdpr** |

---

## Config Hierarchy

```
config/
├── base/values.yaml          ← schema + defaults; new params land here once
├── regions/
│   ├── us-east.yaml          ← region delta (datacenter, latency target)
│   └── eu-west.yaml          ← adds complianceMode: gdpr
├── customers/
│   ├── customer-a.yaml       ← standard tier, crd-0001, 200 max connections
│   ├── customer-b.yaml       ← premium tier, crd-0002, advancedAnalytics: true
│   └── customer-c.yaml       ← enterprise tier, crd-0003, riskEngine: v2
├── envs/
│   ├── dev.yaml              ← replicas: 1, logLevel: debug
│   └── prod.yaml             ← replicas: 2, logLevel: warn
└── instances/
    └── customer-*.yaml       ← one file per instance; also the AppSet source
```

Merge order (last wins): `base ← region ← customer ← env`

---

## Kargo Pipeline

```
Warehouse  (polls ghcr.io/akuity/guestbook)
    │
    ▼
dev  ─── auto-promote ──► renders 4 dev instances simultaneously
    │
    ▼
qa   ─── manual gate (no rendering — pure approval checkpoint)
    │
    ▼
prod-us-east  ─── auto-promote ──► renders customer-a + customer-b us-east prod
    │   [2m soak]
    ▼
prod-eu-west  ─── auto-promote ──► renders customer-a + customer-c eu-west prod
```

Stages model the **promotion axis only** (4 stages). ApplicationSet handles the per-instance fan-out at each stage. Adding a customer never adds a Stage.

---

## Demo Moments

### Act 1 — O(1) config change

```bash
# Add a new feature flag to base — touches exactly one file
echo "  newRiskEngine: false" >> config/base/values.yaml
git commit -am "feat: add newRiskEngine feature flag"
git push
```

On push, CI renders all 8 instances and opens a PR. The diff shows `feature-new-risk-engine: "false"` appearing in every `manifests.yaml`. Merge once — every customer gets it.

### Act 2 — Release train promotion

A new image build is detected → Kargo creates one Freight → auto-promotes to `dev` → all 4 dev instances update simultaneously. Click approve at `qa` → `prod-us-east` fires → 2m soak → `prod-eu-west` fires automatically.

One Freight. One approval. Eight instances in two coordinated waves.

### Act 3 — Add a new customer

```bash
# One file = one new customer
cat > config/instances/customer-d-us-east-dev.yaml <<EOF
customer: customer-d
region: us-east
env: dev
stage: dev
EOF
git commit -am "onboard customer-d to us-east/dev"
git push
```

The ApplicationSet detects the new file and generates a new ArgoCD Application within ~30s. The next Kargo promotion automatically includes it.

### Act 4 — Holdback (enterprise change-freeze)

To give `customer-c` an independent cadence, move it to a dedicated Stage lane:

1. Uncomment `# holdback: true` in `config/instances/customer-c-eu-west-prod.yaml`
2. Update the ApplicationSet annotation to point at the new stage
3. Add a `prod-eu-west-customer-c` Stage sourcing from `prod-eu-west` with `autoPromotionEnabled: false`

This is the *exception* model — a few customers needing change windows, not the default.

---

## Key Talking Points

- **Adding a parameter is O(1):** touch `base/values.yaml` once. The rendered PR shows the blast radius across all N instances — that review is the safety net.
- **Scale doesn't change the model:** 8 instances today, 300 next year. The hierarchy doesn't grow. The pipeline doesn't grow. Only `config/instances/` gets one file per new customer.
- **Rendered manifests = real diffs:** Every promotion is a real git commit. Rollback is `git revert`. Argo CD syncs plain YAML with no CMP overhead at scale.
- **Holdbacks are exceptions, not the model:** Dedicated Stage lanes for change-freeze customers exist as an escape hatch — not the default design.

---

## File Layout

```
apps/demo-downstream/
├── argocd/
│   ├── appproject.yaml       ← AppProject: demo-downstream
│   └── appset.yaml           ← Git file generator → N Applications
├── kargo/
│   ├── project.yaml          ← Project + auto-promote policies
│   ├── warehouse.yaml        ← Watches ghcr.io/akuity/guestbook
│   └── stages.yaml           ← dev, qa, prod-us-east, prod-eu-west
├── chart/                    ← Helm chart (Deployment + Service + ConfigMap)
├── config/                   ← Layered values hierarchy
│   ├── base/, regions/, customers/, envs/, instances/
└── rendered/                 ← Kargo writes here; ArgoCD reads from here
    ├── customer-a/us-east/dev/
    ├── customer-a/us-east/prod/
    └── ...
```
