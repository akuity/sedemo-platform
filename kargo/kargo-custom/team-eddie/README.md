# Many ArgoCDs

This project demonstrates how a single Kargo workflow could deploy across several different ArgoCD instances.  

The kargo control plane needs to be connected to many argoCD instances, and the stages use shard and label matching to target the appropriate applications. 