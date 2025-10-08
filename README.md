# Argo Demo - Platform Setup

This repo respresents the typical objects under control of a central infrastructure or platform team for organizations using Argo CD and Kargo.



### TODOS

- [x] Delcarative Management (seeting in argo cluster settings)
- [ ] Use Application set for app environments.
- [ ] Kargo declarative
    Apparently this will need to be a CI pipeline to call kargo apply directly.
- [ ] Push analysisTemplate for use in verifications
- [x] Implement round-robin coloring.
- [x] Implement webhooks for faster response by kargo 
 - [x] Argo (argo cd calls from kargo not working :()
- [x] understand argocd implict health checks - https://docs.kargo.io/user-guide/how-to-guides/argo-cd-integration