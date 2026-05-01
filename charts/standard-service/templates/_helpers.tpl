{{/*
Expand the name of the chart.
*/}}
{{- define "standard-service.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited
to that (DNS-1035 label).
*/}}
{{- define "standard-service.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Chart name + version label value (compliant with the standard label).
*/}}
{{- define "standard-service.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels — every paved-road resource inherits these. Adopters do
not override; the consistency is the point. `app.kubernetes.io/part-of`
is hard-coded to `gridstream` so observability tooling can filter by it.
*/}}
{{- define "standard-service.labels" -}}
helm.sh/chart: {{ include "standard-service.chart" . }}
{{ include "standard-service.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: gridstream
{{- end }}

{{/*
Selector labels — the subset that must match between Deployment.spec.selector
and Service.spec.selector. Kept narrow so chart upgrades don't fight
immutable selector fields.
*/}}
{{- define "standard-service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "standard-service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
