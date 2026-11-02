#!/usr/bin/env bash
# Shows what a tenant's app-values.yaml turns into, without deploying anything.
#
# Usage:
#   governed-teams/tests/render.sh checkout                    # a folder in example-tenants/
#   governed-teams/tests/render.sh path/to/app-values.yaml     # any values file
#   governed-teams/tests/render.sh checkout --full             # print every rendered object
#
# If the file breaks a guardrail, you'll see the same GUARDRAIL error Argo CD
# would show. Needs helm 3. Set HELM=/path/to/helm to use a different binary.
set -u
HELM="${HELM:-helm}"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
arg="${1:?usage: render.sh <tenant-name | path/to/app-values.yaml> [--full]}"
full="${2:-}"

if [ -f "$arg" ]; then
  f="$arg"
  if [ "$(basename "$f")" = "app-values.yaml" ]; then
    name="$(basename "$(dirname "$(dirname "$f")")")"
  else
    name="$(basename "$f" .yaml)"
  fi
else
  name="$arg"
  f="$DIR/example-tenants/$name/platform/app-values.yaml"
  [ -f "$f" ] || { echo "No tenant file at $f" >&2; exit 1; }
fi
SET="application.name=gov-$name,project.name=governed-$name,project.path=governed/$name"
OUT="$(mktemp -d)"

if ! "$HELM" template "gov-$name" "$DIR/kargo-chart" -f "$f" -f "$DIR/tests/platform-values.yaml" \
     --set "$SET" >"$OUT/kargo.yaml" 2>"$OUT/err"; then
  echo "Rejected. Argo CD would show this on gov-$name-kargo:" >&2
  sed 's/.*GUARDRAIL/GUARDRAIL/' "$OUT/err" >&2
  exit 1
fi
"$HELM" template "gov-$name" "$DIR/project-templates" -f "$f" -f "$DIR/tests/platform-values.yaml" \
  --set "$SET" >"$OUT/argocd.yaml" 2>"$OUT/err" || { cat "$OUT/err" >&2; exit 1; }

if [ "$full" = "--full" ]; then
  cat "$OUT/argocd.yaml" "$OUT/kargo.yaml"
  exit 0
fi

# Summary: one line per object, plus where each Stage gets its Freight from.
summarize() {
  awk '
    function flush() {
      if (kind != "") {
        line = sprintf("  %-15s %s", kind, name)
        if (kind == "Stage") line = line sprintf("   (from: %s%s)", from, tier != "" ? ", tier: " tier : "")
        print line
      }
      kind = ""; name = ""; from = ""; tier = ""; insrc = 0
    }
    /^---/ { flush(); next }
    /^kind:/ { kind = $2 }
    /^  name:/ && name == "" { name = $2; gsub(/\047/, "", name) }
    /^    tier:/ { tier = $2 }
    /^      direct: true/ { if (from == "") from = "new images and chart changes"; next }
    /^      stages:/ { insrc = 1; next }
    insrc && /^      - / { s = $2; if (index(", " from ", ", ", " s ", ") == 0) from = (from == "" ? s : from ", " s); next }
    { insrc = 0 }
    END { flush() }
  ' "$1"
}
echo "Argo CD objects for gov-$name (project-templates):"
summarize "$OUT/argocd.yaml"
echo
echo "Kargo objects for gov-$name (kargo-chart):"
summarize "$OUT/kargo.yaml"
echo
echo "Passed the guardrails. Add --full to see every object."
