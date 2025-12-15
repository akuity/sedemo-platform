# Argo Demo - Platform Setup

This repo respresents the typical objects under control of a central platform team for organizations using Argo CD and Kargo on the Akuity Platform.

## General Access and Change Mangement

### Access to EKS Cluster

To use this repo, first ensure you have access to AWS Account and roles as described in [Infra Demo - AWS Readme](https://github.com/akuity/sedemo-infra-iac/blob/main/core-env/aws/README.md)

### Making changes

Because the new demo environment if fully defined as IaC, you can open pull requests on this repo or infra repo to add or change demos.

## Directory Structure

This repo contains ArgoCD `application` manifests that control all apps, components, and Kargo workflows used in our demo clusters.

- [Demo Apps `apps`](/apps/)  
- [Component Management `components`](/components/)
- [Kargo Projects `kargo`](/kargo/)
- [External Secrets `secrets`](/secrets/)
- [Helm Value Overrides `value-overrides`](/value-overrides)


## Use Cases Demonstrated

### Progressive Delivery with Argo Rollouts

Several apps make use of Argo-Rollouts in their delivery, but the primary one is [rollouts-app](apps/rollouts-app/) which also uses a `control-flow` and `fan-out` pattern in Kargo to deploy to several prod stages concurrently.

#### Rollouts analysis

To enable realistic demo of rollouts, the cluster includes a deployment of Prometheus which monitors traffic for non-200 response codes (which can be triggered from rollouts app UI).  You can see analysis results in Argo's Rollouts tab.

#### App URLS

- [demo-{stage}.akpdemoapps.link](demo-dev.akpdemoapps.link)
- [prometheus.akpdemoapps.link](prometheus.akpdemoapps.link)

### Vendor Helm Charts with custom values

Most external helm charts will need some level of internal customizations. For that we make use of multi-source applications from [components](/components/) which reference value files in [value-overrides](/value-overrides/)

For instance, our [prometheus](/components/)

### Missing / Needed Use Cases

Please note any use cases we should expand, add, or refine.



## Contributing & Dev Notes

### TODOS


- [ ] Push analysisTemplate for use in verifications
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