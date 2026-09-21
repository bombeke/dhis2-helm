{{- define "gravitino.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "gravitino.fullname" -}}
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

{{- define "gravitino.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Pods carrying this label may reach the REST port when networkPolicy.allowExternal is false. */}}
{{- define "gravitino.clientLabel" -}}
{{- printf "%s-client" (include "gravitino.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "gravitino.labels" -}}
helm.sh/chart: {{ include "gravitino.chart" . }}
{{ include "gravitino.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{- define "gravitino.selectorLabels" -}}
app.kubernetes.io/name: {{ include "gravitino.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: iceberg-rest
{{- end }}

{{- define "gravitino.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "gravitino.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "gravitino.image" -}}
{{- printf "%s/%s:%s" .Values.image.registry .Values.image.repository .Values.image.tag }}
{{- with .Values.image.digest }}@{{ . }}{{ end }}
{{- end }}

{{/* Paths. */}}
{{- define "gravitino.home" -}}/opt/gravitino-iceberg-rest-server{{- end }}
{{- define "gravitino.confDir" -}}/etc/gravitino/conf{{- end }}
{{- define "gravitino.scriptDir" -}}/etc/gravitino/scripts{{- end }}
{{- define "gravitino.secretDir" -}}/etc/gravitino/secrets{{- end }}
{{- define "gravitino.tlsDir" -}}/etc/gravitino/tls{{- end }}
{{/* The assembled config: an emptyDir, because it is the ConfigMap plus the
Secret files, joined at start-up. GRAVITINO_CONF_DIR points here. */}}
{{- define "gravitino.runtimeDir" -}}/etc/gravitino/runtime{{- end }}
{{- define "gravitino.extraLibsDir" -}}/opt/gravitino-extra-libs{{- end }}
{{- define "gravitino.dataDir" -}}/var/lib/gravitino{{- end }}

{{- define "gravitino.sqlite" -}}
{{- if eq .Values.catalog.backend "sqlite" }}true{{ end }}
{{- end }}

{{- define "gravitino.postgresql" -}}
{{- if eq .Values.catalog.backend "postgresql" }}true{{ end }}
{{- end }}

{{- define "gravitino.downloadDriver" -}}
{{- if and (include "gravitino.postgresql" .) .Values.catalog.postgresql.driver.download }}true{{ end }}
{{- end }}

{{- define "gravitino.staticKeys" -}}
{{- if eq .Values.storage.credentials.source "static" }}true{{ end }}
{{- end }}

{{- define "gravitino.pathStyle" -}}
{{- if kindIs "bool" .Values.storage.pathStyleAccess }}
{{- .Values.storage.pathStyleAccess }}
{{- else }}
{{- eq .Values.storage.provider "minio" }}
{{- end }}
{{- end }}

{{- define "gravitino.scheme" -}}
{{- if .Values.tls.enabled }}https{{ else }}http{{ end }}
{{- end }}

{{- define "gravitino.serviceHost" -}}
{{- printf "%s.%s.svc.%s" (include "gravitino.fullname" .) .Release.Namespace .Values.clusterDomain }}
{{- end }}

{{- define "gravitino.catalogUri" -}}
{{- printf "%s://%s:%d/iceberg" (include "gravitino.scheme" .) (include "gravitino.serviceHost" .) (int .Values.service.port) }}
{{- end }}

{{- define "gravitino.claimName" -}}
{{- default (printf "%s-data" (include "gravitino.fullname" .)) .Values.persistence.existingClaim }}
{{- end }}

{{/* The chart's own Secret, holding whatever the user did not bring. */}}
{{- define "gravitino.secretName" -}}
{{- include "gravitino.fullname" . }}
{{- end }}

{{- define "gravitino.storageSecretName" -}}
{{- default (include "gravitino.secretName" .) .Values.storage.credentials.existingSecret }}
{{- end }}

{{- define "gravitino.storageAccessKeyKey" -}}
{{- if .Values.storage.credentials.existingSecret }}{{ .Values.storage.credentials.accessKeyKey }}{{ else }}s3-access-key-id{{ end }}
{{- end }}

{{- define "gravitino.storageSecretKeyKey" -}}
{{- if .Values.storage.credentials.existingSecret }}{{ .Values.storage.credentials.secretKeyKey }}{{ else }}s3-secret-access-key{{ end }}
{{- end }}

{{- define "gravitino.dbSecretName" -}}
{{- default (include "gravitino.secretName" .) .Values.catalog.postgresql.existingSecret }}
{{- end }}

{{- define "gravitino.dbPasswordKey" -}}
{{- if .Values.catalog.postgresql.existingSecret }}{{ .Values.catalog.postgresql.existingSecretPasswordKey }}{{ else }}jdbc-password{{ end }}
{{- end }}

{{/* Does the chart need a Secret of its own at all? */}}
{{- define "gravitino.ownSecret" -}}
{{- if or (and (include "gravitino.staticKeys" .) (not .Values.storage.credentials.existingSecret)) (and (include "gravitino.postgresql" .) (not .Values.catalog.postgresql.existingSecret)) .Values.extraSecretConfig }}true{{ end }}
{{- end }}

{{- define "gravitino.jdbcUri" -}}
{{- if include "gravitino.sqlite" . -}}
jdbc:sqlite:{{ include "gravitino.dataDir" . }}/{{ .Values.catalog.sqlite.file }}?busy_timeout={{ int .Values.catalog.sqlite.busyTimeoutMs }}&journal_mode=WAL&synchronous=NORMAL
{{- else -}}
jdbc:postgresql://{{ .Values.catalog.postgresql.host }}:{{ int .Values.catalog.postgresql.port }}/{{ .Values.catalog.postgresql.database }}{{ with .Values.catalog.postgresql.params }}?{{ . }}{{ end }}
{{- end -}}
{{- end }}

{{/*
gravitino-iceberg-rest-server.conf, minus the secrets. Property names were
extracted from the 1.3.0 jars, not recalled.
*/}}
{{- define "gravitino.serverConf" -}}
{{- $p := "gravitino.iceberg-rest." -}}
{{- $reserved := list "host" "httpPort" "httpsPort" "enableHttps" "keyStorePath" "keyStorePassword" "keyStoreType" "managerPassword" "catalog-backend" "catalog-backend-name" "uri" "warehouse" "io-impl" "jdbc-driver" "jdbc-user" "jdbc-password" "jdbc-initialize" "jdbc.schema-version" "credential-providers" "credential-provider-type" -}}
# Managed by the gravitino chart. Assembled at pod start from the ConfigMap and
# the Secret; edit values.yaml, not this.

# --- Owned by the chart: these have to agree with the Service, the probes and
# the volume mounts.
{{ $p }}host = 0.0.0.0
{{- if .Values.tls.enabled }}
{{ $p }}enableHttps = true
{{ $p }}httpsPort = {{ .Values.service.port }}
{{ $p }}keyStorePath = {{ include "gravitino.tlsDir" . }}/{{ .Values.tls.keystoreKey }}
{{ $p }}keyStoreType = {{ .Values.tls.keystoreType }}
{{- else }}
{{ $p }}httpPort = {{ .Values.service.port }}
{{- end }}

# --- The catalog. jdbc always: the shipped `memory` holds every table
# definition in RAM and loses them on restart without a word.
{{ $p }}catalog-backend = jdbc
{{- with .Values.catalog.name }}
{{ $p }}catalog-backend-name = {{ . }}
{{- end }}
{{ $p }}uri = {{ include "gravitino.jdbcUri" . }}
{{- if include "gravitino.sqlite" . }}
{{ $p }}jdbc-driver = org.sqlite.JDBC
# Required by the JDBC catalog, meaningless to SQLite.
{{ $p }}jdbc-user = gravitino
{{ $p }}jdbc-password = gravitino
{{- else }}
{{ $p }}jdbc-driver = org.postgresql.Driver
{{ $p }}jdbc-user = {{ .Values.catalog.postgresql.username }}
# jdbc-password is appended from the Secret.
{{- end }}
{{ $p }}jdbc-initialize = {{ .Values.catalog.initialize }}
{{ $p }}jdbc.schema-version = V1

# --- Data files.
{{ $p }}warehouse = {{ .Values.catalog.warehouse }}
{{ $p }}io-impl = org.apache.iceberg.aws.s3.S3FileIO
{{- with .Values.storage.endpoint }}
{{ $p }}s3-endpoint = {{ . }}
{{- end }}
{{ $p }}s3-region = {{ .Values.storage.region }}
{{ $p }}s3-path-style-access = {{ include "gravitino.pathStyle" . }}
{{- if include "gravitino.staticKeys" . }}
# s3-access-key-id and s3-secret-access-key are appended from the Secret.
{{- else }}
# No keys: the AWS SDK default chain (IRSA, Pod Identity, instance profile).
{{- end }}
{{- if .Values.storage.credentialVending.enabled }}
{{ $p }}credential-providers = {{ .Values.storage.credentialVending.provider }}
{{- with .Values.storage.credentialVending.roleArn }}
{{ $p }}s3-role-arn = {{ . }}
{{- end }}
{{- with .Values.storage.credentialVending.externalId }}
{{ $p }}s3-external-id = {{ . }}
{{- end }}
{{- with .Values.storage.credentialVending.tokenServiceEndpoint }}
{{ $p }}s3-token-service-endpoint = {{ . }}
{{- end }}
{{- end }}

# --- From `config` in values.yaml.
{{- range $key := (keys .Values.config | sortAlpha) }}
{{- if and (not (has $key $reserved)) (not (hasPrefix "s3-" $key)) (not (hasPrefix "jdbc" $key)) }}
{{ $p }}{{ $key }} = {{ get $.Values.config $key }}
{{- end }}
{{- end }}

# --- From `rawConfig` in values.yaml.
{{- range $key := (keys .Values.rawConfig | sortAlpha) }}
{{ $key }} = {{ get $.Values.rawConfig $key }}
{{- end }}
{{- end }}

{{/* Console logging: the image's own config writes rolling files under
logs/, which is on the read-only root filesystem and not what kubectl reads. */}}
{{- define "gravitino.log4j2" -}}
status = warn
appender.console.type = Console
appender.console.name = console
appender.console.target = SYSTEM_OUT
appender.console.layout.type = PatternLayout
appender.console.layout.pattern = %d{yyyy-MM-dd'T'HH:mm:ss.SSSZ} %-5level [%t] %c{1.} - %msg%n
rootLogger.level = {{ .Values.logLevel }}
rootLogger.appenderRef.console.ref = console
# The AWS SDK and Jetty are noisy at INFO and say nothing actionable there.
logger.aws.name = software.amazon.awssdk
logger.aws.level = warn
logger.jetty.name = org.eclipse.jetty
logger.jetty.level = warn
{{- end }}

{{- define "gravitino.javaOpts" -}}
-XX:+UseContainerSupport -XX:MaxRAMPercentage={{ .Values.jvm.maxRAMPercentage }} -XX:InitialRAMPercentage={{ .Values.jvm.initialRAMPercentage }}
{{- with .Values.jvm.activeProcessorCount }} -XX:ActiveProcessorCount={{ . }}{{ end }}
{{- with .Values.jvm.extraOpts }} {{ . }}{{ end }}
{{- end }}

{{- define "gravitino.validate" -}}
{{- if not (has .Values.catalog.backend (list "sqlite" "postgresql")) -}}
{{- fail (printf "catalog.backend %q is not supported: use sqlite or postgresql. The shipped `memory` backend holds every table definition in RAM and loses them on restart, silently." .Values.catalog.backend) -}}
{{- end -}}
{{- if not .Values.catalog.warehouse -}}
{{- fail "catalog.warehouse is empty. The shipped default is /tmp, which works perfectly and loses every data file on restart with nothing in any log. Set it to an object-store URI, e.g. s3://lake/warehouse." -}}
{{- end -}}
{{- if not (hasPrefix "s3://" .Values.catalog.warehouse) -}}
{{- fail (printf "catalog.warehouse %q must be an s3:// URI (MinIO included): anything else lands on the pod's own filesystem." .Values.catalog.warehouse) -}}
{{- end -}}
{{- if not (has .Values.storage.provider (list "minio" "s3")) -}}
{{- fail "storage.provider must be minio or s3" -}}
{{- end -}}
{{- if and (eq .Values.storage.provider "minio") (not .Values.storage.endpoint) -}}
{{- fail "storage.provider=minio needs storage.endpoint (e.g. http://minio.minio.svc:9000): without it the S3 client goes to AWS." -}}
{{- end -}}
{{- if not (has .Values.storage.credentials.source (list "static" "defaultChain")) -}}
{{- fail "storage.credentials.source must be static or defaultChain" -}}
{{- end -}}
{{- if and (eq .Values.storage.credentials.source "defaultChain") (eq .Values.storage.provider "minio") -}}
{{- fail "storage.credentials.source=defaultChain is AWS-only (IRSA, Pod Identity, instance profile). MinIO needs static keys." -}}
{{- end -}}
{{- if and (include "gravitino.staticKeys" .) (not .Values.storage.credentials.existingSecret) (or (not .Values.storage.credentials.accessKey) (not .Values.storage.credentials.secretKey)) -}}
{{- fail "static storage credentials need storage.credentials.existingSecret, or both accessKey and secretKey" -}}
{{- end -}}
{{- if .Values.storage.credentialVending.enabled -}}
{{- if not (has .Values.storage.credentialVending.provider (list "s3-secret-key" "s3-token")) -}}
{{- fail "storage.credentialVending.provider must be s3-secret-key or s3-token" -}}
{{- end -}}
{{- if and (eq .Values.storage.credentialVending.provider "s3-token") (not .Values.storage.credentialVending.roleArn) -}}
{{- fail "credential vending with s3-token needs storage.credentialVending.roleArn: it is the role STS assumes on each client's behalf" -}}
{{- end -}}
{{- if and (eq .Values.storage.credentialVending.provider "s3-secret-key") (not (include "gravitino.staticKeys" .)) -}}
{{- fail "credential vending with s3-secret-key hands out the static keys, so it needs storage.credentials.source=static" -}}
{{- end -}}
{{- end -}}
{{- if include "gravitino.sqlite" . -}}
{{- if gt (int .Values.replicaCount) 1 -}}
{{- fail "catalog.backend=sqlite supports exactly one replica: the catalog is a single file on a ReadWriteOnce volume. Use catalog.backend=postgresql to scale out." -}}
{{- end -}}
{{- if not .Values.persistence.enabled -}}
{{- fail "catalog.backend=sqlite with persistence.enabled=false keeps the catalog in an emptyDir and loses every table definition when the pod goes. Enable persistence or use postgresql." -}}
{{- end -}}
{{- end -}}
{{- if include "gravitino.postgresql" . -}}
{{- if not .Values.catalog.postgresql.host -}}
{{- fail "catalog.backend=postgresql needs catalog.postgresql.host" -}}
{{- end -}}
{{- if and (not .Values.catalog.postgresql.existingSecret) (not .Values.catalog.postgresql.password) -}}
{{- fail "catalog.backend=postgresql needs catalog.postgresql.existingSecret or catalog.postgresql.password" -}}
{{- end -}}
{{- if and .Values.catalog.postgresql.driver.download (not .Values.catalog.postgresql.driver.sha256) -}}
{{- fail "catalog.postgresql.driver.sha256 is empty: the chart will not put an unverified jar on the classpath" -}}
{{- end -}}
{{- end -}}
{{- if and .Values.tls.enabled (or (not .Values.tls.existingSecret) (not .Values.tls.passwordSecret)) -}}
{{- fail "tls.enabled needs tls.existingSecret (with the keystore) and tls.passwordSecret (with its password)" -}}
{{- end -}}
{{- if and .Values.podAntiAffinityPreset (not (has .Values.podAntiAffinityPreset (list "soft" "hard"))) -}}
{{- fail "podAntiAffinityPreset must be soft, hard, or empty" -}}
{{- end -}}
{{- end }}

{{/* Default anti-affinity, used only when .Values.affinity is empty. */}}
{{- define "gravitino.affinity" -}}
{{- if .Values.affinity }}
{{- toYaml .Values.affinity }}
{{- else if le (int .Values.replicaCount) 1 }}
{{- else if eq .Values.podAntiAffinityPreset "hard" }}
podAntiAffinity:
  requiredDuringSchedulingIgnoredDuringExecution:
    - topologyKey: kubernetes.io/hostname
      labelSelector:
        matchLabels:
          {{- include "gravitino.selectorLabels" . | nindent 10 }}
{{- else if eq .Values.podAntiAffinityPreset "soft" }}
podAntiAffinity:
  preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        topologyKey: kubernetes.io/hostname
        labelSelector:
          matchLabels:
            {{- include "gravitino.selectorLabels" . | nindent 12 }}
{{- end }}
{{- end }}

{{/* Is there anything for the init container to append from a Secret? */}}
{{- define "gravitino.hasSecrets" -}}
{{- if or (include "gravitino.staticKeys" .) (include "gravitino.postgresql" .) .Values.extraSecretConfig .Values.tls.enabled }}true{{ end }}
{{- end }}
