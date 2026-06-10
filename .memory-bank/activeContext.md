# Active Context

## Current Session Focus (2026-06-10)
Building and debugging the `platform/` local development stack using `frappe/bench` image.
The dev stack is now functional — site accessible at `http://dev.localhost`.

## Current State of `platform/` Dev Stack

| Component | Status |
|---|---|
| `docker-compose.dev.yml` | Working — uses `frappe/bench` image, workspace mount |
| `scripts/bootstrap.sh` | Working — idempotent bench init + site creation |
| nginx reverse proxy | Working — routes `/socket.io/` → websocket, rest → frappe-web |
| Traefik | Working — file provider (avoids Docker Desktop socket issues) |
| MariaDB | Working — `--mariadb-user-host-login-scope=%` for container networking |
| Asset serving | Working — `bench serve` includes SharedDataMiddleware for `/assets/` |
| WebSocket | Partially working — "Invalid origin" error in dev only (known Frappe bug, waived) |
| `platform/Makefile` | Complete — all dev targets including mariadb, fixtures, get-app |

## Known Open Issues (Dev Only — Not Production Blockers)
- **WebSocket "Invalid origin"**: Frappe's `authenticate.js` has a missing `return` after namespace check + doesn't handle absent `Origin` on same-origin HTTP polling. Does not affect prod (nginx handles it differently). **Do not patch frappe source.**
- **`window.dev_server` behaviour**: When true, socket.io appends `socketio_port` (9000) to host. When false (default in our setup), connects without port through nginx correctly.

## Architecture Decisions Made This Session

### Why `frappe/bench` over `frappe/erpnext` for dev
- `frappe/erpnext` has pre-installed apps but no bench CLI flexibility
- `frappe/bench` + `bench init` clones all apps fresh, handles pip+apps.txt atomically
- App source lives on host (`development/frappe-bench/apps/`) — directly editable, no bind-mount conflicts

### Why workspace mount over per-app bind mounts
- Per-app bind mounts: Docker pre-creates dirs as root → git clone permission failures
- Workspace mount (`..:/workspace`): bench lives on host filesystem, edits are direct

### Why nginx in front of `bench serve`
- `bench serve` (werkzeug) does NOT proxy socket.io to port 9000
- nginx splits: `/socket.io/` → websocket:9000, rest → frappe-web:8001
- nginx has Docker network alias `dev.localhost` so websocket can resolve it internally for API auth calls

### Why Traefik uses file provider (not Docker provider)
- Docker Desktop (WSL2 + macOS) blocks the `/events` stream the Docker provider needs
- File provider with `traefik/routes.yml` works identically on all platforms

### `webserver_port = 8000` in common_site_config
- Frappe's `realtime/utils.js` `get_url()` appends this port to origin URL for API auth calls in dev mode
- Must match nginx's internal container port (8000) since nginx has the `dev.localhost` alias

## Developer Workflow
1. `cd platform && make dev-start` — starts full stack (bootstraps on first run)
2. Edit code at `development/frappe-bench/apps/nusakura_app/` (on host, changes live)
3. Python changes: auto-reload via `bench serve`
4. JS/CSS changes: `make dev-clear-cache` + rebuild assets
5. Commit from inside each app directory (their own git repos)
6. `apps.json` is source of truth for app versions in both dev and prod

## Next Recommended Actions
- [ ] Production Dockerfile refinement (multi-stage, frappe/build + frappe/base)
- [ ] Nomad HCL job spec (`platform/nomad/frappe.nomad.hcl`)
- [ ] Dokploy compose manifest (`platform/dokploy/dokploy.yml`)
- [ ] GitHub Actions CI for `org-bench build --push`
- [ ] `org-bench` CLI polish (dev setup/start/new-app commands)
