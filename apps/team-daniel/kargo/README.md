# Team Daniel Kargo Pipeline - Ringed Deployment Strategy

This directory demonstrates a **ringed deployment strategy** using Kargo, showcasing progressive rollout patterns commonly used in enterprise environments.

## Ringed Deployment Overview

Ringed deployments (also known as progressive rollout or ring-based deployments) minimize risk by gradually expanding the blast radius of changes:

```
                                        ┌─→ ring-2-useast ─┐
Warehouse → ring-0-canary → ring-1-early┤                  ├→ ring-3-global  
                                        └─→ ring-2-euwest ─┘
```

### Ring Definitions

| Ring | Stage | Purpose | Blast Radius | Auto-Promote |
|------|-------|---------|--------------|--------------|
| **0** | `ring-0-canary` | Internal/canary testing | <1% | ✅ Yes |
| **1** | `ring-1-early` | Early adopters | ~5% | ✅ Yes |
| **2** | `ring-2-useast` | Regional (US East) | ~30% | ❌ No |
| **2** | `ring-2-euwest` | Regional (EU West) | ~30% | ❌ No |
| **3** | `ring-3-global` | Full production | 100% | ❌ No |

## Verification Gates

Each ring has verification analysis to validate health before proceeding:

| Template | Used By | Purpose |
|----------|---------|---------|
| `ring-health-check` | Ring 0 | Basic health validation |
| `ring-success-rate` | Ring 1 | Success rate meets threshold |
| `ring-regional-health` | Ring 2 | Regional latency & error rates |

## Promotion Flow

1. **Ring 0 (Canary)**: New freight auto-promotes immediately for fast feedback
2. **Ring 1 (Early)**: Auto-promotes after Ring 0 verification passes
3. **Ring 2 (Regional)**: Manual approval required; US East and EU West deploy in parallel
4. **Ring 3 (Global)**: Requires BOTH Ring 2 stages to be verified before promotion

## Key Features Demonstrated

- **Parallel stages**: Ring 2 regions deploy simultaneously
- **Convergent promotion**: Ring 3 requires multiple upstream stages
- **Graduated auto-promotion**: Fast iteration in early rings, controlled rollout in production
- **Verification gates**: Analysis templates between rings

## Files

- [project.yaml](project.yaml) - Project + promotion policies (auto-promote config per ring)
- [warehouse.yaml](warehouse.yaml) - Subscribes to Git repo and container image
- [stages.yaml](stages.yaml) - 5-stage ringed pipeline definition
- [tasks.yaml](tasks.yaml) - PromotionTasks for promotion strategies
- [analysis.yaml](analysis.yaml) - Dummy verification templates for demo
