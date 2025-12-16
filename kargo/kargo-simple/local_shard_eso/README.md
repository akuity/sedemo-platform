# Local Shard w/ ESO

Runs all warehouse and stages on kargo shard running on EKS cluster. 

- Pulls all secrets from ESO, no secrets stored in Kargo control plane.
- Integrates with Jira for Change Management approval
- Makes call to HTTP service to random service during prod deploy.


## Story Telling

- Heightened security with ESO allows secrets for Github to be rotated on regular basis.
- JIra integration conforms to organization change control process, requiring external approvals.
- HTTP service call allows injecting "dynamic" state to either rendering of manifests or ArgoCD notification. Specific use case was a customer that alternated primary and secondary production environments quarterly. This would allow the deployment stage to query for current leader, and alter the application named passed to ArgoCD control plane. (or use conditional steps, etc.)