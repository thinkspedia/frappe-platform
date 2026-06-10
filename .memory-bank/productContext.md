# Product Context

## Problem Being Solved
Running Frappe/ERPNext in production requires assembling many moving parts: database, Redis, Gunicorn workers, a queue processor, a scheduler, and an Nginx frontend. This repo eliminates that assembly burden by providing tested, composable Docker Compose configurations for every common topology.

## Target Users
1. **Self-hosters** — individuals or small teams deploying ERPNext on a VPS or local server
2. **Platform engineers** — teams managing multi-tenant Frappe deployments at scale
3. **App developers** — who need a reproducible local dev environment matching production
4. **CI/CD pipelines** — automated systems pulling images from Docker Hub

## Core Value Propositions
- **Composability:** Pick your DB, pick your proxy, pick your SSL strategy — combine overrides without modifying the base
- **Reproducibility:** Pinned base images (Python 3.14.2, Node 24.13.0) via `docker-bake.hcl` variables
- **Multi-version support:** v15, v16, and develop branches all tested in CI
- **Dev parity:** Devcontainer config mirrors the production image toolchain

## Deployment Targets (Current and Planned)
| Target | Status |
|---|---|
| Local Docker Compose | Active |
| VSCode Devcontainer | Active |
| JetBrains Devcontainer | Active |
| Dokploy | Planned |
| HashiCorp Nomad | Planned |

## Product Constraints
- Images must remain immutable — no writes to image layers at runtime; all state in the `sites/` volume
- Public Docker Hub images must be multi-arch (amd64 + arm64)
- `pwd.yml` is the single-file demo artifact — it must remain auto-generated from scripts

## Documentation Site
VitePress at `docs/` — auto-deployed to GitHub Pages on every merge to `main`. Covers getting started, setup, production, operations, development, migration, troubleshooting, and reference.
