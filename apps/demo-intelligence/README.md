# Intelligence Demo

This demo is migrated from https://github.com/dhpup/akp-demo and demonstrates Akuity Platform capabilities including:

- Guestbook application with progressive delivery through dev → staging → prod
- OOM (Out of Memory) demo for incident response scenarios
- Crashloop demo for debugging scenarios

## Structure

### ArgoCD Applications (`apps/demo-intelligence/`)
- **appproject.yaml** - ArgoCD project definition
- **application-set.yaml** - ApplicationSet for guestbook stages + individual apps for OOM/crashloop demos
- **guestbook/chart/** - Helm chart for the guestbook application
- **oom-demo/** - Deployment that intentionally triggers OOM
- **crashloop-demo/** - Deployment that intentionally crashloops
- **runbooks/** - Runbook documentation for incident response

### Kargo Resources (`kargo/kargo-custom/demo-intelligence/`)
- **project.yaml** - Kargo project with auto-promotion for crashloop stage
- **warehouse.yaml** - Watches `ghcr.io/akuity/guestbook` images
- **stages.yaml** - Five stages: dev, staging, prod, prod-oom, prod-crashloop
- **tasks.yaml** - Promotion tasks for updating Helm values or sync-only

## Stages

### Dev → Staging → Prod
Progressive delivery of guestbook application with image tag updates via Helm.

### Prod-OOM
Sync-only promotion - demonstrates OOM scenario for incident response training.

### Prod-Crashloop
Auto-promoted, sync-only - demonstrates crashloop scenario for debugging.

## Running the OOM demo

Git always holds the **broken** state (128Mi limit, `stress` allocates ~143Mi). The
AI-SRE agent only patches the live Deployment, so a sync from Git resets the demo.

1. **Prerequisite:** paste `runbooks/oom.md` into the instance's AI runbook settings in
   the Akuity Platform and replace the `PLEASE REPLACE` Slack channel.
2. **Break it:** sync `demo-intelligence-prod-oom` (or promote freight to the
   `prod-oom` stage). The pod is OOMKilled and never becomes Ready. After ~30s the app
   goes **Degraded** and stays Degraded.
3. **Fix it:** the agent triages, proposes a +50Mi memory bump (128Mi → 178Mi), and
   waits for approval. Approve it. About 20s later the app is **Healthy** and shows
   **OutOfSync** because the change is live-only.
4. **Reset:** sync `demo-intelligence-prod-oom` again. The 128Mi limit is restored and
   the app goes Degraded again, ready for the next run.

Do not commit memory changes for `oom-demo/manifest.yaml` to Git, and don't enable
automated sync or self-heal on `demo-intelligence-prod-oom`. Either one would break the
reset loop or undo the agent's fix mid-demo.

## Deployment

```bash
# Apply ArgoCD resources
kubectl apply -f apps/demo-intelligence/

# Apply Kargo resources  
kubectl apply -f kargo/kargo-custom/demo-intelligence/
```
