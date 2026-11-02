#!/usr/bin/env bash
# Reproduce Okta direct-OIDC (no Dex) problems on a throwaway Akuity Platform instance.
#
#   okta-sso-repro.sh [argocd|kargo] <command>      the target defaults to argocd
#
# Each target defines its own scenario in targets/<target>.sh:
#   argocd  `argocd login --sso` fails with an Okta 400 redirect_uri error; fix adds a CLI app.
#   kargo   the Akuity Kargo + Okta guide setup (groups on the ID token only) plus a
#           wait-for-approval project; fix also puts groups on the access token.
#
#   up      create the instance and Okta objects, and wire the instance to Okta.
#   fix     apply the target's fix.
#   probe   (argocd only) print the Okta authorize status for the browser and CLI redirects.
#   status  show what the state file says this script created.
#   down    delete only what this script created (per the state file). The Okta tenant and the
#           API token are never touched.
#
# Secrets: the Okta API token is read from pass and only passed to curl via a header file.
# Any client secret goes from Okta into a mode-600 temp file and is never printed.
set -euo pipefail
# without this, a failed API call inside $(...) is ignored and its empty output gets used
shopt -s inherit_errexit

TARGET=argocd
case "${1:-}" in argocd|kargo) TARGET=$1; shift ;; esac

: "${OKTA_DOMAIN:?set OKTA_DOMAIN, e.g. integrator-1234567.okta.com}"
OKTA_TOKEN_PASS="${OKTA_TOKEN_PASS:-$OKTA_DOMAIN/api-token}"
AKUITY_ORG="${AKUITY_ORG:-demo}"

HERE="$(cd "$(dirname "$0")" && pwd)"
OKTA="https://$OKTA_DOMAIN"

work=$(mktemp -d); chmod 700 "$work"; trap 'rm -rf "$work"' EXIT
hdr="$work/okta-auth-header"

log() { printf '==> %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

okta_auth() {
  [[ -s "$hdr" ]] && return
  local tok
  tok=$(pass show "$OKTA_TOKEN_PASS" | head -1) || die "could not read $OKTA_TOKEN_PASS from pass (unlock gpg-agent first)"
  [[ -n "$tok" ]] || die "$OKTA_TOKEN_PASS is empty"
  printf 'Authorization: SSWS %s\n' "$tok" >"$hdr"
}

okta() { # method path [json]
  okta_auth
  curl -fsS -X "$1" "$OKTA$2" -H @"$hdr" -H 'Accept: application/json' -H 'Content-Type: application/json' ${3:+-d "$3"}
}

okta_delete() { # path; a 404 means it is already gone
  local code
  code=$(curl -sS -o /dev/null -w '%{http_code}' -X DELETE "$OKTA$1" -H @"$hdr" -H 'Accept: application/json')
  [[ "$code" == 204 || "$code" == 200 || "$code" == 404 ]] || die "DELETE $1 returned $code"
}

state_get() { [[ -f "$STATE" ]] && jq -r "$1 // empty" "$STATE" || true; }
state_set() { # jq-path value
  mkdir -p "$STATE_DIR"
  [[ -f "$STATE" ]] || echo '{}' >"$STATE"
  jq --arg v "$2" "$1 = \$v" "$STATE" >"$STATE.tmp" && mv "$STATE.tmp" "$STATE"
}
state_del() { # jq-path
  [[ -f "$STATE" ]] || return 0
  jq "del($1)" "$STATE" >"$STATE.tmp" && mv "$STATE.tmp" "$STATE"
}

instance_json() { akuity "$TARGET" instance get --organization-name "$AKUITY_ORG" "$INSTANCE_NAME" -o json 2>/dev/null; }

# only "not found" means absent; any other failure (e.g. an expired akuity login) is fatal
instance_exists() {
  local err
  instance_json >/dev/null && return 0
  err=$(akuity "$TARGET" instance get --organization-name "$AKUITY_ORG" "$INSTANCE_NAME" 2>&1 >/dev/null || true)
  [[ "$err" == *"not found"* ]] && return 1
  die "could not look up instance $INSTANCE_NAME (run 'akuity login'?): $err"
}

# shellcheck disable=SC2120  # the kargo target passes --version
ensure_instance() { # [extra create flags...]
  if ! instance_exists; then
    log "creating $TARGET instance $INSTANCE_NAME in org $AKUITY_ORG"
    akuity "$TARGET" instance create --organization-name "$AKUITY_ORG" "$@" \
      --description "Temporary: Okta SSO repro (scripts/okta-sso-repro)" "$INSTANCE_NAME" -o json >/dev/null
    state_set .instance "$INSTANCE_NAME"
  fi
  local host health
  for _ in $(seq 60); do
    # a failed poll is retried, not fatal
    host=$( (instance_json || true) | jq -r '.hostname // empty')
    health=$( (instance_json || true) | jq -r '.healthStatus.code // empty')
    [[ -n "$host" && "$health" == STATUS_CODE_HEALTHY ]] && break
    sleep 10
  done
  [[ -n "$host" ]] || die "instance $INSTANCE_NAME has no hostname yet"
  state_set .host "$host"
  log "instance host: $host ($health)"
}

ensure_group() {
  local id me members
  id=$(okta GET "/api/v1/groups?q=$GROUP_NAME" | jq -r --arg n "$GROUP_NAME" '.[] | select(.profile.name==$n) | .id')
  if [[ -z "$id" ]]; then
    id=$(okta POST /api/v1/groups "$(jq -nc --arg n "$GROUP_NAME" '{profile:{name:$n,description:"Okta SSO repro admins"}}')" | jq -r .id)
    state_set .group "$id"
  fi
  # the API token's owner becomes the test user; record the membership only if we added it
  me=$(okta GET /api/v1/users/me | jq -r .id)
  members=$(okta GET "/api/v1/groups/$id/users?limit=200")
  if ! jq -e --arg u "$me" 'any(.[]; .id==$u)' <<<"$members" >/dev/null; then
    okta PUT "/api/v1/groups/$id/users/$me" >/dev/null
    [[ -n "$(state_get .group)" ]] || state_set .membership "$id/$me"
  fi
  echo "$id"
}

ensure_app() { # key label app_type auth_method redirects_json logout_json group_id -> client_id
  local app id
  id=$(state_get ".apps.$1")
  if [[ -z "$id" ]]; then
    app=$(okta POST /api/v1/apps "$(jq -nc --arg l "$2" --arg t "$3" --arg m "$4" --argjson r "$5" --argjson o "$6" '{
      name:"oidc_client", label:$l, signOnMode:"OPENID_CONNECT",
      credentials:{oauthClient:{token_endpoint_auth_method:$m, pkce_required:($m=="none")}},
      settings:{oauthClient:{application_type:$t, grant_types:["authorization_code"], response_types:["code"],
        redirect_uris:$r, post_logout_redirect_uris:$o, consent_method:"REQUIRED"}}}')")
    id=$(jq -r .id <<<"$app")
    state_set ".apps.$1" "$id"
  fi
  # idempotent, so a re-run repairs an assignment that failed after the app was recorded
  okta PUT "/api/v1/apps/$id/groups/$7" '{}' >/dev/null
  echo "$id"
}

# Okta denies every token request from a client no policy rule covers. Runs on every call, so a
# re-run repairs a policy whose rule failed to create.
ensure_policy_rule() { # server policy_id
  [[ $(okta GET "/api/v1/authorizationServers/$1/policies/$2/rules" | jq 'length') -gt 0 ]] && return
  okta POST "/api/v1/authorizationServers/$1/policies/$2/rules" '{"type":"RESOURCE_ACCESS","name":"allow-authcode","priority":1,"status":"ACTIVE","conditions":{"people":{"groups":{"include":["EVERYONE"]}},"grantTypes":{"include":["authorization_code"]},"scopes":{"include":["*"]}},"actions":{"token":{"accessTokenLifetimeMinutes":60,"refreshTokenLifetimeMinutes":0,"refreshTokenWindowMinutes":10080}}}' >/dev/null
}

# adds a groups claim to an authorization server -> claim id
add_groups_claim() { # server claim_type filter_regex scopes_json
  okta POST "/api/v1/authorizationServers/$1/claims" "$(jq -nc --arg t "$2" --arg r "$3" --argjson s "$4" \
    '{name:"groups",status:"ACTIVE",claimType:$t,valueType:"GROUPS",group_filter_type:"REGEX",value:$r,alwaysIncludeInToken:true,conditions:{scopes:$s}}')" | jq -r .id
}

cmd_status() {
  [[ -f "$STATE" ]] || { echo "nothing created for $INSTANCE_NAME"; return; }
  jq . "$STATE"
}

cmd_down() {
  [[ -f "$STATE" ]] || { echo "nothing created for $INSTANCE_NAME"; return; }
  # each state key is cleared as soon as its object is gone, so a failed down can be re-run
  local id key server
  okta_auth
  if [[ -n "$(state_get .instance)" ]]; then
    if instance_exists; then
      log "deleting instance $INSTANCE_NAME"
      akuity "$TARGET" instance delete --organization-name "$AKUITY_ORG" "$INSTANCE_NAME" >/dev/null
    fi
    target_forget_host "$(state_get .host)"
    state_del .instance
  fi
  for key in $(jq -r '.apps // {} | keys[]' "$STATE"); do
    id=$(state_get ".apps.$key")
    log "deleting Okta app $id"
    okta POST "/api/v1/apps/$id/lifecycle/deactivate" >/dev/null 2>&1 || true
    okta_delete "/api/v1/apps/$id"; state_del ".apps.$key"
  done
  server=$(state_get .authzServer)
  if [[ -n "$server" ]]; then
    # a server this script created owns its scope, claims and policy, so they go with it
    log "deleting authorization server $server"
    okta POST "/api/v1/authorizationServers/$server/lifecycle/deactivate" >/dev/null 2>&1 || true
    okta_delete "/api/v1/authorizationServers/$server"
    state_del .policy; state_del .claims; state_del .scope; state_del .authzServer
  fi
  # otherwise only the pieces added to a pre-existing server are removed
  id=$(state_get .policy)
  if [[ -n "$id" ]]; then
    log "deleting access policy on $AUTHZ_SERVER"
    okta_delete "/api/v1/authorizationServers/$AUTHZ_SERVER/policies/$id"; state_del .policy
  fi
  for key in .claims.IDENTITY .claims.RESOURCE; do
    id=$(state_get "$key"); [[ -n "$id" ]] || continue
    log "deleting groups claim ${key#.claims.}"
    okta_delete "/api/v1/authorizationServers/$AUTHZ_SERVER/claims/$id"; state_del "$key"
  done
  id=$(state_get .scope)
  if [[ -n "$id" ]]; then
    log "deleting groups scope"
    okta_delete "/api/v1/authorizationServers/$AUTHZ_SERVER/scopes/$id"; state_del .scope
  fi
  id=$(state_get .membership)
  if [[ -n "$id" ]]; then
    log "removing the token owner from pre-existing group $GROUP_NAME"
    okta_delete "/api/v1/groups/${id%/*}/users/${id#*/}"; state_del .membership
  fi
  id=$(state_get .group)
  if [[ -n "$id" ]]; then
    log "deleting group $GROUP_NAME"
    okta_delete "/api/v1/groups/$id"; state_del .group
  fi
  rm -f "$STATE"
  log "done; the Okta tenant and API token are untouched"
}

# shellcheck source=targets/argocd.sh
source "$HERE/targets/$TARGET.sh"
STATE_DIR="$HERE/.state"
STATE="$STATE_DIR/$INSTANCE_NAME.json"

case "${1:-}" in
  up|fix|status|down) "cmd_$1" ;;
  probe) declare -F cmd_probe >/dev/null || die "probe is not available for $TARGET"; cmd_probe ;;
  *) echo "usage: $0 [argocd|kargo] up|fix|probe|status|down" >&2; exit 2 ;;
esac
