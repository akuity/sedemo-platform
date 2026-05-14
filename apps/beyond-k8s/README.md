# Beyond Kubernetes Demo

Demonstrates GitOps promotion that extends beyond Kubernetes — the same pipeline deploys a container app via Argo CD **and** an AWS Lambda function via Terraform, all driven by Kargo.

## Pipeline

```
Warehouse: app (guestbook image + git)
  → dev         auto-promote; yaml-update Helm values → ArgoCD sync
      → staging-a   parallel; manual gate
      → staging-b   parallel; manual gate
          → prod    requires both staging-a + staging-b; PR gate before merge

Warehouse: fargate (ghcr.io/akuity/sedemo-monorepo-fargate-app)
  → fargate-task-def  updates task definition HCL → terraform apply
```

## Key Concepts

### Kubernetes + Lambda in one pipeline
The `dev`/`staging`/`prod` stages update Helm values and trigger Argo CD syncs for the Kubernetes workload. The parallel `fargate-task-def` stage runs `terraform apply` to update the AWS Lambda task definition — both driven by the same Kargo freight.

### Convergence gate at prod
`prod` uses `availabilityStrategy: All` on its upstream sources, requiring freight to have passed through **both** `staging-a` and `staging-b` before it can proceed.

### PR gate at prod
`prod` opens a pull request for the manifest change rather than pushing directly to main, enabling a human approval step before production.

### Custom promotion steps
Promotions use custom steps: `yaml-update` for Helm values, HCL file patching for Terraform, and `terraform apply`/output to propagate infra changes back into git.

## Namespaces

| Stage | Namespace |
|-------|-----------|
| dev | `beyond-k8s-dev` |
| staging-a | `beyond-k8s-staging-a` |
| staging-b | `beyond-k8s-staging-b` |
| prod | `beyond-k8s-prod` |

## Storytelling Points

- Show the dual warehouse — a container image change and a Lambda change flowing through the same Kargo project
- Show the convergence gate: block one staging branch and observe prod stays locked
- Open the PR created by the prod gate — show that infra promotion is a real, reviewable git event
- Show the Terraform output (Lambda function URL) being committed back to the repo after `apply`
