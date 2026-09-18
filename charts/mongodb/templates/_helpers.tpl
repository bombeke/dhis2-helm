{{- define "mongodb.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "mongodb.fullname" -}}
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

{{- define "mongodb.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "mongodb.headlessName" -}}
{{- printf "%s-headless" (include "mongodb.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Pods carrying this label may reach MongoDB when networkPolicy.allowExternal is false. */}}
{{- define "mongodb.clientLabel" -}}
{{- printf "%s-client" (include "mongodb.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "mongodb.labels" -}}
helm.sh/chart: {{ include "mongodb.chart" . }}
{{ include "mongodb.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{- define "mongodb.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mongodb.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: mongodb
{{- end }}

{{- define "mongodb.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "mongodb.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "mongodb.image" -}}
{{- printf "%s/%s:%s" .Values.image.registry .Values.image.repository .Values.image.tag }}
{{- end }}

{{- define "mongodb.secretName" -}}
{{- default (include "mongodb.fullname" .) .Values.auth.existingSecret }}
{{- end }}

{{/*
A password: explicit value > live Secret > freshly generated. Reusing the live
Secret keeps the value stable across upgrades.
Call with (dict "ctx" $ "value" <explicit> "key" <secret key>).
*/}}
{{- define "mongodb.password" -}}
{{- if .value -}}
{{- .value -}}
{{- else -}}
{{- $existing := lookup "v1" "Secret" .ctx.Release.Namespace (include "mongodb.fullname" .ctx) -}}
{{- if and $existing (index $existing.data .key) -}}
{{- index $existing.data .key | b64dec -}}
{{- else -}}
{{- randAlphaNum 24 -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/* In-cluster host:port for clients. */}}
{{- define "mongodb.host" -}}
{{- printf "%s.%s.svc.%s:%d" (include "mongodb.fullname" .) .Release.Namespace .Values.clusterDomain (int .Values.service.port) }}
{{- end }}

{{/*
mongod.conf. The chart-computed settings come first; `config` is merged over
them, so a key set there wins.
*/}}
{{- define "mongodb.config" -}}
{{- $base := dict
  "net" (dict "port" (int .Values.containerPort) "bindIpAll" true)
  "storage" (dict "dbPath" "/data/db")
  "security" (dict "authorization" "enabled")
-}}
{{- toYaml (mergeOverwrite $base (deepCopy .Values.config)) }}
{{- end }}

{{/*
Probe command. `ping` needs no authentication, so the probe does not have to
read the root password.
*/}}
{{- define "mongodb.probeCommand" -}}
- mongosh
- --quiet
- --norc
- --port
- {{ .Values.containerPort | quote }}
- --eval
- "quit(db.adminCommand({ ping: 1 }).ok === 1 ? 0 : 1)"
{{- end }}

{{- define "mongodb.validate" -}}
{{- if and .Values.auth.existingSecret .Values.auth.rootPassword -}}
{{- fail "set auth.rootPassword or auth.existingSecret, not both" -}}
{{- end -}}
{{- if and .Values.auth.username (not .Values.auth.database) -}}
{{- fail "auth.username needs auth.database" -}}
{{- end -}}
{{- if and .Values.persistence.existingClaim (not .Values.persistence.enabled) -}}
{{- fail "persistence.existingClaim needs persistence.enabled: true" -}}
{{- end -}}
{{- end }}
