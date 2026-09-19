{{- define "dashboard.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "dashboard.fullname" -}}
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

{{- define "dashboard.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Pods carrying this label may reach the web port when networkPolicy.allowExternal is false. */}}
{{- define "dashboard.clientLabel" -}}
{{- printf "%s-client" (include "dashboard.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* The label the Valkey subchart's NetworkPolicy admits (see valkey.networkPolicy in values.yaml). */}}
{{- define "dashboard.valkeyClientLabel" -}}dashboard-valkey-client{{- end }}

{{- define "dashboard.labels" -}}
helm.sh/chart: {{ include "dashboard.chart" . }}
{{ include "dashboard.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: superset
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{- define "dashboard.selectorLabels" -}}
app.kubernetes.io/name: {{ include "dashboard.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* Selector labels for one component: web, worker, beat or init. */}}
{{- define "dashboard.componentSelectorLabels" -}}
{{ include "dashboard.selectorLabels" .ctx }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{- define "dashboard.componentLabels" -}}
{{ include "dashboard.labels" .ctx }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{- define "dashboard.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "dashboard.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/* registry/repository:tag, or @digest when one is given. */}}
{{- define "dashboard.imageRef" -}}
{{- if .digest }}
{{- printf "%s/%s@%s" .registry .repository .digest }}
{{- else }}
{{- printf "%s/%s:%s" .registry .repository .tag }}
{{- end }}
{{- end }}

{{- define "dashboard.image" -}}
{{- include "dashboard.imageRef" .Values.image }}
{{- end }}

{{/* The worker's image: worker.image where set, field by field, else `image`. */}}
{{- define "dashboard.workerImage" -}}
{{- $w := .Values.worker.image }}
{{- if or $w.repository $w.digest $w.tag }}
{{- include "dashboard.imageRef" (dict
      "registry" (default .Values.image.registry $w.registry)
      "repository" (default .Values.image.repository $w.repository)
      "tag" (default .Values.image.tag $w.tag)
      "digest" $w.digest) }}
{{- else }}
{{- include "dashboard.image" . }}
{{- end }}
{{- end }}

{{/* Paths. */}}
{{- define "dashboard.confDir" -}}/etc/superset/conf{{- end }}
{{- define "dashboard.overridesDir" -}}/etc/superset/overrides{{- end }}
{{- define "dashboard.secretOverridesDir" -}}/etc/superset/secret-overrides{{- end }}
{{- define "dashboard.secretDir" -}}/etc/superset/secrets{{- end }}
{{- define "dashboard.metastoreTlsDir" -}}/etc/superset/tls/metastore{{- end }}
{{- define "dashboard.valkeyTlsDir" -}}/etc/superset/tls/valkey{{- end }}
{{- define "dashboard.indexDir" -}}/etc/superset/package-index{{- end }}
{{- define "dashboard.driversDir" -}}/opt/superset/drivers{{- end }}
{{- define "dashboard.extensionsDir" -}}/opt/superset/extensions{{- end }}
{{- define "dashboard.extensionsSrcDir" -}}/opt/superset/extensions-src{{- end }}
{{- define "dashboard.homeDir" -}}/app/superset_home{{- end }}

{{- define "dashboard.secretName" -}}
{{- default (include "dashboard.fullname" .) .Values.auth.existingSecret }}
{{- end }}

{{/*
Named after the RELEASE, not the fullname, because the Valkey subchart has to
compute the same name from `{{ .Release.Name }}` alone (valkey.auth.usersExistingSecret).
*/}}
{{- define "dashboard.valkeySecretName" -}}
{{- printf "%s-dashboard-valkey" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* True when the chart creates the shared Valkey password Secret. */}}
{{- define "dashboard.createValkeySecret" -}}
{{- if and (not .Values.valkeyConnection.existingSecret) (or .Values.valkeyConnection.password (and .Values.valkey.enabled .Values.valkey.auth.enabled)) }}true{{ end }}
{{- end }}

{{/* Where the Valkey password comes from, as {name, key}; empty when there is none. */}}
{{- define "dashboard.valkeyPasswordRef" -}}
{{- if .Values.valkeyConnection.existingSecret }}
{{- dict "name" .Values.valkeyConnection.existingSecret "key" .Values.valkeyConnection.existingSecretPasswordKey | toJson }}
{{- else if include "dashboard.createValkeySecret" . }}
{{- dict "name" (include "dashboard.valkeySecretName" .) "key" "valkey-password" | toJson }}
{{- end }}
{{- end }}

{{/* The bundled subchart's Service, computed the way the subchart computes it. */}}
{{- define "dashboard.valkeyHost" -}}
{{- if .Values.valkeyConnection.host }}
{{- .Values.valkeyConnection.host }}
{{- else }}
{{- $v := .Values.valkey }}
{{- $svc := "" }}
{{- if $v.fullnameOverride }}
{{- $svc = $v.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default "valkey" $v.nameOverride }}
{{- if contains $name .Release.Name }}
{{- $svc = .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $svc = printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- printf "%s.%s.svc.%s" $svc .Release.Namespace .Values.clusterDomain }}
{{- end }}
{{- end }}

{{- define "dashboard.metastorePort" -}}
{{- if .Values.metastore.port }}{{ .Values.metastore.port }}{{ else if eq .Values.metastore.type "mysql" }}3306{{ else }}5432{{ end }}
{{- end }}

{{- define "dashboard.metastoreDriver" -}}
{{- if eq .Values.metastore.type "mysql" }}mysql+pymysql{{ else }}postgresql+psycopg2{{ end }}
{{- end }}

{{- define "dashboard.serviceHost" -}}
{{- printf "%s.%s.svc.%s" (include "dashboard.fullname" .) .Release.Namespace .Values.clusterDomain }}
{{- end }}

{{- define "dashboard.beatEnabled" -}}
{{- if or .Values.alerts.enabled .Values.beat.enabled }}true{{ end }}
{{- end }}

{{/*
A secret value: explicit value > live Secret > freshly generated. Reusing the
live Secret keeps it stable across upgrades; `helm template` cannot look it up.
*/}}
{{- define "dashboard.secretValue" -}}
{{- if .value -}}
{{- .value -}}
{{- else -}}
{{- $existing := lookup "v1" "Secret" .ctx.Release.Namespace .secret -}}
{{- if and $existing $existing.data (index $existing.data .key) -}}
{{- index $existing.data .key | b64dec -}}
{{- else -}}
{{- randAlphaNum (int (default 48 .length)) -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
Feature flags: the user's, plus the four the chart manages. A user value that
contradicts a managed one is an error rather than a silent override — each of
those flags needs infrastructure the switch provides.
*/}}
{{- define "dashboard.featureFlags" -}}
{{- $managed := dict
    "ALERT_REPORTS" (.Values.alerts.enabled | default false)
    "EMBEDDED_SUPERSET" (.Values.embedding.enabled | default false)
    "ENABLE_EXTENSIONS" (.Values.extensions.enabled | default false)
    "PLAYWRIGHT_REPORTS_AND_THUMBNAILS" (and .Values.alerts.enabled .Values.alerts.screenshots.enabled | default false) }}
{{- $switch := dict
    "ALERT_REPORTS" "alerts.enabled"
    "EMBEDDED_SUPERSET" "embedding.enabled"
    "ENABLE_EXTENSIONS" "extensions.enabled"
    "PLAYWRIGHT_REPORTS_AND_THUMBNAILS" "alerts.screenshots.enabled" }}
{{- $flags := deepCopy (default dict .Values.featureFlags) }}
{{- range $k, $v := $managed }}
{{- if and (hasKey $flags $k) (ne (toString (get $flags $k)) (toString $v)) }}
{{- fail (printf "featureFlags.%s is managed by the chart: set %s instead" $k (get $switch $k)) }}
{{- end }}
{{- $_ := set $flags $k $v }}
{{- end }}
{{- toJson $flags }}
{{- end }}

{{/* Everything superset_config.py needs, as data. */}}
{{- define "dashboard.settings" -}}
{{- $m := .Values.metastore }}
{{- $query := deepCopy (default dict $m.query) }}
{{- if and (eq $m.type "postgresql") $m.sslMode }}
{{- $_ := set $query "sslmode" $m.sslMode }}
{{- end }}
{{- if and (eq $m.type "mysql") $m.tls.existingSecret }}
{{- if $m.tls.caKey }}{{ $_ := set $query "ssl_ca" (printf "%s/%s" (include "dashboard.metastoreTlsDir" .) $m.tls.caKey) }}{{ end }}
{{- if $m.tls.certKey }}{{ $_ := set $query "ssl_cert" (printf "%s/%s" (include "dashboard.metastoreTlsDir" .) $m.tls.certKey) }}{{ end }}
{{- if $m.tls.keyKey }}{{ $_ := set $query "ssl_key" (printf "%s/%s" (include "dashboard.metastoreTlsDir" .) $m.tls.keyKey) }}{{ end }}
{{- end }}
{{- $vc := .Values.valkeyConnection }}
{{- $vcCa := "" }}
{{- if and $vc.tls.enabled $vc.tls.existingSecret }}
{{- $vcCa = printf "%s/%s" (include "dashboard.valkeyTlsDir" .) $vc.tls.caKey }}
{{- end }}
{{- $webdriver := .Values.alerts.webdriverBaseUrl | default (printf "http://%s:%d/" (include "dashboard.serviceHost" .) (int .Values.service.port)) }}
{{- $friendly := .Values.alerts.webdriverBaseUrlUserFriendly }}
{{- if and (not $friendly) .Values.ingress.enabled .Values.ingress.hosts }}
{{- $friendly = printf "%s://%s/" (ternary "https" "http" (gt (len .Values.ingress.tls) 0)) (index .Values.ingress.hosts 0).host }}
{{- end }}
{{- $smtp := .Values.alerts.smtp }}
{{- $settings := dict
    "paths" (dict
      "secrets" (include "dashboard.secretDir" .)
      "drivers" (include "dashboard.driversDir" .)
      "overrides" (include "dashboard.overridesDir" .)
      "secretOverrides" (include "dashboard.secretOverridesDir" .)
      "home" (include "dashboard.homeDir" .))
    "metastore" (dict
      "driver" (include "dashboard.metastoreDriver" .)
      "host" $m.host
      "port" (int (include "dashboard.metastorePort" .))
      "database" $m.database
      "username" $m.username
      "query" $query
      "engineOptions" (default dict $m.engineOptions))
    "valkey" (dict
      "host" (include "dashboard.valkeyHost" .)
      "port" (int $vc.port)
      "username" $vc.username
      "tls" $vc.tls.enabled
      "certReqs" $vc.tls.certReqs
      "caFile" $vcCa
      "databases" $vc.databases
      "keyPrefix" $vc.keyPrefix)
    "featureFlags" (include "dashboard.featureFlags" . | fromJson)
    "security" (dict
      "proxyFix" .Values.security.proxyFix
      "sessionCookieSecure" .Values.security.sessionCookieSecure
      "sessionCookieSameSite" .Values.security.sessionCookieSameSite
      "talisman" .Values.security.talisman)
    "embedding" (dict
      "enabled" .Values.embedding.enabled
      "allowedDomains" .Values.embedding.allowedDomains
      "guestRoleName" .Values.embedding.guestRoleName
      "guestTokenExpirySeconds" (int .Values.embedding.guestTokenExpirySeconds)
      "guestTokenAudience" .Values.embedding.guestTokenAudience)
    "alerts" (dict
      "enabled" .Values.alerts.enabled
      "dryRun" .Values.alerts.dryRun
      "webdriverBaseUrl" $webdriver
      "webdriverBaseUrlUserFriendly" (default $webdriver $friendly)
      "smtp" (dict
        "host" $smtp.host
        "port" (int $smtp.port)
        "starttls" $smtp.starttls
        "ssl" $smtp.ssl
        "sslServerAuth" $smtp.sslServerAuth
        "user" $smtp.user
        "mailFrom" $smtp.mailFrom))
    "extensions" (dict
      "enabled" .Values.extensions.enabled
      "path" (include "dashboard.extensionsDir" .)
      "bundles" (default list .Values.extensions.bundles))
    "config" (default dict .Values.config) }}
{{- toPrettyJson $settings }}
{{- end }}

{{/* requirements.txt for the drivers init container. */}}
{{- define "dashboard.requirements" -}}
{{- range (concat (default list .Values.drivers.packages) (default list .Values.drivers.extraPackages) (ternary (default list .Values.extensions.pythonPackages) list .Values.extensions.enabled)) }}
{{ . }}
{{- end }}
{{- end }}

{{- define "dashboard.installDrivers" -}}
{{- if and .Values.drivers.install (trim (include "dashboard.requirements" .)) }}true{{ end }}
{{- end }}

{{- define "dashboard.validate" -}}
{{- $m := .Values.metastore }}
{{- if not (has $m.type (list "postgresql" "mysql")) }}
{{- fail "metastore.type must be postgresql or mysql" }}
{{- end }}
{{- if not (or $m.host $m.uriSecret.name) }}
{{- fail "set metastore.host (or metastore.uriSecret.name): Superset needs an existing PostgreSQL or MySQL database for its metastore" }}
{{- end }}
{{- if and $m.existingSecret $m.password }}
{{- fail "set metastore.password or metastore.existingSecret, not both" }}
{{- end }}
{{- if and (eq $m.type "mysql") .Values.drivers.install }}
{{- $found := false }}
{{- range (concat (default list .Values.drivers.packages) (default list .Values.drivers.extraPackages)) }}
{{- if regexMatch "(?i)^pymysql([<>=!~ ;\\[]|$)" . }}{{ $found = true }}{{ end }}
{{- end }}
{{- if not $found }}
{{- fail "metastore.type is mysql: add a PyMySQL pin (e.g. \"pymysql==1.2.3\") to drivers.extraPackages" }}
{{- end }}
{{- end }}
{{- if not (or .Values.valkey.enabled .Values.valkeyConnection.host) }}
{{- fail "set valkeyConnection.host, or enable the bundled valkey subchart" }}
{{- end }}
{{- if and .Values.valkeyConnection.existingSecret .Values.valkeyConnection.password }}
{{- fail "set valkeyConnection.password or valkeyConnection.existingSecret, not both" }}
{{- end }}
{{- if and .Values.valkey.enabled .Values.valkey.auth.enabled .Values.valkeyConnection.existingSecret }}
{{- if ne (tpl .Values.valkey.auth.usersExistingSecret .) .Values.valkeyConnection.existingSecret }}
{{- fail "valkeyConnection.existingSecret and valkey.auth.usersExistingSecret must name the same Secret, or Superset and Valkey disagree on the password" }}
{{- end }}
{{- end }}
{{- if not (has .Values.valkeyConnection.tls.certReqs (list "required" "optional" "none")) }}
{{- fail "valkeyConnection.tls.certReqs must be required, optional or none" }}
{{- end }}
{{- if and .Values.alerts.enabled (not .Values.worker.enabled) }}
{{- fail "alerts.enabled needs worker.enabled: the Celery worker is what executes alerts and reports" }}
{{- end }}
{{- if and .Values.alerts.screenshots.enabled (not .Values.alerts.enabled) }}
{{- fail "alerts.screenshots.enabled needs alerts.enabled" }}
{{- end }}
{{- if and .Values.alerts.smtp.existingSecret .Values.alerts.smtp.password }}
{{- fail "set alerts.smtp.password or alerts.smtp.existingSecret, not both" }}
{{- end }}
{{- if and .Values.alerts.slack.existingSecret .Values.alerts.slack.token }}
{{- fail "set alerts.slack.token or alerts.slack.existingSecret, not both" }}
{{- end }}
{{- if .Values.embedding.enabled }}
{{- if not .Values.embedding.allowedDomains }}
{{- fail "embedding.enabled needs embedding.allowedDomains: the origins allowed to frame Superset" }}
{{- end }}
{{- range .Values.embedding.allowedDomains }}
{{- if not (regexMatch "^https?://[^/*\\s]+$" .) }}
{{- fail (printf "embedding.allowedDomains: %q must be a scheme and host (https://portal.example.org), with no path and no wildcard" .) }}
{{- end }}
{{- end }}
{{- if not .Values.security.sessionCookieSecure }}
{{- fail "embedding.enabled needs security.sessionCookieSecure: browsers reject SameSite=None cookies without Secure" }}
{{- end }}
{{- end }}
{{- if not (has .Values.security.sessionCookieSameSite (list "Lax" "Strict" "None")) }}
{{- fail "security.sessionCookieSameSite must be Lax, Strict or None" }}
{{- end }}
{{- range $k, $v := .Values.config }}
{{- if not (regexMatch "^[A-Z][A-Z0-9_]*$" $k) }}
{{- fail (printf "config.%s: keys must be UPPERCASE Superset settings" $k) }}
{{- end }}
{{- end }}
{{- range $k, $v := .Values.configOverrides }}
{{- if not (regexMatch "^[A-Za-z0-9][A-Za-z0-9_-]*$" $k) }}
{{- fail (printf "configOverrides.%s: names may contain letters, digits, - and _ only" $k) }}
{{- end }}
{{- end }}
{{- if and .Values.configOverridesSecret .Values.configOverridesExistingSecret }}
{{- fail "set configOverridesSecret or configOverridesExistingSecret, not both" }}
{{- end }}
{{- range $k, $v := .Values.configOverridesSecret }}
{{- if not (regexMatch "^[A-Za-z0-9][A-Za-z0-9_-]*$" $k) }}
{{- fail (printf "configOverridesSecret.%s: names may contain letters, digits, - and _ only" $k) }}
{{- end }}
{{- end }}
{{- if .Values.extensions.enabled }}
{{- range .Values.extensions.bundles }}
{{- if not (regexMatch "^[a-z0-9][a-z0-9._-]*$" (toString .name)) }}
{{- fail (printf "extensions.bundles: name %q must be lowercase letters, digits, ., - and _" (toString .name)) }}
{{- end }}
{{- if not (hasPrefix "https://" (toString .url)) }}
{{- fail (printf "extensions.bundles.%s: url must be https://" .name) }}
{{- end }}
{{- if not (regexMatch "^[0-9a-fA-F]{64}$" (toString .sha256)) }}
{{- fail (printf "extensions.bundles.%s: sha256 is required (64 hex characters) — extensions run code in every Superset process" .name) }}
{{- end }}
{{- end }}
{{- end }}
{{- if and .Values.web.autoscaling.enabled (lt (int .Values.web.autoscaling.minReplicas) 1) }}
{{- fail "web.autoscaling.minReplicas must be at least 1" }}
{{- end }}
{{- with .Values.config.SUPERSET_WEBSERVER_TIMEOUT }}
{{- if le (int $.Values.web.gunicorn.timeout) (int .) }}
{{- fail (printf "web.gunicorn.timeout (%d) must exceed config.SUPERSET_WEBSERVER_TIMEOUT (%d), or gunicorn kills requests before Superset can time them out cleanly" (int $.Values.web.gunicorn.timeout) (int .)) }}
{{- end }}
{{- end }}
{{- end }}

{{/*
The files under /etc/superset/secrets, each projected from wherever it lives.
Every Superset container mounts this; `admin` adds the admin password (the
init Job only).
*/}}
{{- define "dashboard.secretSources" -}}
{{- $ctx := .ctx }}
{{- $v := $ctx.Values }}
{{- $main := include "dashboard.secretName" $ctx }}
{{- $chart := include "dashboard.fullname" $ctx }}
- secret:
    name: {{ $main }}
    items:
      - key: secret-key
        path: secret-key
      - key: guest-token-jwt-secret
        path: guest-token-jwt-secret
      - key: async-queries-jwt-secret
        path: async-queries-jwt-secret
      {{- if .admin }}
      - key: admin-password
        path: admin-password
      {{- end }}
{{- if or $v.auth.existingSecret $v.auth.previousSecretKey }}
- secret:
    name: {{ $main }}
    optional: true
    items:
      - key: previous-secret-key
        path: previous-secret-key
{{- end }}
{{- if $v.metastore.uriSecret.name }}
- secret:
    name: {{ $v.metastore.uriSecret.name }}
    items:
      - key: {{ $v.metastore.uriSecret.key }}
        path: metastore-uri
{{- else if $v.metastore.existingSecret }}
- secret:
    name: {{ $v.metastore.existingSecret }}
    items:
      - key: {{ $v.metastore.existingSecretPasswordKey }}
        path: metastore-password
{{- else if $v.metastore.password }}
- secret:
    name: {{ $chart }}-credentials
    items:
      - key: metastore-password
        path: metastore-password
{{- end }}
{{- with (include "dashboard.valkeyPasswordRef" $ctx) }}
{{- $ref := fromJson . }}
- secret:
    name: {{ $ref.name }}
    items:
      - key: {{ $ref.key }}
        path: valkey-password
{{- end }}
{{- if $v.alerts.enabled }}
{{- if $v.alerts.smtp.existingSecret }}
- secret:
    name: {{ $v.alerts.smtp.existingSecret }}
    items:
      - key: {{ $v.alerts.smtp.existingSecretPasswordKey }}
        path: smtp-password
{{- else if $v.alerts.smtp.password }}
- secret:
    name: {{ $chart }}-credentials
    items:
      - key: smtp-password
        path: smtp-password
{{- end }}
{{- if $v.alerts.slack.existingSecret }}
- secret:
    name: {{ $v.alerts.slack.existingSecret }}
    items:
      - key: {{ $v.alerts.slack.existingSecretKey }}
        path: slack-api-token
{{- else if $v.alerts.slack.token }}
- secret:
    name: {{ $chart }}-credentials
    items:
      - key: slack-api-token
        path: slack-api-token
{{- end }}
{{- end }}
{{- end }}

{{/* True when the chart renders its -credentials Secret (inline integration passwords). */}}
{{- define "dashboard.hasCredentials" -}}
{{- $v := .Values }}
{{- if or (and $v.metastore.password (not $v.metastore.uriSecret.name)) (and $v.alerts.enabled $v.alerts.smtp.password) (and $v.alerts.enabled $v.alerts.slack.token) }}true{{ end }}
{{- end }}

{{- define "dashboard.hasSecretOverrides" -}}
{{- if or .Values.configOverridesSecret .Values.configOverridesExistingSecret }}true{{ end }}
{{- end }}

{{/* Environment shared by every Superset container (not the gunicorn tuning). */}}
{{- define "dashboard.env" -}}
- name: SUPERSET_CONFIG_PATH
  value: {{ include "dashboard.confDir" . }}/superset_config.py
- name: SUPERSET_CHART_CONF_DIR
  value: {{ include "dashboard.confDir" . }}
# The root filesystem is read-only; do not even try to write .pyc files.
- name: PYTHONDONTWRITEBYTECODE
  value: "1"
- name: PYTHONUNBUFFERED
  value: "1"
- name: TMPDIR
  value: /tmp
{{- $t := .Values.metastore.tls }}
{{- if and (eq .Values.metastore.type "postgresql") $t.existingSecret }}
# libpq reads these even when the DSN comes from metastore.uriSecret and does
# not name the files itself.
{{- if $t.caKey }}
- name: PGSSLROOTCERT
  value: {{ include "dashboard.metastoreTlsDir" . }}/{{ $t.caKey }}
{{- end }}
{{- if $t.certKey }}
- name: PGSSLCERT
  value: {{ include "dashboard.metastoreTlsDir" . }}/{{ $t.certKey }}
{{- end }}
{{- if $t.keyKey }}
- name: PGSSLKEY
  value: {{ include "dashboard.metastoreTlsDir" . }}/{{ $t.keyKey }}
{{- end }}
{{- end }}
{{- with .Values.extraEnv }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/* Mounts for a Superset process (not the drivers/extensions installers). */}}
{{- define "dashboard.volumeMounts" -}}
- name: conf
  mountPath: {{ include "dashboard.confDir" . }}
  readOnly: true
- name: secrets
  mountPath: {{ include "dashboard.secretDir" . }}
  readOnly: true
{{- if .Values.configOverrides }}
- name: overrides
  mountPath: {{ include "dashboard.overridesDir" . }}
  readOnly: true
{{- end }}
{{- if include "dashboard.hasSecretOverrides" . }}
- name: secret-overrides
  mountPath: {{ include "dashboard.secretOverridesDir" . }}
  readOnly: true
{{- end }}
{{- if .Values.metastore.tls.existingSecret }}
- name: metastore-tls
  mountPath: {{ include "dashboard.metastoreTlsDir" . }}
  readOnly: true
{{- end }}
{{- if and .Values.valkeyConnection.tls.enabled .Values.valkeyConnection.tls.existingSecret }}
- name: valkey-tls
  mountPath: {{ include "dashboard.valkeyTlsDir" . }}
  readOnly: true
{{- end }}
{{- if include "dashboard.installDrivers" . }}
- name: drivers
  mountPath: {{ include "dashboard.driversDir" . }}
  readOnly: true
{{- end }}
{{- if .Values.extensions.enabled }}
- name: extensions
  mountPath: {{ include "dashboard.extensionsDir" . }}
  readOnly: true
{{- end }}
- name: home
  mountPath: {{ include "dashboard.homeDir" . }}
- name: tmp
  mountPath: /tmp
{{- end }}

{{/* Pod volumes. `admin` projects the admin password as well (init Job only). */}}
{{- define "dashboard.volumes" -}}
{{- $ctx := .ctx }}
{{- $v := $ctx.Values }}
- name: conf
  configMap:
    name: {{ include "dashboard.fullname" $ctx }}
    defaultMode: 0444
- name: secrets
  projected:
    # root:fsGroup, readable by the superset user and nothing else.
    defaultMode: 0440
    sources:
      {{- include "dashboard.secretSources" . | nindent 6 }}
{{- if $v.configOverrides }}
- name: overrides
  configMap:
    name: {{ include "dashboard.fullname" $ctx }}-overrides
    defaultMode: 0444
{{- end }}
{{- if include "dashboard.hasSecretOverrides" $ctx }}
- name: secret-overrides
  secret:
    secretName: {{ default (printf "%s-overrides" (include "dashboard.fullname" $ctx)) $v.configOverridesExistingSecret }}
    defaultMode: 0440
{{- end }}
{{- if $v.metastore.tls.existingSecret }}
- name: metastore-tls
  secret:
    secretName: {{ $v.metastore.tls.existingSecret }}
    # 0440 root:fsGroup is what libpq accepts for a client key it does not own.
    defaultMode: 0440
{{- end }}
{{- if and $v.valkeyConnection.tls.enabled $v.valkeyConnection.tls.existingSecret }}
- name: valkey-tls
  secret:
    secretName: {{ $v.valkeyConnection.tls.existingSecret }}
    defaultMode: 0440
{{- end }}
{{- if include "dashboard.installDrivers" $ctx }}
- name: drivers
  emptyDir:
    sizeLimit: 1Gi
{{- if $v.drivers.indexUrlSecret.name }}
- name: package-index
  secret:
    secretName: {{ $v.drivers.indexUrlSecret.name }}
    defaultMode: 0440
    items:
      - key: {{ $v.drivers.indexUrlSecret.key }}
        path: index-url
{{- end }}
{{- end }}
{{- if $v.extensions.enabled }}
- name: extensions
  emptyDir:
    sizeLimit: 512Mi
{{- with $v.extensions.volume }}
- name: extensions-src
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}
- name: home
  emptyDir:
    sizeLimit: 1Gi
- name: tmp
  emptyDir:
    sizeLimit: 1Gi
{{- end }}

{{/*
Init containers, in order: install the drivers, fetch the extensions, wait for
the metastore and Valkey (and, with `migrations`, for the schema to be at this
image's head).
*/}}
{{- define "dashboard.initContainers" -}}
{{- $ctx := .ctx }}
{{- $v := $ctx.Values }}
{{- if include "dashboard.installDrivers" $ctx }}
- name: install-drivers
  image: {{ .image }}
  imagePullPolicy: {{ $v.image.pullPolicy }}
  securityContext:
    {{- toYaml $v.securityContext | nindent 4 }}
  command: ["/bin/sh", "{{ include "dashboard.confDir" $ctx }}/install_drivers.sh"]
  env:
    - name: TMPDIR
      value: /tmp
    {{- with $v.drivers.indexUrl }}
    - name: UV_INDEX_URL
      value: {{ . | quote }}
    {{- end }}
  resources:
    {{- toYaml $v.drivers.resources | nindent 4 }}
  volumeMounts:
    - name: conf
      mountPath: {{ include "dashboard.confDir" $ctx }}
      readOnly: true
    - name: drivers
      mountPath: {{ include "dashboard.driversDir" $ctx }}
    {{- if $v.drivers.indexUrlSecret.name }}
    - name: package-index
      mountPath: {{ include "dashboard.indexDir" $ctx }}
      readOnly: true
    {{- end }}
    - name: tmp
      mountPath: /tmp
{{- end }}
{{- if $v.extensions.enabled }}
- name: fetch-extensions
  image: {{ .image }}
  imagePullPolicy: {{ $v.image.pullPolicy }}
  securityContext:
    {{- toYaml $v.securityContext | nindent 4 }}
  command:
    - python
    - {{ include "dashboard.confDir" $ctx }}/fetch_extensions.py
    - {{ include "dashboard.extensionsDir" $ctx }}
    - {{ include "dashboard.extensionsSrcDir" $ctx }}
  env:
    - name: SUPERSET_CHART_CONF_DIR
      value: {{ include "dashboard.confDir" $ctx }}
    - name: PYTHONDONTWRITEBYTECODE
      value: "1"
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      memory: 256Mi
  volumeMounts:
    - name: conf
      mountPath: {{ include "dashboard.confDir" $ctx }}
      readOnly: true
    - name: extensions
      mountPath: {{ include "dashboard.extensionsDir" $ctx }}
    {{- if $v.extensions.volume }}
    - name: extensions-src
      mountPath: {{ include "dashboard.extensionsSrcDir" $ctx }}
      readOnly: true
    {{- end }}
    - name: tmp
      mountPath: /tmp
{{- end }}
{{- if $v.waitForDependencies.enabled }}
- name: wait-for-dependencies
  image: {{ .image }}
  imagePullPolicy: {{ $v.image.pullPolicy }}
  securityContext:
    {{- toYaml $v.securityContext | nindent 4 }}
  command:
    - python
    - {{ include "dashboard.confDir" $ctx }}/wait_for_dependencies.py
    {{- if and .migrations $v.init.enabled }}
    - --migrations
    {{- end }}
  env:
    {{- include "dashboard.env" $ctx | nindent 4 }}
    - name: WAIT_TIMEOUT_SECONDS
      value: {{ $v.waitForDependencies.timeoutSeconds | quote }}
  {{- with $v.extraEnvFrom }}
  envFrom:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  resources:
    {{- toYaml $v.waitForDependencies.resources | nindent 4 }}
  volumeMounts:
    {{- include "dashboard.volumeMounts" $ctx | nindent 4 }}
{{- end }}
{{- end }}

{{/* Pod-level fields shared by every workload. */}}
{{- define "dashboard.podSpecCommon" -}}
{{- with .Values.imagePullSecrets }}
imagePullSecrets:
  {{- toYaml . | nindent 2 }}
{{- end }}
serviceAccountName: {{ include "dashboard.serviceAccountName" . }}
# Superset never talks to the Kubernetes API.
automountServiceAccountToken: false
enableServiceLinks: false
securityContext:
  {{- toYaml .Values.podSecurityContext | nindent 2 }}
{{- with .Values.priorityClassName }}
priorityClassName: {{ . }}
{{- end }}
{{- with .Values.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.affinity }}
affinity:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.tolerations }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{/* Labels every Superset pod carries, beyond its selector labels. */}}
{{- define "dashboard.podLabels" -}}
{{ include "dashboard.valkeyClientLabel" . }}: "true"
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/* Config and Secret checksums: superset_config.py is read once per process. */}}
{{- define "dashboard.checksums" -}}
checksum/config: {{ include (print .Template.BasePath "/configmap.yaml") . | sha256sum }}
checksum/secret: {{ include (print .Template.BasePath "/secret.yaml") . | sha256sum }}
{{- end }}

{{/* Egress rules for networkPolicy.restrictEgress. */}}
{{- define "dashboard.egressRules" -}}
# DNS.
- ports:
    - port: 53
      protocol: UDP
    - port: 53
      protocol: TCP
# The metastore and Valkey, wherever they are. Port-only: either may live
# outside the cluster.
- ports:
    - port: {{ include "dashboard.metastorePort" . }}
      protocol: TCP
    - port: {{ .Values.valkeyConnection.port }}
      protocol: TCP
# The web tier, which the worker renders screenshots through.
- to:
    - podSelector:
        matchLabels:
          {{- include "dashboard.componentSelectorLabels" (dict "ctx" . "component" "web") | nindent 10 }}
  ports:
    - port: {{ .Values.service.port }}
      protocol: TCP
{{- with .Values.networkPolicy.extraEgress }}
{{ toYaml . }}
{{- end }}
{{- end }}
