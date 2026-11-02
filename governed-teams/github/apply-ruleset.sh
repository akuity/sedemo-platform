#!/usr/bin/env bash
# Creates (or updates) the GitHub ruleset that makes Kargo the only writer to
# governed tenants' prod branches (gauntlet 4e).
#
# Argo CD syncs prod from rendered/gov-<tenant>/prod. With this ruleset, only
# the Kargo GitHub App can update those branches (by merging the PR that
# prod-controls approved). A person pushing straight to the branch, even an
# org admin, is rejected.
#
# Usage:
#   governed-teams/github/apply-ruleset.sh <owner/repo> <kargo-github-app-id> [--dry-run]
#   governed-teams/github/apply-ruleset.sh akuity/sedemo-monorepo 123456 --dry-run
#
# Needs the gh CLI logged in as a repo admin. --dry-run prints the request only.
#
# Before applying: Kargo must push with a GitHub App, not a personal token.
# Today the demo environment uses a shared PAT (secrets/argo-secrets.yaml), and
# a PAT isn't a bypass actor, so applying this first would block Kargo itself.
set -euo pipefail
repo="${1:?usage: apply-ruleset.sh <owner/repo> <kargo-github-app-id> [--dry-run]}"
app_id="${2:?usage: apply-ruleset.sh <owner/repo> <kargo-github-app-id> [--dry-run]}"
dry="${3:-}"
dir="$(cd "$(dirname "$0")" && pwd)"
body="$(sed "s/\"actor_id\": 0/\"actor_id\": ${app_id}/" "$dir/prod-branch-ruleset.json")"

existing="$(gh api "repos/$repo/rulesets" --jq '.[] | select(.name=="governed-prod-branches") | .id' 2>/dev/null || true)"
if [ -n "$existing" ]; then method=PUT; path="repos/$repo/rulesets/$existing"; else method=POST; path="repos/$repo/rulesets"; fi

echo "$method $path"
if [ "$dry" = "--dry-run" ]; then
  echo "$body"
  exit 0
fi
echo "$body" | gh api -X "$method" "$path" --input - --jq '"Ruleset \(.name) (id \(.id)) is \(.enforcement)"'
