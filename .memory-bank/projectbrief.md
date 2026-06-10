# Project Brief

## Name
Frappe Builder

## One-Line Purpose
Production-grade Docker orchestration framework for deploying, managing, and developing Frappe/ERPNext environments — **not** a Frappe application.

## What This Repo Does
- Defines multi-stage Docker images for Frappe/ERPNext (production, bench dev, custom, layered)
- Provides a composable Docker Compose system (`compose.yaml` + 18 `overrides/` fragments)
- Supports local development via VSCode Devcontainer and JetBrains
- Automates CI/CD with GitHub Actions (build matrix, lint gate, image publishing, docs)
- Ships integration tests (pytest) that spin up real Docker stacks
- Manages version pinning through automation scripts

## What This Repo Does NOT Do
- No Frappe DocTypes, Server Scripts, Hooks, or app business logic
- No Nomad HCL files (planned but not yet present)
- No Dokploy configuration (planned but not yet present)

## Supported Matrix
| Dimension | Options |
|---|---|
| Frappe versions | v15, v16, develop |
| Databases | MariaDB (default), PostgreSQL |
| Reverse proxies | Traefik v3, nginx-proxy, none |
| Dev IDEs | VS Code Devcontainer, JetBrains |

## Canonical AI Instruction Files
- `AGENTS.md` — full operational guide (commands, style, architecture, constraints)
- `CLAUDE.md` — redirects to `AGENTS.md`

## Key Stakeholders
- Platform/DevOps engineers deploying Frappe stacks
- Open-source contributors extending image configurations
- CI/CD automation (GitHub Actions publishing to Docker Hub `frappe/` namespace)
