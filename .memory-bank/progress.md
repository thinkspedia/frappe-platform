# Progress

## What Is Working (Confirmed)

### Upstream Repo Infrastructure
- [x] Full repository structure documented in AGENTS.md
- [x] 18 override files present and documented
- [x] CI/CD workflows (12 total) present and categorised
- [x] Test suite (`tests/`) with conftest, fixtures, integration tests
- [x] Pre-commit hooks configured

### Platform Layer (`platform/`) — 2026-06-10
- [x] `platform/Dockerfile` — multi-stage production image (frappe/build + frappe/base)
- [x] `platform/apps.json` — app registry: erpnext, hrms, offsite_backups, nusakura_app, nusakura_waha_app
- [x] `platform/.env.example` — complete source of truth for all config
- [x] `platform/docker-compose.dev.yml` — full local dev stack with adminer + mailpit (tools profile)
- [x] `platform/scripts/bootstrap.sh` — idempotent bench init + site creation (`webserver_port=80`)
- [x] `platform/scripts/configure-site.sh` — writes host_name to site_config
- [x] `platform/scripts/mariadb.cnf` — Frappe-compatible MariaDB config
- [x] `platform/nginx/dev.conf` — routes /socket.io/ and web traffic
- [x] `platform/traefik/routes.yml` — file-provider static routes
- [x] `platform/Makefile` — full dev/build/deploy target set, startup prints all URLs + credentials
- [x] `platform/docs/developer-workflow.md` — developer workflow source of truth

### Dev Stack Verified Working
- [x] `http://dev.localhost` accessible in browser
- [x] Login page renders with compiled assets (JS/CSS bundles)
- [x] Bootstrap: bench init, bench get-app, bench new-site, bench build all succeed
- [x] MariaDB user created with `%` host scope (container networking works)
- [x] Asset symlinks work inside container via `bench serve` SharedDataMiddleware
- [x] Traefik file provider eliminates Docker Desktop socket errors
- [x] nginx splits web/socket.io traffic correctly
- [x] Adminer accessible at http://localhost:8081
- [x] Mailpit accessible at http://localhost:8025, email trap configured in ERPNext
- [x] Email URLs generate as `http://dev.localhost` (no `:8000` port bug)

### App Versioning — 2026-06-10
- [x] `nusakura_app` — `Makefile` + `scripts/bump_version.py` (Conventional Commits auto-detect)
- [x] `nusakura_waha_app` — same setup copied over

## What Is Partially Working
- [~] **WebSocket real-time**: "Invalid origin" in dev only (Frappe bug, waived)
  - Root cause: `authenticate.js` missing `return` + browsers omit `Origin` on same-origin polling
  - Does not affect staging/production. **Do NOT patch frappe/erpnext source.**

## What Is Planned But Not Yet Implemented
- [ ] `platform/nomad/frappe.nomad.hcl` — Nomad job spec (prestart migrate, zero-downtime)
- [ ] `platform/dokploy/dokploy.yml` — Dokploy compose manifest
- [ ] `platform/cli/` — org-bench CLI (dev setup/start/build/deploy commands)
- [ ] GitHub Actions CI for `org-bench build --push`
- [ ] End-to-end staging deployment test

## Known Constraints and Gotchas

### Platform Layer
1. **`make dev-destroy` must remove bench dir** — `rm -rf ../development/frappe-bench` in addition to `docker compose down -v`. Without this, stale site_config.json causes bootstrap to skip new-site after MariaDB volume wipe.
2. **`bench build` requires nvm** — source `/home/frappe/.nvm/nvm.sh` explicitly in non-interactive scripts before running bench build.
3. **Asset symlinks use absolute container paths** — broken on host (`/workspace/...` doesn't exist on host), valid inside container. Expected and harmless.
4. **`host_name` must be in common_site_config** — socketio reads global config, not site config. `bench --site X set-config` goes to site_config; `bench set-config -g` goes to common_site_config.
5. **`webserver_port = 80`** — must match the public entry point (Traefik:80). Setting to 8000 causes Frappe email URLs to include `:8000`. The `dev.localhost` alias is on Traefik (not nginx) so `dev.localhost:80` resolves correctly inside Docker for socketio API calls.
6. **`--mariadb-user-host-login-scope=%`** — required on `bench new-site` for Docker container networking.
7. **GITHUB_TOKEN for private repos** — injected into clone URL at runtime, never stored.
8. **`frappe` and `erpnext` are BUNDLED** — skip in get-app loop; bench init installs frappe, erpnext is in apps.json for bench get-app.
9. **Mailpit Email Account requires dummy credentials** — use Login ID: `test`, Password: `mailpit`. Do NOT use Awaiting Password (bypasses save but fails at send time).
10. **`dev.localhost` alias on Traefik, NOT nginx** — intentional. Traefik is port 80 = `webserver_port`. Moving it back to nginx would re-introduce the `:8000` email URL bug.

### Upstream Repo
9. **`pwd.yml` is auto-generated** — never edit manually
10. **`CLAUDE.md` gets rewritten by hook** — maintain `AGENTS.md` as source of truth
11. **Tests require live Docker stack** — `pytest tests/` fails without services running
12. **Nomad host volume `frappe_sites` must be pre-created** on each Nomad client node

## Session History
| Date | Action |
|---|---|
| 2026-06-10 | Initial CLAUDE.md + Memory Bank initialized |
| 2026-06-10 | `platform/` system designed and implemented (frappe/erpnext based) |
| 2026-06-10 | Switched to `frappe/bench` image — resolved pip/bind-mount/apps.txt issues |
| 2026-06-10 | Fixed: externally-managed-environment, PLATFORM_DIR, pyproject.toml build-backend |
| 2026-06-10 | Fixed: WSL2 file bind-mounts, bench get-app TTY prompts, bind-mount ownership |
| 2026-06-10 | Fixed: MariaDB user host scope, asset 404s, nginx routing, Traefik file provider |
| 2026-06-10 | Fixed: webserver_port + nginx alias → socketio internal API calls working |
| 2026-06-10 | WebSocket "Invalid origin" waived — dev-only Frappe quirk, not a prod issue |
| 2026-06-10 | Makefile extended: mariadb console, export-fixtures, get-app targets |
| 2026-06-10 | Added adminer + mailpit optional tools (profile: tools, default enabled) |
| 2026-06-10 | Added versioning (Makefile + bump_version.py) to nusakura_app + nusakura_waha_app |
| 2026-06-10 | Created `platform/docs/developer-workflow.md` — full dev workflow source of truth |
| 2026-06-10 | Fixed email URL bug: moved `dev.localhost` alias to Traefik, set webserver_port=80 |
| 2026-06-10 | Documented Mailpit ERPNext setup (dummy creds required, Awaiting Password pitfall) |
