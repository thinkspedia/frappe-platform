# Active Context

## Current State (2026-06-10)

The platform is fully working end-to-end for local development. The entire developer
experience is documented, the VSCode setup is auto-configured, and the GitHub repos
are clean and published.

## What Was Just Completed

### Developer Workflow
- `platform/docs/developer-workflow.md` is the source of truth for all dev scenarios
- All `git push/pull origin` corrected to `upstream` throughout the doc
- App-level Makefile targets documented as the primary workflow (no directory switching)
- `make code APP=<name>` shortcut documented

### VSCode + WSL2 IntelliSense Setup
- Discovered: bench venv `python` symlinks to `/home/frappe/.pyenv/...` (container-only path)
- Fix: install pyenv + Python 3.14.2 on WSL2 (with build deps)
- Both app repos' `.vscode/settings.json` updated to:
  - `python.defaultInterpreterPath`: `~/.pyenv/versions/3.14.2/bin/python3`
  - `python-envs.defaultEnvManager`: `ms-python.python:pyenv`
- WSL2 setup now: install deps → pyenv install → `/workspace` symlink → `make code APP=<name>`
- No manual VSCode interpreter selection needed
- Committed and pushed to both app repos

### Repo Cleanup
- Removed all 130 upstream `frappe_docker` files from the repo root
- `README.md` completely rewritten for Thinkspedia Frappe Platform
- `.gitignore` cleaned up
- Platform repo pushed to `git@github.com:thinkspedia/frappe-platform.git`

## Current Dev Stack State

| Component | Status |
|---|---|
| `docker-compose.dev.yml` | Working |
| `scripts/bootstrap.sh` | Working — idempotent, `webserver_port=80` |
| nginx | Working — web/socket routing |
| Traefik | Working — file provider, `dev.localhost` alias |
| MariaDB | Working |
| Asset serving | Working |
| Adminer | Working — http://localhost:8081 |
| Mailpit | Working — http://localhost:8025, configured in ERPNext |
| Email URLs | Working — `http://dev.localhost` (no `:8000` bug) |
| App Makefiles | Working — both app repos have full target set |
| VSCode config | Working — committed to both app repos, auto-configures on open |
| Versioning | Working — `make release-version` in both apps |
| Developer docs | Complete — `platform/docs/developer-workflow.md` |

## Known Open Issues (Dev Only — Not Production Blockers)
- **WebSocket "Invalid origin"**: Frappe's `authenticate.js` bug — does not affect prod.
  Do not patch `frappe/` source.

## Next Recommended Actions
- [ ] `platform/nomad/frappe.nomad.hcl` — Nomad job spec (prestart migrate, zero-downtime)
- [ ] `platform/dokploy/dokploy.yml` — Dokploy compose manifest
- [ ] GitHub Actions CI for image build + push to Harbor registry
- [ ] Production environment `.env` and deployment docs
- [ ] `platform/cli/` — org-bench CLI (dev setup / build / deploy commands)
