# Tech Context

## Language Stack

| Language | Role | Tooling |
|---|---|---|
| Shell (POSIX sh / bash) | Container entrypoints, resource scripts | shfmt (2-space indent), shellcheck |
| Python | Test suite, automation scripts | black, isort (black profile), pyupgrade (py37+) |
| YAML | Docker Compose files | prettier |
| HCL | Docker Buildx Bake (`docker-bake.hcl`) | — |
| Markdown | Documentation (`docs/`), READMEs | prettier, codespell |

## Base Image Versions (pinned in `docker-bake.hcl`)
- **Python:** 3.14.2-slim-bookworm
- **Node.js:** 24.13.0 (installed via NVM inside image)
- **OS base:** debian:bookworm-slim

## Runtime Services (defined in `compose.yaml`)
| Service | Image | Port | Purpose |
|---|---|---|---|
| `backend` | frappe/erpnext | 8000 | Gunicorn WSGI server |
| `frontend` | frappe/erpnext | 8080 | Nginx reverse proxy |
| `websocket` | frappe/erpnext | 9000 | Socket.IO (Node.js) |
| `queue-short` | frappe/erpnext | — | Short background jobs |
| `queue-long` | frappe/erpnext | — | Long background jobs |
| `scheduler` | frappe/erpnext | — | Cron-like task runner |
| `configurator` | frappe/erpnext | — | One-shot bench config writer |

## Database Options
| Override file | Database | Notes |
|---|---|---|
| `compose.mariadb.yaml` | MariaDB (default) | Recommended for production |
| `compose.mariadb-shared.yaml` | MariaDB shared | Multiple benches share one DB server |
| `compose.mariadb-secrets.yaml` | MariaDB + Docker Secrets | Production security hardening |
| `compose.postgres.yaml` | PostgreSQL 15.17 | Alternative, fully supported |

## Reverse Proxy Options
| Override file | Proxy | SSL |
|---|---|---|
| `compose.noproxy.yaml` | None | No |
| `compose.proxy.yaml` | Basic | No |
| `compose.traefik.yaml` | Traefik v3 | No |
| `compose.traefik-ssl.yaml` | Traefik v3 | Yes (Let's Encrypt) |
| `compose.nginxproxy.yaml` | nginx-proxy | No |
| `compose.nginxproxy-ssl.yaml` | nginx-proxy | Yes |

## Key Dependencies (test suite)
- `pytest==9.0.3` (from `requirements-test.txt`)
- `pytest` config in `setup.cfg`: `-s --exitfirst`

## Pre-commit Hooks
Configured in `.pre-commit-config.yaml`:
- `black` — Python formatter
- `isort` — Python import sorter
- `pyupgrade --py37-plus` — Python syntax upgrader
- `shfmt` — Shell formatter
- `shellcheck` — Shell linter
- `prettier` — YAML/Markdown/JSON formatter
- `codespell` — Spell checker (skips `images/bench/Dockerfile`)
- `trailing-whitespace`, `end-of-file-fixer` — General hygiene

## CI/CD Technology
- **Platform:** GitHub Actions
- **Build tool:** Docker Buildx Bake (`docker-bake.hcl`)
- **Registry:** Docker Hub (`frappe/` namespace)
- **Docs:** VitePress → GitHub Pages
- **Dependency updates:** Dependabot (configured in `.github/dependabot.yml`)

## Environment Configuration
All configurable via `.env` file (template: `example.env`). Key variables:
- `ERPNEXT_VERSION` — image tag
- `DB_PASSWORD`, `DB_HOST`, `DB_PORT`
- `REDIS_CACHE`, `REDIS_QUEUE`
- `GUNICORN_WORKERS`, `GUNICORN_THREADS`, `GUNICORN_TIMEOUT`
- `FRAPPE_SITE_NAME_HEADER` — multi-tenancy routing
- `SITES_RULE` — Traefik routing rule
- `CLIENT_MAX_BODY_SIZE`, `PROXY_READ_TIMEOUT` — Nginx tuning
