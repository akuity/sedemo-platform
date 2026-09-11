# Gatekeeper-Stage Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a two-repo demo (`sedemo-monorepo` app + `sedemo-platform` Kargo/Argo CD config) that shows the gatekeeper-Stage pattern: a Warehouse creates Freight from every new Git commit with no `freightCreationCriteria`, and a first `gate` Stage verifies a matching commit-SHA-tagged image exists in the registry before anything promotes further.

**Architecture:** `sedemo-monorepo/gatekeeper-app/` is a trivial static nginx app whose CI publishes images tagged only by `git sha`, with a `workflow_dispatch` toggle to skip publishing on demand. `sedemo-platform/apps/gatekeeper-stage/` adds a Warehouse (git + image subscriptions, no criteria), a `gate` → `dev` → `prod` Stage chain, and an `AnalysisTemplate` that runs `crane manifest` in a Job to check for the commit-SHA tag. Both repos are onboarded via each platform's existing auto-discovery conventions — no bootstrap-file edits needed.

**Tech Stack:** Kargo (Warehouse/Stage/AnalysisTemplate CRDs), Argo CD (AppProject/ApplicationSet), Helm, GitHub Actions, nginx, `crane` (go-containerregistry).

**Spec:** `docs/superpowers/specs/2026-09-11-gatekeeper-stage-demo-design.md`

## Global Constraints

- Image tag scheme: `ghcr.io/akuity/sedemo-monorepo-gatekeeper-app:<git-sha>` — full 40-char SHA, no run-number/color tag, no `latest` tag (spec: "the SHA tag is the entire mechanism this demo depends on").
- Warehouse for this app MUST NOT set `freightCreationCriteria` (spec: Freight creation must be unconditional on Git commits alone — that's the gap the gate exists to catch).
- `gate` Stage verification uses the `job` provider running `crane manifest` — not the `web` provider (ruled out: GHCR's anonymous bearer-token exchange is a two-step dance the `web` provider can't perform).
- `failureLimit: 0` on the `image-exists` metric — a missing tag is a definitive failure, not something to retry (spec: "the tag either exists or it doesn't, and won't start existing mid-check").
- All new `sedemo-platform` app files live under `apps/gatekeeper-stage/{argocd,kargo}/` to match the existing `apps/*/argocd` and `apps/*/kargo` auto-discovery generators in `bootstrap/argocd-apps.yaml` and `bootstrap/kargo-apps.yaml` — do not edit those bootstrap files.
- Per user's global git-worktrees rule: all branch work happens in a worktree at `<repo-root>/.worktrees/<branch-name>`, and each repo's `.gitignore` must have `.worktrees/` before creating one. `sedemo-platform/.gitignore` already has this; `sedemo-monorepo` currently has no `.gitignore` at all — Task 1 creates one.
- Akuity org's GHCR packages default to public visibility (confirmed live against the sibling `sedemo-monorepo-rollouts-app` package) — no explicit visibility step needed in the publish workflow.

---

## Task 1: `sedemo-monorepo` — worktree, gitignore, and `gatekeeper-app` scaffold

**Files:**
- Create: `sedemo-monorepo/.gitignore`
- Create: `sedemo-monorepo/gatekeeper-app/index.html`
- Create: `sedemo-monorepo/gatekeeper-app/Dockerfile`
- Create: `sedemo-monorepo/gatekeeper-app/README.md`

**Interfaces:**
- Produces: an image built `FROM nginx:1.27-alpine`, serving a single static page at `/`, with the build's git SHA baked in via a build-arg (`GIT_SHA`) substituted into `index.html` at build time. This is what Task 2's Helm chart deploys and Task 4's Warehouse/AnalysisTemplate check the tag of.

- [ ] **Step 1: Create the worktree for this repo's branch work**

```bash
git -C /Users/ada/src/github.com/akuity/sedemo-monorepo status
```

Confirm no uncommitted work is in the way, then:

```bash
git -C /Users/ada/src/github.com/akuity/sedemo-monorepo worktree add .worktrees/gatekeeper-app -b feature/gatekeeper-app
```

All remaining steps in this repo run inside `/Users/ada/src/github.com/akuity/sedemo-monorepo/.worktrees/gatekeeper-app`.

- [ ] **Step 2: Add `.gitignore` with the worktrees entry**

Create `sedemo-monorepo/.gitignore`:

```gitignore
.worktrees/
```

- [ ] **Step 3: Write the static page**

Create `sedemo-monorepo/gatekeeper-app/index.html`:

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>gatekeeper-app</title>
  <style>
    body { font-family: monospace; background: #111; color: #eee; padding: 3rem; }
    .sha { color: #6cf; font-size: 1.5rem; }
  </style>
</head>
<body>
  <h1>gatekeeper-app</h1>
  <p>Running from commit: <span class="sha">__GIT_SHA__</span></p>
</body>
</html>
```

- [ ] **Step 4: Write the Dockerfile**

Create `sedemo-monorepo/gatekeeper-app/Dockerfile`:

```dockerfile
FROM nginx:1.27-alpine

ARG GIT_SHA=unknown
COPY index.html /usr/share/nginx/html/index.html
RUN sed -i "s/__GIT_SHA__/${GIT_SHA}/" /usr/share/nginx/html/index.html

EXPOSE 80
```

- [ ] **Step 5: Build and verify locally**

Run:
```bash
docker build --build-arg GIT_SHA=$(git -C /Users/ada/src/github.com/akuity/sedemo-monorepo/.worktrees/gatekeeper-app rev-parse HEAD) -t gatekeeper-app:local /Users/ada/src/github.com/akuity/sedemo-monorepo/.worktrees/gatekeeper-app/gatekeeper-app
docker run --rm -d -p 8090:80 --name gatekeeper-app-local gatekeeper-app:local
curl -s http://localhost:8090/ | grep -o '<span class="sha">[a-f0-9]*</span>'
docker stop gatekeeper-app-local
```

Expected: the curl output shows the real commit SHA substituted in, not `__GIT_SHA__` or `unknown`.

- [ ] **Step 6: Write the app README**

Create `sedemo-monorepo/gatekeeper-app/README.md`:

```markdown
# gatekeeper-app

Trivial static app used by the `gatekeeper-stage` demo in `sedemo-platform`.
It has no behavior of its own — its only purpose is to be an image tagged
by git commit SHA, so a Kargo `gate` Stage can verify a matching image
exists before promoting a Freight built from that commit.

See `sedemo-platform/apps/gatekeeper-stage/README.md` for the full demo
story and how to run it.
```

- [ ] **Step 7: Commit**

```bash
cd /Users/ada/src/github.com/akuity/sedemo-monorepo/.worktrees/gatekeeper-app
git add .gitignore gatekeeper-app/
git commit -m "Add gatekeeper-app static demo image"
```

---

## Task 2: `sedemo-monorepo` — Helm chart for `gatekeeper-app`

**Files:**
- Create: `sedemo-monorepo/gatekeeper-app/deploy/chart/Chart.yaml`
- Create: `sedemo-monorepo/gatekeeper-app/deploy/chart/values.yaml`
- Create: `sedemo-monorepo/gatekeeper-app/deploy/chart/.helmignore`
- Create: `sedemo-monorepo/gatekeeper-app/deploy/chart/templates/_helpers.tpl`
- Create: `sedemo-monorepo/gatekeeper-app/deploy/chart/templates/deployment.yaml`
- Create: `sedemo-monorepo/gatekeeper-app/deploy/chart/templates/service.yaml`
- Create: `sedemo-monorepo/gatekeeper-app/deploy/chart/templates/ingress.yaml`

**Interfaces:**
- Consumes: nothing from Task 1 except the image name convention `ghcr.io/akuity/sedemo-monorepo-gatekeeper-app`.
- Produces: a chart at `gatekeeper-app/deploy/chart` with `setValues`-compatible keys `image.tag`, `kargo.stage`, `ingress.root_domain` — this is exactly what Task 5's `helm-template` promotion steps set via `${{ imageFrom(...).Tag }}` and `${{ ctx.stage }}`.

- [ ] **Step 1: Chart.yaml**

Create `sedemo-monorepo/gatekeeper-app/deploy/chart/Chart.yaml` (all work continues in the Task 1 worktree):

```yaml
apiVersion: v2
name: deploy
description: Deployment Helm chart for the gatekeeper-app demo application
type: application
version: 0.1.0
appVersion: "0.1.0"
```

- [ ] **Step 2: values.yaml**

Create `sedemo-monorepo/gatekeeper-app/deploy/chart/values.yaml`:

```yaml
replicaCount: 1

image:
  repository: ghcr.io/akuity/sedemo-monorepo-gatekeeper-app
  pullPolicy: IfNotPresent
  tag: unset

kargo:
  stage: dev

ingress:
  root_domain: akpdemoapps.link
```

- [ ] **Step 3: .helmignore**

Create `sedemo-monorepo/gatekeeper-app/deploy/chart/.helmignore` (copy verbatim from `auto-rollback-app/deploy/chart/.helmignore`):

```
# Patterns to ignore when building packages.
# This supports shell glob matching, relative path matching, and
# negation (prefixed with !). Only one pattern per line.
.DS_Store
# Common VCS dirs
.git/
.gitignore
.bzr/
.bzrignore
.hg/
.hgignore
.svn/
# Common backup files
*.swp
*.bak
*.tmp
*.orig
*~
# Various IDEs
.project
.idea/
*.tmproj
.vscode/
```

- [ ] **Step 4: _helpers.tpl**

Create `sedemo-monorepo/gatekeeper-app/deploy/chart/templates/_helpers.tpl` (copy verbatim from `auto-rollback-app/deploy/chart/templates/_helpers.tpl`):

```
{{/*
Expand the name of the chart.
*/}}
{{- define "deploy.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "deploy.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "deploy.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "deploy.labels" -}}
helm.sh/chart: {{ include "deploy.chart" . }}
{{ include "deploy.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "deploy.selectorLabels" -}}
app.kubernetes.io/name: {{ include "deploy.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "deploy.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "deploy.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
```

- [ ] **Step 5: deployment.yaml**

Create `sedemo-monorepo/gatekeeper-app/deploy/chart/templates/deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gatekeeper-app
spec:
  replicas: {{ .Values.replicaCount | default 1 }}
  selector:
    matchLabels:
      app: gatekeeper-app
  template:
    metadata:
      labels:
        app: gatekeeper-app
    spec:
      containers:
        - image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
          name: gatekeeper-app
          ports:
            - containerPort: 80
          env:
            - name: STAGE
              value: {{ .Values.kargo.stage }}
            - name: NAMESPACE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
  minReadySeconds: 10
  revisionHistoryLimit: 3
```

- [ ] **Step 6: service.yaml**

Create `sedemo-monorepo/gatekeeper-app/deploy/chart/templates/service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: gatekeeper-svc
spec:
  ports:
  - port: 80
    targetPort: 80
  selector:
    app: gatekeeper-app
```

- [ ] **Step 7: ingress.yaml**

Create `sedemo-monorepo/gatekeeper-app/deploy/chart/templates/ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: gatekeeper-ingress
spec:
  ingressClassName: nginx
  rules:
  - host: "{{ .Release.Namespace }}.{{ .Values.ingress.root_domain }}"
    http:
      paths:
      - pathType: Prefix
        path: /
        backend:
          service:
            name: gatekeeper-svc
            port:
              number: 80
```

- [ ] **Step 8: Validate the chart renders**

Run:
```bash
helm template gatekeeper-test /Users/ada/src/github.com/akuity/sedemo-monorepo/.worktrees/gatekeeper-app/gatekeeper-app/deploy/chart \
  --set image.tag=deadbeef0000000000000000000000000000beef \
  --namespace gatekeeper-dev
```

Expected: valid YAML output for Deployment, Service, Ingress with the image tag `ghcr.io/akuity/sedemo-monorepo-gatekeeper-app:deadbeef...` and no template errors.

- [ ] **Step 9: Commit**

```bash
cd /Users/ada/src/github.com/akuity/sedemo-monorepo/.worktrees/gatekeeper-app
git add gatekeeper-app/deploy/
git commit -m "Add Helm chart for gatekeeper-app"
```

---

## Task 3: `sedemo-monorepo` — publish workflow with `skip_publish` dispatch input

**Files:**
- Create: `sedemo-monorepo/.github/workflows/publish-gatekeeper-app.yml`

**Interfaces:**
- Consumes: `gatekeeper-app/Dockerfile` (Task 1), `GIT_SHA` build-arg contract from Task 1.
- Produces: pushes `ghcr.io/akuity/sedemo-monorepo-gatekeeper-app:<full 40-char git sha>` on every push to `main` under `gatekeeper-app/**`, unless run via `workflow_dispatch` with `skip_publish: true`. This tag scheme is exactly what Task 4's Warehouse image subscription and Task 5's `image-exists` AnalysisTemplate depend on.

- [ ] **Step 1: Write the workflow**

Create `sedemo-monorepo/.github/workflows/publish-gatekeeper-app.yml`:

```yaml
name: Publish gatekeeper-app image
run-name: Publish gatekeeper-app image${{ inputs.skip_publish && ' (build only, publish skipped)' || '' }}

on:
  push:
    branches:
      - main
    paths:
      - 'gatekeeper-app/**'
      - '.github/workflows/publish-gatekeeper-app.yml'
  workflow_dispatch:
    inputs:
      skip_publish:
        description: 'Build the image but do not push it (simulates a commit with no matching image yet)'
        type: boolean
        default: false

permissions:
  packages: write
  attestations: write
  contents: read
  id-token: write

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}-gatekeeper-app

jobs:
  publish:
    defaults:
      run:
        working-directory: gatekeeper-app
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v3
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v2
      - name: Log in to GitHub Container Registry
        if: ${{ !inputs.skip_publish }}
        uses: docker/login-action@v2
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - name: Build and push Docker image
        uses: docker/build-push-action@v5
        id: push
        with:
          context: gatekeeper-app
          push: ${{ !inputs.skip_publish }}
          platforms: linux/amd64,linux/arm64
          build-args: |
            GIT_SHA=${{ github.sha }}
          labels: |
            org.opencontainers.image.title="Gatekeeper App"
            org.opencontainers.image.description="Trivial static app for the gatekeeper-stage Kargo demo"
            org.opencontainers.image.revision=${{ github.sha }}
            org.opencontainers.image.url=${{ github.repositoryUrl }}
            org.opencontainers.image.source=${{ github.repositoryUrl }}
          tags: |
            ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
      - name: Generate artifact attestation
        if: ${{ !inputs.skip_publish }}
        uses: actions/attest-build-provenance@v3
        with:
          subject-name: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          subject-digest: ${{ steps.push.outputs.digest }}
          push-to-registry: true

  cleanup:
    name: ghcr.io cleanup action
    if: ${{ !inputs.skip_publish }}
    needs: publish
    runs-on: ubuntu-latest
    permissions:
      packages: write
    steps:
      - uses: dataaxiom/ghcr-cleanup-action@v1
        with:
          keep-n-tagged: 10
          delete-ghost-images: true
          delete-orphaned-images: true
          delete-untagged: true
          packages: sedemo-monorepo-gatekeeper-app
```

Note: the image tag is `${{ github.sha }}` (the full 40-char SHA GitHub Actions provides), not `${{ github.sha }}` truncated — Kargo's git commit `.ID` value from `commitFrom()`/the Freight's commit metadata is also the full SHA, so these must match exactly for the `crane manifest` check in Task 5 to find the tag.

- [ ] **Step 2: Validate workflow YAML syntax**

Run:
```bash
cd /Users/ada/src/github.com/akuity/sedemo-monorepo/.worktrees/gatekeeper-app
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/publish-gatekeeper-app.yml'))" && echo "valid YAML"
```

Expected: `valid YAML` with no errors.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/publish-gatekeeper-app.yml
git commit -m "Add publish workflow for gatekeeper-app with skip_publish dispatch input"
```

- [ ] **Step 4: Push the branch**

```bash
git push -u origin feature/gatekeeper-app
```

This task's deliverable (an app + chart + workflow that publishes a SHA-tagged image) is independently testable once pushed: merging to `main` triggers the workflow and a real image tag appears in GHCR, before any `sedemo-platform` config exists to consume it.

---

## Task 4: `sedemo-platform` — worktree, `argocd/` and `kargo/project.yaml` + `warehouse.yaml`

**Files:**
- Create: `sedemo-platform/apps/gatekeeper-stage/argocd/appproject.yaml`
- Create: `sedemo-platform/apps/gatekeeper-stage/argocd/application-set.yaml`
- Create: `sedemo-platform/apps/gatekeeper-stage/kargo/project.yaml`
- Create: `sedemo-platform/apps/gatekeeper-stage/kargo/warehouse.yaml`

**Interfaces:**
- Consumes: image repo `ghcr.io/akuity/sedemo-monorepo-gatekeeper-app` and git repo path `gatekeeper-app` from Task 1/3.
- Produces: a `Warehouse/gatekeeper-stage` in namespace `gatekeeper-stage` with no `freightCreationCriteria`, and three `AppProject`-authorized ArgoCD Applications (`gatekeeper-stage-gate`, `gatekeeper-stage-dev`, `gatekeeper-stage-prod`) that Task 6's `stages.yaml` promotion templates target by name.

- [ ] **Step 1: Create the worktree for this repo's branch work**

```bash
git -C /Users/ada/src/github.com/akuity/sedemo-platform status
git -C /Users/ada/src/github.com/akuity/sedemo-platform worktree add .worktrees/gatekeeper-stage -b feature/gatekeeper-stage
```

All remaining `sedemo-platform` steps run inside `/Users/ada/src/github.com/akuity/sedemo-platform/.worktrees/gatekeeper-stage`. (`.worktrees/` is already gitignored in this repo — no gitignore edit needed here.)

- [ ] **Step 2: appproject.yaml**

Create `sedemo-platform/apps/gatekeeper-stage/argocd/appproject.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: gatekeeper-stage
  namespace: argocd
spec:
  description: Gatekeeper-Stage Kargo pattern demo
  sourceRepos:
    - '*'
  destinations:
    - server: '*'
      name: '*'
      namespace: '*'
  clusterResourceWhitelist:
    - group: '*'
      kind: '*'
```

- [ ] **Step 3: application-set.yaml**

Create `sedemo-platform/apps/gatekeeper-stage/argocd/application-set.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: gatekeeper-stage
  namespace: argocd
spec:
  generators:
  - list:
      elements:
      - stage: gate
      - stage: dev
      - stage: prod
  template:
    metadata:
      name: gatekeeper-stage-{{stage}}
      annotations:
        kargo.akuity.io/authorized-stage: gatekeeper-stage:{{stage}}
    spec:
      project: gatekeeper-stage
      source:
        repoURL: https://github.com/akuity/sedemo-monorepo
        targetRevision: env-gatekeeper-stage/{{stage}}
        path: .
      destination:
        name: sedemo-primary
        namespace: gatekeeper-{{stage}}
      syncPolicy:
        automated:
          prune: true
          enabled: true
          selfHeal: true
        syncOptions:
        - CreateNamespace=true
```

- [ ] **Step 4: kargo/project.yaml**

Create `sedemo-platform/apps/gatekeeper-stage/kargo/project.yaml`:

```yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: Project
metadata:
  name: gatekeeper-stage
  annotations:
    argocd.argoproj.io/sync-wave: "-1"
---
apiVersion: kargo.akuity.io/v1alpha1
kind: ProjectConfig
metadata:
  name: gatekeeper-stage
  namespace: gatekeeper-stage
spec:
  stageLinks:
    - title: App UI
      description: The gatekeeper-app instance running at this stage
      url: 'http://gatekeeper-{{ .stage.metadata.name }}.akpdemoapps.link/'
```

- [ ] **Step 5: kargo/warehouse.yaml**

Create `sedemo-platform/apps/gatekeeper-stage/kargo/warehouse.yaml`:

```yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: Warehouse
metadata:
  name: gatekeeper-stage
  namespace: gatekeeper-stage
spec:
  subscriptions:
  - git:
      repoURL: https://github.com/akuity/sedemo-monorepo
      commitSelectionStrategy: NewestCommit
      discoveryLimit: 20
      includePaths:
      - gatekeeper-app
  - image:
      repoURL: akuity/sedemo-monorepo-gatekeeper-app
      discoveryLimit: 20
      imageSelectionStrategy: NewestBuild
```

No `freightCreationCriteria` block — this is the load-bearing omission the whole demo depends on (see Global Constraints). Do not add one.

- [ ] **Step 6: Validate manifests against the cluster API**

Run:
```bash
kubectl apply --dry-run=server -f /Users/ada/src/github.com/akuity/sedemo-platform/.worktrees/gatekeeper-stage/apps/gatekeeper-stage/argocd/appproject.yaml
kubectl apply --dry-run=server -f /Users/ada/src/github.com/akuity/sedemo-platform/.worktrees/gatekeeper-stage/apps/gatekeeper-stage/argocd/application-set.yaml
kubectl apply --dry-run=server -f /Users/ada/src/github.com/akuity/sedemo-platform/.worktrees/gatekeeper-stage/apps/gatekeeper-stage/kargo/project.yaml
kubectl apply --dry-run=server -f /Users/ada/src/github.com/akuity/sedemo-platform/.worktrees/gatekeeper-stage/apps/gatekeeper-stage/kargo/warehouse.yaml
```

Expected: each command reports `configured (dry run)` or `created (dry run)` with no schema-validation errors (requires the demo cluster's kubeconfig to be active — if targeting a cluster where Kargo/Argo CD CRDs aren't installed, confirm CRDs exist first with `kubectl get crd warehouses.kargo.akuity.io`).

- [ ] **Step 7: Commit**

```bash
cd /Users/ada/src/github.com/akuity/sedemo-platform/.worktrees/gatekeeper-stage
git add apps/gatekeeper-stage/argocd/ apps/gatekeeper-stage/kargo/project.yaml apps/gatekeeper-stage/kargo/warehouse.yaml
git commit -m "Add gatekeeper-stage AppProject, ApplicationSet, Kargo Project, and Warehouse"
```

---

## Task 5: `sedemo-platform` — `image-exists` AnalysisTemplate

**Files:**
- Create: `sedemo-platform/apps/gatekeeper-stage/kargo/analysis.yaml`

**Interfaces:**
- Consumes: image repo `akuity/sedemo-monorepo-gatekeeper-app` (Task 4's warehouse.yaml uses the same repo).
- Produces: `AnalysisTemplate/image-exists` in namespace `gatekeeper-stage`, taking an arg named `commit-sha`, exit-code-gated via a Job running `crane manifest`. Task 6's `gate` Stage references this template by name and supplies `commit-sha` as an arg.

- [ ] **Step 1: Write the AnalysisTemplate**

Create `sedemo-platform/apps/gatekeeper-stage/kargo/analysis.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: image-exists
  namespace: gatekeeper-stage
spec:
  args:
  - name: commit-sha
  metrics:
  - name: image-exists
    failureLimit: 0
    provider:
      job:
        spec:
          backoffLimit: 0
          template:
            spec:
              restartPolicy: Never
              containers:
              - name: check
                image: gcr.io/go-containerregistry/crane:debug
                command:
                - crane
                - manifest
                - ghcr.io/akuity/sedemo-monorepo-gatekeeper-app:{{ args.commit-sha }}
```

The `job` provider's built-in success condition is the container's exit code: `crane manifest <ref>` exits `0` and prints the manifest JSON if the tag exists, and exits non-zero (typically after logging a `MANIFEST_UNKNOWN` error) if it doesn't — no `successCondition` field is needed for the job provider, unlike the `prometheus`/`web` providers used elsewhere in this repo, since a Job's pass/fail already comes from its exit status.

- [ ] **Step 2: Validate manifest against the cluster API**

Run:
```bash
kubectl apply --dry-run=server -f /Users/ada/src/github.com/akuity/sedemo-platform/.worktrees/gatekeeper-stage/apps/gatekeeper-stage/kargo/analysis.yaml
```

Expected: `created (dry run)` with no schema errors.

- [ ] **Step 3: Smoke-test the crane check manually against a real (pre-existing) tag**

Run, against any already-published sibling image to confirm the check mechanics work before this repo's own image exists yet:
```bash
kubectl run crane-smoke-test --rm -i --restart=Never \
  --image=gcr.io/go-containerregistry/crane:debug \
  -- manifest ghcr.io/akuity/sedemo-monorepo-rollouts-app:218-yellow
```

Expected: prints a JSON image manifest and exits 0, proving anonymous GHCR pulls work from inside the cluster for this org's packages (confirmed separately for `rollouts-app`; this exercises the exact same code path `image-exists` will use).

Then test the negative case with a tag that does not exist:
```bash
kubectl run crane-smoke-test-missing --rm -i --restart=Never \
  --image=gcr.io/go-containerregistry/crane:debug \
  -- manifest ghcr.io/akuity/sedemo-monorepo-rollouts-app:this-tag-does-not-exist
```

Expected: non-zero exit, error output mentioning the tag/manifest was not found.

- [ ] **Step 4: Commit**

```bash
cd /Users/ada/src/github.com/akuity/sedemo-platform/.worktrees/gatekeeper-stage
git add apps/gatekeeper-stage/kargo/analysis.yaml
git commit -m "Add image-exists AnalysisTemplate using crane job provider"
```

---

## Task 6: `sedemo-platform` — `tasks.yaml` and `stages.yaml` (`gate` → `dev` → `prod`)

**Files:**
- Create: `sedemo-platform/apps/gatekeeper-stage/kargo/tasks.yaml`
- Create: `sedemo-platform/apps/gatekeeper-stage/kargo/stages.yaml`

**Interfaces:**
- Consumes: `Warehouse/gatekeeper-stage` (Task 4), `AnalysisTemplate/image-exists` (Task 5), Helm chart at `gatekeeper-app/deploy/chart` (Task 2), ArgoCD Applications `gatekeeper-stage-{gate,dev,prod}` (Task 4).
- Produces: the full promotion pipeline — this is the last piece needed for the demo to be runnable end-to-end.

- [ ] **Step 1: Write shared PromotionTasks**

Create `sedemo-platform/apps/gatekeeper-stage/kargo/tasks.yaml`:

```yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: PromotionTask
metadata:
  name: prepare-workdir
  namespace: gatekeeper-stage
spec:
  vars:
  - name: gitRepo
  - name: sourceBranch
    value: main
  - name: targetBranch
    value: env-gatekeeper-stage/${{ ctx.stage }}
  - name: path_src
    value: ./src
  - name: path_out
    value: ./out
  steps:
    - uses: git-clone
      config:
        repoURL: ${{ vars.gitRepo }}
        checkout:
        - branch: ${{ vars.sourceBranch }}
          path: ${{ vars.path_src }}
        - branch: ${{ vars.targetBranch }}
          create: true
          path: ${{ vars.path_out }}
    - uses: git-clear
      config:
        path: ${{ vars.path_out }}
---
apiVersion: kargo.akuity.io/v1alpha1
kind: PromotionTask
metadata:
  name: push-manifests
  namespace: gatekeeper-stage
spec:
  vars:
  - name: gitRepo
  - name: imageRepo
  - name: targetBranch
    value: env-gatekeeper-stage/${{ ctx.stage }}
  - name: path_out
    value: ./out
  steps:
    - uses: git-commit
      as: commit
      config:
        path: ${{ vars.path_out }}
        message: "Promote ${{ imageFrom(vars.imageRepo).Tag }} to ${{ ctx.stage }} [skip ci]"
    - uses: git-push
      as: push
      config:
        path: ${{ vars.path_out }}
        targetBranch: ${{ vars.targetBranch }}
    - uses: compose-output
      as: output
      config:
        commit: ${{ task.outputs['push'].commit }}
        branch: ${{ task.outputs['push'].branch }}
        url: ${{ task.outputs['push'].commitURL }}
```

- [ ] **Step 2: Write the `gate` Stage**

Create `sedemo-platform/apps/gatekeeper-stage/kargo/stages.yaml` (start with the `gate` stage document):

```yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: gate
  namespace: gatekeeper-stage
  annotations:
    kargo.akuity.io/color: red
spec:
  requestedFreight:
  - origin:
      kind: Warehouse
      name: gatekeeper-stage
    sources:
      direct: true
  verification:
    analysisTemplates:
    - name: image-exists
    args:
    - name: commit-sha
      value: ${{ commitFrom("https://github.com/akuity/sedemo-monorepo").ID }}
  promotionTemplate:
    spec:
      vars:
      - name: gitRepo
        value: https://github.com/akuity/sedemo-monorepo
      - name: imageRepo
        value: akuity/sedemo-monorepo-gatekeeper-app
      - name: path_src
        value: ./src
      - name: path_out
        value: ./out
      steps:
      - task:
          name: prepare-workdir
      - uses: git-clear
        config:
          path: ${{ vars.path_out }}
      - task:
          name: push-manifests
```

Per the spec's resolved open question: the `gate` Stage deploys nothing but an empty commit marker to its environment branch — no Helm render, no ArgoCD sync of a real workload. Its only job is to run `verification` and gate what flows onward; simplicity over running a live "unverified" copy of the app.

Append the `dev` Stage to the same `stages.yaml` file:

```yaml
---
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: dev
  namespace: gatekeeper-stage
  annotations:
    kargo.akuity.io/color: amber
spec:
  requestedFreight:
  - origin:
      kind: Warehouse
      name: gatekeeper-stage
    sources:
      stages:
      - gate
      autoPromotionOptions:
        selectionPolicy: MatchUpstream
  promotionTemplate:
    spec:
      vars:
      - name: gitRepo
        value: https://github.com/akuity/sedemo-monorepo
      - name: imageRepo
        value: akuity/sedemo-monorepo-gatekeeper-app
      - name: path_src
        value: ./src
      - name: path_out
        value: ./out
      steps:
      - task:
          name: prepare-workdir
      - uses: helm-template
        config:
          releaseName: deploy
          path: ${{ vars.path_src }}/gatekeeper-app/deploy/chart
          valuesFiles:
          - ${{ vars.path_src }}/gatekeeper-app/deploy/chart/values.yaml
          outPath: ${{ vars.path_out }}/manifests.yaml
          namespace: gatekeeper-dev
          setValues:
            - key: image.tag
              value: ${{ imageFrom(vars.imageRepo).Tag }}
            - key: kargo.stage
              value: ${{ ctx.stage }}
            - key: ingress.root_domain
              value: akpdemoapps.link
      - task:
          name: push-manifests
      - uses: argocd-update
        continueOnError: true
        config:
          apps:
          - name: gatekeeper-stage-dev
            namespace: argocd
```

Append the `prod` Stage:

```yaml
---
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: prod
  namespace: gatekeeper-stage
  annotations:
    kargo.akuity.io/color: violet
spec:
  requestedFreight:
  - origin:
      kind: Warehouse
      name: gatekeeper-stage
    sources:
      stages:
      - dev
      autoPromotionOptions:
        selectionPolicy: MatchUpstream
  promotionTemplate:
    spec:
      vars:
      - name: gitRepo
        value: https://github.com/akuity/sedemo-monorepo
      - name: imageRepo
        value: akuity/sedemo-monorepo-gatekeeper-app
      - name: path_src
        value: ./src
      - name: path_out
        value: ./out
      steps:
      - task:
          name: prepare-workdir
      - uses: helm-template
        config:
          releaseName: deploy
          path: ${{ vars.path_src }}/gatekeeper-app/deploy/chart
          valuesFiles:
          - ${{ vars.path_src }}/gatekeeper-app/deploy/chart/values.yaml
          outPath: ${{ vars.path_out }}/manifests.yaml
          namespace: gatekeeper-prod
          setValues:
            - key: image.tag
              value: ${{ imageFrom(vars.imageRepo).Tag }}
            - key: kargo.stage
              value: ${{ ctx.stage }}
            - key: ingress.root_domain
              value: akpdemoapps.link
      - task:
          name: push-manifests
      - uses: argocd-update
        continueOnError: true
        config:
          apps:
          - name: gatekeeper-stage-prod
            namespace: argocd
```

- [ ] **Step 3: Validate manifests against the cluster API**

Run:
```bash
kubectl apply --dry-run=server -f /Users/ada/src/github.com/akuity/sedemo-platform/.worktrees/gatekeeper-stage/apps/gatekeeper-stage/kargo/tasks.yaml
kubectl apply --dry-run=server -f /Users/ada/src/github.com/akuity/sedemo-platform/.worktrees/gatekeeper-stage/apps/gatekeeper-stage/kargo/stages.yaml
```

Expected: all documents report `created (dry run)` with no schema errors. If the `gate` Stage's `verification.args` expression syntax is rejected, cross-check against `docs.kargo.io`'s expression-language reference for the exact `commitFrom(...)` call signature current at implementation time — the spec's research already confirmed `commitFrom(repo).ID` as the field name, but re-verify the function is callable outside `freightCreationCriteria` (inside `verification.args`) before treating a rejection as a typo.

- [ ] **Step 4: Commit**

```bash
cd /Users/ada/src/github.com/akuity/sedemo-platform/.worktrees/gatekeeper-stage
git add apps/gatekeeper-stage/kargo/tasks.yaml apps/gatekeeper-stage/kargo/stages.yaml
git commit -m "Add gate/dev/prod Stage chain and shared PromotionTasks"
```

---

## Task 7: `sedemo-platform` — demo README

**Files:**
- Create: `sedemo-platform/apps/gatekeeper-stage/README.md`

**Interfaces:**
- Consumes: nothing new — this documents Tasks 1-6's already-built pipeline.
- Produces: the customer-facing narrative and live-demo script; no other task depends on this file existing.

- [ ] **Step 1: Write the README**

Create `sedemo-platform/apps/gatekeeper-stage/README.md`:

```markdown
# Gatekeeper Stage

Demonstrates how to handle a Warehouse where a Git subscription and an
image subscription can legitimately drift — for example, an image
repository shared across several services, where the newest image in the
repo isn't necessarily built from the newest commit on the branch you're
tracking.

## The problem this solves

A customer asked whether Kargo can create Freight from the newest Git
commit only when a matching image (tagged with that commit's SHA) already
exists. Their `freightCreationCriteria` (`imageFrom(repo).Tag ==
commitFrom(repo).ID`) only matched when the newest commit and newest image
happened to share a build — unreliable when the image repo is shared
across services.

**`imageFrom()` and `commitFrom()` don't mean "the newest image" or "the
newest commit."** Each resolves to the one candidate that subscription's
own selection strategy already picked as the artifact that would go into
Freight if Freight were created. `freightCreationCriteria` is a yes/no veto
on that one proposed pairing — it was never a search over all discovered
artifacts, and can't become one without breaking the Warehouse's
one-candidate-per-subscription contract and paying an unbounded tag-scan
cost on every reconcile that the OCI Distribution API isn't built to serve
cheaply.

The right place to ask "does a matching image exist yet" is where the
registry can answer it cheaply — a single tag lookup, done once, at the
moment it matters: before promoting past the first Stage. That's this
demo's **gatekeeper Stage**. It's the intended design, not a workaround
standing in for a missing Warehouse feature.

## How it works

- `kargo/warehouse.yaml` subscribes to `sedemo-monorepo`'s `gatekeeper-app`
  path and its image repo, with **no `freightCreationCriteria`** — Freight
  is created from every new commit, unconditionally.
- The `gate` Stage's `verification` runs `AnalysisTemplate/image-exists`
  (a Job running `crane manifest` against
  `ghcr.io/akuity/sedemo-monorepo-gatekeeper-app:<commit-sha>`). Only
  Freight whose verification passes can auto-promote to `dev` and `prod`.
- `dev` and `prod` deploy via `imageFrom(...).Tag`, which by the time they
  run has already been proven to exist by the gate.

## Running the live demo

1. Push a commit under `sedemo-monorepo/gatekeeper-app/` (e.g. edit
   `index.html`), or manually dispatch
   `publish-gatekeeper-app.yml` with `skip_publish: true`.
   - Watch a new Freight appear in the `gatekeeper-stage` Warehouse for
     that commit.
   - Watch the `gate` Stage's verification fail or stay pending — no image
     exists yet for that commit's SHA.
2. Re-run `publish-gatekeeper-app.yml` for the same commit with
   `skip_publish: false` (or push a follow-up no-op commit that triggers a
   normal publish).
   - Watch `gate` verification pass once the SHA-tagged image appears in
     GHCR.
   - Watch the Freight auto-promote through `dev` and `prod`.
```

- [ ] **Step 2: Commit**

```bash
cd /Users/ada/src/github.com/akuity/sedemo-platform/.worktrees/gatekeeper-stage
git add apps/gatekeeper-stage/README.md
git commit -m "Add gatekeeper-stage demo README"
```

- [ ] **Step 3: Push the branch**

```bash
git push -u origin feature/gatekeeper-stage
```

---

## Task 8: End-to-end verification

**Files:** none created — this task exercises Tasks 1-7's output against a real cluster.

**Interfaces:**
- Consumes: everything from Tasks 1-7.
- Produces: confirmation the whole pipeline behaves as designed; no downstream task depends on this.

- [ ] **Step 1: Merge/land both branches so ApplicationSets pick them up**

Follow this repo pair's normal PR process for `feature/gatekeeper-app` (sedemo-monorepo) and `feature/gatekeeper-stage` (sedemo-platform) — this plan does not itself open or merge PRs; hand off to the user for review per the git-worktrees and PR conventions already in effect for this repo.

- [ ] **Step 2: Confirm auto-discovery picked up the new app**

Run:
```bash
kubectl get application -n argocd argocd-gatekeeper-stage kargo-gatekeeper-stage
kubectl get application -n argocd gatekeeper-stage-gate gatekeeper-stage-dev gatekeeper-stage-prod
```

Expected: all Applications exist and sync healthy, created purely from the `apps/*/argocd` and `apps/*/kargo` ApplicationSets with no bootstrap-file changes.

- [ ] **Step 3: Walk the live-demo script from Task 7's README**

Execute the two numbered steps in `apps/gatekeeper-stage/README.md` against the real cluster: dispatch a `skip_publish: true` run, confirm Freight is created but `gate` verification fails/blocks; then dispatch a real publish for the same commit and confirm the Freight promotes through `gate → dev → prod`.

Expected: observed behavior matches the README exactly. If it diverges, treat this as a bug in the plan's manifests, not the README — fix the manifests to match the documented, agreed-upon behavior from the spec.

- [ ] **Step 4: Clean up worktrees once both PRs are merged**

```bash
git -C /Users/ada/src/github.com/akuity/sedemo-monorepo worktree remove .worktrees/gatekeeper-app
git -C /Users/ada/src/github.com/akuity/sedemo-platform worktree remove .worktrees/gatekeeper-stage
```

---

## Self-Review Notes

- **Spec coverage:** every section of the design spec maps to a task —
  `gatekeeper-app` (Tasks 1-3), Warehouse without criteria (Task 4),
  `image-exists` AnalysisTemplate via `job`+`crane` (Task 5), `gate → dev →
  prod` Stage chain (Task 6), README with corrected mental model (Task 7),
  live verification (Task 8). The spec's "open question" about what `gate`
  deploys is resolved in Task 6 Step 2 per the spec's own recommendation
  (option a: gate deploys nothing but a verification run).
- **Placeholder scan:** no TBD/TODO markers; all code blocks are complete,
  copy-pasteable manifests, not descriptions of manifests.
- **Type/name consistency:** image repo string `akuity/sedemo-monorepo-gatekeeper-app`
  (no `ghcr.io/` prefix) is used consistently in Kargo `image:` subscription
  fields (Task 4) and `imageFrom(vars.imageRepo)` calls (Task 6), matching
  how `demo-auto-rollback/kargo/warehouse.yaml` and `stages.yaml` reference
  `argoproj/rollouts-demo` without a registry host prefix. The full
  `ghcr.io/...` form is used only in the AnalysisTemplate's raw `crane`
  command (Task 5) and the GitHub Actions workflow (Task 3), which do need
  the explicit registry host. Namespace names (`gatekeeper-stage`,
  `gatekeeper-dev`, `gatekeeper-prod`) and Stage names (`gate`, `dev`,
  `prod`) are used identically across Tasks 4-7.
