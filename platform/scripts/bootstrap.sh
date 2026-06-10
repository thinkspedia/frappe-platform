#!/bin/bash
# =============================================================================
# bootstrap.sh — Idempotent bench + site initialisation
#
# Runs inside frappe/bench container with /workspace bound to the repo root.
# Bench lives at /workspace/development/frappe-bench (editable on the host).
#
# First run:
#   1. bench init (creates bench with frappe @ FRAPPE_BRANCH)
#   2. bench get-app for every non-frappe app in platform/apps.json
#   3. bench set-config (redis, db, developer_mode)
#   4. bench new-site + install-app for each app
#   5. bench migrate
#
# Subsequent runs: detects existing site_config.json and exits 0 immediately.
#
# App versions are driven entirely by platform/apps.json — same file used by
# the production Dockerfile, so dev and prod always track the same branches.
# =============================================================================
set -euo pipefail

WORKSPACE="/workspace"
BENCH_PARENT="${WORKSPACE}/development"
BENCH_NAME="frappe-bench"
BENCH_DIR="${BENCH_PARENT}/${BENCH_NAME}"
APPS_JSON="${WORKSPACE}/platform/apps.json"
SITE="${FRAPPE_SITE_NAME:-dev.localhost}"
FRAPPE_BRANCH="${FRAPPE_BRANCH:-version-16}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

# ---------------------------------------------------------------------------
# Wait for MariaDB to be ready (frappe/bench has no wait-for-it)
# ---------------------------------------------------------------------------
echo "[bootstrap] Waiting for MariaDB at ${DB_HOST}:${DB_PORT}..."
for i in $(seq 1 60); do
    if bash -c "echo > /dev/tcp/${DB_HOST}/${DB_PORT}" 2>/dev/null; then
        echo "[bootstrap] MariaDB is up."
        break
    fi
    [ "$i" -eq 60 ] && echo "[bootstrap] ERROR: MariaDB not ready after 60s." && exit 1
    sleep 2
done

# ---------------------------------------------------------------------------
# Early exit: site exists AND database is reachable
# Checking only site_config.json is not enough — if the MariaDB volume was
# wiped (make dev-destroy) the bench dir on the host still has site_config.json
# but the database and user are gone. Verify connectivity before skipping.
# ---------------------------------------------------------------------------
if [ -f "${BENCH_DIR}/sites/${SITE}/site_config.json" ]; then
    DB_NAME=$(python3 -c "
import json
cfg = json.load(open('${BENCH_DIR}/sites/${SITE}/site_config.json'))
print(cfg.get('db_name',''))
" 2>/dev/null)
    DB_USER=$(python3 -c "
import json
cfg = json.load(open('${BENCH_DIR}/sites/${SITE}/site_config.json'))
print(cfg.get('db_name',''))
" 2>/dev/null)
    DB_PASS=$(python3 -c "
import json
cfg = json.load(open('${BENCH_DIR}/sites/${SITE}/site_config.json'))
print(cfg.get('db_password',''))
" 2>/dev/null)

    if mysql -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_NAME}" -p"${DB_PASS}" \
             -e "SELECT 1;" "${DB_NAME}" &>/dev/null; then
        echo "[bootstrap] Site '${SITE}' exists and DB is reachable — nothing to do."
        exit 0
    else
        echo "[bootstrap] Site config exists but DB is not reachable — re-running site creation."
        # Remove stale site dir so bench new-site can recreate it cleanly
        rm -rf "${BENCH_DIR}/sites/${SITE}"
    fi
fi

# ---------------------------------------------------------------------------
# bench init — creates the bench with frappe only
# Skip if bench dir already exists (partial previous run)
# ---------------------------------------------------------------------------
if [ ! -d "${BENCH_DIR}" ]; then
    echo "[bootstrap] Running bench init (frappe @ ${FRAPPE_BRANCH})..."
    mkdir -p "${BENCH_PARENT}"
    cd "${BENCH_PARENT}"
    bench init \
        --skip-redis-config-generation \
        --frappe-branch="${FRAPPE_BRANCH}" \
        --verbose \
        "${BENCH_NAME}"
else
    echo "[bootstrap] Bench dir exists — skipping bench init."
fi

cd "${BENCH_DIR}"

# ---------------------------------------------------------------------------
# Configure common_site_config.json
# ---------------------------------------------------------------------------
echo "[bootstrap] Writing bench config..."
bench set-config -g  db_host         "${DB_HOST}"
bench set-config -gp db_port         "${DB_PORT}"
bench set-config -g  redis_cache     "redis://${REDIS_CACHE}"
bench set-config -g  redis_queue     "redis://${REDIS_QUEUE}"
bench set-config -g  redis_socketio  "redis://${REDIS_SOCKETIO}"
bench set-config -gp socketio_port   9000
bench set-config -gp developer_mode  1
# webserver_port: used by socketio's get_url() in developer_mode to call the
# Frappe API for socket auth. Must match nginx's internal container port (8000)
# since nginx has a Docker network alias of HOST_NAME (e.g. dev.localhost),
# making http://dev.localhost:8000 resolvable from within the Docker network.
bench set-config -gp webserver_port  8000
# socketio.js reads host_name from common_site_config (global), not site_config.
bench set-config -g  host_name       "http://${HOST_NAME:-dev.localhost}"

# ---------------------------------------------------------------------------
# Fetch all non-frappe apps listed in apps.json
# bench get-app handles: git clone, pip install, apps.txt registration
# ---------------------------------------------------------------------------
echo "[bootstrap] Fetching apps from ${APPS_JSON}..."

python3 - <<PYEOF
import json, subprocess, os, sys
from pathlib import Path

bench_dir = "${BENCH_DIR}"
apps_file = "${APPS_JSON}"
token     = "${GITHUB_TOKEN}"
SKIP      = {"frappe"}   # bench init already installed frappe

if not Path(apps_file).exists():
    print(f"[bootstrap] {apps_file} not found — skipping.", flush=True)
    sys.exit(0)

apps = json.load(open(apps_file))

for app in apps:
    url    = app["url"]
    branch = app.get("branch", "main")
    name   = url.rstrip("/").split("/")[-1].replace(".git", "")

    if name in SKIP:
        print(f"[bootstrap] {name} — already in bench, skipping.", flush=True)
        continue

    app_path = Path(bench_dir) / "apps" / name
    if app_path.exists() and any(app_path.iterdir()):
        print(f"[bootstrap] {name} — already present, skipping.", flush=True)
        continue

    # Inject token for private thinkspedia repos only
    auth_url = url
    if token and "thinkspedia" in url and url.startswith("https://"):
        auth_url = url.replace("https://", f"https://{token}@")

    print(f"[bootstrap] bench get-app {name} @ {branch}...", flush=True)
    subprocess.run(
        ["bench", "get-app", "--branch", branch, auth_url],
        cwd=bench_dir,
        check=True,
    )

print("[bootstrap] All apps fetched.", flush=True)
PYEOF

# ---------------------------------------------------------------------------
# Create site and install all apps
# ---------------------------------------------------------------------------
echo "[bootstrap] Creating site '${SITE}'..."

# Build install-app flags from apps.json (frappe is auto-installed by new-site)
INSTALL_ARGS=$(python3 - <<PYEOF
import json, os
apps = json.load(open("${APPS_JSON}"))
skip = {"frappe"}
flags = []
for a in apps:
    name = a["url"].rstrip("/").split("/")[-1].replace(".git","")
    if name not in skip:
        flags.append(f"--install-app={name}")
print(" ".join(flags))
PYEOF
)

# shellcheck disable=SC2086
bench new-site "${SITE}" \
    --db-root-password "${DB_ROOT_PASSWORD}" \
    --admin-password "${SITE_ADMIN_PASSWORD}" \
    --mariadb-user-host-login-scope="%" \
    ${INSTALL_ARGS}

# ---------------------------------------------------------------------------
# Set current site (single-site dev convenience)
# ---------------------------------------------------------------------------
bench use "${SITE}"

# ---------------------------------------------------------------------------
# Set host_name in site_config.json
# ---------------------------------------------------------------------------
bench --site "${SITE}" set-config host_name "http://${HOST_NAME:-$SITE}"

# ---------------------------------------------------------------------------
# Build frontend assets (JS/CSS bundles)
# frappe/bench installs Node via nvm which only activates in interactive shells.
# Source nvm explicitly so yarn/node are in PATH for non-interactive scripts.
# ---------------------------------------------------------------------------
echo "[bootstrap] Setting up Node via nvm..."
export NVM_DIR="${NVM_DIR:-/home/frappe/.nvm}"
# shellcheck source=/dev/null
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"

if ! command -v node &>/dev/null; then
    echo "[bootstrap] ERROR: node not found after sourcing nvm. Cannot build assets." >&2
    exit 1
fi
echo "[bootstrap] Node $(node --version), yarn $(yarn --version)"

echo "[bootstrap] Building frontend assets (this takes a few minutes)..."
bench build

# Verify assets were actually written
ASSET_CHECK="${BENCH_DIR}/sites/assets/frappe/dist"
if [ ! -d "${ASSET_CHECK}" ]; then
    echo "[bootstrap] ERROR: bench build completed but assets not found at ${ASSET_CHECK}" >&2
    exit 1
fi

echo "[bootstrap] Done. Site '${SITE}' is ready at http://${HOST_NAME:-$SITE}"
