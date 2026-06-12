# Project Brief

## Name
Frappe Platform — Thinkspedia

## GitHub
`git@github.com:thinkspedia/frappe-platform.git`

## One-Line Purpose
Docker-based development and production platform for Frappe/ERPNext v16 with Thinkspedia
custom apps — automated bootstrap, Traefik reverse proxy, unified Makefile workflow.

## What This Repo Does
- Runs a full Frappe/ERPNext v16 local dev stack via `make dev-start` (one command)
- Auto-bootstraps bench, clones all apps, creates site, builds assets on first run
- Provides `platform/docs/developer-workflow.md` as the source of truth for all developer workflows
- Ships app-level Makefiles in each custom app repo so developers never need to switch directories
- Tracks two private custom apps: `nusakura_app` and `nusakura_waha_app`

## What This Repo Does NOT Do
- No Frappe DocTypes, Server Scripts, Hooks, or app business logic (those live in app repos)
- Does NOT modify `frappe/` or `erpnext/` source — hard constraint

## Current Deployment Targets
| Target | Status |
|---|---|
| Local Docker Compose (`make dev-start`) | Working |
| Dokploy VPS (nusakura-stg.erp.thinkspedia.id) | Live — migrated 2026-06-11 |
| Nomad cluster (3 servers, 3 clients) | Infrastructure phases 0–3 complete; Phase 5 (ERPNext job) in progress |

## Repository Structure
```
frappe-platform/
├── platform/                    # Docker Compose stack + Makefile + configs
│   ├── docker-compose.dev.yml
│   ├── Makefile
│   ├── .env.example
│   ├── apps.json                # App registry (URLs + branches)
│   ├── scripts/bootstrap.sh
│   └── docs/developer-workflow.md
├── development/
│   └── frappe-bench/            # Git-ignored — created by bootstrap
│       └── apps/
│           ├── frappe/          # DO NOT MODIFY
│           ├── erpnext/         # DO NOT MODIFY
│           ├── nusakura_app/    # github.com/thinkspedia/nusakura_app
│           └── nusakura_waha_app/  # github.com/thinkspedia/nusakura_waha_app
├── AGENTS.md                    # AI coding assistant rules
└── CLAUDE.md                    # Redirects to AGENTS.md
```

## Custom App Repos
| App | GitHub | Remote name in bench |
|-----|--------|----------------------|
| `nusakura_app` | `github.com/thinkspedia/nusakura_app` | `upstream` (set by `bench get-app`) |
| `nusakura_waha_app` | `github.com/thinkspedia/nusakura_waha_app` | `upstream` (set by `bench get-app`) |

**Critical:** `bench get-app` names the remote `upstream`, not `origin`. All push/pull
commands in app repos use `git push upstream main` / `git pull --ff-only upstream main`.

## Canonical AI Instruction Files
- `AGENTS.md` — full operational guide (commands, style, architecture, constraints)
- `CLAUDE.md` — redirects to `AGENTS.md`

## Key Constraint
**Never touch `frappe/` or `erpnext/` app source.** All customisation goes through
hooks, override files, and custom apps only.
