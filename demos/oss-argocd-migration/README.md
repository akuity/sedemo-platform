# OSS Argo CD → Akuity: zero-downtime migration demo

A local k3d cluster stands in for an on-prem site running its own self-hosted
Argo CD. We connect it to the hosted Akuity instance with the agent, hand the
apps over, and prove nothing was redeployed and the service never dropped a
request.

The whole migration, per app:

1. **Old Argo CD: turn off auto-sync and self-heal.** It keeps comparing but never writes.
2. **Akuity: apply the same Application, same Git repo.** Only `destination` changes
   (`server: https://kubernetes.default.svc` → `name: <agent cluster>`). The app
   name is unchanged, so the tracking id on the live resources still matches and
   Akuity adopts them in place.
3. **Later: retire the old Application, non-cascade.** Until then it is the rollback path.

## Prerequisites

- `k3d`, `kubectl`, `yq` (mikefarah v4), `jq`, `akuity`, `argocd` CLIs
- `akuity login` (Akuity org `demo`, instance `se-demo-iac`)
- `argocd login argo.akpdemoapps.link --sso --grpc-web` (teardown only)

Settings live in `env.sh`; override with env vars (`CLUSTER_NAME`, `OSS_ARGOCD_VERSION`, ...).

## Before the call

```bash
./00-setup.sh        # k3d cluster edge-site-1 + OSS Argo CD + 3 apps + uptime probe (~3 min)
akuity whoami        # token still valid? (it expires daily: akuity login)
for i in 1 2 3 4 5; do git ls-remote https://github.com/argoproj/argocd-example-apps HEAD; done
```

Every `ls-remote` should return a commit ID immediately. If any hang, switch
networks (phone hotspot): GitHub is served from many IPs, and an ISP path
problem to some of them makes the agent's repo-server intermittently fail.
The app then shows sync `Unknown` with a Git timeout while health stays
`Healthy` and the workloads are untouched; it recovers on its own.

Open three windows: the Akuity UI (Applications, filter `edge-`), the OSS UI
(`kubectl --context k3d-edge-site-1 -n argocd port-forward svc/argocd-server 8080:443`,
password printed by setup), and a terminal in this directory.

Fallback if the network is bad: run `./02-connect.sh` before the call, so the
agent is already connected and the live portion starts at step 03.

## Live run

`PAUSE=1` prints each command and waits for Enter before running it.

| Script | Say |
|---|---|
| `PAUSE=1 ./01-before.sh` | "Self-hosted Argo CD, three apps, all auto-sync and self-heal. Note the pod UIDs. This annotation is how Argo CD knows what it owns: app name plus resource." |
| `PAUSE=1 ./02-connect.sh` | "Register the site, then one manifest. The agent dials out to the control plane; nothing inbound is opened. It runs in its own namespace, next to the existing Argo CD, with no CRDs and no shared RBAC objects." |
| `PAUSE=1 ./03-handoff.sh` | "Step one, old Argo CD stops writing. Step two, the same Application from the same repo on Akuity; only the destination changes." Switch to the Akuity UI: `edge-guestbook` is Synced/Healthy **without running a sync**. |
| `PAUSE=1 ./04-verify.sh` | "Same pods, same UIDs, zero restarts, zero failed requests. Now who's in charge? Scale it to 2 by hand: Akuity puts it back within seconds. The old instance's last sync time hasn't moved." |
| `PAUSE=1 ./05-bulk.sh` | "Now every remaining app and project on that instance in one pass: export, rewrite, **diff against the instance before touching anything**, disable on OSS, apply." |
| `PAUSE=1 ./03b-retire.sh edge-guestbook edge-helm-guestbook edge-kustomize-guestbook` | "Once you're comfortable, retire the old Applications. Drop the finalizer first so the delete doesn't cascade. Then the old Argo CD can be uninstalled." |

## Verified in rehearsal (Akuity Argo CD v3.5.5-ak, agent v0.5.10x)

| | OSS v3.5.5 (annotation tracking) | OSS v2.14.21 (label tracking) |
|---|---|---|
| Agent install next to OSS | No CRDs, cluster-suffixed ClusterRoles, OSS unaffected | same |
| Adoption on apply | Synced/Healthy, no sync operation | Synced/Healthy, no sync operation |
| Pods across cutover | identical UIDs, 0 restarts | identical UIDs, 0 restarts |
| Uptime probe (2 req/s) | 868/868 OK | 292/292 OK |
| Tracking metadata | already matches | **one sync** rewrites label → annotation (metadata-only patch, pods untouched) |

Label-tracked (2.x) sources: run one sync per app after cutover so Akuity records
ownership and pruning works. After that, rolling back to the old 2.x instance needs
an OSS sync to restore its label.

## Gotchas found in rehearsal

- **Export before you disable.** Whatever the OSS spec says at export time is what
  Akuity gets. Export an app after removing `automated` and it lands on Akuity with
  no auto-sync. `akuity argocd diff` shows this before you apply it.
- **Never `akuity argocd apply --prune`** against a shared instance: it deletes every
  app/project/etc. of that type not present in the file.
- **Non-cascade means no finalizer.** OSS Applications carry
  `resources-finalizer.argocd.argoproj.io`. A default delete from the old UI or CLI
  removes the live workloads that Akuity now manages.
- **Nobody clicks Sync on the old instance** while both exist. With auto-sync off it
  only compares, but a manual sync still writes.
- `akuity argocd diff` takes the instance as a positional argument; `apply` uses `--name`.
- `argocd app delete --wait` never returns over grpc-web; teardown polls instead.
- In `argocd-rbac-cm`, a `*/*` object pattern matches apps (`project/app`) but not
  projects (`project`). That's why teardown leaves the `edge-site` AppProject in place.

## Reset

```bash
./99-teardown.sh     # Akuity apps (non-cascade), cluster registration, k3d cluster
./00-setup.sh
```

## Not covered here; confirm before claiming

- Agent behavior while a site is disconnected. The documented feature is **State
  Replication** (`STATE_REPLICATION=1 ./02-connect.sh`, i.e. `cluster create
  --state-replication`): "allows disconnecting the cluster from the Akuity Platform
  without losing core Argo CD features", and it can **only be set at initial agent
  deployment**, so decide per site before connecting. Not documented: which
  features exactly, whether Git must be reachable from the site, reconnect behavior.
- `get-agent-manifests --offline-installation` is for self-hosted / air-gapped
  installs, not for intermittently connected sites.
- Private repos: repo credentials are Secrets labeled
  `argocd.argoproj.io/secret-type`; export and apply them alongside the apps.
