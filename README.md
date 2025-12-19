# Argo Demo - Platform Setup

This repo respresents the typical objects under control of a central platform team for organizations using Argo CD and Kargo on the Akuity Platform.

## General Access and Change Mangement

### Access to EKS Cluster

To use this repo, first ensure you have access to AWS Account and roles as described in [Infra Demo - AWS Readme](https://github.com/akuity/sedemo-infra-iac/blob/main/core-env/aws/README.md)

### Making changes

Because the new demo environment if fully defined as IaC, you can open pull requests on this repo or infra repo to add or change demos.

## Directory Structure

This repo contains ArgoCD `application` manifests that control all apps, components, and Kargo workflows used in our demo clusters.

- [Demo Apps `apps`](/apps/)  is most of the argo Applications. If adding your own app, add it here. 
- [Component Management `components`](/components/) is for cluster components.
- [Kargo Projects `kargo`](/kargo/) defines the workflows that deploy apps in the first directory.  If creating custom kargo workflows, add it here.
- [External Secrets `secrets`](/secrets/) defines the secrets on our EKS cluster, setup by ESO or cert-manager.
- [Templated Projects](/value-overrides) defines "platform owned" projects where kargo and k8s resources are locked down from application teams. Actual deployable binaries are defined in [app monorepo](https://github.com/akuity/sedemo-monorepo/tree/main/templated)


## Use Cases Demonstrated

### Progressive Delivery with Argo Rollouts

Several apps make use of Argo-Rollouts in their delivery, but the primary one is [rollouts-app](apps/rollouts-app/) which also uses a `control-flow` and `fan-out` pattern in Kargo to deploy to several prod stages concurrently.

#### Rollouts analysis

To enable realistic demo of rollouts, the cluster includes a deployment of Prometheus which monitors traffic for non-200 response codes (which can be triggered from rollouts app UI).  You can see analysis results in Argo's Rollouts tab.

#### App URLS

- [demo-{stage}.akpdemoapps.link](demo-dev.akpdemoapps.link)
- [prometheus.akpdemoapps.link](prometheus.akpdemoapps.link)

### Templatized Projects w/ Helm

The idea of a "golden path" or "standard pipeline" was manifested as a single Kargo project definition templatized w/ Helm. The k8s rollout and ingress is all controlled by central team.  Application teams just build a docker image and have a few parameters they can play with. 
[Templated Projects](/value-overrides)


### Vendor Helm Charts with custom values

Most external helm charts will need some level of internal customizations. For that we make use of multi-source applications from [components](/components/) which reference value files in [value-overrides](/components/value-overrides/)

#### Prometheus 

For instance, our [prometheus](/components/) install pulls vendor provided helm chart, and customizes the use of custom url and scrap jobs via our own [values file](/components/value-overrides/prometheus-values.yaml)

#### Cert Manager

**Not Currently Implemented**

#### External Secrets Operator

Connects to AWS Secrets Manager to pull secrets used in [Local SHard demo](/kargo/kargo-simple/local_shard_eso/).   See Also [secrets](/secrets/)

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