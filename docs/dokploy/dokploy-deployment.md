# Dokploy Deployment Guide — Thinkspedia Frappe Platform

This guide documents the exact steps to deploy a new Frappe/ERPNext environment on Dokploy,
including every problem encountered and its solution. Follow this when setting up a new
environment (staging, production, or any client site).

---

## Prerequisites

| Item | Notes |
|------|-------|
| Dokploy instance running | `https://vps.thinkspedia.id` |
| Dokploy API token | Settings → Profile → API/CLI Keys |
| Harbor registry credentials | `registry.corp.thinkspedia.id/frappe/nusakura` |
| DNS A record pointing to VPS | e.g. `nusakura-stg.erp.thinkspedia.id` → VPS IP |
| Image already built and pushed | `make build-push tag=vX.Y.Z` |

---

## Step 1 — Create the Project in Dokploy UI

1. Dokploy UI → **Projects** → **New Project**
2. Name it to match your env file prefix, e.g. `nusakura-erp-stg`
3. Inside the project → **New Service** → **Docker Compose**
4. Set the source to **Git Repository** → point to `github.com/thinkspedia/frappe-platform`
5. Set the compose file path to `platform/dokploy/docker-compose.yml`

> **Do NOT click Deploy yet.** Configure the environment variables first.

---

## Step 2 — Environment Variables

Paste the contents of `platform/dokploy/.nusakura-erp-stg.thinkspedia.id.env` into the
Dokploy compose environment variables UI.

### Critical values to get right

```env
# These two MUST be identical strings — nginx selects the site by matching
# FRAPPE_SITE_NAME_HEADER against the sites/ directory name on disk.
FRAPPE_SITE_NAME_HEADER=nusakura-stg.erp.thinkspedia.id
SITE_NAME=nusakura-stg.erp.thinkspedia.id   # ← must match FRAPPE_SITE_NAME_HEADER exactly

SITE_HOST_NAME=https://nusakura-stg.erp.thinkspedia.id

# Published host port — 8088 because 8080 is taken by Traefik Dashboard on the VPS
HTTP_PUBLISH_PORT=8088
```

> **Gotcha — SITE_NAME vs FRAPPE_SITE_NAME_HEADER mismatch:**
> If these differ (e.g. `nusakura-erp.stg.thinkspedia.id` vs `nusakura-stg.erp.thinkspedia.id`),
> nginx will return 404 on every request because it looks for
> `sites/${FRAPPE_SITE_NAME_HEADER}/site_config.json` but bench created
> `sites/${SITE_NAME}/`. The site loads but nothing renders.

### First-deploy triggers

```env
CREATE_SITE=1       # provisions the Frappe site (bench new-site + app install)
MIGRATE=0
REGENERATE_APPS_TXT=1
```

---

## Step 3 — Deploy (First Time)

Click **Deploy** in Dokploy UI, or run:

```bash
cd platform
make push-deploy-dokploy tag=v1.0.1 env=stg
```

`create-site` installs all apps (`erpnext`, `hrms`, `offsite_backups`, `nusakura_app`,
`nusakura_waha_app`). This takes **5–15 minutes** on first run. Watch the logs in Dokploy UI
→ Logs → `create-site` container.

---

## Step 4 — Configure the Domain in Dokploy UI

Once the stack is running, add the domain:

**Dokploy UI → Project → Service → Domains → Add Domain**

| Field | Value |
|-------|-------|
| Service | Frontend |
| Host | `nusakura-stg.erp.thinkspedia.id` |
| Path | `/` |
| Internal Path | `/` |
| Strip Path | False |
| **Container Port** | **8080** |
| Custom Entrypoint | False |
| HTTPS | True |
| Certificate Provider | Let's Encrypt |
| Middlewares | None |

> **Gotcha — Container Port vs Host Port:**
> The `HTTP_PUBLISH_PORT=8088` in the env is the **host-published port** (used for direct
> VPS access). Dokploy's Traefik connects to the container via Docker's internal network,
> so it uses the container's actual listening port: **8080** (nginx inside the container).
> Entering 8088 here causes Traefik to silently fail to route — 404 on all requests.

> **Gotcha — Do NOT add Traefik labels to docker-compose.yml if using Dokploy UI domain:**
> Having both Traefik labels in the compose AND a Dokploy UI domain creates two conflicting
> routers for the same hostname. Use one approach only. This repo uses the **Dokploy UI domain**
> approach (labels are removed from the compose file).

---

## Step 5 — Reload Traefik

After saving the domain config, Traefik needs to pick up the new router:

**Dokploy UI → Settings → Traefik → Reload**

Without this step, requests to the domain return 404 even though the domain is configured.

---

## Step 6 — Verify Routing

```bash
# Should return 308 redirect to HTTPS
curl -I http://nusakura-stg.erp.thinkspedia.id/

# Should return 200
curl -I https://nusakura-stg.erp.thinkspedia.id/

# Direct nginx check via published host port (plain HTTP — no TLS here)
curl -I http://localhost:8088/api/v2/method/ping
```

---

## Step 7 — Reset One-Time Triggers

After `create-site` completes successfully, update the env in Dokploy UI and redeploy:

```env
CREATE_SITE=0
MIGRATE=0
```

> If you skip this, `create-site` will attempt to run on every future redeploy. It exits
> gracefully because the site already exists, but it's slow and noisy.

---

## Step 8 — Post-Install Frappe Configuration

After first login, set the home page values in the database. Without this,
`frappe.boot.home_page` is absent from the boot object and the JavaScript router
navigates to `/undefined`.

```bash
bench --site nusakura-stg.erp.thinkspedia.id console
```

```python
frappe.db.set_value('System Settings', 'System Settings', 'home_page', 'workspace')
frappe.db.set_value('Website Settings', 'Website Settings', 'home_page', 'login')
frappe.db.commit()
```

Then clear the cache:

```bash
bench --site nusakura-stg.erp.thinkspedia.id clear-cache
```

---

## Redeploy (Subsequent Deploys)

For all subsequent deploys (code changes, app updates):

```bash
# Push pre-built image and trigger redeploy (most common)
make push-deploy-dokploy tag=vX.Y.Z env=stg

# Build + push + redeploy in one step
make deploy-dokploy tag=vX.Y.Z env=stg

# Check deploy status
make dokploy-status env=stg
```

For migrations after an app update:

1. Set `MIGRATE=1` in Dokploy env → redeploy
2. Wait for migration to complete (watch `migration` container logs)
3. Set `MIGRATE=0` → redeploy again

---

## Troubleshooting

### 404 from Traefik (plain text, `Content-Type: text/plain`)

Traefik has no matching router for the hostname.

**Causes and fixes:**

| Cause | Fix |
|-------|-----|
| Dokploy domain not yet configured | Add domain in Dokploy UI (Step 4) |
| Traefik not reloaded after domain add | Reload Traefik in Dokploy UI (Step 5) |
| `frontend` container not on `default` network | Ensure `docker-compose.yml` frontend service includes `default` in its `networks` list |

> **Root cause of network issue:** Dokploy's Traefik runs on the `default` network. Containers
> must be on that same network to be reachable. The `frontend` service must have:
> ```yaml
> networks:
>   - bench-network
>   - default    # required for Traefik to reach the container
> ```

### 404 from nginx (HTML, `server: nginx/1.22.1`)

Traefik is routing correctly but nginx can't find the Frappe site.

**Causes and fixes:**

| Cause | Fix |
|-------|-----|
| `SITE_NAME` ≠ `FRAPPE_SITE_NAME_HEADER` | Make both values identical in the env file |
| `create-site` still running | Wait for it to finish (check container logs) |
| `create-site` ran with old `SITE_NAME`, then name changed | Drop the old DB and redeploy with `CREATE_SITE=1` |

**Drop the old database (if site was created with wrong name):**

```bash
docker exec -it $(docker ps --filter name=nusakura-erp-stg_db --format '{{.Names}}' | head -1) \
  mysql -uroot -p<DB_ROOT_PASSWORD> \
  -e "DROP DATABASE IF EXISTS \`<old_site_name_underscored>\`; \
      DROP USER IF EXISTS '<old_site_name_underscored>'@'%';"
```

### `GET /undefined` in browser console

`frappe.boot.home_page` is absent from the boot object (key not present, not just null).

```bash
bench --site <site> console
```
```python
# Check current values
print(frappe.db.get_value('System Settings', 'System Settings', 'home_page'))
print(frappe.db.get_value('Website Settings', 'Website Settings', 'home_page'))

# Fix
frappe.db.set_value('System Settings', 'System Settings', 'home_page', 'workspace')
frappe.db.set_value('Website Settings', 'Website Settings', 'home_page', 'login')
frappe.db.commit()
```

```bash
bench --site <site> clear-cache
```

### 308 redirect loop or HTTPS cert not issued

- Verify DNS A record is pointing to the correct VPS IP
- Check Let's Encrypt rate limits (5 failures per hour per domain)
- Confirm the domain is reachable on port 80 from the internet (Let's Encrypt HTTP-01 challenge)

### `create-site` keeps running on every deploy

`deploy.replicas: 0` only works in Docker Swarm mode. This repo uses env-var gating instead:
the service checks `CREATE_SITE != 1` at startup and exits immediately. If it's still running
when it shouldn't, verify `CREATE_SITE=0` is set in the Dokploy compose env.

---

## Environment File Reference

Full reference: `platform/dokploy/.nusakura-erp-stg.thinkspedia.id.env`

| Variable | Purpose | Notes |
|----------|---------|-------|
| `IMAGE_REGISTRY` | Registry path | `registry.corp.thinkspedia.id/frappe/nusakura` |
| `IMAGE_TAG` | Image version | Updated per deploy by `dokploy-deploy.sh` |
| `FRAPPE_SITE_NAME_HEADER` | nginx site selector | Must match `SITE_NAME` exactly |
| `SITE_NAME` | Bench site directory name | Must match `FRAPPE_SITE_NAME_HEADER` exactly |
| `SITE_HOST_NAME` | URL written to `site_config.json` | Used for email link generation |
| `HTTP_PUBLISH_PORT` | Host-published port | `8088` (8080 taken by Traefik Dashboard) |
| `DB_ROOT_PASSWORD` | MariaDB root password | Used by `create-site` and health checks |
| `ADMIN_PASSWORD` | ERPNext admin password | Used by `create-site` only |
| `INSTALL_APP_ARGS` | Apps to install on site creation | Space-separated `--install-app` flags |
| `GUNICORN_WORKERS` | Gunicorn process count | Formula: `(2 × CPU cores) + 1` |
| `CREATE_SITE` | Trigger: provision new site | Set to `1` first deploy, `0` after |
| `MIGRATE` | Trigger: run bench migrate | Set to `1` for app updates, `0` otherwise |

---

## CLI Automation Reference

All deploy commands are in `platform/Makefile`. Requires `platform/.env.stg` with
`DOKPLOY_SERVER`, `DOKPLOY_TOKEN`, and `DOKPLOY_PROJECT_NAME`.

```bash
make deploy-dokploy tag=v1.0.1 env=stg        # build + push + redeploy
make push-deploy-dokploy tag=v1.0.1 env=stg   # push existing image + redeploy
make dokploy-status env=stg                    # check current status
make build tag=v1.0.1                          # build locally only
make push tag=v1.0.1                           # push to registry only
make build-push tag=v1.0.1                     # build + push only (no deploy)
```
