#!/bin/sh
# =============================================================================
# configure-site.sh — Write site_config.json values from environment
#
# Ensures host_name in site_config.json matches the HOST_NAME env var.
# Called by bootstrap.sh after site creation, and can be called standalone
# when the hostname changes (e.g., promoting from staging to production).
#
# Required env vars: FRAPPE_SITE_NAME, HOST_NAME
# =============================================================================
set -e

BENCH_DIR="/home/frappe/frappe-bench"
SITE="${FRAPPE_SITE_NAME:?FRAPPE_SITE_NAME is required}"
HOST="${HOST_NAME:?HOST_NAME is required}"

echo "[configure-site] Setting host_name='${HOST}' for site '${SITE}'..."

bench --site "${SITE}" set-config host_name "https://${HOST}"

echo "[configure-site] site_config.json updated."
