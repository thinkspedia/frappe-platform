# Tech Context

## Platform Stack

| Technology | Version / Tag | Role |
|---|---|---|
| `frappe/bench` | `latest` | Dev base image (bench CLI, nvm, pyenv) |
| MariaDB | `10.6` | Database |
| Redis | `7-alpine` | Cache, queue, socketio (3 separate instances) |
| nginx | `alpine` | Dev reverse proxy (splits web/socketio) |
| Traefik | `v3.0` | Dev entry point on port 80; carries `dev.localhost` alias |
| Adminer | `latest` | DB UI — `http://localhost:8081` (tools profile) |
| Mailpit | `axllent/mailpit` | Email trap — `http://localhost:8025` (tools profile) |
| Python | `3.14.2` | Bench + app runtime (pyenv-managed in container) |
| Node.js | via nvm in `frappe/bench` | Asset compilation |

## Dev Stack Service Map

| Service | Image | Internal Port | External | Notes |
|---|---|---|---|---|
| `traefik` | traefik:v3.0 | 80 | `${TRAEFIK_HTTP_PORT:-80}` | Carries `dev.localhost` alias |
| `nginx` | nginx:alpine | 8000 | none (via Traefik) | Splits web/socketio |
| `frappe-web` | frappe/bench | 8001 | none (via nginx) | |
| `websocket` | frappe/bench | 9000 | `9000` | |
| `worker-default/long/short` | frappe/bench | — | none | |
| `scheduler` | frappe/bench | — | none | |
| `mariadb` | mariadb:10.6 | 3306 | none | |
| `redis-cache/queue/socketio` | redis:7-alpine | 6379 | none | |
| `bootstrap` | frappe/bench | — | none (one-shot) | |
| `adminer` | adminer:latest | 8080 | `${ADMINER_PORT:-8081}` | profile: tools |
| `mailpit` | axllent/mailpit | 8025/1025 | `${MAILPIT_UI_PORT:-8025}` / `${MAILPIT_SMTP_PORT:-1025}` | profile: tools |

## Frappe Apps in Platform

| App | Repo | Branch | Type |
|---|---|---|---|
| frappe | github.com/frappe/frappe | version-16 | Bundled (bench init) |
| erpnext | github.com/frappe/erpnext | version-16 | Public |
| hrms | github.com/frappe/hrms | version-16 | Public |
| offsite_backups | github.com/frappe/offsite_backups | version-16 | Public |
| nusakura_app | github.com/thinkspedia/nusakura_app | main | Private — remote: `upstream` |
| nusakura_waha_app | github.com/thinkspedia/nusakura_waha_app | main | Private — remote: `upstream` |

## GitHub Repos

| Repo | URL | Remote | Notes |
|---|---|---|---|
| frappe-platform | `github.com/thinkspedia/frappe-platform` | `origin` | This repo |
| nusakura_app | `github.com/thinkspedia/nusakura_app` | `upstream` | Set by `bench get-app` |
| nusakura_waha_app | `github.com/thinkspedia/nusakura_waha_app` | `upstream` | Set by `bench get-app` |

## Key File Locations

| Path | Purpose |
|---|---|
| `platform/.env.example` | Source of truth — copy to `.env` |
| `platform/apps.json` | App registry (dev bootstrap) |
| `platform/docker-compose.dev.yml` | Local dev stack |
| `platform/scripts/bootstrap.sh` | Idempotent site init |
| `platform/scripts/configure-site.sh` | Writes host_name to site_config |
| `platform/scripts/mariadb.cnf` | MariaDB settings for Frappe |
| `platform/nginx/dev.conf` | nginx routing config |
| `platform/traefik/routes.yml` | Traefik static routes |
| `platform/Makefile` | All platform-level dev commands |
| `platform/docs/developer-workflow.md` | Developer workflow source of truth |
| `development/frappe-bench/` | Bench dir — gitignored, created by bootstrap |
| `development/frappe-bench/apps/nusakura_app/Makefile` | App-level commands + versioning |
| `development/frappe-bench/apps/nusakura_app/scripts/bump_version.py` | Conventional Commit version script |
| `development/frappe-bench/apps/nusakura_app/.vscode/settings.json` | Auto-configured VSCode settings |
| `development/frappe-bench/apps/nusakura_waha_app/Makefile` | Same as nusakura_app |
| `development/frappe-bench/apps/nusakura_waha_app/.vscode/settings.json` | Auto-configured VSCode settings |

## VSCode Configuration (committed to each app repo)

`.vscode/settings.json`:
- `python.defaultInterpreterPath`: `~/.pyenv/versions/3.14.2/bin/python3`
- `python-envs.defaultEnvManager`: `ms-python.python:pyenv`
- `python.analysis.extraPaths`: frappe, erpnext, hrms, the app itself (all via `/workspace/...`)
- Ruff as formatter + import organizer on save
- `python.analysis.diagnosticSeverityOverrides`: suppresses Frappe-specific Pylance warnings

`.vscode/extensions.json`: recommends ms-python.python, vscode-pylance, charliermarsh.ruff,
remote-wsl, remote-containers, prettier, vue.volar, sqltools, sqltools-driver-mysql

`.vscode/launch.json`: debugpy attach on localhost:5678 with `/workspace/...` path mappings

## Environment Variables (`.env`)

| Variable | Default | Purpose |
|---|---|---|
| `FRAPPE_SITE_NAME` | `dev.localhost` | Site name |
| `HOST_NAME` | `dev.localhost` | Public hostname (Traefik alias) |
| `DB_ROOT_PASSWORD` | `changeme` | MariaDB root password |
| `ADMIN_PASSWORD` | `changeme` | ERPNext Administrator password |
| `GITHUB_TOKEN` | `` | Private repo cloning (never commit) |
| `COMPOSE_PROFILES` | `tools` | Enable adminer + mailpit (`=` to disable) |
| `ADMINER_PORT` | `8081` | Adminer UI port |
| `MAILPIT_UI_PORT` | `8025` | Mailpit web UI port |
| `MAILPIT_SMTP_PORT` | `1025` | Mailpit SMTP port |
| `TRAEFIK_DASHBOARD_PORT` | `8082` | Traefik dashboard |
| `TRAEFIK_HTTP_PORT` | `80` | Traefik entry port (use 8080+ on Linux without root) |

## WSL2 Developer Setup Requirements

1. Install build deps: `sudo apt-get install -y libbz2-dev libncurses-dev libreadline-dev libsqlite3-dev libssl-dev liblzma-dev libffi-dev zlib1g-dev tk-dev`
2. Install pyenv: `curl https://pyenv.run | bash` + add init to `~/.zshrc`
3. Install Python: `pyenv install 3.14.2`
4. Create `/workspace` symlink: `sudo ln -sf /path/to/frappe-platform /workspace`
5. Open app: `cd platform && make code APP=nusakura_app`

No manual VSCode interpreter selection needed — `settings.json` handles it.

## Nomad Infrastructure (Production Cluster)

### Cluster Access
| Target | Address |
|---|---|
| Nomad UI | https://100.85.99.16:4646 or http://nomad.corp.thinkspedia.id/ |
| Nomad API | https://100.85.99.16:4646/v1 (header: `X-Nomad-Token`) |
| Operator token | `47a19c79-4f0e-bec9-7a17-c8bb5ceadeeb` |
| SSH key | `~/.ssh/id_ansible` (user: `opsadmin` on all nodes) |

### Nomad Servers
| Node | Netbird IP | Status |
|---|---|---|
| nomad-core-01 | 100.85.99.16 | alive |
| nomad-core-02 | 100.85.196.70 | alive |
| nomad-core-03 | 100.85.13.200 | alive (Raft data wiped + rejoined 2026-06-12) |

### Nomad Clients
| Node | Netbird IP | Notes |
|---|---|---|
| nomad-client-core-01 | 100.85.17.19 | Redis + old ERPNext running here |
| nomad-client-core-02 | 100.85.129.187 | — |
| nomad-client-core-03 | 100.85.14.86 | MariaDB running here |

### Consul
- Servers: 100.85.242.94 (consul-core-01), 100.85.148.198, 100.85.215.250
- Client agents on all Nomad clients: HTTPS only on port 8501 (no HTTP 8500)
- TLS certs on clients: `/etc/nomad.d/tls/consul-{ca,cli,cli-key}.pem`
- Consul token (from Nomad client config): `ed4c0149-4de8-35a0-36ba-910420d4f99c`
- Known issue: TLS cert IP mismatch (cert for 100.85.229.181, server at 100.85.242.94) — non-blocking

### Consul Services (registered 2026-06-12)
| Service | Address | Port |
|---|---|---|
| erpnext-nusakura-redis-cache | 100.85.17.19 | 6379 |
| erpnext-nusakura-redis-queue | 100.85.17.19 | 6380 |
| erpnext-nusakura-redis-socketio | 100.85.17.19 | 6381 |
| erpnext-nusakura-mariadb | 100.85.14.86 | 3306 |

### CSI Storage (democratic-csi NFS-ZFS)
- Plugin: `org.democratic-csi.nfs-zfs` — NFS on `nfs-core-01` (172.16.200.23), ZFS pool `tank/nomad`
- Volumes in namespace `erpnext-nusakura`:
  - `erpnext-nusakura-db` → MariaDB `/var/lib/mysql`
  - `erpnext-nusakura-redis` → Redis socketio `/data`
  - `erpnext-nusakura-sites` → Frappe sites dir (mounted on core-01, contains live site)
  - `erpnext-nusakura-logs` → Frappe logs
- Mount path on clients: `/opt/nomad/client/csi/node/org.democratic-csi.nfs-zfs/staging/erpnext-nusakura/<vol-id>/rw-file-system-single-node-writer/`

### Running Jobs (erpnext-nusakura namespace)
| Job | Node | Status | Notes |
|---|---|---|---|
| erpnext-nusakura-mariadb | core-03 (100.85.14.86) | running | Static port 3306 |
| erpnext-nusakura-redis | core-01 (100.85.17.19) | running | Static ports 6379/6380/6381 |
| nusakura-erpnext (old v0) | core-01 (100.85.17.19) | running | Monolithic, deployment=failed but alloc alive |

### Vault
- Version: v1.17.6, running on all 3 Nomad server nodes, port 8200
- Initialized and unsealed — but Nomad-Vault integration NOT yet configured (no vault{} stanza in /etc/nomad.d/nomad.hcl)
- Phase 4 work: wire Vault to Nomad for secrets management

### Production Image Registry
- `registry.corp.thinkspedia.id` — Harbor, internal CA
- Current ERPNext image: `registry.corp.thinkspedia.id/erpnext/nusakuraerp:v1.3.19`

## Cross-Platform Notes

| Platform | Known Issues / Notes |
|---|---|
| WSL2 | Bench venv `python` symlinks to `/home/frappe/.pyenv/...` (container-only). Fix: install pyenv on WSL2 + `/workspace` symlink |
| WSL2 | Traefik Docker provider fails → use file provider (`platform/traefik/routes.yml`) |
| macOS | Same Traefik issue → file provider. `/workspace` symlink may need SIP disabled |
| macOS | Alternative: Attach to Running Container in VSCode |
| Linux (no root) | Port 80 binding fails → set `TRAEFIK_HTTP_PORT=8080` in `.env` |
