{{/*
Guardrails: checks on a tenant's app-values.yaml before anything renders.
A failure shows as "GUARDRAIL [rule]: reason" on the tenant's gov-<name>-kargo app.
The allowlists live in ../platform-controls.yaml; the structural lists are below.
*/}}

{{/* Top-level keys a tenant may set in app-values.yaml. */}}
{{- define "governed.tenantKeys" -}}
image rollouts environments services notifications pipeline ingress replicaCount labels nameOverride fullnameOverride deploy
{{- end -}}

{{/* Top-level keys the platform sets (project-templates valuesObject wins over the tenant file). */}}
{{- define "governed.platformKeys" -}}
application project platform team kargo git repoUrl chartUrl chartPath isStandalone global
{{- end -}}

{{/* Step aliases the platform's own steps use. */}}
{{- define "governed.reservedAliases" -}}
clone-base-chart clone-app-team-values commit push open-pr wait-for-pr policy approve-kyverno-exception prod-controls deploy deploy-finished
{{- end -}}

{{/* Stage names only the platform uses. */}}
{{- define "governed.platformStages" -}}
dev staging prod
{{- end -}}


{{/* governed.checkSteps: validate a list of tenant steps. Args: dict "where" "steps" "allowed" "root". */}}
{{- define "governed.checkSteps" -}}
{{- $where := .where -}}
{{- $allowed := .allowed -}}
{{- $reserved := splitList " " (include "governed.reservedAliases" .root) -}}
{{- if not (kindIs "slice" (.steps | default list)) -}}
  {{- fail (printf "GUARDRAIL [pipeline-shape]: %s must be a list of steps." $where) -}}
{{- end -}}
{{- range $i, $s := (.steps | default list) -}}
  {{- if not (kindIs "map" $s) -}}
    {{- fail (printf "GUARDRAIL [pipeline-shape]: %s[%d] isn't a step." $where $i) -}}
  {{- end -}}
  {{- if hasKey $s "task" -}}
    {{- fail (printf "GUARDRAIL [step-allowlist]: %s[%d] runs a PromotionTask. Tenant steps must name one allowed step with 'uses': %s" $where $i (join ", " $allowed)) -}}
  {{- end -}}
  {{- $uses := get $s "uses" | toString -}}
  {{- if not (has $uses $allowed) -}}
    {{- fail (printf "GUARDRAIL [step-allowlist]: %s[%d] uses '%s', which tenants can't run because it could write to Git or Argo CD outside the platform's path. Allowed steps: %s" $where $i $uses (join ", " $allowed)) -}}
  {{- end -}}
  {{- if hasKey $s "as" -}}
    {{- if has (get $s "as" | toString) $reserved -}}
      {{- fail (printf "GUARDRAIL [step-allowlist]: %s[%d] uses the alias '%s', which is reserved for platform steps. Pick another name." $where $i (get $s "as")) -}}
    {{- end -}}
  {{- end -}}
  {{- if contains "sharedSecret(" (toJson $s) -}}
    {{- fail (printf "GUARDRAIL [shared-secrets]: %s[%d] reads a platform shared secret. Tenant steps can only use their own project's secrets." $where $i) -}}
  {{- end -}}
{{- end -}}
{{- end -}}


{{/* governed.guardrails: run every check. Included once by templates/kargo/guardrails.yaml. */}}
{{- define "governed.guardrails" -}}
{{- $v := .Values -}}
{{- $c := .Files.Get "platform-controls.yaml" | fromYaml -}}

{{- /* locked-setting: only known keys. Catches attempts like prodControls:, approvers:, prod: */ -}}
{{- $known := concat (splitList " " (include "governed.tenantKeys" .)) (splitList " " (include "governed.platformKeys" .)) -}}
{{- range $key, $_ := $v -}}
  {{- if not (has $key $known) -}}
    {{- fail (printf "GUARDRAIL [locked-setting]: '%s' can't be set in app-values.yaml. Prod controls, approvers and the prod pipeline belong to the platform team. Tenants can set: %s" $key (include "governed.tenantKeys" $)) -}}
  {{- end -}}
{{- end -}}

{{- /* locked-setting: staging can't be skipped */ -}}
{{- if not $v.environments.staging -}}
  {{- fail "GUARDRAIL [locked-setting]: environments.staging can't be turned off. Every release goes through staging before prod." -}}
{{- end -}}

{{- /* registry-allowlist */ -}}
{{- $repo := $v.image.repository | toString -}}
{{- $approved := $c.approvedRegistries -}}
{{- $ok := false -}}
{{- range $prefix := $approved -}}
  {{- if hasPrefix $prefix $repo -}}{{- $ok = true -}}{{- end -}}
{{- end -}}
{{- if not $ok -}}
  {{- fail (printf "GUARDRAIL [registry-allowlist]: image.repository '%s' isn't from an approved registry (%s). Use an endorsed image." $repo (join ", " $approved)) -}}
{{- end -}}

{{- /* deploy-allowlist: how the tenant deploys. argocd (default) or github-actions. */ -}}
{{- $d := $v.deploy | default dict -}}
{{- if not (kindIs "map" $d) -}}
  {{- fail "GUARDRAIL [deploy-allowlist]: deploy must be a map, e.g. deploy: {method: github-actions, githubActions: {...}}." -}}
{{- end -}}
{{- range $key, $_ := $d -}}
  {{- if not (has $key (list "method" "githubActions")) -}}
    {{- fail (printf "GUARDRAIL [deploy-allowlist]: deploy.%s isn't a setting. Use deploy.method and deploy.githubActions." $key) -}}
  {{- end -}}
{{- end -}}
{{- $method := get $d "method" | default "argocd" | toString -}}
{{- if not (has $method (list "argocd" "github-actions")) -}}
  {{- fail (printf "GUARDRAIL [deploy-allowlist]: deploy.method '%s' isn't supported. Use argocd or github-actions." $method) -}}
{{- end -}}
{{- if eq $method "github-actions" -}}
  {{- $g := get $d "githubActions" | default dict -}}
  {{- if not (kindIs "map" $g) -}}
    {{- fail "GUARDRAIL [deploy-allowlist]: deploy.githubActions must set repo, workflow and ref." -}}
  {{- end -}}
  {{- range $key, $_ := $g -}}
    {{- if not (has $key (list "repo" "workflow" "ref")) -}}
      {{- fail (printf "GUARDRAIL [deploy-allowlist]: deploy.githubActions.%s isn't a setting. Use repo, workflow and ref." $key) -}}
    {{- end -}}
  {{- end -}}
  {{- $grepo := get $g "repo" | toString -}}
  {{- $gok := false -}}
  {{- range $prefix := $c.approvedDeployRepos -}}
    {{- if hasPrefix $prefix $grepo -}}{{- $gok = true -}}{{- end -}}
  {{- end -}}
  {{- if not $gok -}}
    {{- fail (printf "GUARDRAIL [deploy-allowlist]: deploy.githubActions.repo '%s' isn't an approved deploy repo (%s)." $grepo (join ", " $c.approvedDeployRepos)) -}}
  {{- end -}}
  {{- if not (regexMatch "^[A-Za-z0-9._-]+\\.ya?ml$" (get $g "workflow" | toString)) -}}
    {{- fail "GUARDRAIL [deploy-allowlist]: deploy.githubActions.workflow must be a workflow file name in .github/workflows, e.g. deploy.yaml." -}}
  {{- end -}}
  {{- if not (regexMatch "^[A-Za-z0-9._/-]+$" (get $g "ref" | default "main" | toString)) -}}
    {{- fail "GUARDRAIL [deploy-allowlist]: deploy.githubActions.ref must be a branch or tag name." -}}
  {{- end -}}
{{- end -}}

{{- /* prod-locked and pipeline-shape */ -}}
{{- $p := $v.pipeline | default dict -}}
{{- if not (kindIs "map" $p) -}}
  {{- fail "GUARDRAIL [pipeline-shape]: pipeline must be a map with dev, staging and extraStages." -}}
{{- end -}}
{{- range $key, $_ := $p -}}
  {{- if eq $key "prod" -}}
    {{- fail "GUARDRAIL [prod-locked]: pipeline.prod can't be set. The prod pipeline is the same for every tenant and only the platform team changes it. To propose a new prod check, open a PR to governed-teams." -}}
  {{- else if not (has $key (list "dev" "staging" "extraStages")) -}}
    {{- fail (printf "GUARDRAIL [pipeline-shape]: pipeline.%s isn't a setting. Use pipeline.dev, pipeline.staging or pipeline.extraStages." $key) -}}
  {{- end -}}
{{- end -}}
{{- $envKeys := dict "dev" (list "extraSteps") "staging" (list "extraSteps" "after") -}}
{{- range $env := list "dev" "staging" -}}
  {{- $e := get $p $env | default dict -}}
  {{- range $key, $_ := $e -}}
    {{- if not (has $key (get $envKeys $env)) -}}
      {{- fail (printf "GUARDRAIL [pipeline-shape]: pipeline.%s.%s isn't a setting. Use: %s." $env $key (join ", " (get $envKeys $env))) -}}
    {{- end -}}
  {{- end -}}
  {{- include "governed.checkSteps" (dict "where" (printf "pipeline.%s.extraSteps" $env) "steps" (get $e "extraSteps") "allowed" $c.allowedTenantSteps "root" $) -}}
{{- end -}}

{{- /* Tenant stages. $side tracks which side of staging each stage is on:
       "pre" (comes from dev) or "post" (comes from staging). Only "pre" stages
       can gate staging, so no stage can loop back in front of staging. */ -}}
{{- $reservedStages := splitList " " (include "governed.platformStages" .) -}}
{{- $side := dict "dev" "pre" "staging" "post" -}}
{{- $stages := get $p "extraStages" | default list -}}
{{- if not (kindIs "slice" $stages) -}}
  {{- fail "GUARDRAIL [pipeline-shape]: pipeline.extraStages must be a list." -}}
{{- end -}}
{{- if gt (len $stages) 5 -}}
  {{- fail (printf "GUARDRAIL [pipeline-shape]: %d extra stages. A tenant can add up to 5." (len $stages)) -}}
{{- end -}}
{{- $stageKeys := list "name" "after" "steps" "deploy" "autoPromote" -}}
{{- range $i, $st := $stages -}}
  {{- if not (kindIs "map" $st) -}}
    {{- fail (printf "GUARDRAIL [pipeline-shape]: pipeline.extraStages[%d] isn't a stage." $i) -}}
  {{- end -}}
  {{- $name := get $st "name" | toString -}}
  {{- range $key, $_ := $st -}}
    {{- if not (has $key $stageKeys) -}}
      {{- fail (printf "GUARDRAIL [prod-source-fixed]: extra stage '%s' sets '%s'. Tenant stages take only %s. Which stages they feed is fixed: only staging feeds prod." $name $key (join ", " $stageKeys)) -}}
    {{- end -}}
  {{- end -}}
  {{- if not (regexMatch "^[a-z0-9]([a-z0-9-]{0,38}[a-z0-9])?$" $name) -}}
    {{- fail (printf "GUARDRAIL [pipeline-shape]: pipeline.extraStages[%d] needs a lowercase name (letters, numbers, dashes)." $i) -}}
  {{- end -}}
  {{- if or (has $name $reservedStages) (contains "prod" $name) -}}
    {{- fail (printf "GUARDRAIL [prod-source-fixed]: extra stage '%s' can't be named like a platform stage. Only the platform's prod Stage deploys to prod, and it only takes Freight from staging." $name) -}}
  {{- end -}}
  {{- if hasKey $side $name -}}
    {{- fail (printf "GUARDRAIL [pipeline-shape]: extra stage '%s' is listed twice." $name) -}}
  {{- end -}}
  {{- $after := get $st "after" | default "staging" | toString -}}
  {{- if not (hasKey $side $after) -}}
    {{- fail (printf "GUARDRAIL [pipeline-shape]: extra stage '%s' follows '%s'. It can follow dev, staging, or a tenant stage listed above it." $name $after) -}}
  {{- end -}}
  {{- $_ := set $side $name (get $side $after) -}}
  {{- range $flag := list "deploy" "autoPromote" -}}
    {{- if and (hasKey $st $flag) (not (kindIs "bool" (get $st $flag))) -}}
      {{- fail (printf "GUARDRAIL [pipeline-shape]: extra stage '%s': %s must be true or false." $name $flag) -}}
    {{- end -}}
  {{- end -}}
  {{- if and (not (get $st "deploy")) (not (get $st "steps")) -}}
    {{- fail (printf "GUARDRAIL [pipeline-shape]: extra stage '%s' doesn't deploy and has no steps. Set deploy: true or add steps." $name) -}}
  {{- end -}}
  {{- include "governed.checkSteps" (dict "where" (printf "pipeline.extraStages[%s].steps" $name) "steps" (get $st "steps") "allowed" $c.allowedTenantSteps "root" $) -}}
{{- end -}}

{{- /* pipeline.staging.after: which stages staging waits for. Only dev-side stages. */ -}}
{{- $stagingCfg := get $p "staging" | default dict -}}
{{- if hasKey $stagingCfg "after" -}}
  {{- $sa := get $stagingCfg "after" -}}
  {{- if or (not (kindIs "slice" $sa)) (not $sa) -}}
    {{- fail "GUARDRAIL [pipeline-shape]: pipeline.staging.after must be a list with at least one stage, e.g. [qa]." -}}
  {{- end -}}
  {{- range $s := $sa -}}
    {{- $s = toString $s -}}
    {{- if not (hasKey $side $s) -}}
      {{- fail (printf "GUARDRAIL [pipeline-shape]: pipeline.staging.after lists '%s', which isn't dev or a tenant stage." $s) -}}
    {{- end -}}
    {{- if ne (get $side $s) "pre" -}}
      {{- fail (printf "GUARDRAIL [pipeline-shape]: pipeline.staging.after lists '%s', which comes after staging. That would loop back in front of staging." $s) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- end -}}


{{/* governed.tenantSteps: render a tenant's extra steps into a Stage. Args: dict "where" "steps". */}}
{{- define "governed.tenantSteps" -}}
{{- if .steps }}
# ---- tenant steps ({{ .where }}), from the tenant's app-values.yaml ----
{{ toYaml .steps }}
# ---- end of tenant steps ----
{{- end }}
{{- end -}}
