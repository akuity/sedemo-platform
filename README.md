# Argo Demo - Platform Setup

This repo respresents the typical objects under control of a central infrastructure or platform team for organizations using Argo CD and Kargo.



### TODOS

- [x] Delcarative Management (seeting in argo cluster settings)
- [ ] Use Application set for app environments.
- [ ] Kargo ROles (dev vs platform)
- [x] Kargo declarative
- [ ] Push analysisTemplate for use in verifications
- [ ] Consider rollouts instead of deployment
- [x] Implement round-robin coloring.
- [x] Implement webhooks for faster response by kargo 
 - [x] Argo (argo cd calls from kargo not working :()
- [x] understand argocd implict health checks - https://docs.kargo.io/user-guide/how-to-guides/argo-cd-integration
- [ ] Source annotations - https://docs.kargo.io/user-guide/how-to-guides/working-with-freight#adding-annotations-with-docker-buildx

## Considerations

### Kargo and ArgoCD Connection

This demo assumes that Kargo and Argo CD are connected with a bi-directional relationship.

#### Kargo has access to Argo CD 
Must be connected when setting up Kargo Agent. If you already have an agent you may add a 2nd, mark it as default, and delete the original.

1) Akuity UI -> Kargo -> <Instance> -> Agents 
2) Register Agent
3) Select Argo CD instance under `Akuity Managed Argo CD Instance`

#### Argo CD can manage Kargo Cluster
1) Akuity UI -> Argo CD -> <Instance> -> Clusters
2) Add Integration
3) Select your Kargo cluster to connect to, and name `kargo` (or upgate kargo app in this repo)