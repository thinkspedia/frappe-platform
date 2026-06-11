# ERPNext Backup & Restore: stg-erp-nusakura.artavica.com → nusakura-stg.erp.thinkspedia.id

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Full backup of ERPNext site `stg-erp-nusakura.artavica.com` from a source VM (SSH access via private key) and restore it onto the running Dokploy stack at `nusakura-stg.erp.thinkspedia.id`.

**Architecture:** Frappe's `bench backup --with-files` produces three artifacts (database SQL gz, private files tar.gz, public files tar.gz). These are transferred to the Dokploy VPS, copied into the running `backend` container, and restored via `bench restore`. Post-restore steps re-point the site name to the new hostname and fix known Dokploy gotchas.

**Tech Stack:** Frappe v15 / ERPNext, bench CLI, Docker / docker compose exec, SSH/SCP, Dokploy VPS (`vps.thinkspedia.id`), Traefik.

---

## Prerequisites Checklist (confirm before starting)

- [ ] You have SSH access to the **source VM** (`stg-erp-nusakura.artavica.com`) with your private key.
- [ ] You have SSH access to the **Dokploy VPS** (`vps.thinkspedia.id`).
- [ ] The target site `nusakura-stg.erp.thinkspedia.id` is up and running (green in Dokploy dashboard). If not, run the stack first per `platform/docs/dokploy-deployment.md`.
- [ ] Enough disk space on the Dokploy VPS (check with `df -h` on VPS — need ~3× the source DB size free).

---

## Task 1: Take a Full Backup on the Source VM

**Where:** SSH session on source VM (`stg-erp-nusakura.artavica.com`)

- [ ] **Step 1.1: SSH into the source VM**

  ```bash
  ssh -i ~/.ssh/<your-private-key> <user>@stg-erp-nusakura.artavica.com
  ```

- [ ] **Step 1.2: Find the bench directory and site name**

  ```bash
  # Frappe is usually in /home/frappe/frappe-bench
  ls /home/frappe/frappe-bench/sites/
  ```

  Note the exact site folder name (e.g. `stg-erp-nusakura.artavica.com`). You'll need it for `--site`.

- [ ] **Step 1.3: Run a full backup with files**

  ```bash
  cd /home/frappe/frappe-bench
  bench --site stg-erp-nusakura.artavica.com backup --with-files
  ```

  Expected output (example):
  ```
  Backing up Database for stg-erp-nusakura.artavica.com
  ...
  Backup stored at:
    /home/frappe/frappe-bench/sites/stg-erp-nusakura.artavica.com/private/backups/20260611_120000-stg-erp-nusakura_artavica_com-database.sql.gz
    /home/frappe/frappe-bench/sites/stg-erp-nusakura.artavica.com/private/backups/20260611_120000-stg-erp-nusakura_artavica_com-private-files.tar.gz
    /home/frappe/frappe-bench/sites/stg-erp-nusakura.artavica.com/private/backups/20260611_120000-stg-erp-nusakura_artavica_com-files.tar.gz
  ```

- [ ] **Step 1.4: Note the exact paths of the 3 backup files**

  ```bash
  ls -lh /home/frappe/frappe-bench/sites/stg-erp-nusakura.artavica.com/private/backups/ | tail -10
  ```

  Copy the 3 filenames (database gz, private-files gz, files gz) — you'll SCP them in Task 2.

- [ ] **Step 1.5: Exit the source VM**

  ```bash
  exit
  ```

---

## Task 2: Transfer Backup Files to the Dokploy VPS

**Where:** Your local machine (or any machine with access to both servers)

- [ ] **Step 2.1: SCP the 3 backup files from source VM to Dokploy VPS**

  Replace `<src-user>`, `<src-key>`, `<YYYYMMDD_HHMMSS>`, `<vps-user>` with real values:

  ```bash
  # Set variables for clarity
  SRC="<src-user>@stg-erp-nusakura.artavica.com"
  SRC_KEY="~/.ssh/<your-private-key>"
  SRC_BACKUP_DIR="/home/frappe/frappe-bench/sites/stg-erp-nusakura.artavica.com/private/backups"
  TIMESTAMP="<YYYYMMDD_HHMMSS>"   # e.g. 20260611_120000
  VPS="<vps-user>@vps.thinkspedia.id"
  VPS_DEST="/tmp/frappe-restore"

  # Create destination dir on VPS
  ssh $VPS "mkdir -p $VPS_DEST"

  # Copy database backup
  scp -i $SRC_KEY \
    "${SRC}:${SRC_BACKUP_DIR}/${TIMESTAMP}-stg-erp-nusakura_artavica_com-database.sql.gz" \
    "${VPS}:${VPS_DEST}/"

  # Copy private files backup
  scp -i $SRC_KEY \
    "${SRC}:${SRC_BACKUP_DIR}/${TIMESTAMP}-stg-erp-nusakura_artavica_com-private-files.tar.gz" \
    "${VPS}:${VPS_DEST}/"

  # Copy public files backup
  scp -i $SRC_KEY \
    "${SRC}:${SRC_BACKUP_DIR}/${TIMESTAMP}-stg-erp-nusakura_artavica_com-files.tar.gz" \
    "${VPS}:${VPS_DEST}/"
  ```

  > **Tip:** If direct SCP between servers fails (firewall), SCP to your local machine first, then SCP to VPS.

- [ ] **Step 2.2: Verify files arrived on VPS**

  ```bash
  ssh $VPS "ls -lh $VPS_DEST"
  ```

  Expected: 3 files, sizes match source.

---

## Task 3: Copy Backup Files into the Running Docker Container

**Where:** SSH session on the Dokploy VPS

- [ ] **Step 3.1: SSH into the Dokploy VPS**

  ```bash
  ssh <vps-user>@vps.thinkspedia.id
  ```

- [ ] **Step 3.2: Find the backend container name**

  ```bash
  docker ps --format "table {{.Names}}\t{{.Image}}" | grep backend
  ```

  Expected: something like `nusakura-erp-stg_backend_1` or `unDMPJe63QFy24yqw2RsY_backend_1`.
  Note the exact container name — used below as `<BACKEND_CONTAINER>`.

- [ ] **Step 3.3: Copy backup files into the container's restore staging path**

  ```bash
  BACKEND="<BACKEND_CONTAINER>"   # from step 3.2
  RESTORE_DIR="/home/frappe/frappe-bench/sites/nusakura-stg.erp.thinkspedia.id/private/backups"
  TIMESTAMP="<YYYYMMDD_HHMMSS>"

  # Ensure directory exists inside container
  docker exec $BACKEND mkdir -p $RESTORE_DIR

  # Copy each file
  docker cp /tmp/frappe-restore/${TIMESTAMP}-stg-erp-nusakura_artavica_com-database.sql.gz \
    ${BACKEND}:${RESTORE_DIR}/

  docker cp /tmp/frappe-restore/${TIMESTAMP}-stg-erp-nusakura_artavica_com-private-files.tar.gz \
    ${BACKEND}:${RESTORE_DIR}/

  docker cp /tmp/frappe-restore/${TIMESTAMP}-stg-erp-nusakura_artavica_com-files.tar.gz \
    ${BACKEND}:${RESTORE_DIR}/
  ```

- [ ] **Step 3.4: Verify files are inside the container**

  ```bash
  docker exec $BACKEND ls -lh $RESTORE_DIR
  ```

---

## Task 4: Run `bench restore` Inside the Container

**Where:** SSH session on Dokploy VPS, exec'd into backend container

- [ ] **Step 4.1: Open a shell in the backend container**

  ```bash
  docker exec -it <BACKEND_CONTAINER> bash
  ```

- [ ] **Step 4.2: Navigate to bench root and confirm site exists**

  ```bash
  cd /home/frappe/frappe-bench
  ls sites/
  ```

  Expected: `nusakura-stg.erp.thinkspedia.id` is listed.

- [ ] **Step 4.3: Run bench restore with all 3 files**

  Replace `<YYYYMMDD_HHMMSS>` with the actual timestamp:

  ```bash
  TIMESTAMP="<YYYYMMDD_HHMMSS>"
  SITE="nusakura-stg.erp.thinkspedia.id"
  BACKUP_DIR="sites/${SITE}/private/backups"

  bench --site $SITE restore \
    ${BACKUP_DIR}/${TIMESTAMP}-stg-erp-nusakura_artavica_com-database.sql.gz \
    --with-public-files  ${BACKUP_DIR}/${TIMESTAMP}-stg-erp-nusakura_artavica_com-files.tar.gz \
    --with-private-files ${BACKUP_DIR}/${TIMESTAMP}-stg-erp-nusakura_artavica_com-private-files.tar.gz
  ```

  Expected: long output ending in `Restored site nusakura-stg.erp.thinkspedia.id` with no ERROR lines.

  > **If you see "Access denied" or MySQL errors:** The restore needs the DB credentials from `sites/<site>/site_config.json`. Check `cat sites/$SITE/site_config.json` — `db_name` and `db_password` must match the running MariaDB container.

- [ ] **Step 4.4: Exit the container shell**

  ```bash
  exit
  ```

---

## Task 5: Post-Restore Fixes

These are mandatory — the restored DB has the old hostname baked into several tables and settings.

**Where:** SSH on Dokploy VPS, exec'd into backend container

- [ ] **Step 5.1: Open bench console**

  ```bash
  docker exec -it <BACKEND_CONTAINER> bash -c \
    "cd /home/frappe/frappe-bench && bench --site nusakura-stg.erp.thinkspedia.id console"
  ```

- [ ] **Step 5.2: Fix System Settings & Website Settings home_page (Dokploy gotcha #7)**

  Inside the bench console:

  ```python
  frappe.db.set_value('System Settings', 'System Settings', 'home_page', 'workspace')
  frappe.db.set_value('Website Settings', 'Website Settings', 'home_page', 'login')
  frappe.db.commit()
  ```

- [ ] **Step 5.3: Update site URL in System Settings to new hostname**

  ```python
  frappe.db.set_value('System Settings', 'System Settings', 'host_name', 'https://nusakura-stg.erp.thinkspedia.id')
  frappe.db.commit()
  ```

- [ ] **Step 5.4: Exit bench console**

  ```python
  exit()
  ```

- [ ] **Step 5.5: Clear Frappe cache**

  ```bash
  docker exec <BACKEND_CONTAINER> bash -c \
    "cd /home/frappe/frappe-bench && bench --site nusakura-stg.erp.thinkspedia.id clear-cache"
  ```

- [ ] **Step 5.6: Reload Traefik in Dokploy UI (Dokploy gotcha #5)**

  In browser: `https://vps.thinkspedia.id` → **Settings → Traefik → Reload**.

---

## Task 6: Smoke Test the Restored Site

**Where:** Browser + bench console as needed

- [ ] **Step 6.1: Open the site in browser**

  Navigate to `https://nusakura-stg.erp.thinkspedia.id` — should show login page (not a Traefik 404, not `/undefined`).

- [ ] **Step 6.2: Log in with the restored admin credentials**

  Use the admin password from the source site. If unknown, reset it:

  ```bash
  docker exec <BACKEND_CONTAINER> bash -c \
    "cd /home/frappe/frappe-bench && bench --site nusakura-stg.erp.thinkspedia.id set-admin-password <new-password>"
  ```

- [ ] **Step 6.3: Verify core data is present**

  - Check a few customers / items / GL entries that exist in the source site.
  - Confirm file attachments load (tests the files restore).

- [ ] **Step 6.4: Check for errors in Frappe Error Log**

  ERPNext → Settings → Error Log — should be empty or only contain pre-existing source-site errors.

- [ ] **Step 6.5: Verify no `/undefined` routing error in browser console**

  Open browser DevTools → Console. If you see `GET /undefined`, run the bench console fix from Step 5.2 again.

---

## Rollback / Recovery Notes

- If `bench restore` fails midway, the site DB may be in a partial state. Drop and recreate the DB, then retry:
  ```bash
  docker exec <BACKEND_CONTAINER> bash -c \
    "cd /home/frappe/frappe-bench && bench --site nusakura-stg.erp.thinkspedia.id drop-site --no-backup --root-login root --root-password <mariadb-root-pw>"
  bench --site nusakura-stg.erp.thinkspedia.id new-site ...  # re-install apps first
  ```
- The original source site is untouched; you can retake the backup and retry at any point.
- The `CREATE_SITE=0` gate in the compose means the Dokploy stack won't wipe the site on container restart.
