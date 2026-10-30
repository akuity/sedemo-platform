# GitHub ruleset: Kargo is the only writer to prod branches

Argo CD deploys a governed tenant's prod from the `rendered/gov-<tenant>/prod`
branch of `akuity/sedemo-monorepo`. If anyone can push to that branch, they
can skip Kargo and its prod controls. This ruleset closes that route
(gauntlet 4e): only the Kargo GitHub App may update those branches.

| File | What it is |
| --- | --- |
| `prod-branch-ruleset.json` | The ruleset: restrict updates, deletion and force-pushes on `refs/heads/rendered/gov-*/prod`, with the Kargo GitHub App as the only bypass actor |
| `apply-ruleset.sh` | Creates or updates it with the `gh` CLI. `--dry-run` prints the request only. |

## Before applying (needs Daniel and a repo admin)

1. **Kargo needs to push as a GitHub App.** The demo environment uses a shared
   personal token today (see `secrets/argo-secrets.yaml`). A personal token
   can't be a bypass actor, so apply the ruleset only after Kargo's Git
   credential for `sedemo-monorepo` is switched to a GitHub App. Note its app
   ID.
2. Run `governed-teams/github/apply-ruleset.sh akuity/sedemo-monorepo <app-id> --dry-run`,
   check the output, then run it without `--dry-run`.

## Show it in the demo

Try to push to a prod branch yourself:

```
git push origin HEAD:rendered/gov-payments/prod
```

GitHub rejects it and names the ruleset. Only do this once the ruleset is
active, or it will actually push.
