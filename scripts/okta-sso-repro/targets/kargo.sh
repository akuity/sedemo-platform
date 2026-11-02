# shellcheck shell=bash disable=SC2154,SC2034  # shared vars come from, and AUTHZ_SERVER is read by, okta-sso-repro.sh
# Kargo target: the Akuity Kargo + Okta guide setup (Native OIDC): two Single-Page Application
# apps, a dedicated custom authorization server, and a groups claim on the ID token only, plus a
# wait-for-approval project from manifests/kargo. The fix also puts groups on the access token.
# Sourced by okta-sso-repro.sh.

INSTANCE_NAME="${INSTANCE_NAME:-kargo-okta-repro}"
KARGO_VERSION="${KARGO_VERSION:-v1.12.4-ak.0}"
AGENT_NAME="${AGENT_NAME:-managed}"
# the guide's example value for the Admin mapping
GROUP_NAME="${GROUP_NAME:-kargo-akpt1}"
# the guide's groups claim filter is kargo-.*, so any other name never reaches the token
[[ "$GROUP_NAME" == kargo-* ]] || die "GROUP_NAME must start with kargo- (the groups claim filter is kargo-.*)"
CLI_PORT="${CLI_PORT:-54321}"
PREFIX="kargo-repro"
# only used by down for pieces added to a pre-existing server, which this target never does
AUTHZ_SERVER=""

target_forget_host() { :; }

# A dedicated server, so the default server's claims (which may already put groups on the
# access token) cannot mask the ID-token-only setup the guide describes.
ensure_authz_server() { # host -> server id
  local id
  id=$(state_get .authzServer)
  if [[ -z "$id" ]]; then
    id=$(okta POST /api/v1/authorizationServers "$(jq -nc --arg n "$PREFIX" --arg a "https://$1" \
      '{name:$n,description:"Okta SSO repro (Kargo)",audiences:[$a]}')" | jq -r .id)
    state_set .authzServer "$id"
  fi
  if [[ -z "$(state_get .scope)" ]]; then
    state_set .scope "$(okta POST "/api/v1/authorizationServers/$id/scopes" \
      '{"name":"groups","consent":"IMPLICIT","metadataPublish":"ALL_CLIENTS"}' | jq -r .id)"
  fi
  [[ -n "$(state_get .claims.IDENTITY)" ]] || state_set .claims.IDENTITY "$(add_groups_claim "$id" IDENTITY 'kargo-.*' '["groups"]')"
  echo "$id"
}

ensure_access_policy() { # server ui_app cli_app
  local pid
  pid=$(state_get .policy)
  if [[ -z "$pid" ]]; then
    pid=$(okta POST "/api/v1/authorizationServers/$1/policies" "$(jq -nc --arg u "$2" --arg c "$3" \
      '{type:"OAUTH_AUTHORIZATION_POLICY",name:"kargo",description:"Kargo UI and CLI",priority:1,status:"ACTIVE",conditions:{clients:{include:[$u,$c]}}}')" | jq -r .id)
    state_set .policy "$pid"
  fi
  ensure_policy_rule "$1" "$pid"
}

apply_kargo() { # issuer ui_client cli_client
  local m="$work/manifests"; mkdir -p "$m"
  cat >"$m/kargo.yaml" <<EOF
apiVersion: kargo.akuity.io/v1alpha1
kind: Kargo
metadata:
  name: $INSTANCE_NAME
spec:
  version: $KARGO_VERSION
  kargoInstanceSpec: {}
  oidcConfig:
    enabled: true
    dexEnabled: false
    issuerUrl: $1
    clientId: $2
    cliClientId: $3
    additionalScopes: [groups]
    adminAccount:
      claims:
        groups:
          values: [$GROUP_NAME]
EOF
  cat >"$m/agent.yaml" <<EOF
apiVersion: kargo.akuity.io/v1alpha1
kind: KargoAgent
metadata:
  name: $AGENT_NAME
spec:
  data:
    akuityManaged: true
EOF
  # warehouses and stages need an explicit shard, or no controller reconciles them
  local f
  for f in "$HERE"/manifests/kargo/*.yaml; do
    sed "s/__SHARD__/$AGENT_NAME/g; s/__ADMIN_GROUP__/$GROUP_NAME/g" "$f" >"$m/$(basename "$f")"
  done
  akuity kargo apply --organization-name "$AKUITY_ORG" --name "$INSTANCE_NAME" -f "$m" >/dev/null
}

cmd_up() {
  ensure_instance --version "$KARGO_VERSION"
  local host gid sid issuer ui cli tokens
  host=$(state_get .host)
  gid=$(ensure_group)
  sid=$(ensure_authz_server "$host")
  issuer=$(okta GET "/api/v1/authorizationServers/$sid" | jq -r .issuer)
  ui=$(ensure_app ui "$PREFIX-ui" browser none "[\"https://$host/login\",\"https://$host/mcp/oauth/callback\"]" "[\"https://$host\"]" "$gid")
  cli=$(ensure_app cli "$PREFIX-cli" browser none "[\"http://localhost:$CLI_PORT/auth/callback\"]" "[\"http://localhost:$CLI_PORT\"]" "$gid")
  ensure_access_policy "$sid" "$ui" "$cli"
  log "applying oidcConfig (issuer $issuer), agent $AGENT_NAME, and the repro project"
  apply_kargo "$issuer" "$ui" "$cli"
  tokens="the ID token only"
  [[ -z "$(state_get .claims.RESOURCE)" ]] || tokens="the ID and access tokens (fix applied)"
  cat <<EOF

Ready. The groups claim is on $tokens.
  open https://$host
  kargo login https://$host --port $CLI_PORT --sso
Wait for agent $AGENT_NAME to report healthy, promote Freight to each Stage in project
approval-repro from the UI, and check the approve button. Then: $0 kargo fix
EOF
}

cmd_fix() {
  local sid
  sid=$(state_get .authzServer)
  [[ -n "$sid" ]] || die "run '$0 kargo up' first"
  if [[ -z "$(state_get .claims.RESOURCE)" ]]; then
    log "adding the groups claim to the access token"
    state_set .claims.RESOURCE "$(add_groups_claim "$sid" RESOURCE 'kargo-.*' '["groups"]')"
  fi
  cat <<EOF

Access tokens now carry groups. Log out of the Kargo UI and back in (and re-run
kargo login) so new tokens are issued, then start a fresh Promotion and check the button.
EOF
}
