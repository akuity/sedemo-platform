{{/*
governed.deployMethod: "argocd" (default) or "github-actions", from the
tenant's deploy.method.
*/}}
{{- define "governed.deployMethod" -}}
{{- (.Values.deploy | default dict).method | default "argocd" -}}
{{- end -}}

{{/*
governed.ghaDeploy: deploy a stage by running the tenant's GitHub Actions
workflow and waiting for it to succeed. For tenants with
deploy.method: github-actions. Args: dict "root" "stage".
The workflow gets two inputs: environment (the stage name) and version (the
image tag). Kargo decides when it runs; the workflow decides how to deploy.
*/}}
{{- define "governed.ghaDeploy" -}}
{{- $v := .root.Values -}}
{{- $g := $v.deploy.githubActions -}}
- uses: gha-dispatch-workflow
  as: deploy
  config:
    repoURL: {{ $g.repo }}
    workflowFile: {{ $g.workflow }}
    ref: {{ $g.ref | default "main" }}
    inputs:
      environment: {{ .stage }}
      version: {{ printf "${{ imageFrom('%s').Tag }}" $v.image.repository | quote }}
- uses: gha-wait-for-workflow
  as: deploy-finished
  config:
    repoURL: {{ $g.repo }}
    runID: {{ `${{ outputs['deploy'].runID }}` }}
    expectedConclusion: success
{{- end -}}
