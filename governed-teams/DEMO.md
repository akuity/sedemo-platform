# Demo runbook: governed releases with Kargo

Ten scenes in about 60 minutes. The prod control comes first and tenant
flexibility second, the order the customer asked for. Each scene says what to show,
what to say, what should happen and what to do if it doesn't.

Share one window, zoomed in.

## The one-sentence story

Controls are defined once by the platform and enforced on every prod release,
for every tenant, whatever their pipeline looks like, with evidence attached.
Kargo is the paved road through the lock; Kyverno and GitHub are the lock.

## Cast

| Tenant | What it shows |
| --- | --- |
| `gov-payments` | The plain golden path: dev → staging → prod |
| `gov-checkout` | Its own pipeline: dev → qa (its own environment) → staging → prod, a smoke-test stage after staging, extra checks. Same prod. |
| `gov-reports` | Doesn't use Argo CD: Kargo runs its GitHub Actions workflow. Same prod controls. |

| Person (SSO group) | Can |
| --- | --- |
| Tenant developer (`sedemo-team`) (not implemented yet) | Promote to dev and the team's own stages. Change the team's `app-values.yaml`. |
| QA (`sedemo-qa`) (not implemented yet)| Promote to staging |
| SRE (`sedemo-admin`) | Promote anywhere; start prod releases and fill in their release type |
| Approver (`sedemo-approver`) | Approve prod releases |
| Break glass (`sedemo-breakglass`) | Authorize emergency prod releases |

You need three logins, one browser profile each, so nobody on screen
approves their own release:

| Login | Groups | Plays |
| --- | --- | --- |
| Tenant developer | `sedemo-team` | The team that built the change. Gets denied in scenes 2 and 4. |
| Releaser | `sedemo-admin` | Starts prod releases and picks the release type (scenes 2, 3, 5). |
| Approver | `sedemo-approver`, `sedemo-breakglass` | Approves normal releases and authorizes break glass (scenes 2, 5). |

## Before the demo

The day before:

- [ ] `governed-teams/tests/verify.sh` passes
- [ ] The `governed-team-projects` ApplicationSet is registered and `payments`, `checkout`, `reports` are in `sedemo-monorepo/governed/` (`demo/reset-tenants.sh`)
- [ ] `gitleaks-scan` and `cosign-verify` exist in Kargo (they deploy from `kargo-shared/` on merge)
- [ ] The groups above exist and all three logins are in the right ones
- [ ] One Freight per tenant is already through staging, so prod promotions are ready to go
- [ ] One full normal prod release and one break-glass release have worked end to end
- [ ] If `changeGate` or `breakGlass.incident` is `servicenow`: the ServiceNow instance is awake (developer instances hibernate)
- [ ] Optional layers you'll show live: ruleset (`github/`), Kyverno backstop (`cluster-policies/`)

The morning of: dry run scenes 2, 3 and 5, then `demo/reset-tenants.sh`.

## Run of show

| # | Scene | Min | Answers |
| --- | --- | --- | --- |
| 0 | The audit question | 3 | Framing |
| 1 | One policy, every prod environment | 7 | Policy first; platform isn't the approver |
| 2 | Replay the audit incident | 8 | "Why didn't you stop it"; segregation of duties |
| 3 | Missing check = no release | 7 | "Without changing pipelines"; missing evidence = failure |
| 4 | Circumvention gauntlet | 12 | "How easy is it to circumvent" |
| 5 | Break glass | 5 | Break glass with review |
| 6 | Evidence for audit | 5 | Audit trail |
| 7 | Fitting the real landscape | 8 | Not everyone uses Argo CD; scale |
| 8 | Is Kargo the right tool? | 3 | "Right tool for the job?" |
| 9 | POC ask | 2 | Next step |

---

## 0. The audit question (3 min)

The reason this came up in the first place: "A team released to prod without a valid change, and the team was asked why they didn't stop it. Today we'll show you stopping it."

**Show:** the diagram in `README.md` ("How it fits together"), or the control
model drawing: Kargo is the paved road, Kyverno and GitHub are the lock for production.

## 1. One policy, every prod environment (7 min)

**Show:**

1. `kargo-chart/platform-controls.yaml`: "This file is your prod
   policy. Which checks run, how changes are approved, who can break glass."
2. `kargo-chart/templates/kargo/prod-controls.yaml`: the one task every prod
   Stage runs.
3. Kargo UI, `gov-payments` then `gov-checkout`: different pipelines before
   prod, the same prod Stage, the same `prod-controls` task.
4. `example-tenants/checkout/platform/app-values.yaml`: the team added a qa
   environment, a smoke-test stage and its own checks without asking anyone.
5. Roles: the table above, including break glass.

 "Change a prod control or security once, here, and every tenant picks it up on the next
sync. Teams don't open PRs to the platform team to ship. The platform team
owns the rules, not each release."

**Optional live change:** set a check to `false` in `platform-controls.yaml`
on your branch, sync, and show both tenants' `prod-controls` changed. Set it back.

## 2. Replay the audit incident (8 min)

**Show:**

1. As the releaser: in `gov-payments`, promote the staged Freight to prod.
2. The release-type form appears: choose **normal**, note "Q4 fee change".
   Only releasers and break glass can answer it; the tenant developer can't.
3. The checks run: image scan, policy check, CI evidence, secret scan.
4. It stops at **change-approval** and waits. Nothing has been written to the prod branch.
5. As the tenant developer: try to approve. Denied (not in `sedemo-approver`). 
6. Rerun the freight and as the approver: approve with a note. It continues: PR opened and merged on
   `rendered/gov-payments/prod`, approve the PR and Argo CD syncs.

Something like: "Without an approved change, it's blocked and waiting. The team that
built it can't approve it. Approval doesn't make the platform team a
bottleneck: it's whoever your change process says. In this demo we users to a specific group that's capable of approval. We also only require one approval in this demo but that number could be increased in the wait-for-approvals configuration, that way even if a member of the approval group shipped something, it would still require an additional set of eyes for review." -- This is being used in the demo instead of ServiceNow.

**With ServiceNow** (`changeGate: servicenow`): step 4 raises a change
request instead. Open it in ServiceNow, move it to Implement, and the release
continues. That's the same as their process today.

**If it doesn't move:** check the promotion's step list in Kargo; the waiting
step says what it's waiting for.

## 3. Missing check = no release (7 min)

**Show the reliable one live: a missing label.**

1. In your sedemo-monorepo clone, remove `labels.purpose` from
   `governed/checkout/platform/app-values.yaml`, commit, push.
2. Promote checkout to staging: the platform policy check **warns** and asks
   for an exception. Teams hear about it early.
3. As the releaser, promote to prod: **policy-check** blocks with the policy's message. The
   audit log records `prod-release-blocked`.
4. Put the label back (`demo/reset-tenants.sh <clone> checkout`).

**Then show the other checks on a blocked promotion, or talk through them:**

| Check | Blocks when | How to stage it for the demo |
| --- | --- | --- |
| image-scan | The image has a CRITICAL CVE | Promote an old image tag with a known critical CVE |
| ci-evidence | The image's source commit has a failed CI check, or no checks at all | Promote a Freight built from a commit whose CI failed |
| secret-scan | gitleaks finds a secret in the source the image was built from | Build an image from a commit containing a fake key |
| signature | The image isn't signed by CI | Once signing is on (`ci/`), promote a tag built without it |

**Say:** "These read evidence your CI already produces. Teams don't change
their pipelines. And if the evidence isn't there, the release doesn't go:
missing evidence is a failure."

## 4. Circumvention gauntlet (12 min)

Show some potential ways an engineer might try to bypass these rules

Start with two live attempts, made the way a tenant developer would: edit the
team's own `governed/payments/platform/app-values.yaml` in GitHub and commit.
That file is the only thing a team controls. Then walk the table for the rest.

**Live attempt 1: switch off a prod check (4a)**

1. Edit the file in GitHub and add at the bottom:

   ```yaml
   prodControls:
     imageScan: false
   ```

2. Commit to `main` ("turn off the prod image scan").
3. In Argo CD, open `gov-payments-kargo` and click **Refresh**. It shows
   `GUARDRAIL [locked-setting]: 'prodControls' can't be set in app-values.yaml…`
4. In Kargo, the payments pipeline hasn't changed.
5. Delete the lines and commit.

This shows: "This is the only file the team controls. They tried to switch off
the prod scan, and the platform refused it before it reached Kargo."

**Live attempt 2: add a step that skips prod's checks (4b)**

1. Same file. Add at the bottom:

   ```yaml
   pipeline:
     staging:
       extraSteps:
       - uses: git-push
         config:
           path: ./out
           targetBranch: rendered/gov-payments/prod
   ```

2. Commit to `main` ("push to prod from staging").
3. Refresh `gov-payments-kargo`. It shows
   `GUARDRAIL [step-allowlist]: pipeline.staging.extraSteps[0] uses 'git-push', which tenants can't run…`
4. Delete the lines and commit.

To show a step added to prod itself, change `staging:` to `prod:`. That's
blocked by `GUARDRAIL [prod-locked]`.

**Say:** "Teams can add steps, but only from the platform's approved list, and
nothing on that list writes to Git or deploys."

**If they ask** "`http` is on the list, so couldn't a step call GitHub's API
and push that way?": a tenant step can't read the platform's credentials
(guardrail `shared-secrets`), and a push with someone's own token hits the
GitHub ruleset on the prod branch (4e). That's what the ruleset is for.

**The full gauntlet.** `demo/gauntlet.sh` prints every config attempt and the
rule that stops it. Keep its output open as a backup.

| # | Attempt | Stopped by | Show it |
| --- | --- | --- | --- |
| 4a | Remove a prod check, or add a step to prod, in the team's values | Guardrail `locked-setting` / `prod-locked` | Live attempt 1 |
| 4b | Add a staging step that pushes to the prod branch | Guardrail `step-allowlist` | Live attempt 2 |
| 4b2 | Deploy an image from an unapproved registry | Guardrail `registry-allowlist`, then the prod policy | `demo/try-rejected.sh <clone> payments unapproved-registry` |
| 4b3 | Turn off staging | Guardrail `locked-setting` | In the team's file, change `staging: true` to `staging: false` and commit |
| 4b4 | Add a stage that feeds prod | Guardrail `prod-source-fixed` | `demo/try-rejected.sh <clone> payments stage-feeds-prod` |
| 4c | Edit the prod Stage in Kargo | Kargo RBAC | As the tenant developer, try in the UI |
| 4d | Approve your own prod release | Approvers group | As the tenant developer, try to approve |
| 4e | Push straight to `rendered/gov-payments/prod` | GitHub ruleset | `git push origin HEAD:rendered/gov-payments/prod` (only once the ruleset is active) |
| 4f | `kubectl apply` into the prod namespace | Kyverno backstop | `demo/gauntlet.sh --live <context>` (server-side dry run) |
| 4g | Deploy from GitHub Actions, skipping Kargo | Kyverno backstop; `deploy-allowlist` for unapproved workflows | Same as 4f |
| 4h | Create a prod Stage without the controls (stretch) | Kyverno on a self-hosted Kargo control plane | Show `cluster-policies/kargo-prod-stages.yaml` |

Reset after: undo each edit, or run `demo/reset-tenants.sh <clone>` and push.

**Say what's left, plainly:** "A cluster-admin, a GitHub org owner or a Kargo
admin can still change the rules themselves. You can't put a gate everywhere.
Those changes go through the platform repo and its review, and real
emergencies go through break glass."

## 5. Break glass (5 min)

**Show:**

1. As the releaser: in `gov-payments`, promote to prod and choose
   **emergency**, reason "Hotfix for payment outage INC-123".
2. The checks still run but only report.
3. It waits for **break-glass-approval**. As the approver (in
   `sedemo-breakglass`), authorize.
4. It releases. Show the Freight: `prod-release: emergency`,
   `break-glass-requested-by`, `-authorized-by`, `-reason`,
   `break-glass-review: pending`.
5. The audit log: a `break-glass` event. With `incident: servicenow`, the
   incident it raised.

**Say:** "Break glass exists, it's recorded as an audit event (a ServiceNow
incident once that's switched on), and it leaves a trail you review
afterwards: who, why, and which checks it skipped."

## 6. Evidence for audit (5 min)

**Show:**

- The Freight from scene 2: `prod-promoted-by`, `prod-note`,
  `prod-approved-by` (or `prod-change`), `prod-checks-passed`,
  `prod-ci-check-runs`, `prod-promotion`.
- The Akuity audit log: `approved`, `prod-release-blocked`, `break-glass`
  events. Export it.
- Git: each merged PR on `rendered/gov-<tenant>/prod` is one release, and
  `git log governed-teams/kargo-chart/platform-controls.yaml` is the history
  of the policy itself.

**Say:** "Next time the audit team asks, you can hand them this."

## 7. Fitting the real landscape (8 min)

**Show:**

1. `gov-reports` in Kargo: the same pipeline shape and the same
   `prod-controls`, but each stage runs the team's GitHub Actions workflow
   (`example-tenants/reports/platform/app-values.yaml`). Promote it and open
   the workflow run Kargo started.
2. The backstop from 4f/4g: if that team's workflow deploys to prod on its
   own, Kyverno stops it. Lock prod first, then make Kargo the easiest way
   through.

**Say:** "Not every tenant uses Argo CD, and you don't have to make the same
mistake twice. And for ~200 Argo CDs: Kargo talks to each through an agent;
the governed chart is per tenant." Keep it short and offer an architecture
session.

## 8. Is Kargo the right tool? (3 min)

| | Kargo + Kyverno | GitHub only | DIY |
| --- | --- | --- | --- |
| Who owns the gate | The platform, in one file | Each repo's settings and workflows | Whoever wrote the scripts |
| Same rules for 200+ tenants | Yes, from one chart | Per repo; drift is easy | Only if everyone uses your tool |
| Tenants not on Argo CD | Yes (GitHub Actions tenants) | Yes | Depends |
| Evidence per release | On the Freight and in the audit log | Spread across runs and PRs | Build it yourself |
| Break glass with review | Built in | Manual | Build it yourself |
| Circumvention | Guardrails, RBAC, ruleset, Kyverno backstop | Rulesets and environments | Build it yourself |

**Say:** "Kargo sits alongside Kyverno and GitHub. It doesn't replace either."

## 9. POC ask (2 min)

A one-tenant POC before Christmas, with success criteria the customer signs off:

- [ ] A prod promotion without a valid change is blocked (scene 2)
- [ ] Unsigned, Snyk-failing or unscanned images are blocked, using evidence from existing CI (scene 3)
- [ ] The same policy applies to two tenants with different pre-prod pipelines (scene 1)
- [ ] Every gauntlet attempt fails at a named layer (scene 4)
- [ ] Break glass works, raises an incident and leaves a reviewable trail (scene 5)
- [ ] Audit evidence can be exported per release (scene 6)

**Close:** "Your controls are defined once and enforced on every prod release,
for every tenant, with evidence attached. Next time audit asks why you didn't
stop it, you'll have stopped it."

---

## Don't say

- "Tenants would PR the platform team." Tenants never wait on the platform team to ship.
- "This is mainly about standardization." Policy first.
- "Kargo replaces Kyverno" or "replaces GitHub." It all plays a part.
- "Nothing can get around it." Show the gauntlet and name what's left.
- Anything about requester ≠ approver, SaaS regions or secret sync until confirmed.

## Say plainly

- Custom steps (the scans) are alpha and need a self-hosted agent and Enterprise license.
- Rollback means promoting older Freight. It doesn't undo side effects such as a ServiceNow ticket or a DB migration.
- Trivy stands in for Snyk; the check calls whatever scanner they use.

## After the demo

`demo/reset-tenants.sh <clone>`, push. Send the POC success criteria to the customer within 48 hours.
