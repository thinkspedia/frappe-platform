# Nomad Upgrade Runbook

Complete reference for the Thinkspedia Nomad infrastructure upgrade. Update this document as phases complete.

**Last verified:** 2026-06-12

---

## Table of Contents

1. [Cluster Access](#1-cluster-access)
2. [Infrastructure Topology](#2-infrastructure-topology)
3. [6-Phase Migration Plan](#3-6-phase-migration-plan)
4. [CSI Storage](#4-csi-storage)
5. [Running Jobs](#5-running-jobs)
6. [Secrets & Credentials](#6-secrets--credentials)
7. [Diagnostic Commands](#7-diagnostic-commands)
8. [Known Issues & Gotchas](#8-known-issues--gotchas)

---

## 1. Cluster Access

| System | Address | Notes |
|--------|---------|-------|
| Nomad UI | https://100.85.99.16:4646 | or http://nomad.corp.thinkspedia.id/ |
| Nomad API | https://100.85.99.16:4646/v1 | Header: `X-Nomad-Token: <token>` |
| Vault UI | https://100.85.99.16:8200 | or any Nomad server IP:8200 |
| Consul | https://100.85.242.94:8501 | SSL, token required |
| SSH key | `~/.ssh/id_ansible` | user: `opsadmin` on all nodes |

### Tokens

| Token | Value | Purpose |
|-------|-------|---------|
| Nomad operator daily | `47a19c79-4f0e-bec9-7a17-c8bb5ceadeeb` | Day-to-day API/CLI — verify expiry before use |
| Nomad bootstrap | stored securely | One-time cluster bootstrap only |
| Nomad ACL job submit | stored securely | CI/CD job submission |
| Consul Traefik | `98b97488-eb83-61c7-49eb-ce9e230835a3` | Traefik → Consul service catalog |

### Quick auth check

```bash
TOKEN="47a19c79-4f0e-bec9-7a17-c8bb5ceadeeb"
curl -sk -H "X-Nomad-Token: $TOKEN" https://100.85.99.16:4646/v1/agent/members | python3 -c "
import sys,json
[print(m['Name'], m['Status']) for m in json.load(sys.stdin)['Members']]
"
```

---

## 2. Infrastructure Topology

### Nomad Servers (3 nodes)

| Node | Netbird IP | Internal IP | Status |
|------|-----------|-------------|--------|
| nomad-core-01 | 100.85.99.16 | — | alive |
| nomad-core-02 | 100.85.196.70 | — | alive |
| nomad-core-03 | 100.85.13.200 | 172.16.200.85 | alive |

- Vault v1.17.6 runs on all 3 server nodes at port `8200` (initialized, unsealed)
- Nomad v1.10.2
- Region: `core`, Datacenter: `core-dc1`
- TLS enabled on HTTP + RPC, `verify_server_hostname = true`
- ACL enabled

### Nomad Clients (3 nodes)

| Node | Netbird IP | Node Pool | Status |
|------|-----------|-----------|--------|
| nomad-client-core-01 | 100.85.17.19 | workload | ready, eligible |
| nomad-client-core-02 | 100.85.129.187 | workload | ready, eligible |
| nomad-client-core-03 | 100.85.14.86 | workload | ready, eligible |

Consul agents running on all 3 clients (datacenter: `core-dc1`).

### Consul Servers (3 nodes)

| Address | Port | Notes |
|---------|------|-------|
| 100.85.242.94 | 8501 | SSL — **known issue: cert is for 100.85.229.181, not this IP** |

> **Consul TLS cert mismatch:** cert issued for `100.85.229.181` but Nomad server config points to `100.85.242.94`. Causes warning in Nomad logs but doesn't break operation. Fix in Phase 4.

### NFS Storage Server

| Node | Internal IP | ZFS Pool | Purpose |
|------|------------|----------|---------|
| nfs-core-01 | 172.16.200.23 | `tank/nomad` | democratic-csi NFS backend |

### Namespaces

| Namespace | Purpose |
|-----------|---------|
| `default` | Traefik (system job) |
| `erpnext-nusakura` | ERPNext jobs + CSI volumes |
| `platform` | CSI controller/node plugin |

---

## 3. 6-Phase Migration Plan

| Phase | Description | Status | Notes |
|-------|-------------|--------|-------|
| **0** | nfs-core-01 VM + nomad-client-core-03 added | ✅ Complete | |
| **1** | HashiCorp Vault HA | ✅ Complete | Vault 1.17.6 on all 3 server nodes, unsealed |
| **2** | democratic-csi + CSI volumes | ✅ Complete | Plugin healthy, 4 volumes provisioned |
| **3** | Nomad + Consul full rebuild | ✅ Complete | 3/3 servers, 3/3 clients, all infra jobs running |
| **4** | Traefik in platform namespace + Vault secrets | ⏳ Pending | Traefik running but Vault-Nomad integration NOT configured. Consul cert mismatch to fix. |
| **5** | ERPNext multi-tenant + nusakura job redesign | 🔄 In progress | Root cause found, Option B redesign in progress |
| **6** | Alerts, runbooks, operational hardening | ⏳ Not started | |

### Phase 3 Fix Applied (2026-06-12)

`nomad-core-03` had diverged Raft state (isolated as 1-node cluster, refusing pre-votes from core-01/02).

Fix:
```bash
ssh -i ~/.ssh/id_ansible opsadmin@100.85.13.200
sudo systemctl stop nomad
sudo rm -rf /opt/nomad/server/raft/
sudo systemctl start nomad
# Verify: watch logs for "Installed remote snapshot"
sudo journalctl -u nomad -f
```

### Phase 4 Remaining Work

1. **Nomad-Vault integration** — add `vault {}` stanza to all Nomad server configs at `/etc/nomad.d/nomad.hcl`:
   ```hcl
   vault {
     enabled = true
     address = "https://100.85.99.16:8200"
     # ca_file, cert_file, key_file for mTLS
   }
   ```
2. **Store secrets in Vault** — migrate DB_PASSWORD, MARIADB_ROOT_PASSWORD, ADMIN_PASSWORD, ENCRYPTION_KEY from job env vars to `secret/erpnext-nusakura/nusakura`
3. **Fix Consul TLS cert** — re-issue cert including `100.85.242.94` SAN
4. **Verify Traefik** uses Vault-sourced secrets (currently using `consulCatalog` for routing, no Vault)

---

## 4. CSI Storage

### Plugin

| Field | Value |
|-------|-------|
| Plugin ID | `org.democratic-csi.nfs-zfs` |
| Driver | `zfs-generic-nfs` |
| Version | v1.9.3 |
| Controllers healthy | 1/1 |
| Nodes healthy | 3/3 |
| ZFS dataset parent | `tank/nomad` on nfs-core-01 (172.16.200.23) |
| NFS share host | `172.16.200.23` |
| Snapshots dataset | `tank/nomad-snapshots` |

### Provisioned Volumes (namespace: erpnext-nusakura)

| Volume ID | Mounted by | Mount path | Access mode |
|-----------|-----------|------------|-------------|
| `erpnext-nusakura-db` | `erpnext-nusakura-mariadb` | `/var/lib/mysql` | single-node-writer |
| `erpnext-nusakura-redis` | `erpnext-nusakura-redis` (redis-socketio task) | `/data` | single-node-writer |
| `erpnext-nusakura-sites` | `nusakura-erpnext` (target) | `/home/frappe/frappe-bench/sites` | multi-node-multi-writer |
| `erpnext-nusakura-logs` | `nusakura-erpnext` (target) | `/home/frappe/frappe-bench/logs` | multi-node-multi-writer |
| `frappe-sites` | none | — | **Duplicate — delete when CSI allows** |

### democratic-csi Quirks

- `datasetEnableQuotas: false` → capacity is reported as 0B — do not set `capacity_min`/`capacity_max` in volume specs or use `capacity_min` only
- `single-node-writer` provisioning fails with quota validation error when quotas are disabled — use `multi-node-multi-writer` for all NFS volumes (single-writer enforcement is at Nomad scheduler level)
- Volume delete may fail with "shareStrategy undefined" if volume was created without proper NFS config — leave and retry after cluster stabilizes

---

## 5. Running Jobs

### Job Inventory

| Job ID | Namespace | Type | Status | Image |
|--------|-----------|------|--------|-------|
| `traefik` | default | system | running | traefik (standard) |
| `csi-controller` | platform | service | running | democraticcsi/democratic-csi:v1.9.3 |
| `csi-node-plugin` | platform | system | running | democraticcsi/democratic-csi:v1.9.3 |
| `erpnext-nusakura-mariadb` | erpnext-nusakura | service | running | mariadb |
| `erpnext-nusakura-redis` | erpnext-nusakura | service | running | redis (custom config) |
| `nusakura-erpnext` | erpnext-nusakura | service | **dead** | `registry.corp.thinkspedia.id/erpnext/nusakuraerp:v1.3.19` |

### Redis Job — Consul Services

Job `erpnext-nusakura-redis` registers 3 Consul services with **static ports**:

| Consul Service Name | Static Port | Purpose |
|--------------------|-------------|---------|
| `erpnext-nusakura-redis-cache` | 6379 | Frappe page cache |
| `erpnext-nusakura-redis-queue` | 6380 | Celery job queue |
| `erpnext-nusakura-redis-socketio` | 6381 | Socket.IO pubsub |

Use these service names in Nomad `template` stanzas for dynamic address resolution:
```
{{ range service "erpnext-nusakura-redis-cache" }}{{ .Address }}:{{ .Port }}{{ end }}
```

### nusakura-erpnext — Root Cause (dead)

**Error:** `connect ECONNREFUSED 127.0.0.1:6380` on websocket + queue workers

**Cause:** Job hardcodes `REDIS_QUEUE=redis://127.0.0.1:6380` — only works if Redis lands on same client node. With 3 nodes, Nomad scheduled ERPNext and Redis on different clients.

**Fix (Phase 5):** Redesign job with `template` stanza resolving Redis addresses from Consul. See `platform/nomad/frappe.nomad.hcl`.

### nusakura-erpnext — Site Config

| Field | Value |
|-------|-------|
| Site name | `nusakura.erp.thinkspedia.id` |
| DB name | derived from site name |
| MariaDB host | resolved via Consul: `erpnext-nusakura-mariadb.service.consul` |

---

## 6. Secrets & Credentials

> **Current state:** Secrets are hardcoded as plaintext env vars in job specs. Migration to Vault planned for Phase 4.

### ERPNext (nusakura-erpnext + erpnext-nusakura-mariadb)

| Secret | Environment Variable | Notes |
|--------|---------------------|-------|
| MariaDB root password | `MARIADB_ROOT_PASSWORD` | Same value as `ENCRYPTION_KEY` |
| MariaDB app password | `MARIADB_PASSWORD` / `DB_PASSWORD` | Same value used in both jobs |
| ERPNext admin password | `ADMIN_PASSWORD` | Site administrator login |
| Frappe encryption key | `ENCRYPTION_KEY` | Must match across all app tasks |

> Retrieve current values: `nomad inspect -namespace=erpnext-nusakura <job-id>` — visible in `Env` fields of task config.

### Vault

| Field | Value |
|-------|-------|
| Version | 1.17.6 |
| Address | https://100.85.99.16:8200 (any server node IP works) |
| Status | Initialized, unsealed |
| Nomad integration | **NOT configured** — no `vault {}` stanza in Nomad server config |

Target Vault secret path for Phase 4: `secret/erpnext-nusakura/nusakura`

---

## 7. Diagnostic Commands

### Full cluster health check

```bash
TOKEN="47a19c79-4f0e-bec9-7a17-c8bb5ceadeeb"
BASE="https://100.85.99.16:4646/v1"

# Servers
echo "=== SERVERS ==="
curl -sk -H "X-Nomad-Token: $TOKEN" "${BASE}/agent/members" | python3 -c "
import sys,json
[print(m['Name'], m['Addr'], m['Status']) for m in json.load(sys.stdin)['Members'] if m['Tags'].get('role')=='nomad']
"

# Clients
echo "=== CLIENTS ==="
curl -sk -H "X-Nomad-Token: $TOKEN" "${BASE}/nodes" | python3 -c "
import sys,json
[print(n['Name'], n['Status'], n['SchedulingEligibility']) for n in json.load(sys.stdin)]
"

# All jobs
echo "=== JOBS ==="
curl -sk -H "X-Nomad-Token: $TOKEN" "${BASE}/jobs?namespace=*" | python3 -c "
import sys,json
[print(j['ID'], '|', j['Namespace'], '|', j['Status']) for j in json.load(sys.stdin)]
"

# CSI plugin
echo "=== CSI PLUGIN ==="
curl -sk -H "X-Nomad-Token: $TOKEN" "${BASE}/plugin/csi/org.democratic-csi.nfs-zfs" | python3 -c "
import sys,json; d=json.load(sys.stdin)
print('Controllers:', d['ControllersHealthy'], '/', d['ControllersExpected'])
print('Nodes:', d['NodesHealthy'], '/', d['NodesExpected'])
"

# Vault
echo "=== VAULT ==="
curl -sk https://100.85.99.16:8200/v1/sys/health | python3 -c "
import sys,json; d=json.load(sys.stdin)
print('Version:', d['version'], '| Initialized:', d['initialized'], '| Sealed:', d['sealed'])
"
```

### Check CSI volumes

```bash
ssh -i ~/.ssh/id_ansible opsadmin@100.85.99.16 \
  "NOMAD_ADDR=https://127.0.0.1:4646 NOMAD_TOKEN=47a19c79-4f0e-bec9-7a17-c8bb5ceadeeb \
   nomad volume status -namespace=erpnext-nusakura"
```

### Check allocation logs (debug failed job)

```bash
ssh -i ~/.ssh/id_ansible opsadmin@100.85.99.16 "
export NOMAD_ADDR=https://127.0.0.1:4646
export NOMAD_TOKEN=47a19c79-4f0e-bec9-7a17-c8bb5ceadeeb
ALLOC=\$(nomad job allocs -namespace=erpnext-nusakura nusakura-erpnext | tail -1 | awk '{print \$1}')
nomad alloc logs -namespace=erpnext-nusakura -stderr \$ALLOC websocket | tail -30
"
```

### Force new evaluation (re-run dead job)

```bash
ssh -i ~/.ssh/id_ansible opsadmin@100.85.99.16 \
  "NOMAD_ADDR=https://127.0.0.1:4646 NOMAD_TOKEN=47a19c79-4f0e-bec9-7a17-c8bb5ceadeeb \
   nomad job eval -namespace=erpnext-nusakura nusakura-erpnext"
```

---

## 8. Known Issues & Gotchas

### Nomad

1. **Raft split-brain on rejoin** — if a server was offline during a cluster rebuild, wipe its Raft data before rejoining: `sudo rm -rf /opt/nomad/server/raft/ && sudo systemctl restart nomad`. The node downloads a fresh snapshot from the leader.

2. **Nomad CLI needs HTTPS** — all nodes use TLS. Always set `NOMAD_ADDR=https://127.0.0.1:4646` (not http). Error: "Client sent an HTTP request to an HTTPS server."

3. **Nomad operator token may expire** — token TTL is 30s for policies. If API calls return 403, the token itself may still be valid but policy cache expired. Retry or use bootstrap token to issue a fresh operator token.

### democratic-csi

4. **Quota validation fails on new volumes** — `datasetEnableQuotas: false` causes `required_bytes > limit_bytes` error. Do not set `capacity_min`/`capacity_max` on new volumes, or set only `capacity_min`.

5. **Volume delete blocked by "shareStrategy undefined"** — happens when a volume was created with missing NFS config. Leave the volume; it's not consuming significant resources. Retry delete after CSI plugin restart.

6. **All NFS volumes must use `multi-node-multi-writer`** — the `single-node-writer` access mode fails provisioning validation. Enforce single-writer at the Nomad scheduling level (count=1 on the task group).

### ERPNext on Nomad

7. **Redis addresses must use Consul service discovery** — hardcoded `127.0.0.1` only works if Redis and ERPNext land on the same node. Use `template` stanza with `{{ range service "erpnext-nusakura-redis-queue" }}{{ .Address }}:{{ .Port }}{{ end }}`.

8. **common_site_config.json must be written before bench starts** — use a `configurator` prestart lifecycle task (mirrors the Docker Compose configurator service). Without it, bench falls back to defaults and may fail to connect to DB/Redis.

9. **bench migrate must run before web tasks** — use `lifecycle { hook = "prestart" }` on the migrate task within the web task group (not a separate group).

10. **Consul constraint on clients** — `nusakura-erpnext` has constraint `${attr.consul.version} semver >= 1.8.0`. All 3 client nodes satisfy this (Consul agents running).

### Vault

11. **Nomad-Vault integration not yet configured** — no `vault {}` stanza in Nomad server `nomad.hcl`. Job specs cannot use `vault { policies = [] }` until Phase 4 configures this.

12. **Secrets currently in plaintext env vars** — visible via `nomad inspect` to anyone with operator token. Migrate to Vault in Phase 4.
