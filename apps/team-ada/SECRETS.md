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
needs to run these -- nothing in this repo or its automation creates them:

```bash
for stage in dev staging prod; do
  aws secretsmanager create-secret \
    --name "team-ada-akkoma-${stage}-app" \
    --secret-string "{\"secret-key-base\":\"$(openssl rand -hex 32)\",\"signing-salt\":\"$(openssl rand -hex 4)\",\"release-cookie\":\"$(openssl rand -hex 32)\"}"

  aws secretsmanager create-secret \
    --name "team-ada-akkoma-${stage}-postgresql" \
    --secret-string "{\"postgres-password\":\"$(openssl rand -hex 16)\"}"
done
```

Until these exist, the `dev` Argo CD Application will sync but report
unhealthy (target Secret not found) -- expected, not a bug in the
manifests. Verify with:

```bash
kubectl -n team-ada-dev get externalsecret team-ada-app-secrets team-ada-postgresql
```

Both should report `SecretSynced` once the AWS Secrets Manager entries
exist and ESO has completed a refresh cycle (up to `refreshInterval: 1h`).
