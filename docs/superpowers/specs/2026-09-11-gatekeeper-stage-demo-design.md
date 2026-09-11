# `gatekeeper-stage` demo: design

## Motivation

A customer (typesafe.ai) asked whether Kargo Warehouses can create Freight
from the newest Git commit only when a matching image (tagged with that
commit's SHA) already exists in the registry. Their setup: one Warehouse
subscribed to a Git repo and an image repo shared across several services,
every image tagged with the commit SHA it was built from. Because the image
repo is shared, its newest image is often built from a different commit than
the newest commit on the branch being watched. `imageFrom(repo).Tag ==
commitFrom(repo).ID` only matches in the coincidental case where the newest
commit and newest image happen to share a build — which isn't reliable when
multiple services publish to the same repo.

### The corrected mental model

`imageFrom()` and `commitFrom()` do not mean "the newest image" / "the newest
commit." Each resolves to *the one candidate that this specific
subscription's own selection strategy has already picked* as the artifact
that would go into Freight if Freight were created. `freightCreationCriteria`
is a yes/no veto evaluated against that one proposed pairing — "do these two
specific things belong together" — not a search or lookup over the set of
discovered candidates.

This is deliberate, not a gap:

- **Warehouse contract.** Each subscription already resolves its own
  candidate via its own selection strategy before criteria ever runs. Turning
  criteria into a combinatorial matcher over all discovered artifacts would
  mean two systems (per-subscription selection and cross-subscription
  criteria) competing to decide what "the" candidate is, breaking the current
  one-candidate-per-subscription contract that the rest of Kargo relies on.
- **OCI API cost.** "Does an image exist for arbitrary commit X" isn't a
  registry operation the OCI Distribution API supports cheaply. Solving it by
  scanning/matching tags inside the Warehouse's reconcile loop would impose
  that cost on every Warehouse, every reconcile, whether or not the check is
  ever needed.

The right place to ask "does a matching image exist yet" is where the
registry can answer it cheaply with a single tag lookup, done once, at the
moment it actually matters: before promoting past the first Stage. That's
the **gatekeeper Stage** pattern this demo builds. It is the intended
design, not a workaround standing in for a missing Warehouse feature.

## What this demo shows

Two repos, one feature:

1. `sedemo-monorepo/gatekeeper-app/` — a trivial app whose CI publishes
   images tagged only by `git sha`, with an on-demand way to skip publishing
   for a given commit (to manufacture the "image not built yet" gap live).
2. `sedemo-platform/apps/gatekeeper-stage/` — a Warehouse with no
   `freightCreationCriteria` (Freight is created from every new commit
   freely) feeding a `gate` Stage whose `verification` step checks the
   registry for a tag matching that Freight's commit SHA. Only Freight that
   passes verification can auto-promote to `dev` and `prod`.

## Component 1: `sedemo-monorepo/gatekeeper-app/`

Modeled on the existing `rollouts-app/` (has its own `Dockerfile` + Helm
chart + publish workflow), but intentionally trivial — a static page
displaying its own build's commit SHA, nothing else. No canary/rollout
behavior; that's not what this demo is about.

- `gatekeeper-app/Dockerfile` — minimal static-content image (e.g. nginx
  serving a generated `index.html` embedding `$GIT_SHA`).
- `gatekeeper-app/deploy/chart/` — Helm chart (Chart.yaml, values.yaml,
  templates for deployment/service/ingress), matching the shape of
  `auto-rollback-app/deploy/chart` and `rollouts-app/deploy/chart`.
- `.github/workflows/publish-gatekeeper-app.yml` — modeled on
  `publish-rollouts-app.yml`:
  - Triggers on push to `main` under `gatekeeper-app/**`, and on
    `workflow_dispatch`.
  - `workflow_dispatch` adds a boolean input `skip_publish` (default
    `false`). When `true`, the job's build/push steps are skipped
    (`if: ${{ !inputs.skip_publish }}`) — this lets an SE push a commit and
    consciously withhold its image to demonstrate the lag the pattern
    guards against.
  - Tags the image **only** as `ghcr.io/akuity/sedemo-monorepo-gatekeeper-app:${{ github.sha }}`
    — no run-number/color tag like `rollouts-app` uses, since the SHA tag is
    the entire mechanism this demo depends on.
  - No `latest` tag, to avoid the gate check accidentally succeeding against
    the wrong image.

## Component 2: `sedemo-platform/apps/gatekeeper-stage/`

Directory layout follows the `apps/*/{argocd,kargo}` auto-discovery
convention (`bootstrap/argocd-apps.yaml` and `bootstrap/kargo-apps.yaml`
generate Applications from any `apps/*/argocd` or `apps/*/kargo` directory —
no bootstrap-file changes needed to onboard this app).

### `argocd/`

- `appproject.yaml` — same shape as `demo-auto-rollback`'s: wildcard
  sources/destinations, named `gatekeeper-stage`.
- `application-set.yaml` — `list` generator over `[gate, dev, prod]`,
  templated Applications named `gatekeeper-stage-{{stage}}`, each annotated
  `kargo.akuity.io/authorized-stage: gatekeeper-stage:{{stage}}`, deploying
  to namespace `gatekeeper-{{stage}}`.

### `kargo/`

- `project.yaml` — `Project` + `ProjectConfig` (stageLinks pointing at each
  stage's app URL, matching the `demo-auto-rollback` pattern).
- `warehouse.yaml`:
  - `git` subscription: `sedemo-monorepo`, `includePaths: [gatekeeper-app]`,
    `commitSelectionStrategy: NewestCommit`.
  - `image` subscription: `ghcr.io/akuity/sedemo-monorepo-gatekeeper-app`,
    `imageSelectionStrategy: NewestBuild`, no tag filtering.
  - **No `freightCreationCriteria`.** Freight is created for every new
    commit regardless of whether a matching image exists yet — that gap is
    intentional and is what the `gate` Stage exists to catch.
- `stages.yaml`:
  - **`gate`** — first Stage, `requestedFreight` direct from the Warehouse.
    `verification.analysisTemplates: [image-exists]`, passing the Freight's
    git commit SHA as an arg. `promotionTemplate` does the standard
    git-clone/helm-template/push/argocd-update sequence into
    `gatekeeper-gate`, so there's something visibly running even at the gate
    stage (a "waiting room" deployment using whatever image tag happens to
    already be resolvable, or a placeholder — see open question below).
  - **`dev`** — `requestedFreight.sources.stages: [gate]`, with
    `autoPromotionOptions.selectionPolicy: MatchUpstream`. Only Freight that
    passed `gate`'s verification can arrive here. Deploys using
    `imageFrom(...).Tag`.
  - **`prod`** — same shape, sourced from `dev`.
- `analysis.yaml` — `AnalysisTemplate/image-exists`, **`job` provider**
  running `crane`:
    ```yaml
    metrics:
    - name: image-exists
      failureLimit: 0
      provider:
        job:
          spec:
            template:
              spec:
                containers:
                - name: check
                  image: gcr.io/go-containerregistry/crane:debug
                  command: ["crane", "manifest",
                    "ghcr.io/akuity/sedemo-monorepo-gatekeeper-app:{{ args.commit-sha }}"]
                restartPolicy: Never
            backoffLimit: 0
    ```
  `crane manifest` performs GHCR's anonymous bearer-token exchange
  internally and exits non-zero if the tag doesn't exist, which Argo
  Rollouts/Kargo's Job provider surfaces as a failed measurement —
  `failureLimit: 0` means one failure fails verification outright (no need
  to retry; the tag either exists or it doesn't, and won't start existing
  mid-check).
- `tasks.yaml` — shared `PromotionTask`s (`prepare-workdir`, `push-manifests`)
  copied from the `demo-auto-rollback` pattern, parameterized per stage.
- `README.md` — states the corrected mental model (Warehouse candidate
  resolution vs. search/lookup), the typesafe.ai scenario as motivation, and
  a live-demo script:
  1. Push a commit to `gatekeeper-app/` with `skip_publish: true` — show
     Freight created immediately from the commit, but `gate` verification
     fails/pending (no image yet).
  2. Re-run the workflow with `skip_publish: false` to publish the image for
     that same commit — show `gate` verification now passes and Freight
     flows through to `dev` and `prod` automatically.

## Open question to resolve during implementation

The `gate` Stage's own `promotionTemplate` needs *something* to deploy even
though, by definition, we don't yet know if an image exists for the
candidate Freight. Options: (a) gate deploys nothing but the verification
Job itself (no app workload at the gate stage — simplest, avoids the
chicken-and-egg), or (b) gate deploys the app pinned to the last known-good
image while verification runs against the new candidate in the background.
Recommend (a) for simplicity — the gate's job is to verify, not to run a
live copy of the app — confirm this during implementation rather than
blocking the spec on it.

## Testing / verification approach

No unit tests — this is Kargo/Argo CD configuration plus a trivial static
app, consistent with how sibling demos in this repo are verified. Validate
via:

- `kubectl apply --dry-run=server` against the Kargo and Argo CD CRDs for
  all new manifests.
- `helm template` against `gatekeeper-app/deploy/chart`.
- A live walkthrough on a real demo cluster following the README's
  live-demo script, confirming Freight is created without an image, gate
  verification blocks promotion, and publishing the image unblocks it.
