{{/*
governed.prodChecks: the evidence checks inside prod-controls.
Rendered twice: blocking for normal releases, report-only for break glass.
Args: "c" (platform controls), "cond" (when to run), "suffix" (alias suffix), "reportOnly".
*/}}
{{- define "governed.prodChecks" -}}
{{- $c := .c -}}
{{- $s := .suffix -}}
{{- $if := printf "${{ success() && (%s) }}" .cond -}}
{{- $ro := .reportOnly -}}
{{- if $c.checks.imageScan }}
# Image scan: no CRITICAL CVEs in the image being released.
- uses: trivy-image
  as: image-scan{{ $s }}
  if: {{ $if | quote }}
  {{- if $ro }}
  continueOnError: true
  {{- end }}
  config:
    image: {{ `"${{ vars.imageRepo }}:${{ imageFrom(vars.imageRepo).Tag }}"` }}
{{- end }}
{{- if $c.checks.policyCheck }}
# Policy check: the rendered prod manifests pass the platform's prod policies.
# Skipped when the tenant doesn't deploy manifests through Kargo.
- uses: kyverno-policy-apply
  as: policy-check{{ $s }}
  if: {{ printf "${{ success() && (%s) && vars.manifests != '' }}" .cond | quote }}
  {{- if $ro }}
  continueOnError: true
  {{- end }}
  config:
    policy: {{ `${{ vars.policy }}` }}
    resource: {{ `${{ vars.manifests }}` }}
{{- end }}
{{- if $c.checks.ciEvidence.enabled }}
# CI evidence: every GitHub check run on the image's source commit succeeded.
# The source commit comes from the image's OCI revision label. No check runs
# means no evidence, which blocks. Still-running checks are waited for.
- uses: http
  as: ci-evidence{{ $s }}
  if: {{ $if | quote }}
  {{- if $ro }}
  continueOnError: true
  {{- end }}
  retry:
    # Waits for running checks. An emergency release only waits briefly.
    timeout: {{ ternary "1m" "10m" $ro }}
  config:
    method: GET
    url: {{ `${{ vars.ciApi }}/commits/${{ imageFrom(vars.imageRepo).Annotations['org.opencontainers.image.revision'] }}/check-runs?per_page=100` }}{{ with $c.checks.ciEvidence.checkName }}&check_name={{ . | urlquery }}{{ end }}
    headers:
    - name: Authorization
      value: {{ printf "Bearer ${{ sharedSecret('%s').token }}" $c.integrations.githubTokenSecret | quote }}
    - name: Accept
      value: application/vnd.github+json
    - name: X-GitHub-Api-Version
      value: "2022-11-28"
    successExpression: >-
      {{ `response.status == 200 && response.body.total_count > 0
      && all(response.body.check_runs, {.status == 'completed' && .conclusion in ['success', 'neutral', 'skipped']})` }}
    failureExpression: >-
      {{ `response.status != 200 || response.body.total_count == 0
      || any(response.body.check_runs, {.conclusion in ['failure', 'cancelled', 'timed_out', 'action_required', 'stale']})` }}
    outputs:
    - name: checkRuns
      fromExpression: response.body.total_count
{{- end }}
{{- if $c.checks.secretScan.enabled }}
# Secret scan: gitleaks on the source commit the image was built from.
- uses: git-clone
  as: clone-release-source{{ $s }}
  if: {{ $if | quote }}
  {{- if $ro }}
  continueOnError: true
  {{- end }}
  config:
    repoURL: {{ `${{ vars.sourceRepo }}` }}
    checkout:
    - commit: {{ `${{ imageFrom(vars.imageRepo).Annotations['org.opencontainers.image.revision'] }}` }}
      path: ./release-source{{ $s }}
- uses: gitleaks-scan
  as: secret-scan{{ $s }}
  if: {{ $if | quote }}
  {{- if $ro }}
  continueOnError: true
  {{- end }}
  config:
    path: ./release-source{{ $s }}/{{ $c.checks.secretScan.path }}
{{- end }}
{{- if $c.checks.signature.enabled }}
# Signature: the image was signed by the CI workflow (cosign keyless).
- uses: cosign-verify
  as: signature{{ $s }}
  if: {{ $if | quote }}
  {{- if $ro }}
  continueOnError: true
  {{- end }}
  config:
    image: {{ `"${{ vars.imageRepo }}:${{ imageFrom(vars.imageRepo).Tag }}"` }}
    identityRegexp: {{ $c.checks.signature.identityRegexp | quote }}
    issuer: {{ $c.checks.signature.issuer | quote }}
{{- end }}
{{- end -}}


{{/*
governed.checkNames: the enabled checks, for audit records and the Freight.
The policy check only runs for tenants whose manifests Kargo renders, so when
it's on this returns a Kargo expression that picks the right list at run time.
*/}}
{{- define "governed.checkNames" -}}
{{- $c := . -}}
{{- $with := list -}}
{{- $without := list -}}
{{- if $c.checks.imageScan }}{{ $with = append $with "image scan" }}{{ $without = append $without "image scan" }}{{ end -}}
{{- if $c.checks.policyCheck }}{{ $with = append $with "policy check" }}{{ end -}}
{{- if $c.checks.ciEvidence.enabled }}{{ $with = append $with "CI evidence" }}{{ $without = append $without "CI evidence" }}{{ end -}}
{{- if $c.checks.secretScan.enabled }}{{ $with = append $with "secret scan" }}{{ $without = append $without "secret scan" }}{{ end -}}
{{- if $c.checks.signature.enabled }}{{ $with = append $with "signature" }}{{ $without = append $without "signature" }}{{ end -}}
{{- if $c.checks.policyCheck -}}
{{- printf "${{ vars.manifests != '' ? '%s' : '%s' }}" (join ", " $with) (join ", " $without) -}}
{{- else -}}
{{- join ", " $with -}}
{{- end -}}
{{- end -}}
