# Edge sites offline: Argo CD State Replication off vs on, and Kargo

Two kind clusters (on OrbStack) stand in for on-prem sites with unreliable connectivity. They
are identical except for one install-time setting on the Akuity Argo CD agent:

| Site | State Replication |
|---|---|
| `edge-sr-off` | off (default) |
| `edge-sr-on` | on (`akuity argocd cluster create ... --state-replication=true`) |

Each site runs the same two apps from the `se-demo-iac` instance:

- `<site>-github`: guestbook from GitHub (a site pulling from cloud Git)
- `<site>-local`: a small app from a **Gitea server inside the site** (a site with
  a local Git mirror, so Git survives a full internet outage)

Kargo (`se-demo-iac-kargo`, project `edge-offline`) has:

- `central-sr-off`, `central-sr-on`: Stages run by the instance's **central
  (Akuity-managed) agent**, promoting GitHub commits into the `-github` apps
- `edge-sr-on-local`: a Warehouse + Stage on a **self-hosted Kargo agent running in
  `edge-sr-on`**; the Warehouse watches the site's own Gitea, so the whole pipeline
  is local to the site

`outage.sh` simulates two kinds of outage inside one site's kind node (iptables /
ip6tables `raw` table; nothing on the laptop changes, and `kubectl` keeps working):

| Mode | Blocks | Still reachable |
|---|---|---|
| `link-down` | Akuity control plane | GitHub, registries, in-site Gitea |
| `offline` | everything leaving the site | in-site traffic, in-site Gitea |

## Setup

```bash
akuity login
argocd login argo.akpdemoapps.link --sso --grpc-web
kargo login https://kargo.akpdemoapps.link --sso     # teardown and scripted promotions
./00-setup.sh        # ~5 min: 2 kind sites, agents, Gitea, apps, Kargo agent + project
./state.sh           # both views of each site: what Akuity says, what's really running
```

## Tools

| Script | Does |
|---|---|
| `outage.sh <site> link-down\|offline\|restore\|status` | start/stop an outage; `status` warns if the hook was displaced |
| `netcheck.sh <site>` | what the site can reach (Akuity, GitHub, in-site Gitea), seen from a policy-selected pod like the agents |
| `state.sh [site...]` | Akuity's view vs the site's reality, incl. SR local copies |
| `push.sh <site> <msg>` | commit a new `edge-config.message` to the site's Gitea (works while offline) |
| `experiment.sh [offline\|link-down] [min]` | the full scripted run below, one log line per minute, re-checking the outage is real on every line |

The in-site Gitea uses a fixed `demo` / `demo-pass-123` login: it exists only inside
the throwaway kind cluster and is reachable only through `kubectl port-forward`.

## Short demo (recommended): sites already offline

```bash
./stage-offline.sh       # 10+ min before: both sites offline; waits until the dashboard shows them down
./demo-offline.sh        # live, ~4 min: drift, new release in local Git, node reboot, recovery
PAUSE=1 ./demo-offline.sh   # same, waiting for Enter before each step
./state.sh --brief       # one line per site: running vs Git, at any time
```

`demo-offline.sh` prints each step, the point to make, and a one-line-per-site view
(green = matches Git, red = doesn't). It waits on real conditions, not fixed sleeps,
and leaves both sites online at the end. Talk track per step:

1. **Manual change**: "Nothing enforces Git at the site without State Replication; with it, the site puts it back on its own."
2. **New release in local Git**: "Argo CD polls Git every few minutes; to save time we ask each site to check now, locally. The SR site refreshes its local copy and deploys from its mirror, no control plane involved. The other site has no local copy to ask." (Unprompted pickup takes 2-6 min: poll interval plus repo-server revision cache.)
3. **Node reboot**: "Without SR the controller can't even load its config. With SR it starts from the local copy."
4. **Link back**: "SR off catches up in about a minute; SR on was already right; the dashboard turns green last."

Run `./stage-offline.sh` again before each rehearsal or call (each run of
`demo-offline.sh` ends with the sites online). It first resets the `-local` apps to
track Git HEAD: a Kargo promotion to `edge-sr-on-local` pins `sr-on-local` to a
commit (`updateTargetRevision`), and a pinned app correctly ignores new commits.

## Live demo, step by step (about 5 minutes)

```bash
./outage.sh edge-sr-off offline; ./outage.sh edge-sr-on offline
./netcheck.sh edge-sr-on                          # Akuity + GitHub unreachable, local Git fine
kubectl --context kind-edge-sr-off -n edge-app scale deploy edge-app --replicas=3
kubectl --context kind-edge-sr-on  -n edge-app scale deploy edge-app --replicas=3
sleep 20; ./state.sh                               # SR on: back to 1. SR off: still 3.
kubectl --context kind-edge-sr-off -n akuity delete pod -l app.kubernetes.io/name=argocd-application-controller
kubectl --context kind-edge-sr-on  -n akuity delete pod -l app.kubernetes.io/name=argocd-application-controller
sleep 60; ./state.sh                               # "node reboot": SR off controller 2/3, SR on 3/3
./outage.sh edge-sr-off restore; ./outage.sh edge-sr-on restore
sleep 45; ./state.sh                               # SR off catches up: drift reverted
```

Talk track: "Same agent, one install-time switch. With it off, the site keeps
running what it has, but nothing enforces Git until the link is back, and a reboot
during the outage leaves it without working GitOps. With it on, the site keeps
enforcing Git on its own, picks up new commits from a local mirror, and survives a
restart. When the link returns, the control plane's view wins."

## Results (Argo CD v3.5.5-ak, agent v0.5.10x, Kargo v1.12.4-ak, 2026-10-20)

Reproduced on k3d (Docker Desktop) and on kind (OrbStack). From `experiment.sh` runs on both sites at once (`offline` and `link-down`, with and
without the controller restart), with the outage verified on every logged line,
plus the targeted UI/CLI tests noted. Both outage modes gave the same results.

| During the outage | SR **off** | SR **on** |
|---|---|---|
| Running workloads | keep running | keep running |
| Manual drift (scale a Deployment) | **stays drifted**, while its controller still shows Ready | **reverted within 20 s** |
| App controller restarted mid-outage (node reboot) | comes back **not Ready (2/3)**: it reads Applications, settings and secrets from the control plane API and can't | comes back **Ready (3/3)** and keeps reverting drift from its local copy |
| New commit in reachable Git (in-site Gitea) | not applied | **applied within 2.7 min** (normal poll; verified with no controller restart) |
| Sync clicked in the UI / CLI | rejected immediately ("error resolving repo revision") | same |
| App edited in the UI / CLI | rejected (validation can't reach the cluster); `--validate=false` forces it | same; the site keeps its local copy until reconnect |
| On reconnect | catches up within 15-70 s: drift reverted, new commits applied | **control plane wins**: an edited spec replaces the local copy |
| Akuity cluster health | lagged the outage by **2.5 to 10 min** across runs (HEALTHY, then DEGRADED or UNKNOWN); PROGRESSING ~60 s after reconnect | same lag |

Kargo, both sites fully offline for 8 min (promotions requested from the Kargo
UI/API while offline; outage re-verified every minute):

| | Central (Akuity-managed) agent | Self-hosted agent in the site |
|---|---|---|
| Promotion requested while the site is offline | starts at once, `argocd-update` waits, then **Aborted: "step timed out after 5m0s"** | **not picked up** (no phase) until the link returns |
| On reconnect | nothing to resume; re-promote | picks it up and **Succeeds ~1.5 min after reconnect** |
| New commit in the site's Git during the outage | n/a (central can't see in-site Git) | **not discovered** until reconnect (~1 min after), because Freight lives in the control plane |

What State Replication changes in the cluster:

- The agent also installs the `applications.argoproj.io` and `appprojects.argoproj.io`
  CRDs (SR off installs **no** CRDs). On a site that still runs OSS Argo CD these
  replace the OSS CRDs (see `demos/oss-argocd-migration/README.md`).
- The site's own Applications are copied into the `akuity` namespace (2 of 198 on
  the instance), and **every AppProject on the instance** (38 of 38), plus the full
  `argocd-cm`, is copied too: other teams'/environments' project definitions live on
  every SR site.
- It can only be set when the cluster is first connected.

## What this suggests (to confirm with engineering)

- Sites that lose their uplink: connect with **State Replication on**, and give them a
  **local Git mirror** if they can lose all internet; without one, SR keeps enforcing
  the last state but can't deploy new commits.
- Kargo for those sites: keep promotion logic **central** and expect promotions to an
  offline site to fail after the step timeout (raise `timeout` on the `argocd-update`
  step, or re-promote after reconnect). A self-hosted Kargo agent at the site doesn't
  help during an outage: it can't see Promotions or publish Freight without the
  control plane.
- Don't rely on cluster health in the UI as an outage alarm; it lagged by minutes.

## Caveats

- Earlier runs (on k3d) used filter-table rules, which **kube-router silently bypassed**: it
  re-inserts its FORWARD jump above other rules and ACCEPTs traffic for pods that
  have any NetworkPolicy (all agent pods). Results from those runs were discarded or
  re-run; `outage.sh` now uses the `raw` table and checks its hook position.
- kind on a laptop, one node per site, one instance; not a scale or soak test.

## Teardown

```bash
./99-teardown.sh
```
