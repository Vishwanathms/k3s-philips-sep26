{{/*
A named template - defined once, invoked with `include` wherever the
release+chart name combination is needed, so every object stays consistent.
*/}}
{{- define "template-lab.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
