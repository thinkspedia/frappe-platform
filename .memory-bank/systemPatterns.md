# System Patterns

## Platform Layer Pattern: Workspace Mount + Host Bench

`platform/docker-compose.dev.yml` mounts the entire repo root as `/workspace`:
```
../:/workspace:cached   (repo root → /workspace inside container)
```
Bench lives at `/workspace/development/frappe-bench` — on the host at `development/frappe-bench/`.
App source is directly editable on the host with no bind-mount permission issues.
`development/frappe-bench/` is gitignored; each app inside is its own git repo.

## Bootstrap Pattern: Idempotent One-Shot Container

`bootstrap` service runs `bench init → bench get-app → bench new-site` once, then exits 0.
All other services `depends_on: bootstrap: condition: service_completed_successfully`.
Idempotency check: verifies site_config.json exists AND MariaDB connection succeeds.
If MariaDB volume was wiped but bench dir remains, bootstrap detects DB unreachable and re-runs new-site.

## App Registry Pattern: `apps.json` as Single Source of Truth

`platform/apps.json` drives bootstrap's `bench get-app` loop.
Format: `[{"url": "...", "branch": "..."}]`
- `frappe` is always skipped (already in bench)
- Private repos (`thinkspedia/*`) get GITHUB_TOKEN injected into URL at runtime only
- **Never** hardcode credentials in apps.json

## Nginx Routing Pattern: Single Entry Point

```
Browser → Traefik:80 → nginx:8000
                         ├── /socket.io/* → websocket:9000  (WebSocket upgrade)
                         └── /*           → frappe-web:8001 (bench serve)
```
Traefik (not nginx) carries the `HOST_NAME` Docker network alias (e.g. `dev.localhost`).
This is intentional: `webserver_port=80` in common_site_config means internal containers
that resolve `dev.localhost:80` reach Traefik → nginx → frappe-web correctly, and Frappe
email URL generation produces `http://dev.localhost` without a port suffix.

## Traefik Pattern: File Provider (not Docker provider)

Docker Desktop (WSL2 + macOS) blocks the `/events` stream the Docker provider needs.
Use static file routing in `platform/traefik/routes.yml` — works on all platforms identically.
Routes everything to nginx, which handles the web/socket split.

## common_site_config Pattern: Key Dev Settings

Set globally via `bench set-config -g`:
- `db_host`, `db_port` — MariaDB container service name
- `redis_cache/queue/socketio` — Redis container service names
- `developer_mode = 1` — enables hot reload, disables caching
- `socketio_port = 9000`
- `webserver_port = 80` — must match Traefik (public entry point); Frappe appends this
  to `host_name` when building email URLs — `8000` causes broken `:8000` links
- `host_name = http://dev.localhost` — required by socketio for origin validation

## App Versioning Pattern

Both `nusakura_app` and `nusakura_waha_app` use identical versioning:
- Version stored in `<app>/__init__.py` as `__version__`
- `pyproject.toml` uses `flit_core` with `dynamic = ["version"]` — single source of truth
- `scripts/bump_version.py` reads Conventional Commits since last git tag to auto-detect bump type
- `Makefile` targets: `version-current`, `version-next`, `version-bump`, `release-version`
- `make release-version` — updates `__init__.py`, commits `chore(release): vX.Y.Z`, creates git tag
- After release: `git push upstream main --tags`
- Conventional Commit → bump: `feat!`/`BREAKING CHANGE` → major, `feat` → minor, `fix`/`perf`/`refactor` → patch

## App-Level Makefile Delegation Pattern

Each custom app (`nusakura_app`, `nusakura_waha_app`) has a `Makefile` that:
1. Delegates platform lifecycle to `platform/Makefile` via `$(MAKE) -C $(PLATFORM) <target>`
2. Runs bench commands inside the container via `docker exec $(CONTAINER) bash -c "..."`
3. Never requires `cd platform/` — developers work entirely from the app directory

Key variables in each app Makefile:
```makefile
CONTAINER ?= platform-frappe-web-1
SITE      ?= dev.localhost
BENCH     := /workspace/development/frappe-bench
PLATFORM  := /workspace/platform
EXEC      := docker exec $(CONTAINER) bash -c
```

Available targets from app directory:
- `make start / stop / logs / restart` — platform lifecycle
- `make sync` — git pull upstream + migrate + clear-cache
- `make dev-migrate / dev-clear-cache / dev-build / dev-console / dev-shell`
- `make dev-export-fixtures`
- `make release-version [VERSION_BUMP=patch|minor|major]`

## VSCode WSL2 Setup Pattern

Two problems prevent IntelliSense from working on WSL2:
1. Bench venv `.pth` files use `/workspace/...` (container path) — doesn't exist on WSL2
2. Bench venv `python` symlinks to `/home/frappe/.pyenv/...` (container-only user)

Fix:
1. Install pyenv + Python 3.14.2 on WSL2 (with build deps first)
2. Create `/workspace` symlink: `sudo ln -sf /path/to/frappe-platform /workspace`
3. Open app via `make code APP=<name>` from `platform/`

The `.vscode/settings.json` committed to each app repo auto-configures:
- `python.defaultInterpreterPath`: `~/.pyenv/versions/3.14.2/bin/python3`
- `python-envs.defaultEnvManager`: `ms-python.python:pyenv`
- `python.analysis.extraPaths`: frappe, erpnext, hrms, app itself
- Ruff formatter + import organizer
- Debugpy attach config on port 5678

## make code Pattern: VSCode Shortcut

`make code APP=<name>` in `platform/Makefile` runs:
```bash
code /workspace/development/frappe-bench/apps/$(APP)
```
Opens VSCode directly to the app folder. Works on WSL2 after creating `/workspace` symlink.

## Git Remote Naming Pattern

`bench get-app` names the remote `upstream`, not `origin`.
All push/pull in app repos must use `upstream`:
```bash
git push upstream main --tags
git pull --ff-only upstream main
git push upstream feat/my-feature
```

## Mailpit Email Trap Pattern

Mailpit runs as optional `tools` profile service on `mailpit:1025` (SMTP).
Frappe Email Account must be configured with dummy credentials (not Awaiting Password):
- SMTP Server: `mailpit`, Port: `1025`, no TLS/SSL
- Login ID: `test`, Password: `mailpit`
- `MP_SMTP_AUTH_ACCEPT_ANY=1` accepts any credentials
- Awaiting Password checkbox bypasses save validation but fails at send time — do not use it

## Security Pattern: Secrets at Runtime

Never hardcode credentials. Two approved approaches for dev:
1. `.env` file loaded by Docker Compose
2. GITHUB_TOKEN injected into clone URL at runtime (`https://token@github.com/...`), never persisted

## make dev-destroy Pattern

Must remove BOTH the Docker volume (MariaDB data) AND the host bench directory:
```bash
docker compose down -v           # removes mariadb-data volume
rm -rf ../development/frappe-bench  # removes bench on host
```
If only volumes are removed, bootstrap sees existing site_config.json and exits early,
but MariaDB has no user/database → connection failures on startup.

## MariaDB Container Networking Pattern

`bench new-site` must include `--mariadb-user-host-login-scope=%` so the created DB user
allows connections from any container IP (not just localhost).

## Asset Build Pattern

`frappe/bench` has raw source — assets are NOT pre-compiled.
`bench build` must run after site creation.
Requires nvm to be sourced in non-interactive scripts:
```bash
export NVM_DIR="/home/frappe/.nvm" && source "$NVM_DIR/nvm.sh"
```
Asset symlinks use absolute container paths (`/workspace/...`) — broken on host, valid
inside container. This is expected.
