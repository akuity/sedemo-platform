# Team Eddie — GitHub App Commit Signing Demo

Demonstrates using Kargo's `http` step to produce **verified (signed) commits** via the GitHub API, without requiring git to be configured with signing keys on the Kargo controller. The commit author is a GitHub App bot identity.

## Pipeline

```
Warehouse (git)
  → dev   single stage; signs commits via GitHub API; no downstream stages
```

## How It Works

A standard `git-commit` + `git-push` produces an unverified commit. This demo replaces that with a multi-step GitHub API workflow:

1. **Clone + update** — checkout the repo, write the promotion ID into `akuity.yaml`
2. **Temp commit** — create an unverified commit authored as `akuity-signing-demo[bot]` and push it to a temp branch (`temp-<promotion-id>`)
3. **Get tree + parent** — call `GET /repos/.../commits/<sha>` to extract the git tree SHA and parent commit SHA from the temp commit
4. **Get App token** — call `POST /app/installations/.../access_tokens` with a JWT signed by the GitHub App private key (stored in `secret('app-jwt').jwt`) to obtain a short-lived installation token
5. **Create signed commit** — call `POST /repos/.../git/commits` authenticated with the App token; GitHub marks this commit as verified because it's created by the App identity
6. **Update ref** — `PATCH /repos/.../git/refs/heads/main` to point `main` at the new signed commit SHA
7. **Delete temp branch** — clean up the temp branch

The net result is that `main` advances to a verified commit with no signing keys ever touching the Kargo agent.

## Required Secrets

| Secret | Key | Used by |
|--------|-----|---------|
| `app-jwt` | `jwt` | `get-token` step — JWT for GitHub App authentication |

## Known Limitations

- The installation access token is short-lived but briefly visible in Kargo promotion logs (noted as a TODO in the step config)
- The demo targets a specific installation ID (`109677952`) and repo (`eddiewebb/circleci-samples`) hardcoded in `stages.yaml`

## Storytelling Points

- Show that the resulting commit in GitHub has the green "Verified" badge
- Contrast with a regular `git-push` from Kargo which produces an unverified commit
- Highlight that no signing keys are stored on the cluster — the GitHub App JWT is the only secret needed
