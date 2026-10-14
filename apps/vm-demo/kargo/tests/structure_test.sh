#!/usr/bin/env bash
# Structural checks on the vm-demo Kargo manifests that schema validation
# misses: step config keys Kargo rejects at run time, and Stage references to
# vm-render outputs that the task never composes. Requires yq.
set -uo pipefail
dir="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0
ok() { echo "ok   - $1"; pass=$((pass + 1)); }
not_ok() { echo "FAIL - $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; fail=$((fail + 1)); }

# record-audit-event accepts only type, message, actor, data.
bad="$(yq ea '.. | select(has("uses") and .uses == "record-audit-event") | .as + ": " + ([.config | keys | .[] | select(. != "type" and . != "message" and . != "actor" and . != "data")] | join(","))' "$dir"/tasks.yaml "$dir"/stages.yaml | grep -v -e ': $' -e '^---$' || true)"
if [ -z "$bad" ]; then ok "record-audit-event configs use only type/message/actor/data"; else not_ok "record-audit-event configs use only type/message/actor/data" "$bad"; fi

# Every outputs.render.<key> a Stage uses must be composed by vm-render.
composed="$(yq 'select(.metadata.name == "vm-render") | .spec.steps[] | select(.uses == "compose-output") | .config | keys | .[]' "$dir"/tasks.yaml | sort -u)"
used="$(grep -oE 'outputs\.render\??\.[A-Za-z]+' "$dir"/stages.yaml | sed -E 's/.*\.//' | sort -u)"
missing="$(comm -23 <(printf '%s\n' "$used") <(printf '%s\n' "$composed"))"
if [ -z "$missing" ]; then ok "every outputs.render.* used by Stages is composed by vm-render"; else not_ok "every outputs.render.* used by Stages is composed by vm-render" "missing: ${missing//$'\n'/ }"; fi

# The rendered branch carries the image's package manifest, so the SysOps PR
# shows OS package changes for base-image promotions.
if yq 'select(.metadata.name == "vm-render") | .spec.steps[] | select(.uses == "copy") | .config.outPath' "$dir"/tasks.yaml | grep -qx './out/packages.txt'; then
  ok "vm-render copies the base image package manifest to the rendered branch"
else
  not_ok "vm-render copies the base image package manifest to the rendered branch"
fi

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
