# Progress

## What Is Working (Confirmed)
- [x] Full repository structure explored and documented
- [x] `AGENTS.md` — comprehensive operational guide (canonical AI guide)
- [x] `CLAUDE.md` — redirect stub pointing to `AGENTS.md`
- [x] `.memory-bank/` — initialized (2026-06-10)
- [x] All 18 override files present and documented
- [x] CI/CD workflows (12 total) present and categorised
- [x] Test suite (`tests/`) present with conftest, fixtures, and integration tests
- [x] Pre-commit hooks configured
- [x] `platform/` — unified dev-to-prod system implemented (2026-06-10)

## Platform Layer — Implemented (2026-06-10)

| File | Purpose |
|---|---|
| `platform/Dockerfile` | 4-stage: base / development / prod-build / production |
| `platform/apps.json` | App registry: erpnext + nusakura_app + nusakura_waha_app |
| `platform/.env.example` | Source of truth for all config (copy to .env) |
| `platform/docker-compose.dev.yml` | Full local dev stack with auto-bootstrap |
| `platform/scripts/bootstrap.sh` | Idempotent site init + app install |
| `platform/scripts/configure-site.sh` | Writes host_name to site_config.json from .env |
| `platform/scripts/mariadb.cnf` | Frappe-compatible MariaDB config |
| `platform/nomad/frappe.nomad.hcl` | Nomad job: prestart migrate + web/worker/scheduler |
| `platform/dokploy/dokploy.yml` | Dokploy-compatible compose manifest |
| `platform/cli/pyproject.toml` | org-bench CLI package definition |
| `platform/cli/org_bench/__init__.py` | CLI entrypoint (Click group) |
| `platform/cli/org_bench/dev.py` | dev setup / start / stop / new-app |
| `platform/cli/org_bench/build.py` | build --tag (BuildKit secrets for private repos) |
| `platform/cli/org_bench/deploy.py` | deploy --env --tag (Nomad pull/ship + Dokploy) |

## What Is Planned But Not Yet Implemented
- [ ] End-to-end smoke test of local dev stack
- [ ] Nomad host volume (`frappe_sites`) pre-provisioning on nodes
- [ ] GitHub Actions CI workflow for `org-bench build --push`

## Known Constraints and Gotchas
1. **`pwd.yml` is auto-generated** — never edit manually; use `.github/scripts/update_pwd.py`
2. **`CLAUDE.md` gets rewritten by a hook** — always maintain `AGENTS.md` as source of truth
3. **No git commits in this working copy** — all files are currently untracked
4. **No Frappe app code here** — this is infrastructure only; Frappe apps live in separate repos
5. **Tests require a live Docker stack** — `pytest tests/` will fail without services running
6. **GITHUB_TOKEN required at build time** — never baked into image; passed as BuildKit secret
7. **Nomad host volume `frappe_sites` must be pre-created** on each Nomad client node before first deploy
8. **Nomad scheduler group always count=1** — never scale it; multiple schedulers cause duplicate tasks

## Session History
| Date | Action |
|---|---|
| 2026-06-10 | Initial `CLAUDE.md` generated (operational guide) |
| 2026-06-10 | Hook rewrote `CLAUDE.md` to redirect; content lives in `AGENTS.md` |
| 2026-06-10 | `.memory-bank/` initialized (first time) |
| 2026-06-10 | `platform/` unified dev-to-prod system fully implemented |
