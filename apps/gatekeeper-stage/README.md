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
