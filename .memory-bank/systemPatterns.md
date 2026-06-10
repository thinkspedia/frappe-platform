# System Patterns

## Core Architectural Pattern: Composable Overrides (upstream repo)

`compose.yaml` is the base service graph — always requires at minimum one database override:
```
docker compose -f compose.yaml -f overrides/<db>.yaml -f overrides/<proxy>.yaml up -d
```
Override files only add `environment`, `volumes`, `networks`, or `depends_on` — never redeclare services.

## Platform Layer Pattern: Workspace Mount + Host Bench

`platform/docker-compose.dev.yml` mounts the entire repo root as `/workspace`:
```
../:/workspace:cached   (repo root → /workspace inside container)
```
Bench lives at `/workspace/development/frappe-bench` — on the host at `development/frappe-bench/`.
This means app source is directly editable on the host with no bind-mount permission issues.
`development/frappe-bench/` is gitignored; each app inside is its own git repo.

## Bootstrap Pattern: Idempotent One-Shot Container

`bootstrap` service runs `bench init → bench get-app → bench new-site` once, then exits 0.
All other services `depends_on: bootstrap: condition: service_completed_successfully`.
Idempotency check: verifies site_config.json exists AND MariaDB connection succeeds.
If MariaDB volume was wiped but bench dir remains, bootstrap detects DB unreachable and re-runs new-site.

## App Registry Pattern: `apps.json` as Single Source of Truth

`platform/apps.json` drives both dev (bootstrap `bench get-app`) and prod (Dockerfile RUN layer).
Format: `[{"url": "...", "branch": "..."}]`
- `frappe` is always skipped (already in bench/image)
- Private repos (`thinkspedia/*`) get GITHUB_TOKEN injected into URL at runtime only
- **Never** hardcode credentials in apps.json

## Nginx Routing Pattern: Single Entry Point

```
Browser → Traefik:80 → nginx:8000
                         ├── /socket.io/* → websocket:9000  (WebSocket upgrade)
                         └── /*           → frappe-web:8001 (bench serve)
```
nginx has Docker network alias matching `HOST_NAME` (e.g. `dev.localhost`) so other containers
can resolve `http://dev.localhost:8000` for internal API calls (used by websocket auth).

## Traefik Pattern: File Provider (not Docker provider)

Docker Desktop (WSL2 + macOS) blocks the `/events` stream the Docker provider needs.
Use static file routing in `platform/traefik/routes.yml` — works on all platforms identically.
Routes everything to nginx, which handles the web/socket split.

## common_site_config Pattern: Key Dev Settings

Set globally via `bench set-config -g`:
- `db_host`, `db_port` — MariaDB container service name
- `redis_cache/queue/socketio` — Redis container service names  
- `developer_mode = 1` — enables hot reload, disables caching
- `socketio_port = 9000` — for socketio client URL construction
- `webserver_port = 8000` — Frappe's `realtime/utils.js` uses this to build internal API URL
- `host_name = http://dev.localhost` — required by socketio for origin validation (reads global config, not site config)

## Security Pattern: Secrets at Runtime

Never hardcode credentials. Three approved approaches:
1. `.env` file loaded by Docker Compose (dev/staging)
2. Docker environment variables at `docker compose up`
3. BuildKit secrets (`--mount=type=secret`) for private repo tokens at image build time

GITHUB_TOKEN: injected via URL (`https://token@github.com/...`) at clone time only, never persisted.

## Asset Build Pattern

`frappe/bench` image has raw source — assets are NOT pre-compiled (unlike `frappe/erpnext`).
`bench build` must run after site creation to compile JS/CSS bundles.
Requires nvm to be sourced in non-interactive scripts:
```bash
export NVM_DIR="/home/frappe/.nvm" && [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
```
Assets land in `sites/assets/{app}/dist/` via symlinks from `sites/assets/{app} → apps/{app}/{app}/public`.
Symlinks use absolute container paths (`/workspace/...`) — broken on host, valid inside container.
`bench serve` uses werkzeug `SharedDataMiddleware` which follows these symlinks correctly.

## Image Build Pattern: Variables-First HCL (production)

All version pins in `variable` blocks in `docker-bake.hcl`. Containerfiles consume `ARG` values.
Never hardcode versions inside a Containerfile.

## MariaDB Container Networking Pattern

`bench new-site` must include `--mariadb-user-host-login-scope=%` so the created DB user
allows connections from any container IP (not just localhost).
Without this, `frappe-web` containers get "Access denied" from changing container IPs.

## make dev-destroy Pattern

Must remove BOTH the Docker volume (MariaDB data) AND the host bench directory:
```
docker compose down -v           # removes mariadb-data volume
rm -rf ../development/frappe-bench  # removes bench on host
```
If only volumes are removed, bootstrap sees existing site_config.json and exits early,
but MariaDB has no user/database → connection failures on startup.
