# Active Context

## Current State (2026-06-11)

The platform is fully working end-to-end for both local development and Dokploy production
deployment. The first successful deployment to `nusakura-erp-stg` was completed today.

## What Was Just Completed

### Dokploy Production Deployment Pipeline
- `make deploy-dokploy tag=v1.0.0` — full build + push + redeploy in one command
- `make push-deploy-dokploy tag=v1.0.0` — push pre-built image + redeploy (skip rebuild)
- `make build` / `make push` / `make build-push` — granular build/push control
- `make dokploy-status` — check live Dokploy compose status

**Fixes discovered during first deploy:**
- Dokploy API uses `x-api-key` header, NOT `Authorization: Bearer`
- `compose.all` endpoint does not exist — compose services are nested under `project.all` → `environments[].compose[]`
- Harbor registry (`registry.corp.thinkspedia.id`) uses internal CA — VPS Docker daemon needs `/etc/docker/certs.d/<registry>/ca.crt` installed
- Dokploy must have the registry credentials configured under Settings → Registries

**Staging deployment confirmed working:**
- Project: `nusakura-erp-stg` (projectId: `5lDuFK1Ht5u7DqGKwsy1u`)
- Compose: `ERPNext App` (composeId: `gFL17GQy7kJI-RzFev-lo`)
- Image: `registry.corp.thinkspedia.id/frappe/nusakura/nusakuraerp:v1.0.0`
- Status: `running` ✓

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
- [ ] GitHub Actions CI — automated image build + push to Harbor on tag push
- [ ] Production environment (separate from staging) — `nusakura-erp-prod`
- [ ] `make prod-new-site` — run once to bootstrap the staging site in Dokploy
- [ ] `platform/cli/` — org-bench CLI (dev setup / build / deploy commands)
- [ ] Document Dokploy VPS CA cert setup in `developer-workflow.md`
