# Product Context

## Problem Being Solved
Setting up a Frappe/ERPNext local dev environment requires assembling many interdependent
services, configuring a bench, installing private apps, and wiring everything together.
This platform eliminates that assembly burden: one `make dev-start` from a cloned repo
boots the entire stack, bootstraps bench, and installs all apps automatically.

For day-to-day development, the platform also eliminates context-switching: developers
work entirely from their app directory (`development/frappe-bench/apps/nusakura_app/`)
without ever needing to navigate to `platform/`.

## Target Users
1. **Thinkspedia developers** — building `nusakura_app` and `nusakura_waha_app`
2. **New team onboards** — needs a single README + workflow doc to be productive
3. **Future production deployment** — via Nomad or Dokploy (planned)

## Core Value Propositions
- **One-command start**: `make dev-start` handles everything, prints all URLs + credentials
- **No directory switching**: app-level Makefile delegates to platform transparently
- **Zero IDE config**: `.vscode/settings.json` committed to each app repo auto-configures
  interpreter, Pylance extra paths, Ruff formatter, and debugger
- **Source of truth docs**: `platform/docs/developer-workflow.md` covers every scenario
  (new feature, bug fix, hotfix, release, IDE setup, troubleshooting)

## User Experience Goals
- Developer opens terminal in app folder → runs `make start` → stack is up
- Developer edits Python file → save → Frappe auto-reloads (no restart needed)
- Developer opens VSCode → IntelliSense and Go-to-Definition work for all Frappe imports
- Developer releases a version → `make release-version` → version bumped, committed, tagged, pushed
- New developer onboards → follows `developer-workflow.md` → productive in < 30 min

## Deployment Targets
| Target | Status |
|---|---|
| Local Docker Compose (`make dev-start`) | Working |
| VSCode WSL2 with IntelliSense | Working (pyenv + /workspace symlink) |
| VSCode Attach to Container | Working |
| JetBrains Docker interpreter | Working (documented) |
| Nomad HCL production | Planned |
| Dokploy compose production | Planned |

## Product Constraints
- No modification to `frappe/` or `erpnext/` source — ever
- `webserver_port=80` must match Traefik's public entry point — changing it breaks email URLs
- App repos use remote name `upstream` (not `origin`) — set by `bench get-app`
- GITHUB_TOKEN never stored in files — injected at runtime only
