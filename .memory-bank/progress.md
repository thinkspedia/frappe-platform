# Progress

## What Is Working (Confirmed)

### Platform Layer (`platform/`)
- [x] `platform/docker-compose.dev.yml` — full local dev stack
- [x] `platform/scripts/bootstrap.sh` — idempotent bench init + site creation
- [x] `platform/scripts/configure-site.sh` — writes host_name to site_config
- [x] `platform/nginx/dev.conf` — routes /socket.io/ and web traffic
- [x] `platform/traefik/routes.yml` — file-provider static routes (works on all platforms)
- [x] `platform/Makefile` — full dev target set, startup prints all URLs + credentials
- [x] `platform/.env.example` — complete env variable reference
- [x] `platform/apps.json` — app registry: erpnext, hrms, offsite_backups, nusakura_app, nusakura_waha_app
- [x] `platform/docs/developer-workflow.md` — source of truth, all scenarios documented

### Dev Stack Verified Working
- [x] `http://dev.localhost` accessible in browser
- [x] Bootstrap: bench init, bench get-app, bench new-site, bench build all succeed
- [x] MariaDB user created with `%` host scope
- [x] Asset symlinks work inside container
- [x] Traefik file provider — no Docker Desktop socket errors
- [x] nginx splits web/socket.io traffic correctly
- [x] Adminer at http://localhost:8081
- [x] Mailpit at http://localhost:8025, Email Account configured in ERPNext
- [x] Email URLs: `http://dev.localhost` (no `:8000` bug — alias on Traefik, webserver_port=80)

### App Versioning
- [x] `nusakura_app` — Makefile + `scripts/bump_version.py` (Conventional Commits auto-detect)
- [x] `nusakura_waha_app` — same setup

### App-Level Makefile (both repos)
- [x] `make start / stop / logs / restart` — delegates to platform
- [x] `make sync` — git pull upstream + migrate + clear-cache
- [x] `make dev-migrate / dev-clear-cache / dev-build / dev-console / dev-shell`
- [x] `make dev-export-fixtures`
- [x] `make release-version [VERSION_BUMP=patch|minor|major]`

### VSCode Configuration (both app repos)
- [x] `.vscode/settings.json` — `python.defaultInterpreterPath: ~/.pyenv/versions/3.14.2/bin/python3`
- [x] `.vscode/settings.json` — `python-envs.defaultEnvManager: ms-python.python:pyenv`
- [x] `.vscode/settings.json` — `python.analysis.extraPaths` for frappe/erpnext/hrms
- [x] `.vscode/extensions.json` — recommends Python, Pylance, Ruff, SQLTools
- [x] `.vscode/launch.json` — debugpy attach config on port 5678
- [x] Committed and pushed to both app repos

### GitHub Repos
- [x] `github.com/thinkspedia/frappe-platform` — this repo, published and clean
- [x] `github.com/thinkspedia/nusakura_app` — custom app repo
- [x] `github.com/thinkspedia/nusakura_waha_app` — custom app repo

### Documentation
- [x] `README.md` — rewritten for Thinkspedia Frappe Platform
- [x] `platform/docs/developer-workflow.md` — comprehensive, all scenarios:
  - A–F: New feature, bug fix, hotfix, enhancement, chore, docs
  - IDE setup: WSL2 + VSCode (full pyenv steps), macOS, JetBrains, Devcontainer
  - Dev tools: Adminer + Mailpit setup + ERPNext configuration
  - Version bump rules + release gate
  - Branch cleanup + PR guidelines
  - Troubleshooting: 7 documented issues (including pyenv build deps, interpreter symlink)

## What Is Partially Working
- [~] **WebSocket real-time**: "Invalid origin" in dev only (Frappe bug, waived)
  - Root cause: `authenticate.js` missing `return` + absent `Origin` header on polling
  - Does not affect staging/production. **Do NOT patch frappe/erpnext source.**

## Dokploy Production Deployment (Completed 2026-06-11)
- [x] `platform/dokploy/docker-compose.yml` — production compose manifest
- [x] `platform/scripts/dokploy-deploy.sh` — API integration (project lookup, env update, redeploy, poll)
- [x] `make deploy-dokploy` — full build+push+redeploy
- [x] `make push-deploy-dokploy` — push pre-built image + redeploy
- [x] `make build` / `make push` / `make build-push` — granular targets
- [x] `make dokploy-status` — live status check
- [x] Staging site live: `https://nusakura-stg.erp.thinkspedia.id` — SSL ✓, ERPNext accessible ✓
- [x] `platform/docs/dokploy-deployment.md` — full deployment guide with all problems and solutions

## What Is Planned But Not Yet Implemented
- [ ] `platform/nomad/frappe.nomad.hcl` — Nomad job spec
- [ ] GitHub Actions CI — image build + push to Harbor on git tag
- [ ] Production environment deployment (`nusakura-erp-prod`)
- [ ] `platform/cli/` — org-bench CLI

## Known Constraints and Gotchas (Dokploy-specific)

14. **Dokploy API uses `x-api-key` header** — NOT `Authorization: Bearer`. Scripts/curl must use `-H "x-api-key: <token>"`.
15. **`compose.all` endpoint does not exist in Dokploy** — compose services are nested under `project.all` response: `environments[].compose[]`.
16. **Harbor internal CA on Dokploy VPS** — Docker daemon cannot pull from `registry.corp.thinkspedia.id` until CA cert is installed: `sudo mkdir -p /etc/docker/certs.d/registry.corp.thinkspedia.id && sudo cp ca.crt /etc/docker/certs.d/registry.corp.thinkspedia.id/ca.crt`. No Docker restart needed.
17. **Dokploy registry credentials** — must be added in Dokploy UI (Settings → Registries) separately from VPS cert trust.
18. **Dokploy `compose.update` sets env vars** — `IMAGE_TAG` is updated in the Dokploy compose env before each redeploy. This is how image version is pinned per deploy.
19. **Traefik labels + Dokploy UI domain = conflicting routers** — use one approach only. This repo uses Dokploy UI domain; Traefik labels are removed from the compose file.
20. **`frontend` must be on `default` network** — Traefik (on `dokploy-network`/`default`) cannot route to containers not on that network. Add `default` to `frontend` service networks alongside `bench-network`.
21. **Dokploy UI "Container Port" = internal container port** — nginx listens on 8080 inside the container. `HTTP_PUBLISH_PORT=8088` is the host-published port; entering 8088 as container port makes Traefik fail silently.
22. **`SITE_NAME` must exactly match `FRAPPE_SITE_NAME_HEADER`** — nginx resolves the site by looking up `sites/${FRAPPE_SITE_NAME_HEADER}/site_config.json`. Any difference in the two values causes nginx 404 on all requests.
23. **Reload Traefik after adding Dokploy UI domain** — new router is not picked up until Settings → Traefik → Reload is clicked.
24. **`deploy.replicas: 0` is Swarm-only** — does not skip services in plain `docker compose up`. Use env-var gate inside the command (`[ "$CREATE_SITE" != "1" ] && exit 0`) instead.
25. **Post-install: set `home_page` in DB** — freshly created Frappe sites have `System Settings.home_page = NULL`. Python omits the key from boot JSON entirely, so `frappe.boot.home_page` is JavaScript `undefined` → router navigates to `/undefined`. Fix: `frappe.db.set_value('System Settings', 'System Settings', 'home_page', 'workspace')` in bench console.

## Known Constraints and Gotchas

1. **`make dev-destroy` must remove bench dir** — `rm -rf ../development/frappe-bench`
   in addition to `docker compose down -v`. Stale site_config.json causes bootstrap to
   skip new-site after MariaDB volume wipe.
2. **`bench build` requires nvm** — source `/home/frappe/.nvm/nvm.sh` in non-interactive scripts.
3. **Asset symlinks use absolute container paths** — broken on host, valid inside container. Expected.
4. **`host_name` in common_site_config** — socketio reads global config, not site config.
   Use `bench set-config -g` (not `bench --site X set-config`).
5. **`webserver_port = 80`** — must match Traefik. Setting to 8000 causes `:8000` in email URLs.
   The `dev.localhost` alias is on Traefik so `dev.localhost:80` resolves correctly inside Docker.
6. **`--mariadb-user-host-login-scope=%`** — required on `bench new-site` for container networking.
7. **GITHUB_TOKEN for private repos** — injected into clone URL at runtime, never stored.
8. **`frappe` and `erpnext` are BUNDLED** — do not add them to the `bench get-app` loop.
9. **Mailpit dummy credentials required** — Login ID: `test`, Password: `mailpit`.
   Awaiting Password bypasses save but fails at send time.
10. **`dev.localhost` alias on Traefik, NOT nginx** — moving it back to nginx re-introduces `:8000` email bug.
11. **App repos use remote name `upstream`** — set by `bench get-app`. All push/pull must use `upstream`.
12. **Bench venv `python` symlinks to `/home/frappe/.pyenv/...`** — container-only path.
    WSL2 fix: install pyenv + Python 3.14.2 on WSL2. Build deps required before pyenv install.
13. **pyenv install requires build deps first** — `libbz2-dev libncurses-dev libreadline-dev
    libsqlite3-dev libssl-dev liblzma-dev libffi-dev zlib1g-dev tk-dev`. Missing deps produce
    silent compile warnings and broken modules (bz2, sqlite3, readline, lzma, tkinter).

## Session History

| Date | Action |
|---|---|
| 2026-06-10 | Initial platform design + implementation (`frappe/bench` image, workspace mount) |
| 2026-06-10 | Fixed: MariaDB host scope, asset 404s, nginx routing, Traefik file provider |
| 2026-06-10 | Fixed: webserver_port + alias → email URLs correct, socketio works |
| 2026-06-10 | Added adminer + mailpit (tools profile) |
| 2026-06-10 | Added versioning (bump_version.py + Makefile) to both app repos |
| 2026-06-10 | Created `platform/docs/developer-workflow.md` |
| 2026-06-10 | Fixed email URL bug — moved alias to Traefik, set webserver_port=80 |
| 2026-06-10 | Added app-level Makefile delegation targets (no directory switching) |
| 2026-06-10 | Added `.vscode/` configs to both app repos — settings, extensions, launch |
| 2026-06-10 | Added `make code APP=<name>` shortcut in platform Makefile |
| 2026-06-10 | Discovered + fixed: bench venv python → `/home/frappe/.pyenv/...` on WSL2 |
| 2026-06-10 | pyenv + Python 3.14.2 installed on WSL2 (with build deps) |
| 2026-06-10 | Updated both app `.vscode/settings.json` to pyenv interpreter + env manager |
| 2026-06-10 | All git push/pull corrected to `upstream` remote throughout all docs |
| 2026-06-10 | Pushed frappe-platform to `github.com/thinkspedia/frappe-platform` |
| 2026-06-10 | Removed all upstream frappe_docker files (130 files), rewrote README.md |
| 2026-06-11 | Built Dokploy production deployment pipeline (dokploy-deploy.sh, Makefile targets) |
| 2026-06-11 | Fixed: Dokploy API auth header (`x-api-key`), compose.all → project.all lookup |
| 2026-06-11 | Fixed: Harbor CA cert on VPS + Dokploy registry credentials |
| 2026-06-11 | First successful deploy: nusakura-erp-stg:v1.0.0 → running |
| 2026-06-11 | Fixed: removed Traefik labels from compose (conflicted with Dokploy UI domain) |
| 2026-06-11 | Fixed: frontend added to `default` network — Traefik couldn't route without it |
| 2026-06-11 | Fixed: Swarm deploy.replicas replaced with in-command env-var gate (Nomad-ready) |
| 2026-06-11 | Fixed: SITE_NAME aligned to FRAPPE_SITE_NAME_HEADER (was nusakura-erp.stg vs nusakura-stg.erp) |
| 2026-06-11 | Fixed: Container Port in Dokploy domain = 8080 (internal), not 8088 (host) |
| 2026-06-11 | Fixed: Traefik reload required after domain config saved |
| 2026-06-11 | Fixed: home_page set in System Settings + Website Settings via bench console |
| 2026-06-11 | Staging live: https://nusakura-stg.erp.thinkspedia.id — SSL ✓ |
| 2026-06-11 | Created platform/docs/dokploy-deployment.md — full deployment guide |
