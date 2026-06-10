# Frappe Platform — Thinkspedia

Docker-based development and production platform for Frappe/ERPNext v16 with custom apps.
Provides automated local environment bootstrap, Traefik reverse proxy, and a unified
Makefile workflow so developers never need to touch Docker Compose directly.

---

## Repository Structure

```
frappe-platform/
├── platform/                    # Docker Compose stack + Makefile + configs
│   ├── docker-compose.dev.yml   # Full local dev stack (Traefik, nginx, MariaDB, Redis, ...)
│   ├── Makefile                 # All dev commands (make start, make dev-migrate, ...)
│   ├── .env.example             # All environment variables with defaults
│   ├── apps.json                # Custom app registry (URLs + branches)
│   ├── scripts/
│   │   └── bootstrap.sh         # Idempotent first-run setup (bench init → site create)
│   └── docs/
│       └── developer-workflow.md  # Source of truth for day-to-day development
│
└── development/
    └── frappe-bench/            # Created on first `make dev-start` (git-ignored)
        └── apps/
            ├── frappe/          # DO NOT MODIFY
            ├── erpnext/         # DO NOT MODIFY
            ├── nusakura_app/    # Custom app — Nusakura EPC
            └── nusakura_waha_app/  # Custom app — WhatsApp integration
```

---

## Quick Start

### Prerequisites

- Docker Desktop (Mac/Windows) or Docker Engine + Compose v2 (Linux/WSL2)
- `127.0.0.1 dev.localhost` in `/etc/hosts`

```bash
# macOS / Linux
sudo sh -c 'echo "127.0.0.1 dev.localhost" >> /etc/hosts'

# WSL2
echo '127.0.0.1 dev.localhost' | sudo tee -a /etc/hosts
```

### First run

```bash
git clone git@github.com:thinkspedia/frappe-platform.git
cd frappe-platform/platform
cp .env.example .env
# edit .env — set DB_ROOT_PASSWORD and ADMIN_PASSWORD at minimum
make dev-start
```

Bootstrap runs automatically on first start (5–10 min): initialises bench, clones all
apps from `apps.json`, creates the site, and builds assets. Subsequent starts are instant.

```
  Web:       http://dev.localhost
  Adminer:   http://localhost:8081  (root / <DB_ROOT_PASSWORD>)
  Mailpit:   http://localhost:8025
  Traefik:   http://localhost:8082
```

---

## Custom Apps

| App | Repo | Purpose |
|-----|------|---------|
| `nusakura_app` | [thinkspedia/nusakura_app](https://github.com/thinkspedia/nusakura_app) | Core EPC business modules (attendance, payroll, project control, procurement) |
| `nusakura_waha_app` | [thinkspedia/nusakura_waha_app](https://github.com/thinkspedia/nusakura_waha_app) | WhatsApp notification integration via Waha |

Each app has its own `Makefile` that delegates to this platform — developers can run all
commands (`make start`, `make dev-migrate`, `make sync`, `make release-version`) directly
from the app directory without switching folders.

---

## Daily Developer Commands

Run from your app directory (e.g. `development/frappe-bench/apps/nusakura_app/`):

```bash
make start              # start the full dev stack
make stop               # stop (data preserved)
make sync               # git pull upstream + migrate + clear-cache
make dev-migrate        # bench migrate after schema changes
make dev-build          # build JS/CSS assets
make dev-console        # Frappe Python console
make dev-shell          # bash shell inside the container
make dev-export-fixtures  # export fixtures for this app
make release-version    # bump version, commit, tag
```

Run from `platform/`:

```bash
make dev-destroy        # full reset — wipes bench dir + DB volume
make dev-ps             # service status
make code APP=nusakura_app  # open app folder in VSCode
```

---

## VSCode Setup (WSL2)

One-time setup per machine — gives full IntelliSense and Go-to-Definition for Frappe
imports without attaching to the container.

```bash
# 1. Install build deps + pyenv + Python 3.14.2
sudo apt-get install -y libbz2-dev libncurses-dev libreadline-dev libsqlite3-dev \
  libssl-dev liblzma-dev libffi-dev zlib1g-dev tk-dev
curl https://pyenv.run | bash          # add pyenv init to ~/.zshrc, then reload
pyenv install 3.14.2

# 2. Create /workspace symlink (bench venv .pth files use this path)
sudo ln -sf /path/to/frappe-platform /workspace

# 3. Open app folder
cd platform && make code APP=nusakura_app
```

The `.vscode/settings.json` in each app repo sets `python.defaultInterpreterPath` to
`~/.pyenv/versions/3.14.2/bin/python3` automatically — no manual interpreter selection
needed.

---

## Documentation

| Document | Purpose |
|----------|---------|
| [`platform/docs/developer-workflow.md`](platform/docs/developer-workflow.md) | **Source of truth** — day-to-day workflow, all scenarios (feature, bug fix, hotfix, release), IDE setup, dev tools, troubleshooting |
| [`platform/.env.example`](platform/.env.example) | All environment variables with descriptions and defaults |
| [`platform/Makefile`](platform/Makefile) | All platform-level commands (`make help` for full list) |
| [`platform/apps.json`](platform/apps.json) | Custom app registry — URLs, branches, install order |
| [`AGENTS.md`](AGENTS.md) | AI coding assistant rules for this repo |

---

## Dev Tools

Adminer (database UI) and Mailpit (email trap) start automatically with the stack.
Enable/disable via `COMPOSE_PROFILES` in `.env`:

```bash
COMPOSE_PROFILES=tools   # enable Adminer + Mailpit (default)
COMPOSE_PROFILES=        # disable all optional tools
```

See [`platform/docs/developer-workflow.md`](platform/docs/developer-workflow.md)
for Mailpit ERPNext configuration.

---

## License

MIT — see [LICENSE](LICENSE).
