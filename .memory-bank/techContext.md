# Tech Context

## Language Stack

| Language | Role | Tooling |
|---|---|---|
| Shell (bash) | Bootstrap, configure-site, entrypoints | shellcheck, shfmt |
| Python | CLI (org-bench), test suite, automation scripts | black, isort, pyupgrade |
| YAML | Docker Compose files | prettier |
| HCL | Docker Buildx Bake (`docker-bake.hcl`) | — |
| Markdown | Documentation | prettier, codespell |

## Platform Layer Stack (`platform/`)

| Technology | Version / Tag | Role |
|---|---|---|
| `frappe/bench` | `latest` | Dev base image (has bench CLI, nvm, pyenv) |
| `frappe/build` | `version-16` | Prod builder image (all build deps) |
| `frappe/base` | `version-16` | Prod runtime image (minimal) |
| MariaDB | `10.6` | Database |
| Redis | `7-alpine` | Cache, queue, socketio (3 separate instances) |
| nginx | `alpine` | Dev reverse proxy (splits web/socketio) |
| Traefik | `v3.0` | Dev entry point on port 80 |
| Node.js | via nvm in `frappe/bench` | Asset compilation |

## Dev Stack Service Map

| Service | Image | Internal Port | External |
|---|---|---|---|
| `traefik` | traefik:v3.0 | 80 | `${TRAEFIK_HTTP_PORT:-80}` |
| `nginx` | nginx:alpine | 8000 | none (via Traefik) |
| `frappe-web` | frappe/bench | 8001 | none (via nginx) |
| `websocket` | frappe/bench | 9000 | `9000` |
| `worker-default` | frappe/bench | — | none |
| `worker-long` | frappe/bench | — | none |
| `worker-short` | frappe/bench | — | none |
| `scheduler` | frappe/bench | — | none |
| `mariadb` | mariadb:10.6 | 3306 | none |
| `redis-cache` | redis:7-alpine | 6379 | none |
| `redis-queue` | redis:7-alpine | 6379 | none |
| `redis-socketio` | redis:7-alpine | 6379 | none |
| `bootstrap` | frappe/bench | — | none (one-shot) |

## Frappe Apps in Platform

| App | Repo | Branch | Type |
|---|---|---|---|
| frappe | github.com/frappe/frappe | version-16 | Bundled (bench init) |
| erpnext | github.com/frappe/erpnext | version-16 | Public |
| hrms | github.com/frappe/hrms | version-16 | Public (bind-mounted for HRMS PWA overrides) |
| offsite_backups | github.com/frappe/offsite_backups | version-16 | Public |
| nusakura_app | github.com/thinkspedia/nusakura_app | main | Private org app |
| nusakura_waha_app | github.com/thinkspedia/nusakura_waha_app | main | Private org app |

## Key File Locations

| Path | Purpose |
|---|---|
| `platform/.env.example` | Source of truth — copy to `.env` |
| `platform/apps.json` | App registry (dev + prod) |
| `platform/docker-compose.dev.yml` | Local dev stack |
| `platform/scripts/bootstrap.sh` | Idempotent site init |
| `platform/scripts/configure-site.sh` | Writes host_name to site_config |
| `platform/scripts/mariadb.cnf` | MariaDB settings for Frappe |
| `platform/nginx/dev.conf` | nginx routing config |
| `platform/traefik/routes.yml` | Traefik static routes |
| `platform/Makefile` | All dev commands |
| `platform/Dockerfile` | Multi-stage production image |
| `development/frappe-bench/` | Bench dir — gitignored, created by bootstrap |

## Environment Variables (`.env`)

| Variable | Default | Purpose |
|---|---|---|
| `FRAPPE_BRANCH` | `version-16` | Frappe branch for bench init + prod build |
| `FRAPPE_BENCH_TAG` | `latest` | frappe/bench image tag for dev |
| `FRAPPE_SITE_NAME` | `dev.localhost` | Site name |
| `HOST_NAME` | `dev.localhost` | Public hostname + nginx network alias |
| `HTTP_PUBLISH_PORT` | `8000` | Direct gunicorn port (debug only) |
| `TRAEFIK_HTTP_PORT` | `80` | Traefik entry port (use 8080+ on Linux without root) |
| `DB_ROOT_PASSWORD` | `changeme` | MariaDB root password |
| `GITHUB_TOKEN` | `` | For private repo cloning (never commit) |

## Cross-Platform Notes

| Platform | Known Issues |
|---|---|
| WSL2 Docker Desktop | Individual file bind-mounts unreliable → use dir mounts |
| WSL2 Docker Desktop | Traefik Docker provider fails → use file provider |
| macOS Docker Desktop | Same Traefik issue → file provider |
| Linux (no root) | Port 80 binding fails → set `TRAEFIK_HTTP_PORT=8080` |
| All | `make dev-setup` checks `/etc/hosts` and shows platform-specific add command |

## Pre-commit Hooks
- `black`, `isort`, `pyupgrade --py37-plus` — Python
- `shfmt`, `shellcheck` — Shell
- `prettier` — YAML/Markdown/JSON
- `codespell` — Spell check
- `trailing-whitespace`, `end-of-file-fixer`
