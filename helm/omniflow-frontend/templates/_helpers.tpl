{{/*
Expand the name of the chart.
*/}}
{{- define "omniflow-frontend.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "omniflow-frontend.fullname" -}}
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
Create chart name and version as used by the chart label.
*/}}
{{- define "omniflow-frontend.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "omniflow-frontend.labels" -}}
helm.sh/chart: {{ include "omniflow-frontend.chart" . }}
{{ include "omniflow-frontend.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: omniflow-platform
{{- end }}

{{/*
Selector labels
*/}}
{{- define "omniflow-frontend.selectorLabels" -}}
app.kubernetes.io/name: {{ include "omniflow-frontend.name" . }}
app.kubernetes.io/component: frontend
{{- end }}

{{/*
Service account name
*/}}
{{- define "omniflow-frontend.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "omniflow-frontend.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
