{{- define "tenant-app.labels" -}}
app.kubernetes.io/name: tenant-app
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: demo-tenant-overrides
{{- end -}}
