{{/* Chart name, truncated to the 63-character DNS label limit. */}}
{{- define "laravel-app.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "laravel-app.fullname" -}}
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

{{- define "laravel-app.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "laravel-app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "laravel-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "laravel-app.labels" -}}
helm.sh/chart: {{ include "laravel-app.chart" . }}
{{ include "laravel-app.selectorLabels" . }}
app.kubernetes.io/version: {{ include "laravel-app.version" . | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "laravel-app.version" -}}
{{- default .Chart.AppVersion .Values.image.tag | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "laravel-app.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "laravel-app.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/* repository@digest when a digest is pinned, repository:tag otherwise. */}}
{{- define "laravel-app.image" -}}
{{- if .Values.image.digest }}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest }}
{{- else }}
{{- printf "%s:%s" .Values.image.repository (default .Chart.AppVersion .Values.image.tag) }}
{{- end }}
{{- end }}

{{/* Environment shared by the application pods and the migration job. */}}
{{- define "laravel-app.env" -}}
{{- range $key, $value := .Values.env }}
- name: {{ $key }}
  value: {{ $value | toString | quote }}
{{- end }}
- name: DB_USERNAME
  valueFrom:
    secretKeyRef:
      name: {{ required "database.existingSecret is required" .Values.database.existingSecret }}
      key: {{ .Values.database.usernameKey }}
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.database.existingSecret }}
      key: {{ .Values.database.passwordKey }}
{{- end }}
