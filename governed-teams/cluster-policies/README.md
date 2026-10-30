# Cluster policies: the backstop

Kargo is the paved road to prod. These Kyverno policies are the lock on the
prod cluster, for anyone who tries to go around the road: `kubectl apply`, a
GitHub Actions job with cluster credentials, an Argo CD app pointed somewhere
else. Many platform teams already run Kyverno, so it's a layer they'll recognize.

They are **not** applied by anything in this repo. Cluster-level policy for the
demo environment lives in `akuity/sedemo-infra-iac`, so applying them is a PR
there and needs the team's agreement. Post in #project-monster-demo first.

| File | Applies to | What it does | Gauntlet |
| --- | --- | --- | --- |
| `prod-only-argocd.yaml` | Prod cluster | In governed prod namespaces, only Argo CD (and the controllers it relies on) may create or change workloads. Everyone else is denied. | 4f, 4g |
| `prod-verify-images.yaml` | Prod cluster | In governed prod namespaces, images must carry a cosign signature from the CI workflow. Starts in Audit; switch to Enforce once CI signs images. | 4f, 4g |
| `kargo-prod-stages.yaml` | Kargo control plane (self-hosted Kargo only, stretch) | A Stage named or labeled prod must run the `prod-controls` task and be labeled `tier: prod`. | 4h |

## Which namespaces they cover

Governed tenants' prod namespaces: anything named `gov-*-prod`, plus anything
labeled `tier: prod`. Argo CD adds that label to every namespace it creates
for a governed tenant (`project-templates/templates/app-applications.yaml`).
The name pattern also covers GitHub Actions tenants, whose namespaces Argo CD
doesn't create. Every other demo's namespaces are left alone.

## Check before applying

- **Argo CD's service account.** `prod-only-argocd.yaml` allows
  `system:serviceaccount:akuity:argocd-application-controller`, which is where
  the Akuity agent runs the application controller. Confirm with
  `kubectl get sa -n akuity` on the cluster.
- **Controllers.** Pods are created by the ReplicaSet controller and Rollouts
  by the Argo Rollouts controller, so both are allowed. If kube-controller-manager
  doesn't use per-controller service accounts on this cluster, also exclude the
  `system:kube-controller-manager` user. If the cluster runs other controllers
  that write to prod namespaces, add them. Test with the dry run below and a
  real sync before switching anything to Enforce in front of a customer.

## Try it without changing anything

Server-side dry run sends a request through admission (including Kyverno)
without creating anything:

```
kubectl apply --dry-run=server -n gov-payments-prod -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata: {name: sneaky, labels: {purpose: demo}}
spec: {containers: [{name: app, image: nginx}]}
YAML
```

With `prod-only-argocd.yaml` applied, this is denied with the policy's message.
`../demo/gauntlet.sh --live` runs these attempts for you.
