#!/usr/bin/env bash
# Tests for apps/vm-demo/kargo/release-diff.sh (the vm-release-diff custom
# step). Builds a throwaway git repo and package manifests, runs the script,
# and checks the JSON it prints. Requires git and jq.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../release-diff.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
ok() { echo "ok   - $1"; pass=$((pass + 1)); }
check() { if [ "$2" = "$3" ]; then ok "$1"; else not_ok "$1" "${4:-got: $3}"; fi; }
not_ok() { echo "FAIL - $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; fail=$((fail + 1)); }

[ -f "$script" ] || { echo "FAIL - $script does not exist"; exit 1; }

# --- fixture repo -----------------------------------------------------------
repo="$tmp/repo"; mkdir -p "$repo"
g() { git -C "$repo" -c user.name=t -c user.email=t@example.com "$@"; }
g init -q
commit() { mkdir -p "$repo/$(dirname "$1")"; echo "$2" >> "$repo/$1"; g add -A; g commit -qm "$3"; g rev-parse HEAD; }
c0=$(commit rollouts-app/main.go v0 "app: initial")
k0=$(commit vm-app/config-chart/values.yaml v0 "chart: initial")
commit rollouts-app/main.go v1 "app: faster bubbles" >/dev/null
commit other-app/x v1 "other: unrelated change" >/dev/null
k1=$(commit vm-app/config-chart/values.yaml v1 "chart: tune latency default")
c2=$(commit rollouts-app/index.html v2 "app: new banner")

printf 'base-files 13ubuntu10\nlinux-image-6.8.0-45-generic 6.8.0-45.45\nopenssl 3.0.13-0ubuntu3.4\ntelnet 0.17-44\n' > "$tmp/old.txt"
printf 'base-files 13ubuntu10\nlinux-image-6.8.0-47-generic 6.8.0-47.47\nopenssl 3.0.13-0ubuntu3.5\njq 1.7.1-3build1\n' > "$tmp/new.txt"

run() { out="$(sh "$script" "$repo" "$@" 2>"$tmp/err")"; rc=$?; }
field() { jq -r --arg k "$1" '.[$k]' <<<"$out"; }

# --- release with app, chart and package changes ----------------------------
run "$c0" "$c2" "$k0" "$k1" "$tmp/old.txt" "$tmp/new.txt"
if [ $rc -ne 0 ] || ! jq -e . >/dev/null 2>&1 <<<"$out"; then
  not_ok "prints valid JSON (exit $rc)" "$(cat "$tmp/err"; echo "$out")"
else
  ok "prints valid JSON"
  a="$(field appLog)"
  case "$a" in *"app: new banner"*"app: faster bubbles"*) ok "appLog lists app commits newest first" ;; *) not_ok "appLog lists app commits newest first" "$a" ;; esac
  case "$a" in *unrelated*|*"chart:"*|*initial*) not_ok "appLog excludes other paths and the previous release" "$a" ;; *) ok "appLog excludes other paths and the previous release" ;; esac
  k="$(field chartLog)"
  case "$k" in *"chart: tune latency default"*) ok "chartLog lists chart commits" ;; *) not_ok "chartLog lists chart commits" "$k" ;; esac
  p="$(field packagesDiff)"
  case "$p" in *"~ openssl 3.0.13-0ubuntu3.4 -> 3.0.13-0ubuntu3.5"*) ok "packagesDiff shows a version change" ;; *) not_ok "packagesDiff shows a version change" "$p" ;; esac
  case "$p" in *"+ jq 1.7.1-3build1"*"+ linux-image-6.8.0-47-generic 6.8.0-47.47"*) ok "packagesDiff shows added packages" ;; *) not_ok "packagesDiff shows added packages" "$p" ;; esac
  case "$p" in *"- linux-image-6.8.0-45-generic 6.8.0-45.45"*"- telnet 0.17-44"*) ok "packagesDiff shows removed packages" ;; *) not_ok "packagesDiff shows removed packages" "$p" ;; esac
  case "$p" in *base-files*) not_ok "packagesDiff omits unchanged packages" "$p" ;; *) ok "packagesDiff omits unchanged packages" ;; esac
  s="$(field packagesSummary)"
  check "packagesSummary counts" "1 changed, 2 added, 2 removed" "$s"
fi

# --- unchanged release --------------------------------------------------------
run "$c2" "$c2" "$k1" "$k1" "$tmp/new.txt" "$tmp/new.txt"
check "same app revision -> (unchanged)" "(unchanged)" "$(field appLog)" "$out"
check "same manifest -> no package changes" "no package changes" "$(field packagesSummary)" "$out"

# --- first release / no previous manifest -------------------------------------
run "" "$c2" "" "$k1" "$tmp/missing.txt" "$tmp/new.txt"
case "$(field appLog)" in "(no previous release"*) ok "no previous app revision -> (no previous release)" ;; *) not_ok "no previous app revision -> (no previous release)" "$out" ;; esac
case "$(field packagesDiff)" in *"no package list for the previous image"*) ok "missing previous manifest is explained" ;; *) not_ok "missing previous manifest is explained" "$out" ;; esac

# --- unknown revision (e.g. force-pushed away) --------------------------------
run "deadbeef" "$c2" "$k0" "$k1" "$tmp/old.txt" "$tmp/new.txt"
check "unknown revision does not fail the step" 0 "$rc" "$(cat "$tmp/err")"
case "$(field appLog)" in *"not found"*) ok "unknown revision is explained" ;; *) not_ok "unknown revision is explained" "$out" ;; esac

# --- inline copy in the CustomPromotionStep -----------------------------------
step="$here/../../../../kargo-shared/vm-release-diff.yaml"
if [ -f "$step" ] && [ "$(yq '.spec.command[2]' "$step")" = "$(cat "$script")" ]; then
  ok "kargo-shared/vm-release-diff.yaml inline script equals release-diff.sh"
else
  not_ok "kargo-shared/vm-release-diff.yaml inline script equals release-diff.sh"
fi

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
