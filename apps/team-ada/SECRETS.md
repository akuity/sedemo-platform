# team-ada Secrets

`env/<stage>/externalsecret-{app,postgresql}.yaml` pull from AWS Secrets
Manager via the repo's existing `aws-secretsmanager` `ClusterSecretStore`
(`secrets/aws-secretstore.yaml`). Argo CD renders this app's chart via
`helm template` with no cluster access, so Helm's `lookup` (which the
chart normally uses to preserve auto-generated secrets across upgrades)
always resolves empty -- these ExternalSecrets exist so the app's
Postgres password and Phoenix secret-key-base/signing-salt/release-cookie
survive every sync instead of regenerating randomly.

## Required AWS Secrets Manager entries

Six entries total (3 stages x 2 secrets), each a JSON object with the
listed properties. A human with access to the shared akuity AWS account
needs to run these -- nothing in this repo or its automation creates them.
The `--region` below must match the region pinned in
`secrets/aws-secretstore.yaml`'s `ClusterSecretStore`, or ESO will report
`SecretNotFound` with nothing pointing back at the cause:

```bash
for stage in dev staging prod; do
  aws secretsmanager create-secret \
    --region us-west-2 \
    --name "team-ada-akkoma-${stage}-app" \
    --secret-string "{\"secret-key-base\":\"$(openssl rand -hex 32)\",\"signing-salt\":\"$(openssl rand -hex 4)\",\"release-cookie\":\"$(openssl rand -hex 32)\"}"

  aws secretsmanager create-secret \
    --region us-west-2 \
    --name "team-ada-akkoma-${stage}-postgresql" \
    --secret-string "{\"postgres-password\":\"$(openssl rand -hex 16)\"}"
done
```

Until these exist, all three Argo CD Applications (`dev`, `staging`,
`prod`) will sync but report unhealthy (target Secret not found) --
`syncPolicy.automated` in `apps/team-ada/argocd/application-set.yaml`
applies to every generated Application, not just `dev` -- expected, not
a bug in the manifests. Verify with:

```bash
for stage in dev staging prod; do
  kubectl -n team-ada-${stage} get externalsecret team-ada-app-secrets team-ada-postgresql
done
```

Both should report `SecretSynced` once the AWS Secrets Manager entries
exist and ESO has completed a refresh cycle (up to `refreshInterval: 1h`).

## Kargo: dispatching akkoma-helm releases

The `release` Stage runs `adamancini/akkoma-helm`'s `release.yml` through
`gha-dispatch-workflow` / `gha-wait-for-workflow`. Those steps use the Git
repository credentials Kargo has for that repo, which come from the
`team-ada-akkoma-helm-creds` `ExternalSecret` in
[`secrets/kargo-sync-secrets.yaml`](../../secrets/kargo-sync-secrets.yaml)
(synced to Kargo's shared resources, so other projects can use it as well).

Create a fine-grained GitHub PAT owned by `adamancini`, limited to the
`adamancini/akkoma-helm` repository, with **Actions: Read and write** (no
other permissions needed), then store it:

```bash
aws secretsmanager create-secret \
  --region us-west-2 \
  --name team-ada-akkoma-helm-gha \
  --secret-string "{\"pat\":\"<token>\"}"
```

Until it exists, promotions to `release` fail at the dispatch step with an
authentication error. Dev, staging and prod keep working without it, and
releases can still be cut by hand with
`gh workflow run release.yml -f sha=<commit> -f version=X.Y.Z` in
akkoma-helm.

## Kargo: commenting on PR previews

Each `pr-<N>` preview Stage comments the preview URL on its akkoma-helm PR.
The comment step reads the same PAT through a second, *generic*
`ExternalSecret`, `team-ada-akkoma-helm-pr-token`, in
[`secrets/kargo-sync-secrets.yaml`](../../secrets/kargo-sync-secrets.yaml),
because `sharedSecret()` only exposes generic secrets. To enable comments,
add **Pull requests: Read and write** to the `team-ada-akkoma-helm-gha` PAT.
No new AWS entry is needed.

The comment is best-effort (`continueOnError`): without that permission
the preview still deploys and verifies, and the comment step shows as
errored in the promotion. An HTTP 401 there means the token secret is
missing or empty (see below); 403 means the PAT lacks the permission.

PR previews need no other secrets. Their `ExternalSecret`s
(`env/preview/`) reuse dev's `team-ada-akkoma-dev-{app,postgresql}`
entries.

## Kargo: signing promotion commits

team-ada's commit-making `git-clone` steps (the `promote` task, staging's
render to `rendered/team-ada/staging`, and the `pr-<N>` previews) set
`author.signingKey` from the generic `team-ada-kargo-signing-key`
`ExternalSecret` in
[`secrets/kargo-sync-secrets.yaml`](../../secrets/kargo-sync-secrets.yaml).
Kargo imports the key with `gpg --import` and signs non-interactively, so:

- it must be an ASCII-armored GPG **private** key with **no passphrase**
- its UID must match the steps' `author.name`/`author.email`
  (`Ada Mancini <ada.mancini@akuity.io>`)
- GitHub shows the commits as **Verified** only if the public key is on a
  GitHub account where that email is verified. A customer would use a bot
  account here instead of a person.

Generate the key in a throwaway keyring, so it never lands in your own:

```bash
export GNUPGHOME=$(mktemp -d)
gpg --batch --passphrase '' --quick-gen-key \
  'Ada Mancini <ada.mancini@akuity.io>' ed25519 sign 1y
gpg --armor --export ada.mancini@akuity.io > kargo-signing.pub.asc
gh gpg-key add kargo-signing.pub.asc --title "Kargo team-ada"  # needs write:gpg_key scope

aws secretsmanager create-secret \
  --region us-west-2 \
  --name team-ada-kargo-signing-key \
  --secret-string "$(gpg --armor --export-secret-keys ada.mancini@akuity.io \
    | jq -Rs '{"signing-key": .}')"

rm -rf "$GNUPGHOME" kargo-signing.pub.asc; unset GNUPGHOME
```

The key expires after a year (`1y`). After that gpg refuses to sign and
every team-ada promotion fails at its commit step, so rerun the above
(`put-secret-value` instead of `create-secret`) before then.

Create the secret and sync the `ExternalSecret` (below) before merging the
Stage changes: without it `sharedSecret()` returns no key, and the
promotions' commits are at best unsigned. Check a promotion's commit with:

```bash
gh api repos/akuity/sedemo-platform/commits/<sha> --jq .commit.verification
```

## Applying changes to `secrets/`

Everything in [`secrets/`](../../secrets/), including
`kargo-sync-secrets.yaml`, is applied by the `eso-secret-store-kargo` Argo
CD Application, which is **synced manually**. Merging a new or changed
`ExternalSecret` there does nothing until someone syncs it, so Kargo steps
that use it fail (or, for the PR comment, send an empty token). Sync just
the resource you changed, so you don't apply other teams' pending
changes to shared secrets:

```bash
argocd app sync eso-secret-store-kargo \
  --resource external-secrets.io:ExternalSecret:akuity/<name>
```

Then check that it reports `SecretSynced`:

```bash
kubectl -n akuity get externalsecret <name>
```
