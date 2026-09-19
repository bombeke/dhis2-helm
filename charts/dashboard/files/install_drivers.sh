#!/bin/sh
# Installs requirements.txt into the drivers volume, as the unprivileged image
# user. Managed by the dashboard Helm chart.
#
#   --constraint  every package already in the image's venv is pinned to the
#                 version it has, so a driver can never pull in a different
#                 SQLAlchemy, urllib3 or anything else Superset depends on.
#   --no-build    wheels only. No sdist is built, so no package's setup.py or
#                 build backend runs in this pod — and the image has no
#                 compiler to build one with anyway.
#   --target      a plain directory that superset_config.py APPENDS to
#                 sys.path, after the venv's site-packages.
set -eu

conf_dir="${SUPERSET_CHART_CONF_DIR:-/etc/superset/conf}"
target="/opt/superset/drivers"
index_file="/etc/superset/package-index/index-url"

export UV_CACHE_DIR=/tmp/uv-cache
export UV_NO_PROGRESS=1
# The cache (/tmp) and the target are different volumes: no hardlinks.
export UV_LINK_MODE=copy
export UV_PYTHON_DOWNLOADS=never

if [ -f "$index_file" ]; then
  # From a Secret, so the credentials in it stay out of the pod spec.
  UV_INDEX_URL="$(cat "$index_file")"
  export UV_INDEX_URL
fi

uv pip freeze --python /app/.venv/bin/python --exclude-editable \
  | grep -E '^[A-Za-z0-9._-]+==' > /tmp/constraints.txt

echo "Installing into ${target}:"
sed 's/^/  /' "${conf_dir}/requirements.txt"

uv pip install \
  --python /app/.venv/bin/python \
  --target "$target" \
  --constraint /tmp/constraints.txt \
  --no-build \
  --requirement "${conf_dir}/requirements.txt"

rm -rf "$UV_CACHE_DIR" /tmp/constraints.txt
echo "Drivers installed."
