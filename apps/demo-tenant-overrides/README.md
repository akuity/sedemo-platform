# demo-tenant-overrides

A self-contained Kargo demo for the shape: **one Helm chart, deployed ~140 times as
near-duplicate Argo CD Applications**, where the only real per-instance variation is a
**versions YAML** — a shared `defaults` block of per-service image tags, plus per-tenant
override files that pin specific services to different tags.

Everything here is a **synthetic, generic stand-in** (no real names) built to be repointed
at a real repo later. Names, paths, and the stand-in image are called out below so each can
be swapped.

---

## ⚠️ Assumptions I invented (correct each against the real repo)

Every one of these is a guess made to build a faithful demo — none is asserted to match a
real setup:

- **Service set:** `api`, `worker`, `frontend` (app services driven by the lifecycle) plus
  `redis`, `nginx` (shared infra, pinned manually in defaults). Real service names/counts differ.
- **Versions schema:** `services.<name>.tag` in each YAML, with image `repo` held in the
  chart's `values.yaml`. The real `defaults`/override files may key differently.
- **Stages:** `dev → uat → prod`. dev auto-promotes; uat/prod are manual + verified.
- **Tenant names:** `alpha` (dev), `bravo` (uat), `charlie`/`delta`/`echo` (prod) — deliberately
  different sets per stage to show tenants do NOT line up across environments. Plus `flagship`
  (prod) as a high-value tenant on its own dedicated lane (see "High-value tenant" below).
- **Single stand-in image:** one public image (`ghcr.io/stefanprodan/podinfo`) stands in for
  the real release artifact so Freight is discoverable. A real setup likely has a per-service build.
- **Workloads:** every service is a `replicas: 0` Deployment + a ConfigMap. Nothing runs; the
  demo proves promotion mechanics and health-gating, not a live app.
- **Tenant axis trigger:** modeled as a **git** subscription on each tier's override files
  (one Warehouse + stage per tier), rolled out by sync only. A real setup might drive tenant
  pins from a tenant-specific image instead (see "Tenant axis: alternative" below).
- **argocd-update scope:** each shared stage gates on its `app-<stage>-default` instance only;
  the rest converge via ApplicationSet auto-sync. At 140 instances you'd gate on a label selector.
- **Fleet size:** represented by a short ApplicationSet list + 2 hand-written Applications, not 140.

---

## The two axes (kept deliberately separate)

| | **Axis 1 — Shared lifecycle** | **Axis 2 — Tenant overrides** |
|---|---|---|
| What varies | default service tags | per-tenant pins on specific services |
| File(s) | `versions/defaults/<stage>.yaml` | `versions/overrides/<stage>/tenant-*.yaml` |
| Warehouse | `defaults-release` (image) | `tenant-overrides-{dev,uat,prod}` (git, one per tier) |
| Flow | linear `dev → uat → prod` | enters at its own tier, **does not promote** |
| Promotion writes | **only** the defaults file | nothing (sync only) — never the defaults file |
| Stage(s) | `dev`, `uat`, `prod` | `dev-tenant-overrides`, `uat-tenant-overrides`, `prod-tenant-overrides`, `prod-tenant-flagship` |

**Why separate?** Tenants don't line up across stages (dev tenants ≠ uat tenants ≠ prod
tenants), so tenancy is not a promotion axis. Modeling it as its own Warehouse + stage at
each tier keeps the linear lifecycle clean and the tenant cadence independent — and shows the
per-tier independence at every tier rather than asserting it.

### High-value tenant: a dedicated lane

Most tenants share one grouped lane per tier (`*-tenant-overrides`), which keeps Kargo readable
at scale. For a tenant that warrants individual treatment, carve out a **dedicated lane**: its
own Warehouse (watching only that tenant's file) + its own Stage. It then appears as its **own
node** in the Kargo pipeline graph and promotes independently of everything else.

`tenant-flagship` (prod) demonstrates this:

- Warehouse `tenant-flagship-prod` watches only `versions/overrides/prod/tenant-flagship.yaml`
  (and the grouped `tenant-overrides-prod` Warehouse **excludes** that file, so the two lanes
  don't overlap).
- Stage `prod-tenant-flagship` syncs only `app-prod-tenant-flagship`.
- The override pins all app services to a frozen, validated build, so the moving prod default
  does not touch it — flagship advances only through its own gated lane.

**Scale caveat:** this per-tenant pattern is ~1 Warehouse + 1 Stage per tenant. Great for a
handful of high-value tenants; doing it for all ~140 would mean ~280 Kargo objects and an
unreadable graph. Keep the majority in the grouped lane and read their per-tenant health in
Argo CD's Applications view; reserve dedicated lanes for the few that earn them.

A service renders from `defaults` **unless** a tenant override pins it (Helm last-file-wins):

```
chart/values.yaml  <  versions/defaults/<stage>.yaml  <  versions/overrides/<stage>/tenant-*.yaml
```

---

## Layout

```
demo-tenant-overrides/
├── chart/                       # the ONE chart (generic multi-service app)
│   ├── values.yaml              #   service catalog: repos here, tags come from versions/**
│   └── templates/               #   replicas:0 Deployment per service + a versions ConfigMap
├── versions/
│   ├── defaults/{dev,uat,prod}.yaml          # AXIS 1 — only these are written by promotions
│   └── overrides/<stage>/tenant-*.yaml       # AXIS 2 — per-tenant pins, never promoted
├── argocd/
│   ├── appproject.yaml
│   ├── applicationset.yaml      # generates the fleet (add a row -> another instance)
│   └── rendered/                # 2 hand-written Applications: the expanded shape, readable
└── kargo/
    ├── project.yaml             # Project + ProjectConfig (dev auto; uat/prod/tenant manual)
    ├── warehouses.yaml          # defaults-release (image) + tenant-overrides-{dev,uat,prod} + tenant-flagship-prod (git)
    ├── stages.yaml              # dev → uat → prod  +  {dev,uat,prod}-tenant-overrides  +  prod-tenant-flagship
    ├── promotion-tasks.yaml     # promote-defaults: edits ONLY defaults/<stage>.yaml
    └── analysis.yaml            # healthy-sync-check verification (uat/prod)
```

---

## How to run

This repo is auto-discovered by the platform bootstrap (`bootstrap/argocd-apps.yaml` syncs
`apps/*/argocd`; `bootstrap/kargo-apps.yaml` syncs `apps/*/kargo`). So:

1. **Commit & push** this folder to the platform repo. Argo CD creates `argocd-demo-tenant-overrides`
   and `kargo-demo-tenant-overrides`; the AppProject, ApplicationSet, instances, and all Kargo
   resources appear. Instances sync to namespaces `demo-tenant-overrides-{dev,uat,prod}` (replicas:0).
2. **Shared lifecycle:** Kargo discovers Freight on `defaults-release`. `dev` auto-promotes
   (edits `defaults/dev.yaml`, syncs `app-dev-default`). Promote `dev → uat → prod` from the
   Kargo UI; each step edits only that stage's defaults file, the ConfigMap re-renders, the app
   reports Healthy, and the `healthy-sync-check` verification runs on uat/prod.
3. **Tenant axis (independent, per tier):** edit a file under `versions/overrides/<tier>/`
   (e.g. bump `prod/tenant-charlie.yaml`'s `api` tag) and push. `tenant-overrides-<tier>` produces
   Freight; promote `<tier>-tenant-overrides` to roll that tenant out — with **no movement** in
   the linear lifecycle and no effect on the other tiers' tenants.

Local sanity check (no cluster needed):

```sh
# default instance vs the same instance with a tenant override layered on top
helm template chart -f versions/defaults/prod.yaml
helm template chart -f versions/defaults/prod.yaml -f versions/overrides/prod/tenant-charlie.yaml
# the second shows services.api pinned by charlie; every other service unchanged
```

---

## The re-tag question — both paths

They regenerate a distinct release tag per stage. Two ways that happens; this demo supports
demoing either:

### (a) Immutable re-tag — the clean case ✅ (what this demo does by default)
Same artifact, new tag for provenance. `promote-defaults` carries the discovered tag forward
into the next stage's defaults via `yaml-update` (see `kargo/promotion-tasks.yaml`, the
`set-defaults` step). The image bytes that ran in uat are the same bytes that run in prod;
the tag is just rewritten so each stage has its own provenance label. Kargo's Freight tracks
that single artifact end-to-end.

### (b) Rebuild between stages — an honest gap ⚠️
If the release tag for each stage comes from a **fresh build** (not a re-tag of the tested
artifact), then **no Kargo topology can make prod's artifact equal to what was tested in uat.**
Kargo promotes Freight (a specific, discovered artifact) along the pipeline; if a new build is
produced per stage, prod runs bytes that uat never saw. Kargo would faithfully promote *a*
version, but the "tested in uat == shipped to prod" guarantee is broken at the build step,
upstream of anything Kargo controls. This is a real gap, not something the demo papers over —
the fix is organizational (build once, re-tag/promote the artifact), not a Kargo setting.

To *show* path (b) live, point each stage's `imageRepo` (or per-service subscriptions) at
distinct per-stage build tags so the promoted tag visibly differs from the upstream stage's —
making the divergence concrete on screen.

---

## Swap to point at a real repo

Mechanical find-and-replace once the real structure is known:

- **Git repo:** `https://github.com/akuity/sedemo-platform` → the real repo (in `kargo/warehouses.yaml`,
  `kargo/promotion-tasks.yaml`, `kargo/stages.yaml`, `argocd/*`).
- **Defaults path + keys:** in `kargo/promotion-tasks.yaml`, the `yaml-update` `path:` and the
  `key:` lines (`services.<svc>.tag`) → the real defaults file path and YAML structure. This is
  the one edit that controls exactly what the promotion writes.
- **Release artifact:** `ghcr.io/stefanprodan/podinfo` → real image repo(s). For per-service
  builds, add one `image:` subscription per repo in `warehouses.yaml` and one matching
  `yaml-update` key in `promotion-tasks.yaml`.
- **Override watch paths:** the `tenant-overrides-{dev,uat,prod}` `includePaths` → the real
  per-tenant override dirs (one Warehouse per tier).
- **Chart:** `chart/` → the real chart (or point `source.path` at it). Keep the layered
  `valueFiles` order (defaults then tenant override).
- **Instances/fleet:** replace the ApplicationSet list generator with a `git` files generator
  or cluster generator to scale to the real ~140.
- **App names:** `app-<stage>-default` / `app-<stage>-tenant-*` → the real naming, in
  `promotion-tasks.yaml` and `stages.yaml` `argocd-update` lists.

---

## Tenant axis: alternative (documented, not built)

This demo's tenant Warehouse watches **git** (the override files) and the tenant stage only
**syncs**. A symmetric alternative: subscribe the tenant Warehouse to a tenant-specific **image**
and have the tenant promotion `yaml-update` the tenant's override file (mirroring the shared
task, but writing `overrides/<stage>/tenant-*.yaml` instead of `defaults/<stage>.yaml`). We did
not build it to keep the two axes visually distinct, but it's a one-task addition if the real
tenant flow is image-driven. **The shared promotion still must never write override files.**

---

## What this demo DOES and does NOT prove

**Does prove**
- One chart → many Argo CD Applications, differing only by layered value files.
- The two axes are mechanically separate: the shared promotion writes **only** `defaults/<stage>.yaml`
  and never an override file; tenant input enters at its own tier and never promotes.
- Promotion gates on **real Application health** (argocd-update waits for Healthy + Synced;
  verification runs on uat/prod) — not "a commit landed".
- Immutable re-tag (path a) carries one artifact across stages with per-stage provenance.

**Does NOT prove**
- That this matches the real repo's chart, paths, service set, stage names, or tenant model
  (all are stand-ins — see Assumptions).
- Anything about a **rebuild-between-stages** workflow (path b) — that's called out as a real gap.
- Real runtime behavior or real verification logic (workloads are `replicas: 0`; the
  AnalysisTemplate is a placeholder Job).
- Scale characteristics at ~140 instances (the fleet is represented, not enumerated).
