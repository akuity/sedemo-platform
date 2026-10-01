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
authentication error. Nothing else depends on it: dev, staging and prod keep
working, and releases can still be cut by hand with
`gh workflow run release.yml -f sha=<commit> -f version=X.Y.Z` in
akkoma-helm.
