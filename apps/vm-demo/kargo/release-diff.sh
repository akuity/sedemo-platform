#!/bin/sh
# release-diff: what changed between the release a stage runs now and the one
# being promoted, for the prod change ticket. Runs as the vm-release-diff
# CustomPromotionStep (cwd = promotion work dir) and prints a YAML map of
# block scalars on stdout; everything else goes to stderr. Needs only git and
# POSIX tools: custom-step containers run as non-root and cannot install
# packages.
#
# Usage: release-diff.sh <app repo URL or path> <prev app rev> <app rev>
#                        <prev chart commit> <chart commit>
#                        <prev packages.txt> <packages.txt>
#
# Output keys: appLog, chartLog (git log --oneline, newest first, limited to
# rollouts-app/ and vm-app/config-chart/), packagesDiff ("~ pkg old -> new",
# "+ pkg ver", "- pkg ver", by package name), packagesSummary.
set -u

REPO="$1"; PREV_APP="$2"; APP="$3"; PREV_CHART="$4"; CHART="$5"
PREV_PKGS="$6"; PKGS="$7"
APP_PATH="rollouts-app"
CHART_PATH="vm-app/config-chart"
MAX_LINES=150

command -v git >/dev/null 2>&1 || { echo "git is required in the step image" >&2; exit 1; }

if [ -d "$REPO/.git" ] || [ -d "$REPO/objects" ]; then
  src="$REPO"
else
  src="$(mktemp -d)/repo"
  git clone -q --filter=blob:none --no-checkout "$REPO" "$src" >&2 \
    || { echo "cannot clone $REPO" >&2; exit 1; }
fi

have() { git -C "$src" cat-file -e "$1^{commit}" 2>/dev/null; }

# changes <prev> <new> <path>
changes() {
  if [ -z "$2" ]; then echo "(unknown revision)"; return; fi
  if ! have "$2"; then echo "(revision $2 not found in repository)"; return; fi
  if [ -z "$1" ]; then
    echo "(no previous release; latest changes)"
    git -C "$src" log -n 10 --format='%h %s' "$2" -- "$3"
    return
  fi
  if [ "$1" = "$2" ]; then echo "(unchanged)"; return; fi
  if ! have "$1"; then echo "(previous revision $1 not found in repository)"; return; fi
  log="$(git -C "$src" log --format='%h %s' "$1..$2" -- "$3")"
  if [ -z "$log" ]; then
    # Rollback: the promoted revision is an ancestor of the running one, so
    # list what is being reverted instead of reporting no changes.
    back="$(git -C "$src" log --format='%h %s' "$2..$1" -- "$3")"
    if [ -n "$back" ] && git -C "$src" merge-base --is-ancestor "$2" "$1"; then
      n="$(printf '%s\n' "$back" | wc -l | tr -d ' ')"
      [ "$n" -eq 1 ] && unit=commit || unit=commits
      echo "(rollback: reverting $n $unit)"
      printf '%s\n' "$back" | head -n "$MAX_LINES"
      [ "$n" -le "$MAX_LINES" ] || echo "... $((n - MAX_LINES)) more"
      return
    fi
    echo "(no changes under $3)"
    return
  fi
  printf '%s\n' "$log" | head -n "$MAX_LINES"
  n="$(printf '%s\n' "$log" | wc -l | tr -d ' ')"
  [ "$n" -le "$MAX_LINES" ] || echo "... $((n - MAX_LINES)) more"
}

pkgs_diff="" ; pkgs_summary=""
if [ ! -s "$PKGS" ]; then
  pkgs_diff="(no package list for this image; it was baked before manifests were recorded)"
  pkgs_summary="this image has no package manifest"
elif [ ! -s "$PREV_PKGS" ]; then
  pkgs_diff="(no package list for the previous image; it was baked before manifests were recorded)"
  pkgs_summary="previous image has no package manifest"
else
  full="$(awk '
    FNR == NR { old[$1] = $2; next }
    { new[$1] = $2 }
    END {
      for (p in old) names[p] = 1
      for (p in new) names[p] = 1
      for (p in names) {
        if (!(p in new))            printf "%s\t- %s %s\n", p, p, old[p]
        else if (!(p in old))       printf "%s\t+ %s %s\n", p, p, new[p]
        else if (old[p] != new[p])  printf "%s\t~ %s %s -> %s\n", p, p, old[p], new[p]
      }
    }' "$PREV_PKGS" "$PKGS" | LC_ALL=C sort -t "$(printf '\t')" -k1,1 | cut -f2-)"
  changed="$(printf '%s\n' "$full" | grep -c '^~ ')"
  added="$(printf '%s\n' "$full" | grep -c '^+ ')"
  removed="$(printf '%s\n' "$full" | grep -c '^- ')"
  if [ -z "$full" ]; then
    pkgs_diff="(no package changes)"
    pkgs_summary="no package changes"
  else
    pkgs_diff="$(printf '%s\n' "$full" | head -n "$MAX_LINES")"
    n="$(printf '%s\n' "$full" | wc -l | tr -d ' ')"
    [ "$n" -le "$MAX_LINES" ] || pkgs_diff="$pkgs_diff
... $((n - MAX_LINES)) more"
    pkgs_summary="$changed changed, $added added, $removed removed"
  fi
fi

# One YAML block scalar per key: indenting every line needs no escaping.
block() {
  printf '%s: |-\n' "$1"
  printf '%s\n' "$2" | sed 's/^/  /'
}
block appLog "$(changes "$PREV_APP" "$APP" "$APP_PATH")"
block chartLog "$(changes "$PREV_CHART" "$CHART" "$CHART_PATH")"
block packagesDiff "$pkgs_diff"
block packagesSummary "$pkgs_summary"
