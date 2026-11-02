#!/usr/bin/env bash
# Point governed-teams/appset.yaml at a fork or branch of sedemo-platform, to
# test changes in the shared demo environment before they're merged.
#
#   governed-teams/demo/use-branch.sh https://github.com/<you>/sedemo-platform <branch> [cluster]
#   governed-teams/demo/use-branch.sh --reset      # back to akuity/sedemo-platform main, sedemo-primary
#
# Changes the two platform repo URLs, the two branch values and (optionally) the
# Argo CD cluster tenant environments deploy to, in appset.yaml.
# The fork must be public (or Argo CD and Kargo need credentials for it).
# Don't merge appset.yaml while it points at your branch: run --reset first.
set -eu
DIR="$(cd "$(dirname "$0")/.." && pwd)"
f="$DIR/appset.yaml"
if [ "${1:-}" = "--reset" ]; then
  repo="https://github.com/akuity/sedemo-platform"; branch="main"; cluster="sedemo-primary"
else
  repo="${1:?usage: use-branch.sh <platform-repo-url> <branch> [cluster] | --reset}"
  branch="${2:?usage: use-branch.sh <platform-repo-url> <branch> [cluster] | --reset}"
  cluster="${3:-}"
fi
repo="${repo%.git}"
tmp="$(mktemp)"
sed -E \
  -e "s#^(      - repoURL: )https://github.com/[^/]+/[^/ ]*sedemo-platform[^ ]*\$#\1${repo}#" \
  -e "s#^(              repoUrl: )https://github.com/[^/]+/[^/ ]*sedemo-platform[^ ]*\$#\1${repo}#" \
  -e "s#^(        targetRevision: )[^ ]+( +\# <- your branch, when testing)\$#\1${branch}\2#" \
  -e "s#^(              branch: )[^ ]+( +\# <- your branch, when testing)\$#\1${branch}\2#" \
  "$f" > "$tmp"
if [ -n "$cluster" ]; then
  sed -E -i.bak "s#^(              cluster: )[^ ]+( +\# <- your cluster, when testing)\$#\1${cluster}\2#" "$tmp"
  rm -f "$tmp.bak"
fi
mv "$tmp" "$f"
echo "appset.yaml now uses $repo @ $branch:"
grep -nE "sedemo-platform|# <- your (branch|cluster)" "$f"
