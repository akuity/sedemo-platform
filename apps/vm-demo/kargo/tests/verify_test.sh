#!/usr/bin/env bash
# Tests for apps/vm-demo/kargo/verify.sh (the vm-health verification script).
#
# Each case builds a fixture tree for a stub server that plays both the
# Proxmox API (under /api2/json) and the rollouts-demo app on the VM (/env,
# /color, /), runs verify.sh against it with POSIX sh, and checks the exit
# code and output. The VM "IP" in the fixtures is 127.0.0.1, and APP_PORT
# points at the stub, so app requests land on the same server.
#
# Requires: bash, python3, curl, jq, yq (mikefarah v4).
# VERIFY_SH selects the shell that runs verify.sh (default: sh).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
kargo_dir="$(dirname "$here")"
script="$kargo_dir/verify.sh"
template="$kargo_dir/analysis-template.yaml"

work="$(mktemp -d)"
server_pid=""
cleanup() {
  if [ -n "$server_pid" ]; then kill "$server_pid" 2>/dev/null || true; fi
  rm -rf "$work"
}
trap cleanup EXIT

pass=0
fail=0
ok() { pass=$((pass + 1)); echo "ok   - $1"; }
not_ok() {
  fail=$((fail + 1))
  echo "FAIL - $1"
  if [ -n "${2:-}" ]; then printf '%s\n' "$2" | sed 's/^/       /'; fi
}

# ---- fixture helpers ------------------------------------------------------

# new_fixture <name>: fresh fixture root, exported as $fx
new_fixture() {
  fx="$work/$1"
  mkdir -p "$fx/api2/json/cluster"
}

# resources <json array of VM entries>
resources() {
  printf '{"data": %s}\n' "$1" > "$fx/api2/json/cluster/resources"
}

# vm_entry <vmid> <name> <tags> [template]
vm_entry() {
  printf '{"type":"qemu","vmid":%s,"node":"pve01","name":"%s","tags":"%s","status":"running","template":%s}' \
    "$1" "$2" "$3" "${4:-0}"
}

# agent_ip <vmid> <ipv4>: guest agent reports lo + eth0 with this address
agent_ip() {
  local d="$fx/api2/json/nodes/pve01/qemu/$1/agent"
  mkdir -p "$d"
  cat > "$d/network-get-interfaces" <<EOF
{"data":{"result":[
  {"name":"lo","ip-addresses":[{"ip-address-type":"ipv4","ip-address":"127.0.0.1","prefix":8},{"ip-address-type":"ipv6","ip-address":"::1","prefix":128}]},
  {"name":"eth0","ip-addresses":[{"ip-address-type":"ipv6","ip-address":"fe80::be24:11ff:fed0:1","prefix":64},{"ip-address-type":"ipv4","ip-address":"$2","prefix":24}]}
]}}
EOF
}

# agent_down <vmid>: guest agent not running yet (Proxmox answers 500)
agent_down() {
  local d="$fx/api2/json/nodes/pve01/qemu/$1/agent"
  mkdir -p "$d"
  echo '{"data":null,"message":"QEMU guest agent is not running"}' > "$d/network-get-interfaces"
  echo 500 > "$d/network-get-interfaces.status"
}

# app <color error %> <semver> <stage> [index body] [index status]
# The rollouts-demo app: /env reports namespace, semver and stage (same JSON
# shape as the real app), /color returns 500 for the given percent of
# requests (stub_server.py .error_rate), / serves the HTML page.
app() {
  echo '"blue"' > "$fx/color"
  echo "$1" > "$fx/color.error_rate"
  printf '{"namespace":"vm-%s","semver":"%s","stage":"%s"}' "$3" "$2" "$3" > "$fx/env"
  printf '%s\n' "${4:-<html><head><title>Argo Rollouts Demo</title></head><body></body></html>}" > "$fx/_root"
  if [ -n "${5:-}" ]; then echo "$5" > "$fx/_root.status"; fi
}

start_server() {
  rm -f "$work/port"
  python3 "$here/stub_server.py" "$fx" "$work/port" &
  server_pid=$!
  for _ in $(seq 1 50); do [ -s "$work/port" ] && break; sleep 0.1; done
  [ -s "$work/port" ] || { echo "stub server did not start"; exit 2; }
  port="$(cat "$work/port")"
}

stop_server() {
  kill "$server_pid" 2>/dev/null || true
  wait "$server_pid" 2>/dev/null || true
  server_pid=""
}

# run_verify <stage> <expectedCount> [smoke] [appVersion]: sets $rc and $out
run_verify() {
  start_server
  set +e
  out="$(
    PROXMOX_URL="http://127.0.0.1:$port" \
    TOKEN_ID='verify@pve!verify' \
    TOKEN_SECRET='00000000-0000-0000-0000-000000000000' \
    STAGE="$1" EXPECTED_COUNT="$2" SMOKE="${3:-false}" APP_VERSION="${4:-}" \
    APP_PORT="$port" \
    DISCOVERY_TIMEOUT=2 DISCOVERY_INTERVAL=1 HTTP_ATTEMPTS=2 HTTP_INTERVAL=0 \
    ${VERIFY_SH:-sh} "$script" 2>&1
  )"
  rc=$?
  set -e
  stop_server
}

expect() { # <name> <want rc> [substring...]
  local name="$1" want="$2"; shift 2
  if [ "$rc" -ne "$want" ]; then not_ok "$name (exit $rc, want $want)" "$out"; return; fi
  for s in "$@"; do
    case "$out" in *"$s"*) ;; *) not_ok "$name (output lacks '$s')" "$out"; return ;; esac
  done
  ok "$name"
}

[ -f "$script" ] || { echo "FAIL - $script does not exist"; exit 1; }

# ---- cases ----------------------------------------------------------------

new_fixture healthy
resources "[$(vm_entry 7101 vm-dev 'stage-dev;vm-demo')]"
agent_ip 7101 127.0.0.1
app 0 50-blue dev
run_verify dev 1 false 50-blue
expect "1 VM healthy, expected 1 -> pass" 0 "ok vm-dev" "0%"

new_fixture none
resources "[$(vm_entry 7102 vm-qa 'stage-qa;vm-demo'),$(vm_entry 9105 ubuntu-2404-base-x 'stage-dev;vm-demo' 1)]"
agent_ip 7102 127.0.0.1
app 0 50-blue qa
run_verify dev 1
expect "0 VMs found (other stage, template ignored), expected 1 -> fail" 1 "found 0 of 1"

new_fixture agent-down
resources "[$(vm_entry 7101 vm-dev 'stage-dev;vm-demo')]"
agent_down 7101
app 0 50-blue dev
run_verify dev 1
expect "guest agent not reporting an IP -> fail, not vacuous pass" 1 "found 0 of 1" "vm-dev"

new_fixture short
resources "[$(vm_entry 7105 vm-prod-1 'stage-prod;vm-demo')]"
agent_ip 7105 127.0.0.1
app 0 50-blue prod
run_verify prod 2
expect "1 of 2 prod VMs found -> fail" 1 "found 1 of 2"

new_fixture color-all-fail
resources "[$(vm_entry 7101 vm-dev 'stage-dev;vm-demo')]"
agent_ip 7101 127.0.0.1
app 100 50-blue dev
run_verify dev 1 false 50-blue
expect "/color 100% errors -> fail fast after 5 samples, naming the VM and rate" 1 "vm-dev" "/color" "100%" "5 of 5 sampled"

new_fixture color-25
resources "[$(vm_entry 7101 vm-dev 'stage-dev;vm-demo')]"
agent_ip 7101 127.0.0.1
app 25 50-blue dev
run_verify dev 1 false 50-blue
expect "/color 25% errors (> 20%) -> fail with rate" 1 "vm-dev" "/color error rate"

new_fixture color-20
resources "[$(vm_entry 7101 vm-dev 'stage-dev;vm-demo')]"
agent_ip 7101 127.0.0.1
app 20 50-blue dev
run_verify dev 1 false 50-blue
expect "/color 20% errors (not > 20%) -> pass, rate printed" 0 "ok vm-dev" "20%"

new_fixture color-slow
resources "[$(vm_entry 7101 vm-dev 'stage-dev;vm-demo')]"
agent_ip 7101 127.0.0.1
app 0 50-blue dev
echo 3 > "$fx/color.delay"
t0=$(date +%s)
run_verify dev 1 false 50-blue
elapsed=$(( $(date +%s) - t0 ))
expect "/color slower than the 2s sample timeout -> fail" 1 "vm-dev" "/color" "5 of 5 sampled"
if [ "$elapsed" -le 20 ]; then ok "slow /color fails fast (${elapsed}s <= 20s)"; else not_ok "slow /color fails fast (${elapsed}s > 20s)" ""; fi

new_fixture semver
resources "[$(vm_entry 7101 vm-dev 'stage-dev;vm-demo')]"
agent_ip 7101 127.0.0.1
app 0 50-blue dev
run_verify dev 1 false 51-yellow
expect "/env semver differs from promoted tag -> fail" 1 "vm-dev" "51-yellow"

new_fixture stage
resources "[$(vm_entry 7101 vm-dev 'stage-dev;vm-demo')]"
agent_ip 7101 127.0.0.1
app 0 50-blue qa
run_verify dev 1 false 50-blue
expect "/env stage differs from the Stage -> fail" 1 "vm-dev" "stage"

new_fixture smoke-ok
resources "[$(vm_entry 7102 vm-qa 'vm-demo;stage-qa')]"
agent_ip 7102 127.0.0.1
app 0 50-blue qa
run_verify qa 1 true 50-blue
expect "qa smoke: / is HTML -> pass" 0 "ok vm-qa"

new_fixture smoke-page
resources "[$(vm_entry 7102 vm-qa 'vm-demo;stage-qa')]"
agent_ip 7102 127.0.0.1
app 0 50-blue qa "Hello"
run_verify qa 1 true 50-blue
expect "qa smoke: / lacks <html -> fail" 1 "vm-qa" "<html"

new_fixture smoke-500
resources "[$(vm_entry 7102 vm-qa 'vm-demo;stage-qa')]"
agent_ip 7102 127.0.0.1
app 0 50-blue qa "" 500
run_verify qa 1 true 50-blue
expect "qa smoke: / returns 500 -> fail" 1 "vm-qa" "500"

new_fixture prefix-tag
resources "[$(vm_entry 7101 vm-dev 'stage-dev2;vm-demo')]"
agent_ip 7101 127.0.0.1
app 0 50-blue dev
run_verify dev 1
expect "tag stage-dev2 does not match stage dev" 1 "found 0 of 1"

# ---- inline copy in the AnalysisTemplate ----------------------------------

if [ -f "$template" ]; then
  inline="$(yq 'select(.kind == "AnalysisTemplate") | .spec.metrics[0].provider.job.spec.template.spec.containers[0].args[0]' "$template")"
  if [ "$inline" = "$(cat "$script")" ]; then
    ok "analysis-template.yaml inline script equals verify.sh"
  else
    not_ok "analysis-template.yaml inline script differs from verify.sh" \
      "$(diff <(printf '%s\n' "$inline") "$script" | head -20)"
  fi
else
  not_ok "analysis-template.yaml does not exist"
fi

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
