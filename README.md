# Akuity Demo - Platform Setup

This repo represents the typical objects under control of a central platform team for organizations using Argo CD and Kargo on the Akuity Platform.

## Just want to run demos?

- [argo.akpdemoapps.link](//argo.akpdemoapps.link)
- [kargo.akpdemoapps.link](//kargo.akpdemoapps.link)

Use SSO sign-in. If you don't have access, bug [@eddiewebb](//github.com/eddiewebb)


## General Access and Change Management

This repo contains 3 layers of IaC

- AWS Infrastructure via Terraform
- K8s Platform Config via Terraform
- Application Layer Config via Argo CD

### Access to EKS Cluster

To make any AWS or EKS level changes you will need access to the AWS Account and roles as described in [Infra Demo - AWS Readme](https://github.com/akuity/sedemo-infra-iac/blob/main/core-env/aws/README.md)

### Making Argo or Kargo demo app changes

Because this demo environment is fully defined as IaC, you can open pull requests on this repo or the infra repo to add or change demos.

## Directory Structure

```
.
├── bootstrap/          # ApplicationSets that bootstrap all ArgoCD and Kargo apps
├── apps/               # One directory per demo app
│   └── <app-name>/
│       ├── argocd/     # AppProject + ApplicationSet for this app
│       ├── kargo/      # Kargo Project, Warehouse, Stages, and Tasks
│       └── ...         # App-specific manifests (base, stages, chart, etc.)
├── kargo-shared/       # Shared Kargo platform resources (CustomPromotionSteps, etc.)
├── components/         # Cluster add-ons (Argo Rollouts, Prometheus, ESO, cert-manager)
├── secrets/            # ExternalSecret and SecretStore resources (backed by AWS Secrets Manager)
└── templated-teams/    # Helm-templated "golden path" projects for app teams
```

### Bootstrap

`bootstrap/` contains two ApplicationSets managed by the top-level `app-of-apps` ArgoCD Application (defined in [`sedemo-infra-iac`](https://github.com/akuity/sedemo-infra-iac)):

- **`argocd-apps.yaml`** — discovers `apps/*/argocd/` and creates one ArgoCD Application per app using `project: default` (avoids chicken-and-egg with AppProjects living inside the synced path)
- **`kargo-apps.yaml`** — discovers `apps/*/kargo/` and creates one ArgoCD Application per app targeting the `kargo` cluster

### Apps

Each app under `apps/` is self-contained:

- `argocd/` holds the `AppProject` and an `ApplicationSet` (or individual `Application` manifests) for that app's stages
- `kargo/` holds all Kargo resources: `Project`, `Warehouse`, `Stage`, `PromotionTask`, etc.
- Additional directories (e.g. `base/`, `stages/`, `chart/`) hold the actual Kubernetes manifests promoted by Kargo

### Components

Cluster add-ons installed via ArgoCD, including:
- Argo Rollouts (with `ServerSideApply=true` due to CRD size)
- Prometheus
- External Secrets Operator
- cert-manager


## Use Cases Demonstrated

### Progressive Delivery with Argo Rollouts

[`apps/demo-rollouts`](/apps/demo-rollouts/) demonstrates blue/green and canary delivery using Argo Rollouts with a `fan-out` pattern in Kargo to deploy to multiple prod stages concurrently.

Prometheus monitors traffic for non-200 response codes (triggerable from the rollouts app UI) and feeds Rollouts analysis results.

**URLs:**
- `demo-{stage}.akpdemoapps.link`
- `prometheus.akpdemoapps.link`

### Templatized Projects with Helm

[`templated-teams/`](/templated-teams/) provides a "golden path" — a single Kargo project definition templated with Helm. The platform team controls the k8s rollout and ingress; app teams only supply a Docker image and a few parameters.

### Vendor Helm Charts with Custom Values

[`components/`](/components/) uses multi-source ArgoCD Applications that pull vendor Helm charts and apply custom value files from `components/value-overrides/`.

### External Secrets

[`secrets/`](/secrets/) defines `ExternalSecret` and `SecretStore` resources connecting to AWS Secrets Manager via the External Secrets Operator.


## Kargo + ArgoCD Connection

This demo assumes Kargo and ArgoCD are connected bidirectionally via the Akuity Platform.

### Kargo has access to ArgoCD

Configured when registering the Kargo agent — select the ArgoCD instance under `Akuity Managed Argo CD Instance`.

1. Akuity UI → Kargo → `<Instance>` → Agents → Register Agent
2. Select your ArgoCD instance

### ArgoCD can manage the Kargo cluster

The Kargo cluster must be registered in ArgoCD as a cluster named `kargo` (this is what `kargo-apps.yaml` targets).

1. Akuity UI → ArgoCD → `<Instance>` → Clusters → Add Integration
2. Select your Kargo cluster and name it `kargo`