{{- define "typesense.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "typesense.fullname" -}}
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

{{- define "typesense.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "typesense.headlessName" -}}
{{- printf "%s-headless" (include "typesense.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Pods carrying this label may reach the API port when networkPolicy.allowExternal is false. */}}
{{- define "typesense.clientLabel" -}}
{{- printf "%s-client" (include "typesense.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "typesense.labels" -}}
helm.sh/chart: {{ include "typesense.chart" . }}
{{ include "typesense.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{- define "typesense.selectorLabels" -}}
app.kubernetes.io/name: {{ include "typesense.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: search
{{- end }}

{{- define "typesense.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "typesense.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "typesense.image" -}}
{{- printf "%s/%s:%s" .Values.image.registry .Values.image.repository .Values.image.tag }}
{{- end }}

{{- define "typesense.clientImage" -}}
{{- printf "%s/%s:%s" .Values.clientImage.registry .Values.clientImage.repository .Values.clientImage.tag }}
{{- end }}

{{- define "typesense.secretName" -}}
{{- default (include "typesense.fullname" .) .Values.auth.existingSecret }}
{{- end }}

{{/* More than one node means Raft, a nodes file, and the peer resolver. */}}
{{- define "typesense.clustered" -}}
{{- if gt (int .Values.replicaCount) 1 }}true{{ end }}
{{- end }}

{{/* Paths. */}}
{{- define "typesense.dataDir" -}}/data{{- end }}
{{- define "typesense.confDir" -}}/etc/typesense/conf{{- end }}
{{- define "typesense.scriptDir" -}}/etc/typesense/scripts{{- end }}
{{- define "typesense.secretDir" -}}/etc/typesense/secrets{{- end }}
{{- define "typesense.tlsDir" -}}/etc/typesense/tls{{- end }}
{{/* The assembled config file: an emptyDir, because it is built at start-up
from the ConfigMap plus the Secret plus this pod's own IP. */}}
{{- define "typesense.runtimeDir" -}}/etc/typesense/runtime{{- end }}
{{- define "typesense.nodesFile" -}}/etc/typesense/nodes/nodes{{- end }}
{{- define "typesense.nodesDir" -}}/etc/typesense/nodes{{- end }}

{{/*
The bootstrap API key: explicit value > live Secret > freshly generated.
Reusing the live Secret keeps the key stable across upgrades, which matters
more here than for a password — every client holds a key derived from it.
*/}}
{{- define "typesense.apiKey" -}}
{{- if .Values.auth.apiKey -}}
{{- .Values.auth.apiKey -}}
{{- else -}}
{{- $existing := lookup "v1" "Secret" .Release.Namespace (include "typesense.fullname" .) -}}
{{- if and $existing (index $existing.data "api-key") -}}
{{- index $existing.data "api-key" | b64dec -}}
{{- else -}}
{{- randAlphaNum 40 -}}
{{- end -}}
{{- end -}}
{{- end }}

{{- define "typesense.scheme" -}}
{{- if .Values.tls.enabled }}https{{ else }}http{{ end }}
{{- end }}

{{- define "typesense.serviceHost" -}}
{{- printf "%s.%s.svc.%s" (include "typesense.fullname" .) .Release.Namespace .Values.clusterDomain }}
{{- end }}

{{- define "typesense.headlessHost" -}}
{{- printf "%s.%s.svc.%s" (include "typesense.headlessName" .) .Release.Namespace .Values.clusterDomain }}
{{- end }}

{{/* Stable per-pod DNS name, e.g. release-typesense-0.release-typesense-headless.ns.svc. */}}
{{- define "typesense.podHost" -}}
{{- printf "%s-%d.%s" (include "typesense.fullname" .ctx) (int .ordinal) (include "typesense.headlessHost" .ctx) }}
{{- end }}

{{/* curl flags for verifying the server, when TLS is on and a CA is supplied. */}}
{{- define "typesense.curlCaFlag" -}}
{{- if and .Values.tls.enabled .Values.tls.caKey }}--cacert {{ include "typesense.tlsDir" . }}/{{ .Values.tls.caKey }}{{ end }}
{{- end }}

{{/*
typesense-server.ini, minus the two lines that cannot be known at template time:
`api-key`, which lives in a Secret, and `peering-address`, which is this pod's
IP. The init container appends both.
*/}}
{{- define "typesense.serverIni" -}}
{{- $reserved := list "api-key" "data-dir" "api-address" "api-port" "peering-port" "peering-address" "nodes" "ssl-certificate" "ssl-certificate-key" "log-dir" "reset-peers-on-error" -}}
; Managed by the typesense chart. Edits here are overwritten on every upgrade;
; change `config` in values.yaml instead.

[server]

; --- Owned by the chart: these have to agree with the volume mounts, the
; Service and the NetworkPolicy.
data-dir = {{ include "typesense.dataDir" . }}
api-address = 0.0.0.0
api-port = {{ .Values.service.port }}
peering-port = {{ .Values.cluster.peeringPort }}
{{- if include "typesense.clustered" . }}
nodes = {{ include "typesense.nodesFile" . }}
reset-peers-on-error = {{ .Values.cluster.resetPeersOnError }}
{{- end }}
{{- if .Values.tls.enabled }}
ssl-certificate = {{ include "typesense.tlsDir" . }}/{{ .Values.tls.certKey }}
ssl-certificate-key = {{ include "typesense.tlsDir" . }}/{{ .Values.tls.keyKey }}
{{- end }}

; --- From `config` in values.yaml.
{{- range $key := (keys .Values.config | sortAlpha) }}
{{- if not (has $key $reserved) }}
{{ $key }} = {{ get $.Values.config $key }}
{{- end }}
{{- end }}
{{- end }}

{{- define "typesense.validate" -}}
{{- $n := int .Values.replicaCount -}}
{{- if lt $n 1 -}}
{{- fail "replicaCount must be at least 1" -}}
{{- end -}}
{{- if and (gt $n 1) (eq (mod $n 2) 0) -}}
{{- fail (printf "replicaCount %d is even: Raft needs a majority, so %d nodes tolerate %d failures — exactly what %d nodes tolerate — while adding one more node that can fail. Use %d or %d." $n $n (sub (div $n 2) 1) (sub $n 1) (sub $n 1) (add $n 1)) -}}
{{- end -}}
{{- if and .Values.auth.existingSecret .Values.auth.apiKey -}}
{{- fail "set auth.apiKey or auth.existingSecret, not both" -}}
{{- end -}}
{{- if and .Values.tls.enabled (not .Values.tls.existingSecret) -}}
{{- fail "tls.enabled needs tls.existingSecret (a Secret with tls.crt and tls.key)" -}}
{{- end -}}
{{- if .Values.backup.enabled -}}
{{- if ge (int .Values.backup.targetOrdinal) $n -}}
{{- fail (printf "backup.targetOrdinal %d does not exist: replicaCount is %d, so ordinals run 0..%d" (int .Values.backup.targetOrdinal) $n (sub $n 1)) -}}
{{- end -}}
{{- if not .Values.persistence.enabled -}}
{{- fail "backup.enabled needs persistence.enabled: the node writes the snapshot to its own filesystem" -}}
{{- end -}}
{{- end -}}
{{- if and .Values.podAntiAffinityPreset (not (has .Values.podAntiAffinityPreset (list "soft" "hard"))) -}}
{{- fail "podAntiAffinityPreset must be soft, hard, or empty" -}}
{{- end -}}
{{- end }}

{{/* Default anti-affinity, used only when .Values.affinity is empty. */}}
{{- define "typesense.affinity" -}}
{{- if .Values.affinity }}
{{- toYaml .Values.affinity }}
{{- else if eq .Values.podAntiAffinityPreset "hard" }}
podAntiAffinity:
  requiredDuringSchedulingIgnoredDuringExecution:
    - topologyKey: kubernetes.io/hostname
      labelSelector:
        matchLabels:
          {{- include "typesense.selectorLabels" . | nindent 10 }}
{{- else if eq .Values.podAntiAffinityPreset "soft" }}
podAntiAffinity:
  preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        topologyKey: kubernetes.io/hostname
        labelSelector:
          matchLabels:
            {{- include "typesense.selectorLabels" . | nindent 12 }}
{{- end }}
{{- end }}
