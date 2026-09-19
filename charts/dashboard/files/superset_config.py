# Managed by the dashboard Helm chart. Edits here are overwritten on every
# upgrade: change values.yaml instead.
#
# This file is logic only. Everything configurable arrives as data in
# settings.json (same ConfigMap) and every credential as a file under the
# secrets directory, so no value from values.yaml is ever pasted into Python
# source, and no secret is ever read from the environment.
#
# Loaded through SUPERSET_CONFIG_PATH, which copies only UPPERCASE names into
# Superset's config — the _private helpers below stay private.

import json
import logging
import os
import site
import ssl
from datetime import timedelta
from pathlib import Path
from urllib.parse import quote, urlencode

from celery.schedules import crontab
from flask_caching.backends.rediscache import RedisCache
from sqlalchemy.engine import URL

_log = logging.getLogger("superset_config")

_CONF_DIR = Path(os.environ.get("SUPERSET_CHART_CONF_DIR", "/etc/superset/conf"))
_S = json.loads((_CONF_DIR / "settings.json").read_text())
_PATHS = _S["paths"]


def _secret(name):
    """The content of a mounted Secret file, or None. Never logged."""
    try:
        value = (Path(_PATHS["secrets"]) / name).read_text()
    except FileNotFoundError:
        return None
    return value.rstrip("\r\n") or None


def _required_secret(name):
    value = _secret(name)
    if not value:
        raise RuntimeError(
            f"{_PATHS['secrets']}/{name} is missing or empty; "
            "check the chart's Secret (or auth.existingSecret)"
        )
    return value


# --- Drivers -----------------------------------------------------------------
# Installed by the install-drivers init container. APPENDED to sys.path, never
# prepended: nothing installed there can shadow a package from the image's own
# environment. site.addsitedir also processes .pth files, which some packages
# rely on.
if Path(_PATHS["drivers"]).is_dir():
    site.addsitedir(_PATHS["drivers"])

# --- Keys --------------------------------------------------------------------
SECRET_KEY = _required_secret("secret-key")
if _secret("previous-secret-key"):
    # Only for `superset re-encrypt-secrets` during a SECRET_KEY rotation.
    PREVIOUS_SECRET_KEY = _secret("previous-secret-key")

# Always set, whether or not embedding / async queries are enabled: upstream's
# defaults for both are well-known strings, and a feature flag flipped later
# through configOverrides must not quietly fall back to them.
GUEST_TOKEN_JWT_SECRET = _required_secret("guest-token-jwt-secret")
GLOBAL_ASYNC_QUERIES_JWT_SECRET = _required_secret("async-queries-jwt-secret")

# --- Metastore ---------------------------------------------------------------
_m = _S["metastore"]
SQLALCHEMY_DATABASE_URI = _secret("metastore-uri") or URL.create(
    drivername=_m["driver"],
    username=_m["username"] or None,
    password=_secret("metastore-password"),
    host=_m["host"],
    port=_m["port"],
    database=_m["database"],
    query={k: str(v) for k, v in _m["query"].items()},
).render_as_string(hide_password=False)
SQLALCHEMY_ENGINE_OPTIONS = _m["engineOptions"]

# --- Valkey ------------------------------------------------------------------
_v = _S["valkey"]
_v_password = _secret("valkey-password")
_v_db = _v["databases"]
_v_prefix = _v["keyPrefix"]
_v_ssl_kwargs = {}
if _v["tls"]:
    _v_ssl_kwargs = {"ssl": True, "ssl_cert_reqs": _v["certReqs"]}
    if _v["caFile"]:
        _v_ssl_kwargs["ssl_ca_certs"] = _v["caFile"]


def _redis_url(db, tls_query=True):
    scheme = "rediss" if _v["tls"] else "redis"
    auth = ""
    if _v_password:
        auth = f"{quote(_v['username'] or '', safe='')}:{quote(_v_password, safe='')}@"
    url = f"{scheme}://{auth}{_v['host']}:{_v['port']}/{db}"
    if _v["tls"] and tls_query:
        query = {"ssl_cert_reqs": _v["certReqs"]}
        if _v["caFile"]:
            query["ssl_ca_certs"] = _v["caFile"]
        url += "?" + urlencode(query)
    return url


def _cache(name, timeout):
    return {
        "CACHE_TYPE": "RedisCache",
        "CACHE_DEFAULT_TIMEOUT": int(timeout.total_seconds()),
        "CACHE_KEY_PREFIX": f"{_v_prefix}{name}_",
        "CACHE_REDIS_URL": _redis_url(_v_db["cache"]),
    }


CACHE_CONFIG = _cache("meta", timedelta(days=1))
DATA_CACHE_CONFIG = _cache("data", timedelta(days=1))
THUMBNAIL_CACHE_CONFIG = _cache("thumbnail", timedelta(days=7))
# FILTER_STATE_CACHE_CONFIG and EXPLORE_FORM_DATA_CACHE_CONFIG deliberately
# keep upstream's SupersetMetastoreCache: they hold state users expect to
# survive, and Valkey here is not durable.

RESULTS_BACKEND = RedisCache(
    host=_v["host"],
    port=_v["port"],
    username=_v["username"] or None,
    password=_v_password,
    db=_v_db["resultsBackend"],
    key_prefix=f"{_v_prefix}results_",
    **_v_ssl_kwargs,
)

# Flask-Limiter (login and API rate limits) — shared across replicas, rather
# than per-process memory that each replica counts separately.
RATELIMIT_STORAGE_URI = _redis_url(_v_db["rateLimit"])

GLOBAL_ASYNC_QUERIES_CACHE_BACKEND = {
    "CACHE_TYPE": "RedisCache",
    "CACHE_REDIS_HOST": _v["host"],
    "CACHE_REDIS_PORT": _v["port"],
    "CACHE_REDIS_USER": _v["username"] or "",
    "CACHE_REDIS_PASSWORD": _v_password or "",
    "CACHE_REDIS_DB": _v_db["asyncQueries"],
    "CACHE_DEFAULT_TIMEOUT": 300,
    "CACHE_REDIS_SSL": bool(_v["tls"]),
    "CACHE_REDIS_SSL_CERT_REQS": _v["certReqs"],
    "CACHE_REDIS_SSL_CA_CERTS": _v["caFile"] or None,
}

_CERT_REQS = {
    "required": ssl.CERT_REQUIRED,
    "optional": ssl.CERT_OPTIONAL,
    "none": ssl.CERT_NONE,
}


class CeleryConfig:  # pylint: disable=too-few-public-methods
    broker_url = _redis_url(_v_db["celeryBroker"], tls_query=False)
    result_backend = _redis_url(_v_db["celeryResults"], tls_query=False)
    broker_connection_retry_on_startup = True
    imports = (
        "superset.sql_lab",
        "superset.tasks.scheduler",
        "superset.tasks.thumbnails",
        "superset.tasks.cache",
        "superset.tasks.slack",
    )
    worker_prefetch_multiplier = 1
    task_acks_late = False
    task_annotations = {
        "sql_lab.get_sql_results": {"rate_limit": "100/s"},
    }
    beat_schedule = {
        "reports.scheduler": {
            "task": "reports.scheduler",
            "schedule": crontab(minute="*", hour="*"),
            "options": {"expires": int(timedelta(weeks=1).total_seconds())},
        },
        "reports.prune_log": {
            "task": "reports.prune_log",
            "schedule": crontab(minute=0, hour=0),
        },
    }
    if _v["tls"]:
        broker_use_ssl = {
            "ssl_cert_reqs": _CERT_REQS[_v["certReqs"]],
            **({"ssl_ca_certs": _v["caFile"]} if _v["caFile"] else {}),
        }
        redis_backend_use_ssl = broker_use_ssl


CELERY_CONFIG = CeleryConfig

# --- Feature flags -----------------------------------------------------------
FEATURE_FLAGS = _S["featureFlags"]

# --- HTTP security -----------------------------------------------------------
_sec = _S["security"]
_emb = _S["embedding"]

ENABLE_PROXY_FIX = _sec["proxyFix"]
PROXY_FIX_CONFIG = {"x_for": 1, "x_proto": 1, "x_host": 1, "x_port": 1, "x_prefix": 1}

SESSION_COOKIE_HTTPONLY = True
SESSION_COOKIE_SECURE = _sec["sessionCookieSecure"]
# A cross-site iframe only gets its cookies back with SameSite=None, and
# browsers only accept that with Secure (the chart enforces both).
SESSION_COOKIE_SAMESITE = "None" if _emb["enabled"] else _sec["sessionCookieSameSite"]
GLOBAL_ASYNC_QUERIES_JWT_COOKIE_SECURE = SESSION_COOKIE_SECURE
GLOBAL_ASYNC_QUERIES_JWT_COOKIE_SAMESITE = SESSION_COOKIE_SAMESITE

_frame_ancestors = ["'self'"]
if _emb["enabled"]:
    _frame_ancestors += _emb["allowedDomains"]

_t = _sec["talisman"]
TALISMAN_ENABLED = _t["enabled"]
TALISMAN_CONFIG = {
    "content_security_policy": {
        **_t["contentSecurityPolicy"],
        "frame-ancestors": _frame_ancestors,
    },
    "content_security_policy_nonce_in": ["script-src"],
    # TLS terminates at the ingress; ProxyFix tells Flask the request was
    # HTTPS, and a redirect here would loop behind a plain-HTTP hop.
    "force_https": False,
    # Talisman writes these three over the SESSION_COOKIE_* settings when it
    # initializes, so they must agree with the values above.
    "session_cookie_secure": SESSION_COOKIE_SECURE,
    "session_cookie_http_only": SESSION_COOKIE_HTTPONLY,
    "session_cookie_samesite": SESSION_COOKIE_SAMESITE,
    "strict_transport_security": True,
    "strict_transport_security_max_age": _t["hsts"]["maxAgeSeconds"],
    "strict_transport_security_include_subdomains": _t["hsts"]["includeSubdomains"],
    # X-Frame-Options cannot express a list of origins, and frame-ancestors
    # above supersedes it in every current browser. Keep it for the
    # non-embedded case, where SAMEORIGIN is exactly right.
    "frame_options": None if _emb["enabled"] else "SAMEORIGIN",
}

# --- Embedding ---------------------------------------------------------------
if _emb["enabled"]:
    GUEST_ROLE_NAME = _emb["guestRoleName"]
    GUEST_TOKEN_JWT_EXP_SECONDS = _emb["guestTokenExpirySeconds"]
    if _emb["guestTokenAudience"]:
        GUEST_TOKEN_JWT_AUDIENCE = _emb["guestTokenAudience"]
    ENABLE_CORS = True
    CORS_OPTIONS = {
        "supports_credentials": True,
        "allow_headers": ["*"],
        "resources": [r"/api/*"],
        "origins": _emb["allowedDomains"],
    }

# --- Alerts & reports --------------------------------------------------------
_a = _S["alerts"]
ALERT_REPORTS_NOTIFICATION_DRY_RUN = _a["dryRun"]
WEBDRIVER_BASEURL = _a["webdriverBaseUrl"]
WEBDRIVER_BASEURL_USER_FRIENDLY = _a["webdriverBaseUrlUserFriendly"]
_smtp = _a["smtp"]
if _smtp["host"]:
    SMTP_HOST = _smtp["host"]
    SMTP_PORT = _smtp["port"]
    SMTP_STARTTLS = _smtp["starttls"]
    SMTP_SSL = _smtp["ssl"]
    SMTP_SSL_SERVER_AUTH = _smtp["sslServerAuth"]
    SMTP_USER = _smtp["user"]
    SMTP_PASSWORD = _secret("smtp-password")
    SMTP_MAIL_FROM = _smtp["mailFrom"]
if _secret("slack-api-token"):
    SLACK_API_TOKEN = _secret("slack-api-token")

# --- Extensions --------------------------------------------------------------
if _S["extensions"]["enabled"]:
    EXTENSIONS_PATH = _S["extensions"]["path"]

# --- Filesystem --------------------------------------------------------------
# The image's default is inside the (read-only) package directory.
UPLOAD_FOLDER = f"{_PATHS['home']}/uploads/"

# --- values.yaml `config` ----------------------------------------------------
for _key, _value in _S["config"].items():
    globals()[_key] = _value

# --- configOverrides, then configOverridesSecret -----------------------------
# Executed in this module's namespace, in file-name order within each
# directory, so they can read and change anything above.
for _dir in (_PATHS["overrides"], _PATHS["secretOverrides"]):
    _path = Path(_dir)
    if not _path.is_dir():
        continue
    for _file in sorted(_path.glob("*.py")):
        exec(compile(_file.read_text(), str(_file), "exec"), globals())  # noqa: S102
