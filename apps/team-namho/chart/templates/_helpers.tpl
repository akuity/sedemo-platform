{{/*
The resource name is fixed, not release-prefixed: the smol-smoke
AnalysisTemplate curls http://smol.<namespace>.svc.cluster.local, and each
Stage deploys into a namespace of its own, so there is nothing to collide with.
*/}}
{{- define "smol.name" -}}smol{{- end -}}

{{- define "smol.host" -}}
{{- .Values.ingress.host | default (printf "smol-%s.akpdemoapps.link" .Values.stage) -}}
{{- end -}}
