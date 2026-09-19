{{- define "timescaledb.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "timescaledb.fullname" -}}
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

{{- define "timescaledb.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "timescaledb.headlessName" -}}
{{- printf "%s-headless" (include "timescaledb.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Pods carrying this label may reach the database when networkPolicy.allowExternal is false. */}}
{{- define "timescaledb.clientLabel" -}}
{{- printf "%s-client" (include "timescaledb.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "timescaledb.labels" -}}
helm.sh/chart: {{ include "timescaledb.chart" . }}
{{ include "timescaledb.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{- define "timescaledb.selectorLabels" -}}
app.kubernetes.io/name: {{ include "timescaledb.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: timescaledb
{{- end }}

{{- define "timescaledb.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "timescaledb.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "timescaledb.image" -}}
{{- printf "%s/%s:%s" .Values.image.registry .Values.image.repository .Values.image.tag }}
{{- end }}

{{- define "timescaledb.secretName" -}}
{{- default (include "timescaledb.fullname" .) .Values.auth.existingSecret }}
{{- end }}

{{/* Paths. The `-ha` image's home is /home/postgres; PGDATA is a SUBDIRECTORY
of the mount point, never the mount point itself, because initdb refuses a
directory that is not empty and a fresh PVC frequently is not (lost+found). */}}
{{- define "timescaledb.dataMount" -}}/home/postgres/pgdata{{- end }}
{{- define "timescaledb.pgdata" -}}/home/postgres/pgdata/data{{- end }}
{{- define "timescaledb.confDir" -}}/etc/postgresql/conf{{- end }}
{{- define "timescaledb.bootstrapDir" -}}/etc/postgresql/bootstrap{{- end }}
{{- define "timescaledb.secretDir" -}}/etc/postgresql/secrets{{- end }}
{{- define "timescaledb.tlsDir" -}}/etc/postgresql/tls{{- end }}
{{- define "timescaledb.clientTlsDir" -}}/etc/postgresql/tls-client{{- end }}
{{- define "timescaledb.socketDir" -}}/var/run/postgresql{{- end }}

{{/*
A password: explicit value > live Secret > freshly generated. Reusing the live
Secret keeps the value stable across upgrades.
Call with (dict "ctx" $ "value" <explicit> "key" <secret key>).
*/}}
{{- define "timescaledb.password" -}}
{{- if .value -}}
{{- .value -}}
{{- else -}}
{{- $existing := lookup "v1" "Secret" .ctx.Release.Namespace (include "timescaledb.fullname" .ctx) -}}
{{- if and $existing (index $existing.data .key) -}}
{{- index $existing.data .key | b64dec -}}
{{- else -}}
{{- randAlphaNum 32 -}}
{{- end -}}
{{- end -}}
{{- end }}

{{- define "timescaledb.serviceHost" -}}
{{- printf "%s.%s.svc.%s" (include "timescaledb.fullname" .) .Release.Namespace .Values.clusterDomain }}
{{- end }}

{{/* libpq sslmode for in-cluster clients: when the server only speaks hostssl,
`prefer` would silently be refused rather than silently downgraded. */}}
{{- define "timescaledb.sslMode" -}}
{{- if .Values.tls.enabled }}require{{ else }}prefer{{ end }}
{{- end }}

{{/*
postgresql.conf. The chart-computed settings come first and are NOT overridable
from `config`, because each one has to agree with the pod's filesystem, the
Service or the Secret. Everything in `config` follows; later assignments win in
postgresql.conf, but these keys are filtered out of `config` so the intent is
visible rather than merely effective.
*/}}
{{- define "timescaledb.postgresqlConf" -}}
{{- $reserved := list "data_directory" "hba_file" "ident_file" "listen_addresses" "port" "unix_socket_directories" "shared_preload_libraries" "password_encryption" "ssl" "ssl_cert_file" "ssl_key_file" "ssl_ca_file" "ssl_min_protocol_version" -}}
# Managed by the timescaledb chart. Edits here are overwritten on every upgrade;
# change `config` in values.yaml instead. ALTER SYSTEM still works and lands in
# postgresql.auto.conf, which is read after this file.

# --- Filesystem and network. Fixed by the chart: these have to agree with the
# pod's volume mounts and the Service.
data_directory = '{{ include "timescaledb.pgdata" . }}'
hba_file = '{{ include "timescaledb.confDir" . }}/pg_hba.conf'
ident_file = '{{ include "timescaledb.confDir" . }}/pg_ident.conf'
unix_socket_directories = '{{ include "timescaledb.socketDir" . }}'
listen_addresses = '*'
port = {{ .Values.containerPort }}

# --- Authentication. scram-sha-256 only; md5 is a wire-visible hash of the
# password and is treated here as though it were plaintext.
password_encryption = 'scram-sha-256'

# --- Preloaded libraries. Changing this list needs a restart, not a reload.
shared_preload_libraries = '{{ join "," .Values.sharedPreloadLibraries }}'

{{- if .Values.tls.enabled }}

# --- TLS.
ssl = 'on'
ssl_cert_file = '{{ include "timescaledb.tlsDir" . }}/{{ .Values.tls.certKey }}'
ssl_key_file = '{{ include "timescaledb.tlsDir" . }}/{{ .Values.tls.keyKey }}'
{{- if .Values.tls.clientAuth }}
ssl_ca_file = '{{ include "timescaledb.tlsDir" . }}/{{ .Values.tls.caKey }}'
{{- end }}
ssl_min_protocol_version = '{{ .Values.tls.minProtocolVersion }}'
{{- else }}

ssl = 'off'
{{- end }}

# --- From `config` in values.yaml.
{{- range $key := (keys .Values.config | sortAlpha) }}
{{- if not (has $key $reserved) }}
{{ $key }} = '{{ get $.Values.config $key | toString | replace "'" "''" }}'
{{- end }}
{{- end }}
{{- end }}

{{/*
pg_hba.conf. Default: scram-sha-256 and nothing else — no `trust`, no `peer`,
no `md5` — with the remote rules promoted to `hostssl` when TLS is on, so an
unencrypted connection is refused by the server rather than merely unused.
*/}}
{{- define "timescaledb.pgHba" -}}
# Managed by the timescaledb chart.
# TYPE  DATABASE  USER  ADDRESS  METHOD
{{- if .Values.auth.hba }}
{{- range .Values.auth.hba }}
{{ . }}
{{- end }}
{{- else }}
{{- $host := ternary "hostssl" "host" .Values.tls.enabled }}
{{- $opts := "" }}
{{- if and .Values.tls.enabled .Values.tls.clientAuth }}
{{- $opts = printf " clientcert=%s" .Values.tls.clientAuth }}
{{- end }}
# The unix socket lives on an emptyDir inside this pod, so it is reachable only
# by a process already inside the container. It still asks for a password:
# `kubectl exec` is not an authentication decision.
local   all   all                       scram-sha-256
{{ $host }}    all   all   127.0.0.1/32    scram-sha-256
{{ $host }}    all   all   ::1/128         scram-sha-256
{{ $host }}    all   all   0.0.0.0/0       scram-sha-256{{ $opts }}
{{ $host }}    all   all   ::/0            scram-sha-256{{ $opts }}
{{- end }}
{{- end }}

{{- define "timescaledb.validate" -}}
{{- if and .Values.auth.existingSecret .Values.auth.password -}}
{{- fail "set auth.password or auth.existingSecret, not both" -}}
{{- end -}}
{{- if not .Values.auth.database -}}
{{- fail "auth.database is required" -}}
{{- end -}}
{{- if and .Values.auth.appUsername (eq .Values.auth.username .Values.auth.appUsername) -}}
{{- fail "auth.appUsername must differ from auth.username; the point of the app role is that it is not the superuser" -}}
{{- end -}}
{{- if and .Values.tls.enabled (not .Values.tls.existingSecret) -}}
{{- fail "tls.enabled needs tls.existingSecret (a Secret with tls.crt and tls.key)" -}}
{{- end -}}
{{- if and .Values.tls.clientAuth (not (has .Values.tls.clientAuth (list "verify-ca" "verify-full"))) -}}
{{- fail "tls.clientAuth must be verify-ca or verify-full" -}}
{{- end -}}
{{- if and .Values.tls.clientAuth (not .Values.tls.clientSecret) -}}
{{- fail "tls.clientAuth needs tls.clientSecret: the bootstrap Job and helm test connect over TCP and would be refused without a client certificate" -}}
{{- end -}}
{{- if not (has "timescaledb" .Values.sharedPreloadLibraries) -}}
{{- fail "sharedPreloadLibraries must include timescaledb; without it the extension loads but never hooks the planner" -}}
{{- end -}}
{{- if and .Values.persistence.existingClaim (not .Values.persistence.enabled) -}}
{{- fail "persistence.existingClaim needs persistence.enabled: true" -}}
{{- end -}}
{{- if and .Values.podDisruptionBudget.enabled .Values.podDisruptionBudget.minAvailable .Values.podDisruptionBudget.maxUnavailable -}}
{{- fail "set podDisruptionBudget.minAvailable or maxUnavailable, not both" -}}
{{- end -}}
{{- end }}

{{/*
Probe command, as a YAML flow sequence.

pg_isready over the LOCAL UNIX SOCKET, not TCP: the socket exists only once the
postmaster has finished starting, and it does not authenticate — so the probes
never need the password, and rotating it can never take the pod down. -U/-d are
passed because pg_isready otherwise defaults to the OS user (`postgres` in this
image), which is a false negative when auth.username is something else.
*/}}
{{- define "timescaledb.probeCommand" -}}
["pg_isready", "-q", "-h", {{ include "timescaledb.socketDir" . | quote }}, "-p", {{ .Values.containerPort | quote }}, "-U", {{ .Values.auth.username | quote }}, "-d", {{ .Values.auth.database | quote }}]
{{- end }}

{{/*
Shell snippet: point libpq at the client certificate, when one is configured.

The key is copied out of the Secret mount because libpq — unlike the server —
rejects a private key with ANY group permission, and a Secret volume cannot
produce a 0600 file owned by the process reading it.
*/}}
{{- define "timescaledb.clientCertSetup" -}}
{{- if .Values.tls.clientSecret }}
install -m 0600 {{ include "timescaledb.clientTlsDir" . }}/{{ .Values.tls.keyKey }} /tmp/client.key
export PGSSLCERT={{ include "timescaledb.clientTlsDir" . }}/{{ .Values.tls.certKey }}
export PGSSLKEY=/tmp/client.key
export PGSSLROOTCERT={{ include "timescaledb.clientTlsDir" . }}/{{ .Values.tls.caKey }}
{{- end }}
{{- end }}

{{/* Volume + mount for the client certificate, when one is configured. */}}
{{- define "timescaledb.clientCertMount" -}}
{{- if .Values.tls.clientSecret }}
- name: tls-client
  mountPath: {{ include "timescaledb.clientTlsDir" . }}
  readOnly: true
{{- end }}
{{- end }}

{{- define "timescaledb.clientCertVolume" -}}
{{- if .Values.tls.clientSecret }}
- name: tls-client
  secret:
    secretName: {{ .Values.tls.clientSecret }}
    defaultMode: 0440
{{- end }}
{{- end }}
