# Guestbook Helm

Simple Helm-based guestbook deployment using the ArgoCD example apps repository. No Kargo pipeline — ArgoCD only, used to demonstrate basic multi-environment Helm deployments.

## Deployment

Three stages managed by a single ApplicationSet:

| Stage | Namespace |
|-------|-----------|
| dev | `guestbook-dev` |
| prod | `guestbook-prod` |
| prod2 | `guestbook-prod2` |

## Source

Chart sourced from [`argoproj/argocd-example-apps`](https://github.com/argoproj/argocd-example-apps) at path `helm-guestbook`. No local chart — all values come from upstream.

## Notes

- No Kargo Warehouse or Stages — promotion is handled manually or via ArgoCD sync policies
- Automated sync with prune enabled on all stages
- Deploys to `sedemo-primary` cluster
