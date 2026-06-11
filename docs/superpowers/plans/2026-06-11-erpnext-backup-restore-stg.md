# ERPNext Backup & Restore: stg-erp-nusakura.artavica.com → nusakura-stg.erp.thinkspedia.id

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Full backup of ERPNext site `stg-erp-nusakura.artavica.com` from a source VM (SSH via private key, Netbird IP `100.85.56.146`) and restore onto the running Dokploy stack at `nusakura-stg.erp.thinkspedia.id`.

**Architecture:** Frappe's `bench backup --with-files` produces 4 artifacts (database SQL gz, private files tar, public files tar, site_config json). These are transferred to the Dokploy VPS, copied into the running `backend` container, and restored via `bench restore`. Post-restore steps re-point the site name to the new hostname and fix known Dokploy gotchas.

**Tech Stack:** Frappe v15 / ERPNext `v1.3.12`, bench CLI, Docker / docker exec, SSH/SCP, Dokploy VPS (`vps.thinkspedia.id`), Traefik.

---

## Known Facts (confirmed from source VM)

| Item | Value |
|------|-------|
| Source VM SSH user | `opsadmin` |
| Source VM IP (Netbird) | `100.85.56.146` |
| Backup host dir (source VM) | `/home/opsadmin/backup/` |
| Backend container name (source) | `nsk-backend-1` |
| Source image | `registry.corp.thinkspedia.id/erpnext/nusakuraerp:v1.3.12` |
| Backup timestamp | `20260611_175254` |
| Database backup | `20260611_175254-stg-erp-nusakura_artavica_com-database.sql.gz` (3.3 MB) |
| Public files backup | `20260611_175254-stg-erp-nusakura_artavica_com-files.tar` (290 KB) |
| Private files backup | `20260611_175254-stg-erp-nusakura_artavica_com-private-files.tar` (6.2 MB) |
| Site config backup | `20260611_175254-stg-erp-nusakura_artavica_com-site_config_backup.json` |

> **Note:** Files archives are plain `.tar` (not `.tar.gz`). `bench restore` handles this correctly — pass them as-is.

---

## Prerequisites Checklist (confirm before starting)

- [x] ~~Task 1 complete~~ — backup files are on source VM at `/home/opsadmin/backup/`
- [x] SSH access to Dokploy VPS confirmed — `opsadmin@100.85.203.161`
- [x] Target site `nusakura-stg.erp.thinkspedia.id` was up and running before restore.
- [x] Disk space sufficient — total backup 9.7 MB, no issues.

---

## ~~Task 1: Take a Full Backup on the Source VM~~ ✅ DONE

Backup was run inside container `nsk-backend-1` and copied to host via:
```bash
docker cp nsk-backend-1:/home/frappe/frappe-bench/sites/stg-erp-nusakura.artavica.com/private/backups/. /home/opsadmin/backup/
```
Files confirmed at `/home/opsadmin/backup/` — 9.7 MB total.

---

## ~~Task 2: Transfer Backup Files to the Dokploy VPS~~ ✅ DONE

**Where:** Your local machine (Netbird connected, so you can reach both `100.85.56.146` and `vps.thinkspedia.id`)

- [ ] **Step 2.1: Create staging dir on Dokploy VPS**

  ```bash
  ssh <vps-user>@vps.thinkspedia.id "mkdir -p /tmp/frappe-restore"
  ```

- [ ] **Step 2.2: SCP all 4 backup files from source VM to Dokploy VPS**

  ```bash
  SRC="opsadmin@100.85.56.146"
  SRC_KEY="~/.ssh/<your-private-key>"
  SRC_DIR="/home/opsadmin/backup"
  TS="20260611_175254"
  PREFIX="${TS}-stg-erp-nusakura_artavica_com"
  VPS="<vps-user>@vps.thinkspedia.id"
  DEST="/tmp/frappe-restore"

  scp -i $SRC_KEY \
    ${SRC}:${SRC_DIR}/${PREFIX}-database.sql.gz \
    ${SRC}:${SRC_DIR}/${PREFIX}-files.tar \
    ${SRC}:${SRC_DIR}/${PREFIX}-private-files.tar \
    ${SRC}:${SRC_DIR}/${PREFIX}-site_config_backup.json \
    ${VPS}:${DEST}/
  ```

  > **Tip:** If direct SCP between servers is blocked, SCP to local first then re-SCP to VPS:
  > ```bash
  > scp -i $SRC_KEY ${SRC}:${SRC_DIR}/${PREFIX}-* ./
  > scp ${PREFIX}-* ${VPS}:${DEST}/
  > ```

- [ ] **Step 2.3: Verify files arrived on VPS**

  ```bash
  ssh ${VPS} "ls -lh ${DEST}"
  ```

  Expected: 4 files, sizes match the table above.

---

## ~~Task 3: Copy Backup Files into the Running Backend Container on Dokploy VPS~~ ✅ DONE

**Where:** SSH session on the Dokploy VPS

- [ ] **Step 3.1: SSH into the Dokploy VPS**

  ```bash
  ssh <vps-user>@vps.thinkspedia.id
  ```

- [ ] **Step 3.2: Find the backend container name**

  ```bash
  docker ps --format "table {{.Names}}\t{{.Image}}" | grep backend
  ```

  Note the exact container name — used below as `BACKEND`.

- [ ] **Step 3.3: Copy backup files into the container's backups directory**

  ```bash
  BACKEND="<container-name-from-3.2>"
  TS="20260611_175254"
  PREFIX="${TS}-stg-erp-nusakura_artavica_com"
  RESTORE_DIR="/home/frappe/frappe-bench/sites/nusakura-stg.erp.thinkspedia.id/private/backups"
  SRC_DIR="/tmp/frappe-restore"

  docker exec $BACKEND mkdir -p $RESTORE_DIR

  for FILE in database.sql.gz files.tar private-files.tar site_config_backup.json; do
    docker cp ${SRC_DIR}/${PREFIX}-${FILE} ${BACKEND}:${RESTORE_DIR}/
  done
  ```

- [ ] **Step 3.4: Verify files are inside the container**

  ```bash
  docker exec $BACKEND ls -lh $RESTORE_DIR
  ```

  Expected: 4 files with matching sizes.

---

## ~~Task 4: Run `bench restore` Inside the Container~~ ✅ DONE

**Where:** SSH session on Dokploy VPS

- [ ] **Step 4.1: Open a shell in the backend container**

  ```bash
  docker exec -it $BACKEND bash
  ```

- [ ] **Step 4.2: Navigate to bench root and confirm target site exists**

  ```bash
  cd /home/frappe/frappe-bench
  ls sites/
  ```

  Expected: `nusakura-stg.erp.thinkspedia.id` is listed.

- [ ] **Step 4.3: Run bench restore with all 3 backup files**

  ```bash
  TS="20260611_175254"
  SITE="nusakura-stg.erp.thinkspedia.id"
  PREFIX="sites/${SITE}/private/backups/${TS}-stg-erp-nusakura_artavica_com"

  bench --site $SITE restore \
    ${PREFIX}-database.sql.gz \
    --with-public-files  ${PREFIX}-files.tar \
    --with-private-files ${PREFIX}-private-files.tar
  ```

  Expected output ends with:
  ```
  Restored site nusakura-stg.erp.thinkspedia.id
  ```
  No `ERROR` lines.

  > **If you see `Access denied` or MySQL auth errors:** The DB credentials in `sites/nusakura-stg.erp.thinkspedia.id/site_config.json` must match the running MariaDB container. Check:
  > ```bash
  > cat sites/nusakura-stg.erp.thinkspedia.id/site_config.json
  > # Compare db_name / db_password against your compose env vars
  > ```

- [ ] **Step 4.4: Exit the container shell**

  ```bash
  exit
  ```

---

## ~~Task 5: Post-Restore Fixes~~ ✅ DONE

These are mandatory — the restored DB has the old hostname baked into settings tables.

**Where:** SSH on Dokploy VPS, exec'd into backend container

- [ ] **Step 5.1: Open bench console**

  ```bash
  docker exec -it $BACKEND bash -c \
    "cd /home/frappe/frappe-bench && bench --site nusakura-stg.erp.thinkspedia.id console"
  ```

- [ ] **Step 5.2: Fix host_name to new domain**

  ```python
  frappe.db.set_value('System Settings', 'System Settings', 'host_name', 'https://nusakura-stg.erp.thinkspedia.id')
  frappe.db.commit()
  ```

- [ ] **Step 5.3: Fix home_page (prevents `/undefined` routing — Dokploy gotcha #7)**

  ```python
  frappe.db.set_value('System Settings', 'System Settings', 'home_page', 'workspace')
  frappe.db.set_value('Website Settings', 'Website Settings', 'home_page', 'login')
  frappe.db.commit()
  ```

- [ ] **Step 5.4: Exit bench console**

  ```python
  exit()
  ```

- [ ] **Step 5.5: Clear Frappe cache**

  ```bash
  docker exec $BACKEND bash -c \
    "cd /home/frappe/frappe-bench && bench --site nusakura-stg.erp.thinkspedia.id clear-cache"
  ```

- [ ] **Step 5.6: Reload Traefik in Dokploy UI (Dokploy gotcha #5)**

  Browser: `https://vps.thinkspedia.id` → **Settings → Traefik → Reload**.

---

## ~~Task 6: Smoke Test the Restored Site~~ ✅ DONE

**Where:** Browser + bench console as needed

- [ ] **Step 6.1: Open the site**

  Navigate to `https://nusakura-stg.erp.thinkspedia.id` — should show the login page (not a 404 or blank).

- [ ] **Step 6.2: Log in**

  Use the admin password from the source site. If unknown, reset it:

  ```bash
  docker exec $BACKEND bash -c \
    "cd /home/frappe/frappe-bench && bench --site nusakura-stg.erp.thinkspedia.id set-admin-password <new-password>"
  ```

- [ ] **Step 6.3: Verify core data is present**

  - Check a few customers / items / GL entries that exist in the source site.
  - Open an attachment on any document — confirms the files restore worked.

- [ ] **Step 6.4: Check Frappe Error Log**

  ERPNext → Settings → Error Log — review any new errors introduced by the restore.

- [ ] **Step 6.5: Verify no `/undefined` in browser console**

  DevTools → Console. If present, re-run Step 5.3 above.

---

## Known Post-Restore Gotchas (encountered during this migration)

### Administrator "Not Permitted" after login

After restore the Administrator user may lose its roles. Symptoms: login succeeds but every page shows "Not Permitted / You are not permitted to access this page."

Fix via bench console:

```bash
bench --site nusakura-stg.erp.thinkspedia.id console
```

```python
frappe.db.set_value('User', 'Administrator', 'user_type', 'System User')
user = frappe.get_doc('User', 'Administrator')
user.add_roles('System Manager', 'Administrator')
frappe.db.commit()
exit()
```

```bash
bench --site nusakura-stg.erp.thinkspedia.id clear-cache
```

If still blocked, run migrate to re-sync all roles from installed apps:

```bash
bench --site nusakura-stg.erp.thinkspedia.id migrate
```

### Administrator login unknown after email change on source site

If the Administrator email was changed on the source site and the password is unknown, reset via:

```bash
bench --site nusakura-stg.erp.thinkspedia.id set-admin-password <new-password>
```

Log in with username `Administrator` (not email) + the new password. The Administrator user is not visible in the normal Users list — filter by **System User = Yes** to find it.

---

## Rollback / Recovery Notes

- If `bench restore` fails midway, the site DB may be in a partial state. Drop and recreate:
  ```bash
  docker exec -it $BACKEND bash
  cd /home/frappe/frappe-bench
  bench --site nusakura-stg.erp.thinkspedia.id drop-site \
    --no-backup --root-login root --root-password <mariadb-root-pw>
  # Then re-create the site and retry restore
  ```
- The source VM backup at `/home/opsadmin/backup/` is untouched — you can retry at any time.
- The `CREATE_SITE` env-var gate in the compose means the Dokploy stack will not wipe the site on container restart.
