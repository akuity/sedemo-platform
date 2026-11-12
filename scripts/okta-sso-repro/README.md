# Okta SSO repro

Stands up a throwaway Akuity Platform Argo CD or Kargo instance wired to an Okta tenant with
direct OIDC (no Dex), so you can reproduce and fix Okta login problems without touching a shared
instance.

```bash
./okta-sso-repro.sh [argocd|kargo] up|fix|probe|status|down   # target defaults to argocd
```

## Targets

### `argocd`: CLI login fails with an Okta 400

Browser login works, but `argocd login <host> --sso` stops on an Okta `400 Bad Request` with
`The 'redirect_uri' parameter must be a Login redirect URI in the client app settings`.
The fix is a separate Okta Single-Page Application app plus `cliClientID` in `oidc.config`, as
described in the [Argo CD Okta guide](https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/okta/)
under "OIDC (without Dex)".

```bash
./okta-sso-repro.sh argocd up      # instance + Okta Web app: browser works, CLI gets the 400
argocd login <host> --sso --grpc-web

./okta-sso-repro.sh argocd probe   # authorize request status for the browser and CLI redirects
./okta-sso-repro.sh argocd fix     # add the SPA app and cliClientID
argocd login <host> --sso --grpc-web
argocd account get-user-info --grpc-web

./okta-sso-repro.sh argocd down    # delete everything the script created
```

### `kargo`: the Akuity Kargo + Okta guide, plus a wait-for-approval project

Sets Okta up the way the
[Akuity Kargo + Okta guide](https://docs.akuity.io/kargo/managing-instances/settings/security-and-access/sso/okta/)
describes it (Native OIDC): two Single-Page Application apps, a custom authorization server, and
a `groups` claim on the ID token only, with the guide's `kargo-akpt1` group mapped to Admin. It
then applies `manifests/kargo/`, a project whose Stages start with a `wait-for-approval` step that
requires `claim: groups`.

`fix` also puts the `groups` claim on the access token. Use it to tell apart problems caused by
which token carries the groups.

```bash
./okta-sso-repro.sh kargo up       # pinned-version instance, managed agent, Okta setup, project
kargo login https://<host> --port 54321 --sso
# promote Freight to each Stage in approval-repro from the UI, check the approve button

./okta-sso-repro.sh kargo fix      # groups on the access token too; log out and back in
./okta-sso-repro.sh kargo down
```

If the approve button (or a `get-user-input` prompt) is missing while the Promotion shows the
step Running, check the network before the Okta setup: a VPN or zero-trust proxy that breaks the
UI's websocket/SSE connections causes exactly that. Retry with the VPN off, and ask for an
exception for `*.akuity.cloud`.

## Prerequisites

- An Okta tenant you control (an Okta Integrator Free Plan org works) with API Access Management,
  so the `default` custom authorization server exists and new ones can be created.
- An Okta API token stored in `pass`, by default at `<OKTA_DOMAIN>/api-token`. Create one in the
  Okta admin console under **Security → API → Tokens**. The token's owner becomes the test user.
- `akuity` CLI logged in (`akuity login`) with rights to create instances in the target org.
  An expired login makes the script stop with an error rather than skip the instance.
- `curl`, `jq`, and `pass` on your `PATH`, plus `argocd` or `kargo` for the target. Unlock
  gpg-agent first (`pass show <entry> >/dev/null`), or `pass` blocks on the passphrase prompt.

`up` and `fix` print the instance host and the commands to run next. Both are safe to re-run.
Running `up` after `fix` keeps the fix; run `down` and then `up` to get the broken state back.
If `down` fails partway, fix the cause and run it again; it resumes where it stopped.

| Variable | Default | Purpose |
|---|---|---|
| `OKTA_DOMAIN` | required | Okta org domain, without `https://` |
| `OKTA_TOKEN_PASS` | `$OKTA_DOMAIN/api-token` | `pass` entry holding the API token |
| `AKUITY_ORG` | `demo` | Akuity organization for the instance |
| `INSTANCE_NAME` | `okta-sso-repro` / `kargo-okta-repro` | Instance name |
| `GROUP_NAME` | `argocd-repro-admins` / `kargo-akpt1` | Okta group mapped to admin; for kargo it must start with `kargo-` |
| `AUTHZ_SERVER` | `default` | argocd only: Okta custom authorization server ID |
| `KARGO_VERSION` | `v1.12.4-ak.0` | kargo only: instance version |
| `AGENT_NAME` | `managed` | kargo only: Akuity-managed agent name, used as the shard |
| `CLI_PORT` | `54321` | kargo only: local port for `kargo login --sso` |

## What it creates

**`argocd`** (Okta objects use the `argocd-repro` prefix):

- Argo CD instance `$INSTANCE_NAME`, with `oidc.config`, `argocd-secret`, and
  `g, $GROUP_NAME, role:admin` in `argocd-rbac-cm`
- Okta apps `argocd-repro-web` (Web, client secret) and, after `fix`, `argocd-repro-cli` (SPA, PKCE)
- `groups` claims and scope on `$AUTHZ_SERVER`, if missing
- An all-clients access policy named `argocd-repro`, only if the server has no policies.
  Okta denies token requests from clients that no policy covers.

**`kargo`** (Okta objects use the `kargo-repro` prefix):

- Kargo instance `$INSTANCE_NAME` at `$KARGO_VERSION` with direct-OIDC `oidcConfig`, an
  Akuity-managed agent, and the `approval-repro` project
- Okta authorization server `kargo-repro` (audience `https://<host>`) with a `groups` scope, a
  `groups` claim (`kargo-.*`, ID token; access token too after `fix`), and an access policy `kargo`
  for both apps. A dedicated server keeps existing claims on `default` from masking the setup.
- Okta apps `kargo-repro-ui` (`/login`, `/mcp/oauth/callback`) and `kargo-repro-cli`
  (`http://localhost:$CLI_PORT/auth/callback`), both SPA with PKCE and no secret

**Both:** Okta group `$GROUP_NAME`, with the token owner as a member.

The script records each object it creates in `.state/<instance>.json`. `down` deletes only those
objects and never removes pre-existing claims, scopes, policies, or groups, the tenant, or the API
token.

## Secrets

The API token goes to `curl` through a header file in a mode-700 temp directory. The argocd Web
app's client secret goes from Okta into a mode-600 temp file for `akuity argocd apply`. The kargo
apps are public PKCE clients with no secret. The script never prints either value, and the temp
directory is removed on exit.
