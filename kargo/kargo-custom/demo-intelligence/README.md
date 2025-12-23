# Intelligence Demo

This demo is migrated from https://github.com/dhpup/akp-demo and demonstrates Akuity Platform capabilities including:

- Guestbook application with progressive delivery through dev → staging → prod
- OOM (Out of Memory) demo for incident response scenarios
- Crashloop demo for debugging scenarios

## Structure

### ArgoCD Applications (`apps/intelligence-demo/`)
- **appproject.yaml** - ArgoCD project definition
- **application-set.yaml** - ApplicationSet for guestbook stages + individual apps for OOM/crashloop demos
- **guestbook/chart/** - Helm chart for the guestbook application
- **oom-demo/** - Deployment that intentionally triggers OOM
- **crashloop-demo/** - Deployment that intentionally crashloops
- **runbooks/** - Runbook documentation for incident response

### Kargo Resources (`kargo/kargo-custom/intelligence-demo/`)
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

## Deployment

```bash
# Apply ArgoCD resources
kubectl apply -f apps/intelligence-demo/

# Apply Kargo resources  
kubectl apply -f kargo/kargo-custom/intelligence-demo/
```
