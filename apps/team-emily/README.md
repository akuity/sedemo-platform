# Team Emily

Advanced multi-region production pipeline with Jira change management, Slack notifications, PR-based approvals, and multi-region fan-out. Demonstrates Kargo's event routing, message channels, and external system integrations.

## Pipeline

```
Warehouse (guestbook image + git: apps/team-emily)
  → test       auto-promote; Jira issue creation; e2e verification
      → uat    auto-promote; Kustomize + PR workflow; Jira tracking; Slack notification; pokemon verification
          → prod-useast  manual; Jira approval gate (waits for RELEASED status)
          → prod-uswest  manual; freight metadata (nickname) from upstream
```

## Stages

| Stage | Namespace | Auto-promote | Key capabilities |
|-------|-----------|-------------|-----------------|
| `test` | `team-emily-guestbook-test` | yes | Jira issue creation, HTTP demo calls, freight metadata, e2e analysis |
| `uat` | `team-emily-guestbook-uat` | yes | Kustomize build + PR, Jira status update, Slack PR notification, pokemon analysis |
| `prod-useast` | `team-emily-guestbook-prod-useast` | no | Jira approval gate (polls for RELEASED), git promotion |
| `prod-uswest` | `team-emily-guestbook-prod-uswest` | no | Freight nickname retrieval, standard process task |

## Key Concepts

### Jira lifecycle integration
`test` creates a Jira deployment issue and attaches a nickname to the freight via metadata. `uat` updates the issue status. `prod-useast` blocks on a Jira approval gate — the promotion waits until the issue reaches RELEASED state before proceeding.

### PR-based UAT
`uat` builds Kustomize manifests, pushes to a branch (`stage/team-emily/uat`), opens a pull request, and waits for it to be merged before the stage completes. This gives a human review step inside an otherwise auto-promoted stage.

### Slack via Message Channel
A Kargo `MessageChannel` + `EventRouter` routes promotion events to a Slack channel. The notification includes the PR link and freight details.

### Multi-region prod
`prod-useast` and `prod-uswest` are independent manual stages both sourcing from `uat`. Either region can be promoted independently after the Jira gate clears.

### Freight nickname
A human-readable nickname is attached to freight at the `test` stage and surfaced in notifications and logs downstream, making it easy to identify what's being promoted in conversation.

## Storytelling Points

- Open the Jira board — show a deployment issue being created automatically as `test` promotes
- Show the UAT PR opened by Kargo — merge it to unblock the stage
- Show the Jira approval gate holding `prod-useast` until the ticket is manually moved to RELEASED
- Show the Slack notification appearing with the PR link when UAT promotes
- Show `prod-uswest` retrieving the freight nickname from metadata set three stages earlier
