#!/bin/bash
# The init Job. Managed by the dashboard Helm chart. Everything here is
# idempotent: it runs on every install and upgrade.
set -euo pipefail

conf_dir="${SUPERSET_CHART_CONF_DIR:-/etc/superset/conf}"

echo "==> superset db upgrade"
superset db upgrade

echo "==> superset init (roles and permissions)"
superset init

if [ "${ADMIN_CREATE:-false}" = "true" ]; then
  echo "==> admin user"
  python "${conf_dir}/create_admin.py"
fi

echo "==> done"
