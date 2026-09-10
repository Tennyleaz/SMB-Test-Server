{{/*
Chart name, overridable.
*/}}
{{- define "smb-test-server.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified resource name. Kept under 63 characters because it becomes a
label value and a DNS label.
*/}}
{{- define "smb-test-server.fullname" -}}
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

{{- define "smb-test-server.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "smb-test-server.labels" -}}
helm.sh/chart: {{ include "smb-test-server.chart" . }}
{{ include "smb-test-server.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels. These are immutable on a Deployment, so nothing release- or
version-specific may appear here.
*/}}
{{- define "smb-test-server.selectorLabels" -}}
app.kubernetes.io/name: {{ include "smb-test-server.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "smb-test-server.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "smb-test-server.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Name of the Secret holding the SMB password: either the user's existing one or
the one this chart creates.
*/}}
{{- define "smb-test-server.secretName" -}}
{{- if .Values.auth.existingSecret }}
{{- .Values.auth.existingSecret }}
{{- else }}
{{- include "smb-test-server.fullname" . }}
{{- end }}
{{- end }}

{{- define "smb-test-server.secretKey" -}}
{{- if .Values.auth.existingSecret }}
{{- .Values.auth.existingSecretKey }}
{{- else }}
{{- "smb-password" }}
{{- end }}
{{- end }}

{{/*
smb.port accepts a space-separated list, mirroring `smb ports` in smb.conf.
Probes and the container port can only use one, so take the first.
*/}}
{{- define "smb-test-server.firstPort" -}}
{{- .Values.smb.port | toString | splitList " " | first }}
{{- end }}
