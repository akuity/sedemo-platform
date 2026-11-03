# Intelligence Demo

This demo is migrated from https://github.com/dhpup/akp-demo and demonstrates Akuity Platform capabilities including:

- Guestbook application with progressive delivery through dev → staging → prod
- OOM (Out of Memory) demo: the AI-SRE agent diagnoses an OOMKilled pod and raises its memory limit
- Crashloop demo: the AI-SRE agent diagnoses a CrashLoopBackOff caused by misconfigured probes and fixes them

The OOM and crashloop demos are independent: each opens its own incident, and each can be
broken, fixed, and reset on its own.

## Structure

### Argo CD (`apps/demo-intelligence/`)
- **argocd/appproject.yaml** - Argo CD project definition
- **argocd/application-set.yaml** - ApplicationSet for guestbook stages + individual apps for the OOM/crashloop demos
- **chart/** - Helm chart for the guestbook application
- **oom-demo/** - Deployment that intentionally gets OOMKilled
- **crashloop-demo/** - Deployment whose probes point at the wrong port, so it crashloops
- **runbooks/** - AI-SRE runbooks (`oom.md`, `crashloop.md`) to paste into the Akuity Platform

### Kargo (`apps/demo-intelligence/kargo/`, auto-synced by the `kargo-demo-intelligence` app)
- **project.yaml** - Kargo project (auto-promotion is **off** for every stage)
- **warehouse.yaml** - Watches `ghcr.io/akuity/guestbook` images
- **stages.yaml** - Five stages: dev, staging, prod, prod-oom, prod-crashloop
- **tasks.yaml** - Promotion tasks for updating Helm values or sync-only

## Stages

### Dev → Staging → Prod
Progressive delivery of guestbook application with image tag updates via Helm.

### Prod-OOM / Prod-Crashloop
Sync-only promotions. Promoting freight to either stage re-syncs the demo app from Git,
which is the same as "break it" below.

## AI-SRE setup (Akuity Platform UI)

Agent configuration for the `se-demo-iac` instance (Incidents tab):

- **Runbooks:** `pod-oom` (from `runbooks/oom.md`) applied to `demo-intelligence-prod-oom`,
  and `pod-crashloop` (from `runbooks/crashloop.md`) applied to
  `demo-intelligence-prod-crashloop`. Both post to the `incidents` Slack channel.
- **Resource Degradation Trigger:** applications `demo-intelligence-*`, any cluster,
  trigger immediately. Scope it by application name: with applications `*`, every
  Degraded app on the instance opens an incident, even when a namespace is also set.
- **Incidents Grouping:** leave **empty**. Grouping by the `demo-intelligence` namespace
  merges the OOM and crashloop incidents into one.

## How every demo works

Git always holds the **broken** state. The AI-SRE agent only patches the live Deployment,
so the app shows **OutOfSync** after the fix, and a sync from Git resets the demo.

Between demos, leave the app in its **fixed** state (Healthy / OutOfSync) so it isn't
crashlooping for days. Break it right before you present.

**Before each run**, check that no incident is open for the app you are about to break.
While an incident is open, new Degraded events are added to it instead of starting a new
triage, and a reset sync during an open incident makes the agent think its fix failed.

Do not commit the fixes to Git, and don't enable automated sync or self-heal on
`demo-intelligence-prod-oom` or `demo-intelligence-prod-crashloop`. Either one would break
the reset loop or undo the agent's fix mid-demo.

## Running the OOM demo

The bug: 128Mi memory limit, while `stress` allocates ~143Mi.

1. **Break it:** sync `demo-intelligence-prod-oom` (or promote freight to `prod-oom`).
   The pod is OOMKilled and never becomes Ready. ~30s later the app goes **Degraded**
   and an incident opens.
2. **Fix it:** the agent triages, proposes a +50Mi memory bump (128Mi → 178Mi), and
   waits for approval. Approve it. ~20s later the app is **Healthy** / **OutOfSync**,
   and the agent resolves the incident after its 60s stability check.
3. **Reset:** once the incident is resolved, sync again to restore the 128Mi limit.

## Running the crashloop demo

The bug: guestbook listens on port 3000 (`--port=3000`), but the liveness and readiness
probes check port 30000. The liveness probe kills the container every ~10s.

1. **Break it:** sync `demo-intelligence-prod-crashloop` (or promote freight to
   `prod-crashloop`). The pod goes into **CrashLoopBackOff** and never becomes Ready.
   ~30s later the app goes **Degraded** and an incident opens.
2. **Fix it:** the agent finds the probe-port mismatch and proposes pointing both
   probes at port 3000. Approve it. The pod becomes Ready within ~15s and the app is
   **Healthy** / **OutOfSync**; the agent resolves the incident after 60s.
3. **Reset:** once the incident is resolved, sync again to restore the broken probes.

## Deployment

```bash
# Apply Argo CD resources
kubectl apply -f apps/demo-intelligence/argocd/

# Kargo resources in apps/demo-intelligence/kargo/ are synced automatically
# by the kargo-demo-intelligence Argo CD application.
```
