# Okta SSO repro

Stands up a throwaway Akuity Platform Argo CD instance wired to an Okta tenant with direct OIDC
(no Dex), so you can reproduce and fix Okta login problems without touching a shared instance.

The default scenario is the CLI login failure: browser login works, but
`argocd login <host> --sso` stops on an Okta `400 Bad Request` with
`The 'redirect_uri' parameter must be a Login redirect URI in the client app settings`.
The fix is a separate Okta Single-Page Application app plus `cliClientID` in `oidc.config`, as
described in the [Argo CD Okta guide](https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/okta/)
under "OIDC (without Dex)".

## Prerequisites

- An Okta tenant you control (an Okta Integrator Free Plan org works) with API Access Management,
  so the `default` custom authorization server exists.
- An Okta API token stored in `pass`, by default at `<OKTA_DOMAIN>/api-token`. Create one in the
  Okta admin console under **Security → API → Tokens**. The token's owner becomes the test user.
- `akuity` CLI logged in (`akuity login`) with rights to create instances in the target org.
- `argocd`, `curl`, `jq`, and `pass` on your `PATH`. Unlock gpg-agent first
  (`pass show <entry> >/dev/null`), or `pass` blocks on the passphrase prompt.

## Usage

```bash
export OKTA_DOMAIN=integrator-1234567.okta.com

./okta-sso-repro.sh up      # instance + Okta Web app: browser works, CLI gets the 400
argocd login <host> --sso --grpc-web

./okta-sso-repro.sh probe   # authorize request status for the browser and CLI redirects
./okta-sso-repro.sh fix     # add the SPA app and cliClientID
argocd login <host> --sso --grpc-web
argocd account get-user-info --grpc-web

./okta-sso-repro.sh down    # delete everything the script created
```

`up` and `fix` print the instance host and the commands to run next.

| Variable | Default | Purpose |
|---|---|---|
| `OKTA_DOMAIN` | required | Okta org domain, without `https://` |
| `OKTA_TOKEN_PASS` | `$OKTA_DOMAIN/api-token` | `pass` entry holding the API token |
| `AKUITY_ORG` | `demo` | Akuity organization for the instance |
| `INSTANCE_NAME` | `okta-sso-repro` | Argo CD instance name |
| `AUTHZ_SERVER` | `default` | Okta custom authorization server ID |

## What it creates

All Okta objects use the `argocd-repro` prefix:

- Argo CD instance `$INSTANCE_NAME`, with `oidc.config`, `argocd-secret`, and
  `g, argocd-repro-admins, role:admin` in `argocd-rbac-cm`
- Okta group `argocd-repro-admins`, with the token owner as a member
- Okta apps `argocd-repro-web` (Web, client secret) and, after `fix`, `argocd-repro-cli` (SPA, PKCE)
- `groups` claims and scope on the authorization server, if missing
- An all-clients access policy named `argocd-repro`, only if the server has no policies.
  Okta denies token requests from clients that no policy covers.

The script records each object it creates in `.state/<instance>.json`. `down` deletes only those
objects and never removes pre-existing claims, scopes, or policies, the tenant, or the API token.

## Secrets

The API token goes to `curl` through a header file in a mode-700 temp directory. The Web app's
client secret goes from Okta into a mode-600 temp file for `akuity argocd apply`. The script never
prints either value, and the temp directory is removed on exit.
