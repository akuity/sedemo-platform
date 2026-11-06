# shellcheck shell=bash disable=SC2154  # work, OKTA, HERE, etc. come from okta-sso-repro.sh
# Argo CD target: browser login works, `argocd login --sso` stops on an Okta 400 redirect_uri
# error. The fix is a separate Okta Single-Page Application app plus cliClientID in oidc.config.
# Sourced by okta-sso-repro.sh.

INSTANCE_NAME="${INSTANCE_NAME:-okta-sso-repro}"
AUTHZ_SERVER="${AUTHZ_SERVER:-default}"
PREFIX="argocd-repro"
GROUP_NAME="${GROUP_NAME:-$PREFIX-admins}"
ISSUER="$OKTA/oauth2/$AUTHZ_SERVER"

# the instance briefly returns 502 while it restarts after a config change
settings() { curl -fsS --retry 12 --retry-all-errors --retry-delay 5 "https://$(state_get .host)/api/v1/settings"; }

wait_for_settings() { # jq-filter expected
  for _ in $(seq 18); do
    [[ $(settings | jq -r "$1") == "$2" ]] && return
    sleep 10
  done
  die "instance settings never showed $1 == $2"
}

target_forget_host() { # host
  if [[ -n "$1" ]]; then argocd context --delete "$1" >/dev/null 2>&1 || true; fi
}

ensure_groups_claim_and_scope() {
  local type claims scopes
  # fetch before testing, so a failed GET aborts instead of reading as "missing"
  claims=$(okta GET "/api/v1/authorizationServers/$AUTHZ_SERVER/claims")
  scopes=$(okta GET "/api/v1/authorizationServers/$AUTHZ_SERVER/scopes")
  for type in IDENTITY RESOURCE; do
    jq -e --arg t "$type" 'any(.[]; .name=="groups" and .claimType==$t)' <<<"$claims" >/dev/null && continue
    state_set ".claims.$type" "$(add_groups_claim "$AUTHZ_SERVER" "$type" '.*' '[]')"
  done
  # Argo CD requests the "groups" scope by default
  jq -e 'any(.[]; .name=="groups")' <<<"$scopes" >/dev/null && return
  state_set .scope "$(okta POST "/api/v1/authorizationServers/$AUTHZ_SERVER/scopes" \
    '{"name":"groups","consent":"IMPLICIT","metadataPublish":"ALL_CLIENTS"}' | jq -r .id)"
}

ensure_access_policy() {
  # Okta denies every token request from a client no policy covers. Leave existing policies alone.
  local count pid
  pid=$(state_get .policy)
  if [[ -z "$pid" ]]; then
    count=$(okta GET "/api/v1/authorizationServers/$AUTHZ_SERVER/policies" | jq 'length')
    if [[ "$count" -gt 0 ]]; then
      log "auth server '$AUTHZ_SERVER' already has access policies; make sure they cover the $PREFIX apps"
      return
    fi
    pid=$(okta POST "/api/v1/authorizationServers/$AUTHZ_SERVER/policies" "$(jq -nc --arg n "$PREFIX" \
      '{type:"OAUTH_AUTHORIZATION_POLICY",name:$n,description:"All clients",priority:1,status:"ACTIVE",conditions:{clients:{include:["ALL_CLIENTS"]}}}')" | jq -r .id)
    state_set .policy "$pid"
  fi
  ensure_policy_rule "$AUTHZ_SERVER" "$pid"
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
}

cmd_up() {
  ensure_instance
  local host gid web cli
  host=$(state_get .host)
  gid=$(ensure_group)
  ensure_groups_claim_and_scope
  ensure_access_policy
  web=$(ensure_app web "$PREFIX-web" web client_secret_basic "[\"https://$host/auth/callback\"]" "[\"https://$host/\"]" "$gid")
  # re-running up after fix keeps the fix; run down then up for a fresh broken state
  cli=$(state_get .apps.cli)
  log "applying oidc.config (Web app $web${cli:+, cliClientID $cli}), RBAC, and client secret"
  apply_argocd "$web" "$cli"
  wait_for_settings .oidcConfig.clientID "$web"
  [[ -z "$cli" ]] || { log "fix already applied; the CLI login should succeed"; return; }
  cat <<EOF

Broken state ready. Expect browser login to work and the CLI to fail with an Okta 400:
  open https://$host
  argocd login $host --sso --grpc-web
Then run: $0 argocd fix
EOF
}

cmd_fix() {
  local host web gid cli
  host=$(state_get .host); web=$(state_get .apps.web)
  [[ -n "$web" ]] || die "run '$0 argocd up' first"
  gid=$(ensure_group)
  cli=$(ensure_app cli "$PREFIX-cli" browser none '["http://localhost:8085/auth/callback"]' '["http://localhost:8085"]' "$gid")
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
  local host client web
  host=$(state_get .host)
  [[ -n "$host" ]] || die "run '$0 argocd up' first"
  web=$(state_get .apps.web)
  client=$(settings | jq -r '.oidcConfig.cliClientID // .oidcConfig.clientID')
  printf 'browser redirect, client %s: ' "$web"
  curl -s -o /dev/null -w '%{http_code}\n' "$ISSUER/v1/authorize?client_id=$web&response_type=code&scope=openid&state=x&redirect_uri=https%3A%2F%2F$host%2Fauth%2Fcallback"
  printf 'CLI redirect,     client %s: ' "$client"
  curl -s -o /dev/null -w '%{http_code}\n' "$ISSUER/v1/authorize?client_id=$client&response_type=code&scope=openid&state=x&redirect_uri=http%3A%2F%2Flocalhost%3A8085%2Fauth%2Fcallback&code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM&code_challenge_method=S256"
}
