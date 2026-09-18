{{- define "kafka.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "kafka.fullname" -}}
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

{{- define "kafka.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "kafka.headlessName" -}}
{{- printf "%s-headless" (include "kafka.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "kafka.uiName" -}}
{{- printf "%s-ui" (include "kafka.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Pods carrying this label may reach the client port when networkPolicy.allowExternal is false. */}}
{{- define "kafka.clientLabel" -}}
{{- printf "%s-client" (include "kafka.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "kafka.labels" -}}
helm.sh/chart: {{ include "kafka.chart" . }}
app.kubernetes.io/name: {{ include "kafka.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{- define "kafka.selectorLabels" -}}
app.kubernetes.io/name: {{ include "kafka.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: broker
{{- end }}

{{- define "kafka.ui.selectorLabels" -}}
app.kubernetes.io/name: {{ include "kafka.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: ui
{{- end }}

{{- define "kafka.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "kafka.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "kafka.image" -}}
{{- printf "%s/%s:%s" .Values.image.registry .Values.image.repository (default .Chart.AppVersion .Values.image.tag) }}
{{- end }}

{{- define "kafka.ui.image" -}}
{{- printf "%s/%s:%s" .Values.ui.image.registry .Values.ui.image.repository .Values.ui.image.tag }}
{{- end }}

{{/* Bootstrap address for in-cluster clients. */}}
{{- define "kafka.bootstrapServers" -}}
{{- printf "%s.%s.svc.%s:%d" (include "kafka.fullname" .) .Release.Namespace .Values.clusterDomain (int .Values.listeners.client.port) }}
{{- end }}

{{/* Static KRaft voter set: <ordinal>@<pod>.<headless>:<controller port> for every replica. */}}
{{- define "kafka.quorumVoters" -}}
{{- $fullname := include "kafka.fullname" . -}}
{{- $headless := include "kafka.headlessName" . -}}
{{- $voters := list -}}
{{- range $i := until (int .Values.replicaCount) -}}
{{- $voters = append $voters (printf "%d@%s-%d.%s.%s.svc.%s:%d" $i $fullname $i $headless $.Release.Namespace $.Values.clusterDomain (int $.Values.listeners.controller.port)) -}}
{{- end -}}
{{- join "," $voters -}}
{{- end }}

{{- define "kafka.listeners" -}}
{{- $l := list (printf "%s://0.0.0.0:%d" .Values.listeners.client.name (int .Values.listeners.client.port)) (printf "%s://0.0.0.0:%d" .Values.listeners.controller.name (int .Values.listeners.controller.port)) -}}
{{- if .Values.externalAccess.enabled -}}
{{- $l = append $l (printf "%s://0.0.0.0:%d" .Values.externalAccess.name (int .Values.externalAccess.containerPort)) -}}
{{- end -}}
{{- join "," $l -}}
{{- end }}

{{/*
Render a property value. YAML integers arrive as float64 and would otherwise
print as 1.073741824e+09.
*/}}
{{- define "kafka.propValue" -}}
{{- if and (kindIs "float64" .) (eq (float64 (int64 .)) .) -}}
{{- int64 . -}}
{{- else -}}
{{- . -}}
{{- end -}}
{{- end }}

{{/*
KRaft cluster id: explicit value > live Secret > freshly generated.
A generated id is 16 random bytes as unpadded base64url, the format
kafka-storage.sh expects.
*/}}
{{- define "kafka.clusterId" -}}
{{- if .Values.clusterId -}}
{{- .Values.clusterId -}}
{{- else -}}
{{- $existing := lookup "v1" "Secret" .Release.Namespace (include "kafka.fullname" .) -}}
{{- if and $existing (index $existing.data "cluster-id") -}}
{{- index $existing.data "cluster-id" | b64dec -}}
{{- else -}}
{{- randAlphaNum 16 | b64enc | trimSuffix "==" | replace "+" "-" | replace "/" "_" -}}
{{- end -}}
{{- end -}}
{{- end }}

{{- define "kafka.secretName" -}}
{{- default (include "kafka.fullname" .) .Values.existingSecret }}
{{- end }}

{{- define "kafka.ui.password" -}}
{{- if .Values.ui.auth.password -}}
{{- .Values.ui.auth.password -}}
{{- else -}}
{{- $existing := lookup "v1" "Secret" .Release.Namespace (include "kafka.uiName" .) -}}
{{- if and $existing (index $existing.data "password") -}}
{{- index $existing.data "password" | b64dec -}}
{{- else -}}
{{- randAlphaNum 24 -}}
{{- end -}}
{{- end -}}
{{- end }}

{{- define "kafka.ui.secretName" -}}
{{- default (include "kafka.uiName" .) .Values.ui.auth.existingSecret }}
{{- end }}

{{/*
Fail at render time on configs that start but do not work: internal topics
cannot have more replicas than there are brokers.
*/}}
{{- define "kafka.validate" -}}
{{- $replicas := int .Values.replicaCount -}}
{{- if lt $replicas 1 -}}
{{- fail "replicaCount must be at least 1" -}}
{{- end -}}
{{- range $k, $v := .Values.config -}}
{{- if or (hasSuffix "replication.factor" $k) (eq $k "min.insync.replicas") (eq $k "transaction.state.log.min.isr") -}}
{{- if gt (int $v) $replicas -}}
{{- fail (printf "config.%s=%v exceeds replicaCount=%d; internal topics would fail to create" $k $v $replicas) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- range .Values.topics -}}
{{- if gt (int (default 1 .replicationFactor)) $replicas -}}
{{- fail (printf "topic %s: replicationFactor exceeds replicaCount=%d" .name $replicas) -}}
{{- end -}}
{{- end -}}
{{- if and .Values.externalAccess.enabled (not (has .Values.externalAccess.service.type (list "ClusterIP" "NodePort"))) -}}
{{- fail "externalAccess.service.type must be ClusterIP or NodePort" -}}
{{- end -}}
{{- end }}

{{/*
Readiness/startup probe command. The tool is a separate JVM that inherits the
container env, including KAFKA_HEAP_OPTS, so its heap is capped here.
*/}}
{{- define "kafka.probeCommand" -}}
- /bin/bash
- -c
- KAFKA_HEAP_OPTS="-Xmx96m" KAFKA_JMX_OPTS="" exec /opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server localhost:{{ .Values.listeners.client.port }} >/dev/null 2>&1
{{- end }}
