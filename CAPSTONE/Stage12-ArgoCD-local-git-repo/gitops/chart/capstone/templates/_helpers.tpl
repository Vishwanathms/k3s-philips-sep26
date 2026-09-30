{{/*
Common labels applied to every object, so `kubectl get all -l app.kubernetes.io/part-of=capstone`
still works exactly like it did with the raw manifests in Stages 02-10.
*/}}
{{- define "capstone.labels" -}}
app.kubernetes.io/part-of: capstone
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
