#!/usr/bin/env bash
# Live gauntlet helper: swap a tenant's app-values.yaml in your sedemo-monorepo
# clone for one of the rejected examples, so Argo CD shows the guardrail error
# on gov-<tenant>-kargo. Doesn't commit or push: it prints the commands.
#
# Usage:
#   governed-teams/demo/try-rejected.sh <sedemo-monorepo-clone> <tenant> <rejected-name>
#   governed-teams/demo/try-rejected.sh ~/Documents/sedemo-monorepo payments skip-staging
#
# Undo with demo/reset-tenants.sh.
set -eu
DIR="$(cd "$(dirname "$0")/.." && pwd)"
clone="${1:?usage: try-rejected.sh <sedemo-monorepo-clone> <tenant> <rejected-name>}"
tenant="${2:?usage: try-rejected.sh <sedemo-monorepo-clone> <tenant> <rejected-name>}"
name="${3:?usage: try-rejected.sh <sedemo-monorepo-clone> <tenant> <rejected-name>}"
src="$DIR/example-tenants/rejected/$name.yaml"
dst="$clone/governed/$tenant/platform/app-values.yaml"
[ -f "$src" ] || { echo "No rejected example named $name. Pick one of:"; ls "$DIR/example-tenants/rejected" | sed 's/\.yaml$//'; exit 1; }
[ -f "$dst" ] || { echo "No tenant at $dst. Run demo/reset-tenants.sh first."; exit 1; }
cp "$src" "$dst"
echo "Replaced $dst with rejected/$name.yaml:"
sed -n '1p' "$src"
echo
echo "To show it live:"
echo "  git -C '$clone' add governed && git -C '$clone' commit -m 'demo: $tenant tries $name' && git -C '$clone' push"
echo "Then open gov-$tenant-kargo in Argo CD and refresh: it shows the GUARDRAIL error."
echo "Kargo keeps running the last good pipeline. Undo with demo/reset-tenants.sh."
