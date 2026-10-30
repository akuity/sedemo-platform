# CI changes for signed images

Prod-controls can check that an image was signed by CI
(`checks.signature.enabled` in `../kargo-chart/platform-controls.yaml`), and
the Kyverno backstop can require it at admission
(`../cluster-policies/prod-verify-images.yaml`). Both need CI to sign images
first, and the image is built in `akuity/sedemo-monorepo`, not here.

`sign-images.yaml` is the snippet to add to that repo's build workflow: cosign
keyless signing with the workflow's GitHub OIDC token, no keys to manage.

Order of operations:

1. Add the signing step to the sedemo-monorepo build workflow (PR there).
2. Build a new image and check it's signed:
   `cosign verify --certificate-identity-regexp '^https://github\.com/akuity/sedemo-monorepo/\.github/workflows/.+$' --certificate-oidc-issuer https://token.actions.githubusercontent.com ghcr.io/akuity/sedemo-monorepo-rollouts-app:<tag>`
3. Set `checks.signature.enabled: true` in `platform-controls.yaml`.
4. Switch `prod-verify-images.yaml` from Audit to Enforce.

For the demo's "unsigned image" moment, keep one tag that was built without
signing. Promoting it to prod stops at the `signature` check.
