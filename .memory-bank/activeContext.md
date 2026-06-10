# Active Context

## Current Session Focus (2026-06-10)
Dev stack is fully working. Session focused on developer workflow, tooling (adminer + mailpit),
versioning, and documentation. All items below are completed and documented.

## Current State of `platform/` Dev Stack

| Component | Status |
|---|---|
| `docker-compose.dev.yml` | Working — `frappe/bench` image, workspace mount, adminer + mailpit |
| `scripts/bootstrap.sh` | Working — idempotent, `webserver_port=80` (fixed email URL bug) |
| nginx reverse proxy | Working — routes `/socket.io/` → websocket, rest → frappe-web |
| Traefik | Working — file provider, carries `dev.localhost` network alias (moved from nginx) |
| MariaDB | Working — `--mariadb-user-host-login-scope=%` for container networking |
| Asset serving | Working — `bench serve` with SharedDataMiddleware for `/assets/` |
| WebSocket | Partially working — "Invalid origin" in dev only (Frappe bug, waived) |
| `platform/Makefile` | Complete — `make dev-start` prints all service URLs + credentials |
| Adminer | Working — http://localhost:8081, shows credentials from `.env` on startup |
| Mailpit | Working — http://localhost:8025, configured in ERPNext Email Account |
| Developer docs | Complete — `platform/docs/developer-workflow.md` |

## Known Open Issues (Dev Only — Not Production Blockers)
- **WebSocket "Invalid origin"**: Frappe's `authenticate.js` missing `return` after namespace check + doesn't handle absent `Origin` on same-origin polling. Does not affect prod. **Do not patch frappe source.**

## Architecture Decisions Made This Session

### Why `frappe/bench` over `frappe/erpnext` for dev
- `frappe/erpnext` has pre-installed apps but no bench CLI flexibility
- `frappe/bench` + `bench init` clones all apps fresh, handles pip+apps.txt atomically
- App source lives on host (`development/frappe-bench/apps/`) — directly editable

### Why workspace mount over per-app bind mounts
- Per-app bind mounts: Docker pre-creates dirs as root → git clone permission failures
- Workspace mount (`..:/workspace`): bench lives on host filesystem, edits are direct

### Why nginx in front of `bench serve`
- `bench serve` (werkzeug) does NOT proxy socket.io to port 9000
- nginx splits: `/socket.io/` → websocket:9000, rest → frappe-web:8001

### Why Traefik carries the `dev.localhost` alias (not nginx)
- `webserver_port=80` in common_site_config so Frappe email URLs are `http://dev.localhost` (no port suffix)
- Traefik listens on port 80 with the alias → websocket's `get_url()` resolves `dev.localhost:80` → Traefik → nginx → frappe-web
- Previously alias was on nginx (port 8000) which caused email links to incorrectly include `:8000`

### Mailpit dummy credentials required
- Frappe Email Account requires Login ID + Password even for servers with no auth
- `MP_SMTP_AUTH_ACCEPT_ANY=1` means any credentials are accepted
- Use `test` / `mailpit` — do not use Awaiting Password checkbox (send still fails)

## Developer Workflow
1. `cd platform && make dev-start` — starts full stack, prints all URLs + credentials
2. Edit code at `development/frappe-bench/apps/nusakura_app/` (on host, live reload)
3. Python changes: auto-reload via `bench serve`
4. JS/CSS changes: `bench build --app <app>` inside container
5. Version bump: `cd apps/<app> && make release-version [VERSION_BUMP=minor]`
6. Commit from inside each app directory (their own git repos)

## Next Recommended Actions
- [ ] Nomad HCL job spec (`platform/nomad/frappe.nomad.hcl`)
- [ ] Dokploy compose manifest (`platform/dokploy/dokploy.yml`)
- [ ] GitHub Actions CI for image build + push
- [ ] `org-bench` CLI polish (dev setup/start/new-app commands)
