#!/bin/sh
# vm-health verification for the vm-demo Kargo project.
#
# This file is the tested source. analysis-template.yaml carries an inline
# copy (tests/verify_test.sh asserts they are identical), so edit here and
# paste it there.
#
# Discovers the stage's VMs through the Proxmox API (tag stage-<stage>,
# templates excluded), reads each VM's IPv4 from the QEMU guest agent, then
# checks the rollouts-demo app on every VM:
#   - GET /env: stage must equal STAGE, semver must equal APP_VERSION;
#   - GET /color COLOR_SAMPLES times: fails when more than
#     COLOR_MAX_ERROR_PCT percent are non-200 (the rate is printed);
#   - SMOKE=true: GET / must return 200 and an HTML page.
# Exits non-zero, naming the VM and the reason, when fewer than
# EXPECTED_COUNT VMs report an IP within DISCOVERY_TIMEOUT or any check
# fails. Never passes with zero VMs.
#
# Required env: PROXMOX_URL (https://host:8006), TOKEN_ID (user@realm!name),
#   TOKEN_SECRET, STAGE, EXPECTED_COUNT.
# Optional env: SMOKE (false), APP_VERSION (empty skips the semver check),
#   APP_PORT (8080), COLOR_SAMPLES (20), COLOR_MAX_ERROR_PCT (20),
#   DISCOVERY_TIMEOUT (300s), DISCOVERY_INTERVAL (10s), HTTP_ATTEMPTS (3),
#   HTTP_INTERVAL (5s).
set -u

: "${PROXMOX_URL:?PROXMOX_URL is required}"
: "${TOKEN_ID:?TOKEN_ID is required}"
: "${TOKEN_SECRET:?TOKEN_SECRET is required}"
: "${STAGE:?STAGE is required}"
: "${EXPECTED_COUNT:?EXPECTED_COUNT is required}"
SMOKE="${SMOKE:-false}"
APP_VERSION="${APP_VERSION:-}"
APP_PORT="${APP_PORT:-8080}"
COLOR_SAMPLES="${COLOR_SAMPLES:-20}"
COLOR_MAX_ERROR_PCT="${COLOR_MAX_ERROR_PCT:-20}"
DISCOVERY_TIMEOUT="${DISCOVERY_TIMEOUT:-300}"
DISCOVERY_INTERVAL="${DISCOVERY_INTERVAL:-10}"
HTTP_ATTEMPTS="${HTTP_ATTEMPTS:-3}"
HTTP_INTERVAL="${HTTP_INTERVAL:-5}"

if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  apk add --no-cache -q curl jq >/dev/null || {
    echo "FAIL: curl and jq are required and could not be installed"
    exit 1
  }
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# api <path>: GET a Proxmox API path; prints the JSON body. The homelab
# Proxmox API uses a self-signed certificate, hence -k.
api() {
  curl -fsS -k --max-time 10 \
    -H "Authorization: PVEAPIToken=${TOKEN_ID}=${TOKEN_SECRET}" \
    "${PROXMOX_URL%/}/api2/json$1"
}

# list_vms: "node vmid name" for every non-template VM tagged stage-<stage>.
list_vms() {
  api "/cluster/resources?type=vm" | jq -r --arg tag "stage-$STAGE" '
    .data[]
    | select((.template // 0) != 1)
    | select([(.tags // "") | splits("[;, ]+")] | index($tag))
    | "\(.node) \(.vmid) \(.name)"'
}

# vm_ip <node> <vmid>: first IPv4 the guest agent reports on an interface
# other than loopback ("lo"), skipping link-local. Prints nothing while the
# agent is not up yet.
vm_ip() {
  api "/nodes/$1/qemu/$2/agent/network-get-interfaces" 2>/dev/null | jq -r '
    [ .data.result[]?
      | select(.name != "lo")
      | ."ip-addresses"[]?
      | select(."ip-address-type" == "ipv4")
      | ."ip-address"
      | select(startswith("169.254.") | not) ]
    | first // empty' 2>/dev/null
}

# ---- discovery: wait until EXPECTED_COUNT VMs report an IP ----------------
deadline=$(( $(date +%s) + DISCOVERY_TIMEOUT ))
while :; do
  found=0
  pending=""
  api_error=""
  : > "$tmp/targets"
  if ! vms="$(list_vms 2>"$tmp/api.err")"; then
    api_error="Proxmox API query failed: $(cat "$tmp/api.err")"
    vms=""
  fi
  while read -r node vmid name; do
    [ -n "$vmid" ] || continue
    ip="$(vm_ip "$node" "$vmid")"
    if [ -n "$ip" ]; then
      echo "$name $ip" >> "$tmp/targets"
      found=$((found + 1))
    else
      pending="$pending $name(vmid $vmid)"
    fi
  done <<EOF
$vms
EOF
  if [ "$found" -ge "$EXPECTED_COUNT" ]; then
    break
  fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "FAIL: found $found of $EXPECTED_COUNT VMs tagged stage-$STAGE with a guest-agent IPv4 after ${DISCOVERY_TIMEOUT}s"
    [ -z "$pending" ] || echo "  no IP reported by:$pending"
    [ -z "$api_error" ] || echo "  $api_error"
    exit 1
  fi
  echo "waiting: found $found of $EXPECTED_COUNT VMs for stage $STAGE${pending:+ (no IP yet:$pending)}"
  sleep "$DISCOVERY_INTERVAL"
done

# ---- checks ---------------------------------------------------------------

# fetch <url> <outfile>: GET with retries; succeeds on HTTP 200. Leaves the
# last status code in $code and the body in <outfile>.
fetch() {
  attempt=1
  while :; do
    code="$(curl -sS --max-time 5 -o "$2" -w '%{http_code}' "$1" 2>"$tmp/curl.err")" || code="000"
    [ "$code" = "200" ] && return 0
    [ "$attempt" -ge "$HTTP_ATTEMPTS" ] && break
    attempt=$((attempt + 1))
    sleep "$HTTP_INTERVAL"
  done
  [ "$code" != "000" ] || cat "$tmp/curl.err" > "$2"
  return 1
}

failures=0
fail_vm() {
  echo "FAIL $1: $2"
  failures=$((failures + 1))
}

while read -r name ip; do
  vm="$name ($ip)"
  base="http://$ip:$APP_PORT"

  # /env reports what the VM is actually running.
  if ! fetch "$base/env" "$tmp/env"; then
    fail_vm "$vm" "/env returned $code: $(head -c 300 "$tmp/env")"
    continue
  fi
  semver="$(jq -r '.semver // ""' "$tmp/env" 2>/dev/null)"
  envstage="$(jq -r '.stage // ""' "$tmp/env" 2>/dev/null)"
  if [ "$envstage" != "$STAGE" ]; then
    fail_vm "$vm" "/env reports stage '$envstage', expected $STAGE"
    continue
  fi
  if [ -n "$APP_VERSION" ] && [ "$semver" != "$APP_VERSION" ]; then
    fail_vm "$vm" "/env reports semver '$semver', expected promoted $APP_VERSION"
    continue
  fi

  # /color is the app's real request path; ERROR_RATE makes it return 500s.
  errors=0
  i=0
  while [ "$i" -lt "$COLOR_SAMPLES" ]; do
    c="$(curl -s --max-time 5 -o /dev/null -w '%{http_code}' "$base/color")" || c="000"
    [ "$c" = "200" ] || errors=$((errors + 1))
    i=$((i + 1))
  done
  rate=$((errors * 100 / COLOR_SAMPLES))
  if [ $((errors * 100)) -gt $((COLOR_MAX_ERROR_PCT * COLOR_SAMPLES)) ]; then
    fail_vm "$vm" "/color error rate ${rate}% ($errors of $COLOR_SAMPLES non-200), limit ${COLOR_MAX_ERROR_PCT}%"
    continue
  fi

  smoked=""
  if [ "$SMOKE" = "true" ]; then
    if ! fetch "$base/" "$tmp/index"; then
      fail_vm "$vm" "/ returned $code"
      continue
    fi
    if ! grep -qi "<html" "$tmp/index"; then
      fail_vm "$vm" "/ does not return an HTML page (no <html)"
      continue
    fi
    smoked=", smoke ok"
  fi
  echo "ok $vm: semver $semver, stage $envstage, /color error rate ${rate}% ($errors of $COLOR_SAMPLES)$smoked"
done < "$tmp/targets"

if [ "$failures" -gt 0 ]; then
  echo "FAIL: $failures VM(s) failed verification for stage $STAGE"
  exit 1
fi
echo "PASS: $found VM(s) healthy for stage $STAGE"
