# System Patterns

## Core Architectural Pattern: Composable Overrides

`compose.yaml` is the base service graph — it defines all runtime services but is **never run alone**. It always requires at minimum one database override:

```
docker compose -f compose.yaml -f overrides/<db>.yaml -f overrides/<proxy>.yaml up -d
```

Override files extend services using Docker Compose merge semantics. **Never redeclare a service** from `compose.yaml` inside an override — only add `environment`, `volumes`, `networks`, or `depends_on` extensions.

## Image Build Pattern: Variables-First HCL

All version pins live in `variable` blocks at the top of `docker-bake.hcl`. Containerfiles consume `ARG` values at build time. **Never hardcode versions inside a Containerfile** — always trace back to a bake variable.

```hcl
variable "PYTHON_VERSION" { default = "3.14.2" }
variable "NODE_VERSION"   { default = "24.13.0" }
```

## Version Automation Pattern

Three Python scripts in `.github/scripts/` automate version synchronisation:
1. `get_latest_tags.py` — fetches upstream Frappe/ERPNext release tags
2. `update_pwd.py` — rewrites `pwd.yml` (demo file — **never edit manually**)
3. `update_example_env.py` — updates version pins in `example.env`

These are called by CI on a schedule. If versions look stale, run these scripts rather than editing files by hand.

## CI/CD Pattern: Reusable Workflow Composition

Workflows are split into:
- `core-build-*.yml` — reusable workflows (called via `workflow_call`)
- `build_*.yml` — caller workflows that provide the matrix inputs

Build matrix: `[v15, v16]` × `[stable, develop]`. All images publish to `frappe/` on Docker Hub.

## Testing Pattern: Real Stack Integration Tests

All tests in `tests/` spin up actual Docker Compose stacks. There are no unit test mocks. The `conftest.py` fixtures:
1. Write a temporary env file
2. Bring up the full Docker stack
3. Create a Frappe test site
4. Tear down after the suite

CI uses `tests/compose.ci.yaml` as an additional override for CI-specific adjustments.

## Security Pattern: Secrets at Runtime

Never hardcode credentials. Three approved approaches in increasing security level:
1. `.env` file loaded by Docker Compose at runtime (dev/staging)
2. Docker environment variables passed at `docker compose up` time
3. Docker Secrets via `compose.mariadb-secrets.yaml` (production)

## Entrypoint Pattern

All containers use scripts in `resources/core/` as entrypoints:
- `main-entrypoint.sh` — general container startup logic
- `start.sh` — launches Gunicorn with configurable workers/threads
- `nginx/nginx-entrypoint.sh` — renders Nginx config from template, starts Nginx

Worker/thread counts are driven by `GUNICORN_WORKERS` and `GUNICORN_THREADS` env vars.

## Site Routing Pattern (Multi-tenancy)

Frappe determines which site to serve via the `HTTP_X_FRAPPE_SITE_NAME` header, set by the `FRAPPE_SITE_NAME_HEADER` env var on the frontend service. For Traefik, the `SITES_RULE` variable holds the routing rule (e.g., `` Host(`erp.example.com`) ``).
