# CLAUDE.md — Frappe Builder Operational Guide

> Engineering manual for AI agents (Claude Code and equivalents) operating in this repository.
> Read this before touching any file.

---

## 1. PROJECT OVERVIEW

This repository is a **Docker orchestration framework** for Frappe/ERPNext. It is **not** a Frappe application — it contains no DocTypes, Server Scripts, or Python business logic. Its sole purpose is to define, build, and deploy containerised Frappe environments.

| Concern | Implementation |
|---|---|
| Image builds | `docker-bake.hcl` + `images/` Dockerfiles |
| Runtime orchestration | `compose.yaml` + `overrides/` fragments |
| Local dev environments | `development/installer.py`, `devcontainer-example/` |
| CI/CD | `.github/workflows/` (GitHub Actions) |
| Integration tests | `tests/` (pytest, Docker-based) |
| Documentation | `docs/` (VitePress, auto-published to GitHub Pages) |

**Supported Frappe versions:** v15, v16, develop
**Database backends:** MariaDB (default), PostgreSQL (via override)
**Reverse proxies:** Traefik v3, nginx-proxy, bare (no proxy)
**Dev IDEs:** VS Code Devcontainer, JetBrains

---

## 2. CRITICAL COMMANDS

### Development & Environment

```bash
# Bootstrap a local development environment
python development/installer.py

# Start Frappe development server (inside bench container)
bench start

# Create a new site
bench new-site <site-name> \
  --db-root-password <root-pass> \
  --admin-password <admin-pass>

# Install a Frappe app onto a site
bench --site <site-name> install-app <app-name>

# Bring up the full stack (minimal: MariaDB, no proxy)
docker compose \
  -f compose.yaml \
  -f overrides/compose.mariadb.yaml \
  -f overrides/compose.noproxy.yaml \
  up -d

# Tear down (preserve volumes)
docker compose -f compose.yaml -f overrides/compose.mariadb.yaml down

# Tear down (destroy volumes — destroys all site data)
docker compose -f compose.yaml -f overrides/compose.mariadb.yaml down -v

# Build images with Buildx Bake
docker buildx bake -f docker-bake.hcl             # all targets
docker buildx bake -f docker-bake.hcl bench        # bench dev image
docker buildx bake -f docker-bake.hcl erpnext      # production ERPNext image
docker buildx bake -f docker-bake.hcl base         # base production image
```

**Multi-tenant / SSL / Production topologies:**
```bash
# Traefik + multi-bench + MariaDB
docker compose \
  -f compose.yaml \
  -f overrides/compose.mariadb.yaml \
  -f overrides/compose.multi-bench.yaml \
  -f overrides/compose.traefik.yaml \
  up -d

# With SSL (Traefik + Let's Encrypt)
docker compose \
  -f compose.yaml \
  -f overrides/compose.mariadb.yaml \
  -f overrides/compose.traefik-ssl.yaml \
  up -d

# PostgreSQL instead of MariaDB
docker compose \
  -f compose.yaml \
  -f overrides/compose.postgres.yaml \
  -f overrides/compose.noproxy.yaml \
  up -d

# Backup cron sidecar
docker compose \
  -f compose.yaml \
  -f overrides/compose.mariadb.yaml \
  -f overrides/compose.backup-cron.yaml \
  up -d
```

### Code Quality & Linting

```bash
# Install pre-commit (once per machine)
uv tool install pre-commit
pre-commit install

# Run all hooks against every file
pre-commit run --all-files

# Individual tools
black .                                    # Python formatting
isort .                                    # Python import ordering
shfmt -w -i 2 resources/core/*.sh         # Shell formatting
shellcheck resources/core/*.sh            # Shell linting
prettier --write "**/*.yaml" "**/*.md"    # YAML/Markdown formatting
codespell --skip="images/bench/Dockerfile"  # Spell check
```

### Testing

```bash
# Install test dependencies
pip install -r requirements-test.txt

# Full integration suite (requires Docker stack to be up)
pytest tests/ -s --exitfirst

# Single test
pytest tests/test_frappe_docker.py::test_<function_name> -s

# PostgreSQL variant
# 1. Bring up stack with compose.postgres.yaml overlay
# 2. Set DB_TYPE=postgres in your shell environment
# 3. Run pytest tests/ -s
```

> Tests spin up real Docker stacks and execute HTTP and DB assertions.
> There are no mocked unit tests — do not introduce them.

### Deployment & Site Operations

```bash
# Run database migrations (all sites)
bench --site all migrate

# Run migrations (single site)
bench --site <site-name> migrate

# Clear application cache
bench --site <site-name> clear-cache
bench --site <site-name> clear-website-cache

# Open Python REPL with Frappe context
bench --site <site-name> console

# Export fixtures (defined in hooks.py of the app)
bench --site <site-name> export-fixtures

# Backup (SQL + files)
bench --site <site-name> backup --with-files

# Restore from backup
bench --site <site-name> restore <path/to/backup.sql.gz> \
  --with-private-files <path/to/private-files.tar.gz> \
  --with-public-files <path/to/public-files.tar.gz>
```

### Version Pinning (Automation Scripts)

```bash
# Fetch latest stable Frappe/ERPNext tags
python .github/scripts/get_latest_tags.py

# Update pwd.yml with latest versions (DO NOT edit pwd.yml manually)
python .github/scripts/update_pwd.py

# Sync example.env with latest versions
python .github/scripts/update_example_env.py
```

---

## 3. CODE STYLE & GUIDELINES

### Shell Scripts

- **Indentation:** 2 spaces (`shfmt -i 2`)
- **Error handling:** `set -e` at the top of every script
- **Variable quoting:** Always `"${VAR}"` — never bare `$VAR`
- **Compatibility:** Write POSIX `sh` unless the shebang is explicitly `#!/usr/bin/env bash`
- **Shellcheck:** Zero warnings required; inline suppressions (`# shellcheck disable=SC####`) must include a justification comment
- **Stderr:** All diagnostic/error output goes to stderr: `echo "error" >&2`
- **No interactive prompts** in scripts executed inside containers

### Python

- **Formatter:** `black` (defaults from `setup.cfg`)
- **Import order:** `isort` with `profile = black`
- **Minimum version:** Python 3.7 (`pyupgrade --py37-plus`)
- **Paths:** Use `pathlib.Path` over `os.path`
- **Types:** Type hints encouraged, not enforced
- **No Frappe imports** — this repo has no Frappe app context; scripts are standalone utilities

### YAML / Docker Compose Files

- **Formatter:** `prettier`
- **Long-form keys only** — no flow-style inline maps/sequences in Compose files
- **Override composability:** Override files (`overrides/*.yaml`) must never re-declare services already defined in `compose.yaml`; they only extend or add
- **Secrets:** Runtime credentials must come from environment variables (`.env` file) or Docker secrets (`compose.mariadb-secrets.yaml`) — never hardcoded
- **Environment template:** Add any new variables to `example.env` with a safe placeholder value

### HCL (`docker-bake.hcl`)

- **Variable declarations first**, then `group` blocks, then `target` blocks
- **All overridable values** (versions, repos, tags) must be `variable` blocks — not hardcoded inside targets
- **Tag convention:** `<registry>/<image>:<version>` and `<registry>/<image>:<short-version>` (e.g., `v16.22.0` and `v16`)

### Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add PostgreSQL 16 override
fix: correct nginx header for multi-site routing
chore: bump ERPNext to v16.22.0
ci: add develop branch nightly build
docs: document backup-cron override usage
refactor: consolidate entrypoint scripts
```

---

## 4. ARCHITECTURE & CONSTRAINTS

### Directory Map

| Path | Responsibility |
|---|---|
| `compose.yaml` | Base service graph — always requires at least one DB override to run |
| `overrides/` | 18 composable Compose fragments (DB, proxy, SSL, backup, multi-bench) |
| `images/production/` | Multi-stage production Containerfile (Python → Node → Frappe build → runtime) |
| `images/bench/` | Development image with full build toolchain |
| `images/custom/` | Extension point for custom app images |
| `images/layered/` | Layered build variant |
| `resources/core/` | Entrypoint scripts and Nginx templates baked into images |
| `development/` | Local dev bootstrapper and example app list |
| `devcontainer-example/` | Drop-in devcontainer config for VS Code and JetBrains |
| `tests/` | Docker-based pytest integration tests |
| `.github/workflows/` | Reusable CI workflows (build matrix, lint, publish, docs) |
| `.github/scripts/` | Python utilities for automated version pinning |
| `docs/` | VitePress site — auto-published on merge to `main` |
| `pwd.yml` | Single-file demo for Play With Docker — auto-generated, do not edit |
| `example.env` | Canonical environment variable reference — committed, no real secrets |
| `docker-bake.hcl` | Buildx Bake targets and version variables |

### CI/CD Structure

- **Reusable workflows:** `core-build-*.yml` — called by other workflows, not triggered directly
- **Build matrix:** `[v15, v16]` × `[stable, develop]`
- **Publishing:** All images push to Docker Hub under the `frappe/` namespace
- **Lint gate:** `lint.yml` runs `pre-commit run --all-files` on every PR and push; failures block merge
- **Docs:** `docs-publish-site.yml` deploys VitePress to GitHub Pages on every push to `main`

### Strict Don'ts

| Rule | Reason |
|---|---|
| **Never edit `pwd.yml` directly** | Auto-generated by `update_pwd.py`; manual edits are overwritten |
| **Never commit `.env` files** | Only `example.env` belongs in the repo |
| **Never hardcode passwords, tokens, or secrets** | Use Docker secrets or runtime environment variables |
| **Never duplicate services from `compose.yaml` in override files** | Breaks Compose merge semantics |
| **Never modify Python/Node base versions in Containerfiles directly** | Change `variable` blocks in `docker-bake.hcl`; versions propagate from there |
| **Never bypass pre-commit with `--no-verify`** | Fix lint errors; hooks are the quality gate |
| **Never run destructive `bench` commands on production** without a verified backup | `migrate`, `restore`, `drop-site` are irreversible |
| **Never add Frappe DocTypes, Server Scripts, or app code** | This repo is infrastructure only; Frappe apps belong in separate repositories |
| **Never introduce unit test mocks for Docker/DB** | All tests are integration tests; mocks caused past production divergence |

### Key Environment Variables (from `example.env`)

| Variable | Purpose |
|---|---|
| `ERPNEXT_VERSION` | ERPNext image tag (e.g., `v16.22.0`) |
| `DB_PASSWORD` | MariaDB/PostgreSQL root password |
| `DB_HOST` / `DB_PORT` | Database host and port |
| `REDIS_CACHE` / `REDIS_QUEUE` | Redis endpoint URIs |
| `GUNICORN_WORKERS` / `GUNICORN_THREADS` | Worker concurrency |
| `FRAPPE_SITE_NAME_HEADER` | Frappe multi-tenancy routing header |
| `SITES_RULE` | Traefik routing rule (e.g., `` Host(`erp.example.com`) ``) |

---

## 5. DEVCONTAINER QUICK-START

```bash
# 1. Copy devcontainer config into .devcontainer/
cp -r devcontainer-example/ .devcontainer

# 2. Open in VS Code and reopen in container
# Command Palette → "Dev Containers: Rebuild and Reopen in Container"

# 3. Inside container: initialise bench
python /workspace/development/installer.py

# 4. Start the dev server
bench start
```

Ports forwarded: `8000` (Frappe), `9000` (WebSocket), `6787` (Redis Insight)

---

*This file is the authoritative operational reference. Update it when commands, paths, or constraints change.*
