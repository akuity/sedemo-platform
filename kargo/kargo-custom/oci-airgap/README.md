# oci-airgap

Demo Kargo pipeline that promotes application manifests through dev → test → stage → prod using OCI artifacts as the transport layer, enabling a fully airgapped prod deployment.

> **Status:** Work in progress — pending a newer Kargo release with stable `CustomPromotionStep` support.

---

## Concept

Instead of writing rendered manifests directly to git branches (the standard pattern), this pipeline renders **all four environment overlays at once during dev promotion** and packages them as a single OCI artifact via [ORAS](https://oras.land). Each subsequent stage fetches only its specific layer by media type.

Prod has no external network access. Kargo's role there is purely an audit gate: it opens a ServiceNow change request with exact pull/apply instructions for the ops team, then waits for ticket closure before marking the freight as promoted.

---

## Pipeline

```
Warehouse  (new image tag or overlay change)
  │
  ▼
dev  [auto-promote]
  • kustomize-set-image on base (stamps tag into all 4 overlays)
  • kustomize-build × 4  →  ./rendered/{dev,test,stage,prod}.yaml
  • oras push  →  single OCI artifact with 4 named layers
  • git-push rendered/dev.yaml  →  stage/oci-airgap/dev
  • argocd-update oci-airgap-dev
  │
  ▼
test  [manual gate]
  • oras pull  (layer: application/vnd.kargo.manifests.test+yaml)
  • git-push  →  stage/oci-airgap/test
  • argocd-update oci-airgap-test
  │
  ▼
stage  [manual gate]
  • oras pull  (layer: application/vnd.kargo.manifests.stage+yaml)
  • git-push  →  stage/oci-airgap/stage
  • argocd-update oci-airgap-stage
  │
  ▼
prod  [manual gate + AIRGAPPED — no Argo CD]
  • snow-create  (ticket includes exact oras pull + kubectl apply commands)
  • snow-wait-for-condition  (polls until state=3 / Closed)
  • snow-update  (closing note)
```

---

## OCI Artifact Structure

Tag: `<bundleRegistry>/<bundleRepo>:<image-tag>`  
Artifact type: `application/vnd.kargo.airgap.bundle.v1`

| Layer | Media type |
|-------|-----------|
| dev rendered manifests | `application/vnd.kargo.manifests.dev+yaml` |
| test rendered manifests | `application/vnd.kargo.manifests.test+yaml` |
| stage rendered manifests | `application/vnd.kargo.manifests.stage+yaml` |
| prod rendered manifests | `application/vnd.kargo.manifests.prod+yaml` |

---

## File Layout

```
kargo/kargo-custom/oci-airgap/
├── README.md            ← this file
├── custom-steps.yaml    ← CustomPromotionStep: oci-airgap-push, oci-airgap-pull
├── project.yaml         ← Project + ProjectConfig (promotion policies)
├── warehouse.yaml       ← subscribes to ghcr.io/akuity/guestbook + git overlays
├── tasks.yaml           ← PromotionTasks: render-and-push-oci, pull-and-apply-oci, airgap-prod-gate
└── stages.yaml          ← Stages: dev, test, stage, prod

apps/oci-airgap/
├── appproject.yaml
├── applicationset.yaml  ← dev/test/stage only (prod excluded — airgapped)
├── base/
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   └── service.yaml
└── overlays/
    ├── dev/kustomization.yaml    (1 replica, namespace oci-airgap-dev)
    ├── test/kustomization.yaml   (1 replica, namespace oci-airgap-test)
    ├── stage/kustomization.yaml  (2 replicas, namespace oci-airgap-stage)
    └── prod/kustomization.yaml   (3 replicas, resource limits, namespace oci-airgap-prod)
```

---

## Prerequisites

### Kargo shared secrets

| Secret name | Keys | Used by |
|-------------|------|---------|
| `oci-airgap-registry` | `username`, `password` | `oci-airgap-push`, `oci-airgap-pull` — needs `write:packages` on the bundle registry |
| `kargo-step-snow` | ServiceNow API token | `airgap-prod-gate` — same format as `demo-snow` |

### Variables to update

In [stages.yaml](stages.yaml), update these vars on all stages that reference the bundle:

```yaml
- name: bundleRegistry
  value: ghcr.io          # your OCI registry host
- name: bundleRepo
  value: akuity/oci-airgap-bundles  # your org/repo
```

---

## Known TODOs / Things to tinker with

- **Workspace mount path** — `custom-steps.yaml` assumes the promotion workspace is mounted at `/workspace` inside the `CustomPromotionStep` container. Verify the actual path for your Kargo version and update `config.workspace` in `tasks.yaml` if different.
- **ORAS version** — pinned to `v1.2.2`. The `go-template` format for `oras manifest fetch` and `oras blob fetch` were validated against that version; test against newer releases.
- **Registry auth** — inline credentials in the shell command are fine for a demo but should be replaced with a mounted Docker config secret in production.
- **Prod OCI transfer** — the ServiceNow ticket describes the manual oras pull + kubectl apply flow but doesn't automate the artifact transfer into the airgapped environment. The actual transfer mechanism (data diode, physical media, etc.) is site-specific.
- **Argo CD OCI native source** — once [native OCI support](https://argo-cd.readthedocs.io/en/stable/proposals/native-oci-support/) ships in Argo CD, `applicationset.yaml` could point directly at the OCI artifact instead of the rendered git branch, removing the git-push step from the test/stage tasks entirely.
- **Verification templates** — no `AnalysisTemplate` is wired up yet; consider adding smoke tests after test/stage deploys (similar to `demo-snow` or `team-emily`).
