#!/usr/bin/env bash
# Reproduce Argo CD direct-OIDC login against Okta on a throwaway Akuity Platform instance.
#
#   up      create the instance, an Okta Web app (browser redirect only), the groups claim/scope,
#           an all-clients access policy if the auth server has none, and wire oidc.config + RBAC.
#           This is the broken state: `argocd login --sso` gets an Okta 400 redirect_uri error.
#   fix     add an Okta Single-Page Application app for the CLI and set cliClientID.
#   probe   send Okta the authorize request `argocd login --sso` builds and print the HTTP status.
#   status  show what the state file says this script created.
#   down    delete only what this script created (per the state file). The Okta tenant and the
#           API token are never touched.
#
# Secrets: the Okta API token is read from pass and only passed to curl via a header file.
# The Web app's client secret goes from Okta into a mode-600 temp file for `akuity argocd apply`
# and is never printed.
set -euo pipefail

: "${OKTA_DOMAIN:?set OKTA_DOMAIN, e.g. integrator-1234567.okta.com}"
OKTA_TOKEN_PASS="${OKTA_TOKEN_PASS:-$OKTA_DOMAIN/api-token}"
AKUITY_ORG="${AKUITY_ORG:-demo}"
INSTANCE_NAME="${INSTANCE_NAME:-okta-sso-repro}"
AUTHZ_SERVER="${AUTHZ_SERVER:-default}"
PREFIX="argocd-repro"
GROUP_NAME="$PREFIX-admins"

STATE_DIR="$(cd "$(dirname "$0")" && pwd)/.state"
STATE="$STATE_DIR/$INSTANCE_NAME.json"
OKTA="https://$OKTA_DOMAIN"
ISSUER="$OKTA/oauth2/$AUTHZ_SERVER"

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

state_get() { [[ -f "$STATE" ]] && jq -r "$1 // empty" "$STATE" || true; }
state_set() { # jq-path value
  mkdir -p "$STATE_DIR"
  [[ -f "$STATE" ]] || echo '{}' >"$STATE"
  jq --arg v "$2" "$1 = \$v" "$STATE" >"$STATE.tmp" && mv "$STATE.tmp" "$STATE"
}

instance_json() { akuity argocd instance get --organization-name "$AKUITY_ORG" "$INSTANCE_NAME" -o json 2>/dev/null; }

# the instance briefly returns 502 while it restarts after a config change
settings() { curl -fsS --retry 12 --retry-all-errors --retry-delay 5 "https://$(state_get .host)/api/v1/settings"; }

ensure_instance() {
  if ! instance_json >/dev/null; then
    log "creating Argo CD instance $INSTANCE_NAME in org $AKUITY_ORG"
    akuity argocd instance create --organization-name "$AKUITY_ORG" \
      --description "Temporary: Okta SSO repro (scripts/okta-sso-repro)" "$INSTANCE_NAME" -o json >/dev/null
    state_set .instance "$INSTANCE_NAME"
  fi
  local host health
  for _ in $(seq 60); do
    host=$(instance_json | jq -r '.hostname // empty')
    health=$(instance_json | jq -r '.healthStatus.code')
    [[ -n "$host" && "$health" == STATUS_CODE_HEALTHY ]] && break
    sleep 10
  done
  [[ -n "$host" ]] || die "instance $INSTANCE_NAME has no hostname yet"
  state_set .host "$host"
  log "instance host: $host ($health)"
}

ensure_group() {
  local id me
  id=$(okta GET "/api/v1/groups?q=$GROUP_NAME" | jq -r --arg n "$GROUP_NAME" '.[] | select(.profile.name==$n) | .id')
  if [[ -z "$id" ]]; then
    id=$(okta POST /api/v1/groups "$(jq -nc --arg n "$GROUP_NAME" '{profile:{name:$n,description:"Argo CD SSO repro admins"}}')" | jq -r .id)
    state_set .group "$id"
  fi
  # the API token's owner becomes the test user
  me=$(okta GET /api/v1/users/me | jq -r .id)
  okta PUT "/api/v1/groups/$id/users/$me" >/dev/null
  echo "$id"
}

ensure_groups_claim_and_scope() {
  local type id
  for type in IDENTITY RESOURCE; do
    okta GET "/api/v1/authorizationServers/$AUTHZ_SERVER/claims" |
      jq -e --arg t "$type" '.[] | select(.name=="groups" and .claimType==$t)' >/dev/null && continue
    id=$(okta POST "/api/v1/authorizationServers/$AUTHZ_SERVER/claims" "$(jq -nc --arg t "$type" \
      '{name:"groups",status:"ACTIVE",claimType:$t,valueType:"GROUPS",group_filter_type:"REGEX",value:".*",alwaysIncludeInToken:true,conditions:{scopes:[]}}')" | jq -r .id)
    state_set ".claims.$type" "$id"
  done
  # Argo CD requests the "groups" scope by default
  okta GET "/api/v1/authorizationServers/$AUTHZ_SERVER/scopes" | jq -e '.[] | select(.name=="groups")' >/dev/null && return
  id=$(okta POST "/api/v1/authorizationServers/$AUTHZ_SERVER/scopes" '{"name":"groups","consent":"IMPLICIT","metadataPublish":"ALL_CLIENTS"}' | jq -r .id)
  state_set .scope "$id"
}

ensure_access_policy() {
  # Okta denies every token request from a client no policy covers. Leave existing policies alone.
  [[ $(okta GET "/api/v1/authorizationServers/$AUTHZ_SERVER/policies" | jq 'length') -gt 0 ]] && {
    log "auth server '$AUTHZ_SERVER' already has access policies; make sure they cover the $PREFIX apps"
    return
  }
  local pid
  pid=$(okta POST "/api/v1/authorizationServers/$AUTHZ_SERVER/policies" "$(jq -nc --arg n "$PREFIX" \
    '{type:"OAUTH_AUTHORIZATION_POLICY",name:$n,description:"All clients",priority:1,status:"ACTIVE",conditions:{clients:{include:["ALL_CLIENTS"]}}}')" | jq -r .id)
  state_set .policy "$pid"
  okta POST "/api/v1/authorizationServers/$AUTHZ_SERVER/policies/$pid/rules" '{"type":"RESOURCE_ACCESS","name":"allow-authcode","priority":1,"status":"ACTIVE","conditions":{"people":{"groups":{"include":["EVERYONE"]}},"grantTypes":{"include":["authorization_code"]},"scopes":{"include":["*"]}},"actions":{"token":{"accessTokenLifetimeMinutes":60,"refreshTokenLifetimeMinutes":0,"refreshTokenWindowMinutes":10080}}}' >/dev/null
}

create_app() { # label app_type auth_method redirects_json logout_json group_id -> client_id
  local app id
  app=$(okta POST /api/v1/apps "$(jq -nc --arg l "$1" --arg t "$2" --arg m "$3" --argjson r "$4" --argjson o "$5" '{
    name:"oidc_client", label:$l, signOnMode:"OPENID_CONNECT",
    credentials:{oauthClient:{token_endpoint_auth_method:$m, pkce_required:($m=="none")}},
    settings:{oauthClient:{application_type:$t, grant_types:["authorization_code"], response_types:["code"],
      redirect_uris:$r, post_logout_redirect_uris:$o, consent_method:"REQUIRED"}}}')")
  id=$(jq -r .id <<<"$app")
  okta PUT "/api/v1/apps/$id/groups/$6" '{}' >/dev/null
  echo "$id"
}

apply_argocd() { # web_client_id [cli_client_id]
  local m="$work/manifests"; mkdir -p "$m"
  cat >"$m/argocd-cm.yaml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  labels:
    app.kubernetes.io/name: argocd-cm
    app.kubernetes.io/part-of: argocd
data:
  admin.enabled: "false"
  oidc.config: |
    name: Okta
    issuer: $ISSUER
    clientID: $1
${2:+    cliClientID: $2
}    clientSecret: \$oidc.okta.clientSecret
    requestedScopes: ["openid", "profile", "email", "groups"]
    requestedIDTokenClaims: {"groups": {"essential": true}}
EOF
  # policy.default is rejected by the Akuity API ("unsupported field"), so only policy.csv is set
  cat >"$m/argocd-rbac-cm.yaml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  labels:
    app.kubernetes.io/name: argocd-rbac-cm
    app.kubernetes.io/part-of: argocd
data:
  policy.csv: |
    g, $GROUP_NAME, role:admin
  scopes: "[groups, email]"
EOF
  if [[ -z "${2:-}" ]]; then
    local sec
    sec=$(okta GET "/api/v1/apps/$1/credentials/secrets" | jq -r '[.[] | select(.status=="ACTIVE")][0].client_secret')
    [[ -n "$sec" && "$sec" != null ]] || die "no active client secret on Okta app $1"
    (umask 077; cat >"$work/argocd-secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: argocd-secret
type: Opaque
stringData:
  oidc.okta.clientSecret: "$sec"
EOF
)
    unset sec
    akuity argocd apply --organization-name "$AKUITY_ORG" --name "$INSTANCE_NAME" -f "$m" -f "$work/argocd-secret.yaml" >/dev/null
  else
    akuity argocd apply --organization-name "$AKUITY_ORG" --name "$INSTANCE_NAME" -f "$m/argocd-cm.yaml" >/dev/null
  fi
}

wait_for_settings() { # jq-filter expected
  for _ in $(seq 18); do
    [[ $(settings | jq -r "$1") == "$2" ]] && return
    sleep 10
  done
  die "instance settings never showed $1 == $2"
}

cmd_up() {
  ensure_instance
  local host gid web
  host=$(state_get .host)
  gid=$(ensure_group)
  ensure_groups_claim_and_scope
  ensure_access_policy
  web=$(state_get .webApp)
  if [[ -z "$web" ]]; then
    web=$(create_app "$PREFIX-web" web client_secret_basic "[\"https://$host/auth/callback\"]" "[\"https://$host/\"]" "$gid")
    state_set .webApp "$web"
  fi
  log "applying oidc.config (Web app $web only), RBAC, and client secret"
  apply_argocd "$web"
  wait_for_settings .oidcConfig.clientID "$web"
  cat <<EOF

Broken state ready. Expect browser login to work and the CLI to fail with an Okta 400:
  open https://$host
  argocd login $host --sso --grpc-web
Then run: $0 fix
EOF
}

cmd_fix() {
  local host web gid cli
  host=$(state_get .host); web=$(state_get .webApp)
  [[ -n "$web" ]] || die "run '$0 up' first"
  gid=$(ensure_group)
  cli=$(state_get .cliApp)
  if [[ -z "$cli" ]]; then
    cli=$(create_app "$PREFIX-cli" browser none '["http://localhost:8085/auth/callback"]' '["http://localhost:8085"]' "$gid")
    state_set .cliApp "$cli"
  fi
  log "adding cliClientID $cli to oidc.config"
  apply_argocd "$web" "$cli"
  wait_for_settings .oidcConfig.cliClientID "$cli"
  cat <<EOF

Fix applied. Expect the CLI login to succeed and list $GROUP_NAME:
  argocd login $host --sso --grpc-web
  argocd account get-user-info --grpc-web
EOF
}

cmd_probe() {
  local host client
  host=$(state_get .host)
  [[ -n "$host" ]] || die "run '$0 up' first"
  client=$(settings | jq -r '.oidcConfig.cliClientID // .oidcConfig.clientID')
  printf 'browser redirect, client %s: ' "$(state_get .webApp)"
  curl -s -o /dev/null -w '%{http_code}\n' "$ISSUER/v1/authorize?client_id=$(state_get .webApp)&response_type=code&scope=openid&state=x&redirect_uri=https%3A%2F%2F$host%2Fauth%2Fcallback"
  printf 'CLI redirect,     client %s: ' "$client"
  curl -s -o /dev/null -w '%{http_code}\n' "$ISSUER/v1/authorize?client_id=$client&response_type=code&scope=openid&state=x&redirect_uri=http%3A%2F%2Flocalhost%3A8085%2Fauth%2Fcallback&code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM&code_challenge_method=S256"
}

cmd_status() {
  [[ -f "$STATE" ]] || { echo "nothing created for $INSTANCE_NAME"; return; }
  jq . "$STATE"
}

cmd_down() {
  [[ -f "$STATE" ]] || { echo "nothing created for $INSTANCE_NAME"; return; }
  local id type host
  host=$(state_get .host)
  if [[ -n "$(state_get .instance)" ]]; then
    log "deleting instance $INSTANCE_NAME"
    akuity argocd instance delete --organization-name "$AKUITY_ORG" "$INSTANCE_NAME" >/dev/null
    [[ -n "$host" ]] && argocd context --delete "$host" >/dev/null 2>&1 || true
  fi
  for id in $(state_get .webApp) $(state_get .cliApp); do
    log "deleting Okta app $id"
    okta POST "/api/v1/apps/$id/lifecycle/deactivate" >/dev/null || true
    okta DELETE "/api/v1/apps/$id" >/dev/null
  done
  id=$(state_get .policy); [[ -n "$id" ]] && { log "deleting access policy $PREFIX"; okta DELETE "/api/v1/authorizationServers/$AUTHZ_SERVER/policies/$id" >/dev/null; }
  for type in IDENTITY RESOURCE; do
    id=$(state_get ".claims.$type"); [[ -n "$id" ]] && { log "deleting groups claim ($type)"; okta DELETE "/api/v1/authorizationServers/$AUTHZ_SERVER/claims/$id" >/dev/null; }
  done
  id=$(state_get .scope); [[ -n "$id" ]] && { log "deleting groups scope"; okta DELETE "/api/v1/authorizationServers/$AUTHZ_SERVER/scopes/$id" >/dev/null; }
  id=$(state_get .group); [[ -n "$id" ]] && { log "deleting group $GROUP_NAME"; okta DELETE "/api/v1/groups/$id" >/dev/null; }
  rm -f "$STATE"
  log "done; the Okta tenant and API token are untouched"
}

case "${1:-}" in
  up|fix|probe|status|down) "cmd_$1" ;;
  *) echo "usage: $0 up|fix|probe|status|down" >&2; exit 2 ;;
esac
