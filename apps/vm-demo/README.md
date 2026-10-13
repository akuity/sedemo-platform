# vm-demo

Kargo governing deployments to plain virtual machines, with the same Freight,
gates and audit trail it uses for Kubernetes. Kargo does not replace the
existing VM tooling: it renders the exact config for each stage, commits it to
git, and dispatches a GitHub Actions workflow that runs Terraform (VM
lifecycle) and Ansible (app deploy) against Proxmox.

The app is the existing rollouts demo (`ghcr.io/akuity/sedemo-monorepo-rollouts-app`,
tags like `50-blue`). Its image is `FROM scratch`, so converge extracts the
binary and web assets and runs them natively on each VM under systemd. The
demo promotes already-published tags only.

## Pipeline

```
Warehouse app         (image ghcr.io/akuity/sedemo-monorepo-rollouts-app
                       + sedemo-monorepo vm-app/config-chart)
Warehouse base-image  (sedemo-vm-infra images/base.json, a Packer-baked template)

dev  -> qa  -> sit  -> uat  -> prod
auto    auto   manual  manual  manual
rollback                PR      change request + PR
```

| Stage | Promotion | Gate | Verification |
|---|---|---|---|
| dev | auto, `autoRollback` | commit + push | `/env` semver + stage, `/color` error rate, every stage VM |
| qa | auto | commit + push | same + smoke (`/` serves the HTML page) |
| sit | manual | commit + push | same as dev |
| uat | manual | PR into `rendered/vm-demo/uat`, wait for merge | same as dev |
| prod | manual | Jira CHANGE issue (wait for Approved) + PR, then a result comment on the issue | same, two VMs |

All Stages run on the self-hosted `team-ada` shard, whose cluster can reach
the Proxmox API and the VMs, so verification jobs run next to them.

## What a promotion does

1. `vm-render` (PromotionTask, `kargo/tasks.yaml`):
   - clones this repo, the config chart at the Freight commit, and the
     infra repo at the base-image Freight commit;
   - reads `images/base.json` for the template name and VMID;
   - renders `rollouts-demo.env` (the app's systemd EnvironmentFile) from
     the chart with `env/<stage>/values.yaml`, setting `color` (the tag
     suffix), `semver` (the tag) and `stage`. A missing required value
     fails here, before any VM is touched;
   - fills `deploy.yaml` (app version, artifact, base template, Freight);
   - commits both files to branch `rendered/vm-demo/<stage>`.
2. The Stage pushes directly (dev, qa, sit) or opens a PR and waits for it
   to merge (uat, prod).
3. `vm-converge` dispatches `converge.yml` in the infra repo with the stage
   and the full rendered commit SHA, then waits for it to succeed. Converge
   is idempotent: an app promotion is a Terraform no-op and an Ansible
   deploy; a base-image promotion replaces the stage's VMs (prod one at a
   time).

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
  `team-ada` shard runs verification jobs. Never committed here.
- Shared Kargo credentials for `jira-access-secret` (prod CHANGE issues) and
  GitHub access to the infra repo for the `gha-*` steps.

## Tests

```
bash apps/vm-demo/kargo/tests/verify_test.sh
```

Requires bash, python3, curl, jq and yq. `VERIFY_SH=dash` runs the script
under another POSIX shell.
