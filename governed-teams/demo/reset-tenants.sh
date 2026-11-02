#!/usr/bin/env bash
# Put the demo tenants back to a known state in your sedemo-monorepo clone:
# copies example-tenants/<tenant>/platform/app-values.yaml to
# governed/<tenant>/platform/app-values.yaml. Doesn't commit or push.
#
# Usage:
#   governed-teams/demo/reset-tenants.sh <sedemo-monorepo-clone> [tenant ...]
#   governed-teams/demo/reset-tenants.sh ~/Documents/sedemo-monorepo            # all example tenants
#   governed-teams/demo/reset-tenants.sh ~/Documents/sedemo-monorepo payments   # just one
set -eu
DIR="$(cd "$(dirname "$0")/.." && pwd)"
clone="${1:?usage: reset-tenants.sh <sedemo-monorepo-clone> [tenant ...]}"
shift
[ -d "$clone/.git" ] || { echo "$clone isn't a git clone of sedemo-monorepo"; exit 1; }
if [ "$#" -eq 0 ]; then
  set -- $(cd "$DIR/example-tenants" && for d in */platform/app-values.yaml; do echo "${d%%/*}"; done)
fi
for t in "$@"; do
  src="$DIR/example-tenants/$t/platform/app-values.yaml"
  [ -f "$src" ] || { echo "No example tenant named $t"; exit 1; }
  mkdir -p "$clone/governed/$t/platform"
  cp "$src" "$clone/governed/$t/platform/app-values.yaml"
  echo "reset governed/$t"
done
echo
git -C "$clone" status --short governed/ || true
echo
echo "Review, then: git -C '$clone' add governed && git -C '$clone' commit -m 'demo: reset governed tenants' && git -C '$clone' push"
