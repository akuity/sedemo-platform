# oci-airgap

Kargo pipeline that promotes application manifests through dev → test → stage → prod using OCI artifacts as both the transport layer and the live source of truth for Argo CD.

---

## Concept

All four environment overlays are rendered at dev time and packaged as a single OCI artifact. Argo CD syncs directly from that artifact using native OCI source support (Argo CD v3.1+) — no rendered git branches, no `oras pull` in downstream stages.

Prod is airgapped. Kargo's role there is an audit gate: it opens a ServiceNow change request with exact `skopeo` mirror instructions for the ops team, then waits for ticket closure. The airgapped cluster has its own Argo CD instance that syncs automatically once the artifact is mirrored into the internal registry.

---

## Pipeline

```
Warehouse  (new image tag)
  │
  ▼
dev  [auto-promote]
  • kustomize-set-image on base  (stamps tag into all 4 overlays)
  • kustomize-build × 4  →  ./bundle/{dev,test,stage,prod}/manifests.yaml
  • tar + oras push  →  single OCI artifact (one tar+gzip layer)
  • oras-resolve  →  resolves tag to digest
  • argocd-update oci-airgap-dev  (sets targetRevision to digest)
  │
  ▼
test  [manual gate]
  • oras-resolve  →  resolves tag to digest
  • argocd-update oci-airgap-test  (sets targetRevision to digest)
  │
  ▼
stage  [manual gate]
  • oras-resolve  →  resolves tag to digest
  • argocd-update oci-airgap-stage  (sets targetRevision to digest)
  │
  ▼
prod  [manual gate + AIRGAPPED]
  • snow-create  (ticket includes exact skopeo export + import commands)
  • snow-wait-for-condition  (polls until state=3 / Closed)
  • snow-update  (closing note)
```

---

## OCI Artifact Structure

Tag: `<bundleRegistry>/<bundleRepo>:<image-tag>`
Layer media type: `application/vnd.oci.image.layer.v1.tar+gzip`

The single layer is a tar+gzip archive with per-env subdirectories:

```
bundle.tar.gz
  ├── dev/manifests.yaml
  ├── test/manifests.yaml
  ├── stage/manifests.yaml
  └── prod/manifests.yaml
```

Argo CD Applications select their env via `source.path: <env>`.

---

## Why digest instead of tag as desiredRevision

Argo CD stores the resolved manifest digest (not the tag) in `status.sync.revision` for OCI sources. Kargo's `argocd-update` health check compares `desiredRevision` against that field — if you pass the image tag, it never matches and the promotion hangs. The `oras-resolve` custom step resolves the tag to its digest before `argocd-update` runs, giving Kargo a revision it can actually match.

---

## File Layout

```
kargo/kargo-custom/oci-airgap/
├── README.md
├── project.yaml         ← Project + ProjectConfig (promotion policies)
├── warehouse.yaml       ← subscribes to ghcr.io/akuity/guestbook
├── tasks.yaml           ← PromotionTasks: render-and-push-oci, pull-and-apply-oci, airgap-prod-gate
└── stages.yaml          ← Stages: dev, test, stage, prod

kargo/kargo-custom/cluster-resources/
└── custom-steps.yaml    ← CustomPromotionSteps: oras-push, oras-resolve

apps/oci-airgap/
├── appproject.yaml
├── applicationset.yaml  ← dev/test/stage only; syncs from oci:// source
├── base/
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   └── service.yaml
└── overlays/
    ├── dev/kustomization.yaml    (1 replica,  namespace oci-airgap-dev)
    ├── test/kustomization.yaml   (1 replica,  namespace oci-airgap-test)
    ├── stage/kustomization.yaml  (2 replicas, namespace oci-airgap-stage)
    └── prod/kustomization.yaml   (3 replicas, resource limits, namespace oci-airgap-prod)
```

---

## Prerequisites

### Argo CD version

Native OCI artifact source support requires Argo CD v3.1+.

### Kargo shared secrets

| Secret name | Keys | Used by |
|---|---|---|
| `oci-airgap-registry` | `username`, `password` | `oras-push`, `oras-resolve` custom steps — needs `read:packages` + `write:packages` |
| `kargo-step-snow` | `apiToken`, `instanceURL` | `airgap-prod-gate` |

### Variables to update

In [stages.yaml](stages.yaml), update these vars on all stages:

```yaml
- name: bundleRegistry
  value: ghcr.io                    # your OCI registry host
- name: bundleRepo
  value: akuity/oci-airgap-bundles  # your org/repo
```

### Prod airgapped Argo CD

The prod Argo CD Application is managed separately in the airgapped cluster — it is not in `applicationset.yaml`. Configure it to point at your internal mirror registry using the same `oci://` source + `path: prod` pattern as the connected-cluster apps.

---

## Prod ops workflow

When a ServiceNow ticket is opened by Kargo:

```bash
# 1. On a connected machine — export the artifact
skopeo copy \
  docker://ghcr.io/akuity/oci-airgap-bundles:<tag> \
  oci-archive:./oci-airgap-<tag>.tar

# 2. Transfer the tar to the airgapped environment via approved procedure

# 3. In the airgapped environment — import into internal registry
skopeo copy \
  oci-archive:./oci-airgap-<tag>.tar \
  docker://INTERNAL_REGISTRY/oci-airgap-bundles:<tag>

# 4. Argo CD syncs automatically; verify and close the ticket
argocd app wait oci-airgap-prod --health
```
