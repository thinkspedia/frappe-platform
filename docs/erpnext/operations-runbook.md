# ERPNext Operations Runbook

Operational reference for backup, restore, and common issue resolution on the Thinkspedia ERPNext platform.

**Environment covered:** Dokploy VPS (`vps.thinkspedia.id` / Netbird `100.85.203.161`), staging site `nusakura-stg.erp.thinkspedia.id`.

---

## Table of Contents

1. [Environment Reference](#1-environment-reference)
2. [Backup](#2-backup)
3. [Restore](#3-restore)
4. [Post-Restore Checklist](#4-post-restore-checklist)
5. [Common Issues & Fixes](#5-common-issues--fixes)
6. [Useful bench Commands](#6-useful-bench-commands)

---

## 1. Environment Reference

### Access

| Target | Address | SSH User | Key |
|--------|---------|----------|-----|
| Dokploy VPS | `100.85.203.161` (Netbird) | `opsadmin` | `/run/keys/id_ansible` |
| Source VM (artavica) | `100.85.56.146` (Netbird) | `opsadmin` | `/run/keys/id_ansible` |

```bash
# VPS
ssh -i /run/keys/id_ansible opsadmin@100.85.203.161

# Source VM
ssh -i /run/keys/id_ansible opsadmin@100.85.56.146
```

### Container Names (Dokploy VPS)

```bash
# List all running containers
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"

# Find backend container specifically
docker ps --format "table {{.Names}}\t{{.Image}}" | grep backend
```

| Service | Container pattern | Notes |
|---------|-------------------|-------|
| Backend (bench) | `<stack>-backend-1` | Runs bench CLI, bench console, workers |
| Frontend (nginx) | `<stack>-frontend-1` | Serves HTTP, Traefik routes here |
| MariaDB | `<stack>-db-1` | Database |
| Redis | `<stack>-redis-*` | Cache / queue / socketio |

### Site Names

| Environment | Site name |
|-------------|-----------|
| Staging | `nusakura-stg.erp.thinkspedia.id` |

### Bench Root (inside backend container)

```
/home/frappe/frappe-bench/
  sites/<site-name>/
    site_config.json          # DB credentials, bench config
    private/backups/          # Backup output directory
    private/files/            # Private file attachments
    public/files/             # Public file attachments
```

---

## 2. Backup

### 2.1 On-Demand Backup (Dokploy VPS)

```bash
# SSH into VPS
ssh -i /run/keys/id_ansible opsadmin@100.85.203.161

# Run backup inside backend container
BACKEND=$(docker ps --format "{{.Names}}" | grep backend | head -1)
SITE="nusakura-stg.erp.thinkspedia.id"

docker exec $BACKEND bash -c "
  cd /home/frappe/frappe-bench &&
  bench --site $SITE backup --with-files
"
```

Output confirms 3 files created inside the container at:
```
sites/<site>/private/backups/<YYYYMMDD_HHMMSS>-<site_slug>-database.sql.gz
sites/<site>/private/backups/<YYYYMMDD_HHMMSS>-<site_slug>-files.tar
sites/<site>/private/backups/<YYYYMMDD_HHMMSS>-<site_slug>-private-files.tar
```

> **Note:** Files archives are plain `.tar` (not `.tar.gz`). This is normal.

### 2.2 Copy Backup Out of Container to VPS Host

```bash
BACKUP_DIR="/home/frappe/frappe-bench/sites/$SITE/private/backups"
HOST_DIR="/home/opsadmin/backup"

mkdir -p $HOST_DIR
docker cp ${BACKEND}:${BACKUP_DIR}/. $HOST_DIR/

ls -lh $HOST_DIR/
```

### 2.3 Backup from a Source VM Running Frappe in Docker

```bash
# SSH into source VM
ssh -i /run/keys/id_ansible opsadmin@100.85.56.146

# Identify container
docker ps --format "table {{.Names}}\t{{.Image}}" | grep backend

# Run backup inside container
docker exec <BACKEND_CONTAINER> bash -c "
  cd /home/frappe/frappe-bench &&
  bench --site stg-erp-nusakura.artavica.com backup --with-files
"

# Copy backup files out of container
mkdir -p /home/opsadmin/backup
docker cp <BACKEND_CONTAINER>:/home/frappe/frappe-bench/sites/stg-erp-nusakura.artavica.com/private/backups/. \
  /home/opsadmin/backup/

ls -lh /home/opsadmin/backup/
```

### 2.4 Transfer Backup to Dokploy VPS

```bash
# From your local machine (Netbird connected to both)
SRC="opsadmin@100.85.56.146"
SRC_KEY="/run/keys/id_ansible"
VPS="opsadmin@100.85.203.161"
TS="<YYYYMMDD_HHMMSS>"
PREFIX="${TS}-stg-erp-nusakura_artavica_com"

ssh -i $SRC_KEY $VPS "mkdir -p /tmp/frappe-restore"

scp -i $SRC_KEY \
  ${SRC}:/home/opsadmin/backup/${PREFIX}-database.sql.gz \
  ${SRC}:/home/opsadmin/backup/${PREFIX}-files.tar \
  ${SRC}:/home/opsadmin/backup/${PREFIX}-private-files.tar \
  ${SRC}:/home/opsadmin/backup/${PREFIX}-site_config_backup.json \
  ${VPS}:/tmp/frappe-restore/

# Verify
ssh -i $SRC_KEY $VPS "ls -lh /tmp/frappe-restore/"
```

> **If direct SCP between servers is blocked:** SCP to your local machine first, then SCP to VPS.

---

## 3. Restore

### 3.1 Copy Backup Files into the Backend Container

```bash
# On Dokploy VPS
BACKEND=$(docker ps --format "{{.Names}}" | grep backend | head -1)
SITE="nusakura-stg.erp.thinkspedia.id"
RESTORE_DIR="/home/frappe/frappe-bench/sites/${SITE}/private/backups"
TS="<YYYYMMDD_HHMMSS>"
PREFIX="${TS}-stg-erp-nusakura_artavica_com"

docker exec $BACKEND mkdir -p $RESTORE_DIR

for FILE in database.sql.gz files.tar private-files.tar site_config_backup.json; do
  docker cp /tmp/frappe-restore/${PREFIX}-${FILE} ${BACKEND}:${RESTORE_DIR}/
done

# Verify
docker exec $BACKEND ls -lh $RESTORE_DIR
```

### 3.2 Run bench restore

```bash
docker exec -it $BACKEND bash

# Inside container:
TS="<YYYYMMDD_HHMMSS>"
SITE="nusakura-stg.erp.thinkspedia.id"
PREFIX="sites/${SITE}/private/backups/${TS}-stg-erp-nusakura_artavica_com"

bench --site $SITE restore \
  ${PREFIX}-database.sql.gz \
  --with-public-files  ${PREFIX}-files.tar \
  --with-private-files ${PREFIX}-private-files.tar
```

Expected final line:
```
Site nusakura-stg.erp.thinkspedia.id has been restored with files
```

> **If you see `Access denied` or MySQL auth errors:** DB credentials in `sites/<site>/site_config.json` must match the running MariaDB. Check `cat sites/$SITE/site_config.json` and compare `db_name` / `db_password` against compose env vars.

---

## 4. Post-Restore Checklist

Run these every time after a restore. The restored DB carries the old site's hostname and settings.

### 4.1 Fix hostname and home_page

```bash
docker exec -it $BACKEND bash -c \
  "cd /home/frappe/frappe-bench && bench --site $SITE console"
```

Inside bench console:

```python
# Update hostname to this environment's domain
frappe.db.set_value('System Settings', 'System Settings', 'host_name', 'https://nusakura-stg.erp.thinkspedia.id')

# Prevent /undefined routing error (NULL home_page → JS undefined → router goes to /undefined)
frappe.db.set_value('System Settings', 'System Settings', 'home_page', 'workspace')
frappe.db.set_value('Website Settings', 'Website Settings', 'home_page', 'login')

frappe.db.commit()
exit()
```

### 4.2 Fix Administrator roles ("Not Permitted" error)

Restore strips the Administrator user's roles. Symptoms: login succeeds but every page shows **"Not Permitted / You are not permitted to access this page."**

```bash
docker exec -it $BACKEND bash -c \
  "cd /home/frappe/frappe-bench && bench --site $SITE console"
```

```python
frappe.db.set_value('User', 'Administrator', 'user_type', 'System User')
user = frappe.get_doc('User', 'Administrator')
user.add_roles('System Manager', 'Administrator')
frappe.db.commit()
exit()
```

If still blocked after re-login, run migrate to re-sync all roles from installed apps:

```bash
docker exec $BACKEND bash -c \
  "cd /home/frappe/frappe-bench && bench --site $SITE migrate"
```

### 4.3 Clear cache

```bash
docker exec $BACKEND bash -c \
  "cd /home/frappe/frappe-bench && bench --site $SITE clear-cache"
```

### 4.4 Reload Traefik

In browser: `https://vps.thinkspedia.id` → **Settings → Traefik → Reload**

Required after any domain or routing change so Traefik picks up new router config.

### 4.5 Verify

- [ ] `https://nusakura-stg.erp.thinkspedia.id` shows login page (not 404, not blank)
- [ ] Login with username `Administrator` + known password (see §5.1 if password unknown)
- [ ] Check a few records (customers, items, GL entries) — confirms DB restore
- [ ] Open a file attachment — confirms files restore
- [ ] Browser DevTools Console — no `GET /undefined` errors
- [ ] ERPNext → Settings → Error Log — no unexpected new errors

---

## 5. Common Issues & Fixes

### 5.1 Administrator password unknown

If the Administrator email was changed on the source site and the password is unknown:

```bash
docker exec $BACKEND bash -c \
  "cd /home/frappe/frappe-bench && bench --site $SITE set-admin-password newpassword123"
```

Log in with:
- **User:** `Administrator` (the username — not the email)
- **Password:** `newpassword123`

> The Administrator user does not appear in the normal Users list. To find it: ERPNext → Settings → Users → filter **System User = Yes**.

### 5.2 "Not Permitted" after login

Administrator user lost its roles (common after restore or migration).

```bash
docker exec -it $BACKEND bash -c \
  "cd /home/frappe/frappe-bench && bench --site $SITE console"
```

```python
frappe.db.set_value('User', 'Administrator', 'user_type', 'System User')
user = frappe.get_doc('User', 'Administrator')
user.add_roles('System Manager', 'Administrator')
frappe.db.commit()
exit()
```

```bash
docker exec $BACKEND bash -c \
  "cd /home/frappe/frappe-bench && bench --site $SITE clear-cache"
```

If still broken:

```bash
docker exec $BACKEND bash -c \
  "cd /home/frappe/frappe-bench && bench --site $SITE migrate"
```

### 5.3 Browser navigates to `/undefined`

`System Settings.home_page` is NULL — Frappe omits it from the boot JSON, JS reads it as `undefined`.

```bash
docker exec -it $BACKEND bash -c \
  "cd /home/frappe/frappe-bench && bench --site $SITE console"
```

```python
frappe.db.set_value('System Settings', 'System Settings', 'home_page', 'workspace')
frappe.db.set_value('Website Settings', 'Website Settings', 'home_page', 'login')
frappe.db.commit()
exit()
```

> **Note:** `bench --site <site> set-config home_page workspace` does NOT fix this. Frappe v15/v16 reads this value from the DB, not `site_config.json`. Must use `frappe.db.set_value` in bench console.

### 5.4 Traefik 404 on all routes

Symptoms: site URL returns Traefik 404 ("404 page not found").

Check in order:

1. **Traefik not reloaded** — Dokploy UI → Settings → Traefik → Reload
2. **Frontend not on `default` network** — Traefik can only proxy containers on its own network. Check `platform/dokploy/docker-compose.yml`: `frontend` service must list both `bench-network` and `default` under `networks`.
3. **Wrong container port** — Dokploy UI domain config "Container Port" must be `8080` (nginx internal port), NOT `8088` (host-published port).
4. **`SITE_NAME` ≠ `FRAPPE_SITE_NAME_HEADER`** — nginx looks up `sites/${FRAPPE_SITE_NAME_HEADER}/site_config.json`. Any mismatch → 404 on all requests even if the site exists.

### 5.5 Stack won't start / container keeps restarting

```bash
# Check logs for all services
docker compose -f /path/to/docker-compose.yml logs --tail=50

# Check specific container
docker logs <BACKEND_CONTAINER> --tail=100
```

Common causes:
- MariaDB not ready when backend starts — wait and check `docker logs <db-container>`
- Missing env vars — compare running compose env against `platform/dokploy/compose.env.example`
- Site doesn't exist yet — if `CREATE_SITE=1` was never set, the site was never created

### 5.6 `bench restore` fails with "Access denied"

The backup was created with different DB credentials than the target site.

```bash
# Check target site DB credentials
docker exec $BACKEND cat /home/frappe/frappe-bench/sites/$SITE/site_config.json
```

The `db_name` and `db_password` in `site_config.json` must match the MariaDB user that exists in the running MariaDB container. If they don't match, the restore is trying to auth with wrong credentials.

Options:
- Use `--force` flag on `bench restore` to let bench recreate the DB user
- Or update `site_config.json` to match the target DB credentials before restoring

### 5.7 Can't pull image on Dokploy VPS (Harbor registry)

```bash
# Check Docker can reach registry
docker pull registry.corp.thinkspedia.id/frappe/nusakura/nusakuraerp:v1.0.1
```

If it fails with certificate error:
```bash
# Install internal CA cert
sudo mkdir -p /etc/docker/certs.d/registry.corp.thinkspedia.id
sudo cp /path/to/ca.crt /etc/docker/certs.d/registry.corp.thinkspedia.id/ca.crt
# No Docker daemon restart needed
```

Also confirm registry credentials are added in Dokploy UI → **Settings → Registries**.

---

## 6. Useful bench Commands

All commands run inside the backend container:

```bash
docker exec -it $BACKEND bash
cd /home/frappe/frappe-bench
```

| Task | Command |
|------|---------|
| Open Python console | `bench --site $SITE console` |
| Open shell in bench | `bench --site $SITE execute frappe.utils.shell` |
| Clear cache | `bench --site $SITE clear-cache` |
| Run DB migrations | `bench --site $SITE migrate` |
| Reset admin password | `bench --site $SITE set-admin-password <password>` |
| Take backup (DB only) | `bench --site $SITE backup` |
| Take backup (DB + files) | `bench --site $SITE backup --with-files` |
| Restore from backup | `bench --site $SITE restore <db.sql.gz> --with-public-files <files.tar> --with-private-files <private-files.tar>` |
| Check scheduler status | `bench --site $SITE scheduler status` |
| Enable scheduler | `bench --site $SITE scheduler enable` |
| Rebuild search index | `bench --site $SITE build-search-index` |
| List installed apps | `bench --site $SITE list-apps` |
| Show site config | `cat sites/$SITE/site_config.json` |
| Show common config | `cat sites/common_site_config.json` |

### Useful bench console one-liners

```python
# Check current System Settings values
frappe.get_doc('System Settings', 'System Settings').as_dict()

# Check user roles
frappe.get_roles('Administrator')

# Reload a doctype from source
frappe.reload_doc('core', 'doctype', 'user')

# Check installed apps
frappe.get_installed_apps()

# Run a background job immediately
frappe.enqueue('frappe.utils.background_jobs.execute_job', queue='short')
```
