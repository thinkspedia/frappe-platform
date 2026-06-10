#!/bin/sh
# =============================================================================
# bootstrap.sh — Idempotent Frappe site initialisation
#
# Runs ONCE as the `bootstrap` service in docker-compose.dev.yml.
# Safe to re-run: checks for existing site before creating.
#
# Required environment variables (all provided by docker-compose.dev.yml):
#   FRAPPE_SITE_NAME, DB_HOST, DB_PORT, DB_ROOT_PASSWORD, DB_PASSWORD,
#   REDIS_CACHE, REDIS_QUEUE, REDIS_SOCKETIO, SITE_ADMIN_PASSWORD, HOST_NAME
# =============================================================================
set -e

BENCH_DIR="/home/frappe/frappe-bench"
APPS_JSON="/home/frappe/apps.json"

echo "[bootstrap] Waiting for MariaDB to be ready..."
wait-for-it "${DB_HOST}:${DB_PORT}" --timeout=120 --strict -- echo "[bootstrap] MariaDB is up"

# ---------------------------------------------------------------------------
# Step 1: Write common_site_config.json
# This is the bench-wide config (all sites share it).
# ---------------------------------------------------------------------------
echo "[bootstrap] Configuring bench..."
cd "${BENCH_DIR}"

bench set-config -g db_host "${DB_HOST}"
bench set-config -gp db_port "${DB_PORT}"
bench set-config -g redis_cache "redis://${REDIS_CACHE}"
bench set-config -g redis_queue "redis://${REDIS_QUEUE}"
bench set-config -g redis_socketio "redis://${REDIS_SOCKETIO}"
bench set-config -gp socketio_port 9000
bench set-config -g developer_mode 1

# ---------------------------------------------------------------------------
# Step 2: Create site if it does not exist
# ---------------------------------------------------------------------------
SITE_DIR="${BENCH_DIR}/sites/${FRAPPE_SITE_NAME}"

if [ -d "${SITE_DIR}" ] && [ -f "${SITE_DIR}/site_config.json" ]; then
  echo "[bootstrap] Site '${FRAPPE_SITE_NAME}' already exists — skipping creation."
else
  echo "[bootstrap] Creating site '${FRAPPE_SITE_NAME}'..."
  bench new-site "${FRAPPE_SITE_NAME}" \
    --db-root-password "${DB_ROOT_PASSWORD}" \
    --admin-password "${SITE_ADMIN_PASSWORD}" \
    --no-mariadb-socket
  echo "[bootstrap] Site created."
fi

# ---------------------------------------------------------------------------
# Step 3: Write host_name into site_config.json from HOST_NAME env var
# ---------------------------------------------------------------------------
/usr/local/bin/configure-site.sh

# ---------------------------------------------------------------------------
# Step 4: Install apps from apps.json (idempotent — skips already-installed)
# ---------------------------------------------------------------------------
echo "[bootstrap] Installing apps from ${APPS_JSON}..."

python3 - <<'PYEOF'
import json, subprocess, os, sys

apps_file = os.environ.get("APPS_JSON", "/home/frappe/apps.json")
site      = os.environ["FRAPPE_SITE_NAME"]
bench_dir = "/home/frappe/frappe-bench"

if not os.path.exists(apps_file):
    print(f"[bootstrap] No apps.json found at {apps_file} — skipping app install.")
    sys.exit(0)

apps = json.load(open(apps_file))

# Get already-installed apps
result = subprocess.run(
    ["bench", "--site", site, "list-apps"],
    cwd=bench_dir,
    capture_output=True,
    text=True,
)
installed = result.stdout.lower()

for app in apps:
    url    = app["url"]
    branch = app.get("branch", "main")
    name   = url.rstrip("/").split("/")[-1].replace(".git", "")

    # bench get-app if app source not present
    app_path = f"{bench_dir}/apps/{name}"
    if not os.path.isdir(app_path):
        print(f"[bootstrap] Fetching app: {name} @ {branch}", flush=True)
        subprocess.run(
            ["bench", "get-app", "--branch", branch, url],
            cwd=bench_dir,
            check=True,
        )

    # bench install-app if not already installed on site
    if name not in installed:
        print(f"[bootstrap] Installing app on site: {name}", flush=True)
        subprocess.run(
            ["bench", "--site", site, "install-app", name],
            cwd=bench_dir,
            check=True,
        )
    else:
        print(f"[bootstrap] App already installed: {name}", flush=True)

print("[bootstrap] All apps installed.")
PYEOF

# ---------------------------------------------------------------------------
# Step 5: Run migrations (idempotent)
# ---------------------------------------------------------------------------
echo "[bootstrap] Running bench migrate..."
bench --site "${FRAPPE_SITE_NAME}" migrate

echo "[bootstrap] Done. Site '${FRAPPE_SITE_NAME}' is ready."
