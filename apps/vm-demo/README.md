# vm-demo

Kargo governing deployments to plain virtual machines, with the same Freight,
gates and audit trail it uses for Kubernetes. Kargo does not replace the
existing VM tooling: it renders the exact config for each stage, commits it to
git, and dispatches a GitHub Actions workflow that runs Terraform (VM
lifecycle) and Ansible (app deploy) against Proxmox.

## Pipeline

```
Warehouse nav-service  (ORAS artifact ghcr.io/akuity/sedemo-monorepo-nav-service
                        + sedemo-monorepo vm-app/config-chart)
Warehouse base-image   (sedemo-vm-infra images/base.json, a Packer-baked template)

dev  -> qa  -> sit  -> uat  -> prod
auto    auto   manual  manual  manual
rollback                PR      change request + PR
```

| Stage | Promotion | Gate | Verification |
|---|---|---|---|
| dev | auto, `autoRollback` | commit + push | `/healthz` on every stage VM |
| qa | auto | commit + push | same + smoke (`/` content, `/version` stage) |
| sit | manual | commit + push | same as dev |
| uat | manual | PR into `rendered/vm-demo/uat`, wait for merge | same as dev |
| prod | manual | change request (wait for Implement) + PR, then `snow-update` to Review | same, two VMs |

All Stages run on the self-hosted `homelab` shard so verification jobs can
reach the Proxmox API and the VMs.

## What a promotion does

1. `vm-render` (PromotionTask, `kargo/tasks.yaml`):
   - clones this repo, the config chart at the Freight commit, and the
     infra repo at the base-image Freight commit;
   - reads `images/base.json` for the template name and VMID;
   - renders `config.yaml` from the chart with `env/<stage>/values.yaml`
     (a missing required value fails here, before any VM is touched);
   - fills `deploy.yaml` (app version, artifact, base template, Freight);
   - commits both files to branch `rendered/vm-demo/<stage>`.
2. The Stage pushes directly (dev, qa, sit) or opens a PR and waits for it
   to merge (uat, prod).
3. `vm-converge` dispatches `converge.yml` in the infra repo with the stage
   and the rendered commit SHA, then waits for it to succeed. Converge is
   idempotent: an app promotion is a Terraform no-op and an Ansible deploy;
   a base-image promotion replaces the stage's VMs (prod one at a time).

Re-promoting the same Freight (auto-rollback, retries) renders identical
files. The commit is a no-op, uat/prod skip the PR, and converge still runs.

## Layout

```
apps/vm-demo/
  env/<stage>/values.yaml   per-stage chart values (platform-owned)
  env/<stage>/deploy.yaml   deploy pin template, filled in by the promotion
  kargo/                    Project, Warehouses, PromotionTasks, Stages,
                            AnalysisTemplate (auto-discovered by
                            bootstrap/kargo-apps.yaml)
  kargo/verify.sh           tested source of the verification script
  kargo/tests/              tests for verify.sh
```

There is no `argocd/` directory: nothing here runs on Kubernetes.

## Out-of-band prerequisites

- Secret `vm-demo-proxmox-verify` (keys `PROXMOX_URL`, `TOKEN_ID`,
  `TOKEN_SECRET`; a read-only Proxmox API token) in the namespace where the
  homelab shard runs verification jobs. Never committed here.
- Shared Kargo credentials for `kargo-step-snow` (prod change requests) and
  GitHub access to the infra repo for the `gha-*` steps.

## Tests

```
bash apps/vm-demo/kargo/tests/verify_test.sh
```
