# Active Context

## Current State (2026-06-11)

The platform is fully working end-to-end for both local development and Dokploy production
deployment. The staging site `nusakura-stg.erp.thinkspedia.id` is live with SSL and fully
accessible. Deployment guide documented at `platform/docs/dokploy-deployment.md`.

## What Was Just Completed

### ERPNext Site Migration: stg-erp-nusakura.artavica.com → nusakura-stg.erp.thinkspedia.id (2026-06-11)

Full backup and restore of an existing ERPNext site onto the Dokploy VPS. Completed successfully.

**Steps performed:**
1. `docker cp` backup files out of source container (`nsk-backend-1`) to host `/home/opsadmin/backup/`
2. SCP 4 files to Dokploy VPS via Netbird (`100.85.56.146` → `100.85.203.161`) using `opsadmin` + `/run/keys/id_ansible`
3. `docker cp` files into target backend container's `private/backups/` dir
4. `bench --site nusakura-stg.erp.thinkspedia.id restore <db.gz> --with-public-files <files.tar> --with-private-files <private-files.tar>`
5. Post-restore bench console fixes: `host_name`, `home_page` (System + Website Settings), clear-cache, Traefik reload
6. Fixed Administrator "Not Permitted" error — roles stripped during restore, re-added via bench console

**Key discovery — Administrator "Not Permitted" after restore:**
The Administrator user exists after restore but loses its roles. Fix:
```python
frappe.db.set_value('User', 'Administrator', 'user_type', 'System User')
user = frappe.get_doc('User', 'Administrator')
user.add_roles('System Manager', 'Administrator')
frappe.db.commit()
```
Then `bench --site <site> clear-cache`. If still broken: `bench --site <site> migrate`.

**Backup file format:** Frappe produces `.tar` (not `.tar.gz`) for files archives. `bench restore` handles both — pass as-is.

**Runbook saved at:** `docs/superpowers/plans/2026-06-11-erpnext-backup-restore-stg.md`

### Dokploy Production Deployment Pipeline
- `make deploy-dokploy tag=v1.0.0` — full build + push + redeploy in one command
- `make push-deploy-dokploy tag=v1.0.0` — push pre-built image + redeploy (skip rebuild)
- `make build` / `make push` / `make build-push` — granular build/push control
- `make dokploy-status` — check live Dokploy compose status

**Fixes discovered during first deploy (2026-06-11 session):**
- Dokploy API uses `x-api-key` header, NOT `Authorization: Bearer`
- `compose.all` endpoint does not exist — compose services are nested under `project.all` → `environments[].compose[]`
- Harbor registry (`registry.corp.thinkspedia.id`) uses internal CA — VPS Docker daemon needs `/etc/docker/certs.d/<registry>/ca.crt` installed
- Dokploy must have the registry credentials configured under Settings → Registries
- Traefik labels in compose + Dokploy UI domain = conflicting routers → removed labels, use Dokploy UI domain only
- `frontend` service must be on `default` network (not just `bench-network`) — Traefik can only route to containers on its own network
- `deploy.replicas: 0` is Swarm-only — replaced with env-var gate (`CREATE_SITE != 1`) inside the command
- `SITE_NAME` must exactly match `FRAPPE_SITE_NAME_HEADER` — nginx looks up `sites/${FRAPPE_SITE_NAME_HEADER}/` on disk
- Dokploy UI domain "Container Port" = container's internal port (8080), NOT the host-published port (8088)
- After adding domain in Dokploy UI, must manually reload Traefik (Settings → Traefik → Reload)
- After first site creation, must set `home_page` in System Settings and Website Settings via bench console or `/undefined` navigation error occurs in the browser

**Staging deployment confirmed working:**
- Project: `nusakura-erp-stg` (composeId: `unDMPJe63QFy24yqw2RsY`)
- Image: `registry.corp.thinkspedia.id/frappe/nusakura/nusakuraerp:v1.0.1`
- URL: `https://nusakura-stg.erp.thinkspedia.id` — SSL via Let's Encrypt ✓
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
- [ ] Resolve `GET /undefined` console error (desk:124 — likely a custom app hook registering a missing JS bundle)
- [ ] `platform/nomad/frappe.nomad.hcl` — Nomad job spec (prestart migrate, zero-downtime)
- [ ] GitHub Actions CI — automated image build + push to Harbor on tag push
- [ ] Production environment (separate from staging) — `nusakura-erp-prod`
- [ ] `platform/cli/` — org-bench CLI (dev setup / build / deploy commands)
