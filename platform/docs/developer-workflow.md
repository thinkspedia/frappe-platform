# Developer Workflow

This is the source of truth for day-to-day development on the Thinkspedia platform.
It covers every scenario a developer will encounter: new features, bug fixes, enhancements,
hotfixes, and cleanup. Follow these steps in order — the workflow is the same for both
`nusakura_app` and `nusakura_waha_app` unless otherwise noted.

---

## Table of Contents

1. [Quick Reference](#quick-reference)
2. [Conventions](#conventions)
3. [IDE & OS Setup](#ide--os-setup)
4. [Local Dev Environment](#local-dev-environment)
5. [Scenario A — New Feature](#scenario-a--new-feature)
6. [Scenario B — Bug Fix](#scenario-b--bug-fix)
7. [Scenario C — Hotfix (urgent fix on main)](#scenario-c--hotfix-urgent-fix-on-main)
8. [Scenario D — Enhancement (improve existing feature)](#scenario-d--enhancement-improve-existing-feature)
9. [Scenario E — Chore / Refactor / Dependency update](#scenario-e--chore--refactor--dependency-update)
10. [Scenario F — Documentation only](#scenario-f--documentation-only)
11. [Version Bump Rules](#version-bump-rules)
12. [Testing Locally](#testing-locally)
13. [Dev Tools Setup](#dev-tools-setup)
14. [Branch Cleanup](#branch-cleanup)
15. [PR Guidelines](#pr-guidelines)
16. [Workflow Diagram](#workflow-diagram)
17. [Troubleshooting](#troubleshooting)

---

## Quick Reference

```
feat/   → new feature    → minor bump
fix/    → bug fix        → patch bump
hotfix/ → urgent fix     → patch bump (skips long review cycle)
refactor/ → code improvement → patch bump
chore/  → build, deps, tooling → patch bump (no version bump if no user impact)
docs/   → documentation only → no version bump
```

```bash
# All commands below run from your app directory (e.g. apps/nusakura_app/)
# No need to switch to platform/ — the app Makefile delegates automatically.

# Start your day
make start

# Sync latest code from upstream, migrate, and clear cache
make sync

# After changing Python / hooks
make dev-migrate

# After changing JS / CSS
# bench build runs automatically in dev mode; if not:
make dev-build

# Open a shell in the container
make dev-shell

# Stop everything
make stop

# Open an app folder in VSCode (run from platform/ only)
make code APP=nusakura_app
```

---

## Conventions

### Branch naming

| Prefix | Use for | Example |
|--------|---------|---------|
| `feat/` | New feature | `feat/leave-encashment-policy` |
| `fix/` | Bug fix | `fix/overtime-calculation-rounding` |
| `hotfix/` | Critical production bug | `hotfix/login-broken-after-v1.4.0` |
| `refactor/` | Code improvement, no behaviour change | `refactor/custom-field-sync-cleanup` |
| `chore/` | Dependencies, build, tooling | `chore/bump-frappe-16-deps` |
| `docs/` | Documentation only | `docs/update-release-workflow` |

### Conventional Commits

Every commit message must follow this format:

```
<type>(<scope>): <short description>

[optional body]

[optional footer: Refs #issue-number]
```

Types and their version impact:

| Type | When to use | Version impact |
|------|-------------|----------------|
| `feat` | New feature visible to users | minor |
| `feat!` or `BREAKING CHANGE:` footer | Breaks existing behaviour | major |
| `fix` | Bug fix | patch |
| `perf` | Performance improvement | patch |
| `refactor` | Code change, no behaviour change | patch |
| `chore` | Build, deps, tooling, no user impact | patch (or none) |
| `docs` | Documentation only | none |
| `test` | Tests only | none |
| `ci` | CI pipeline changes | none |

Examples:

```
feat(leave): add leave encashment policy calculation
fix(overtime): correct rounding error for half-day OT
feat!: remove legacy salary slip custom fields
chore: upgrade erpnext to version-16.18
docs: document custom field release gate
```

### Commit scope

Use the functional area, not the file name:

```
feat(attendance): ...
fix(payroll): ...
chore(deps): ...
```

---

## IDE & OS Setup

There are two development approaches in this repo. Choose one — do not run both simultaneously
as they use overlapping ports.

---

### Approach A — Platform stack (recommended for most developers)

This is the approach documented throughout this guide. Run `make dev-start` from the
`platform/` directory. Everything starts automatically. Your code lives on the host
filesystem and is editable in any IDE or editor.

**Works identically on:**
- macOS (Docker Desktop)
- Linux
- Windows WSL2 (Docker Desktop)

**macOS prerequisites:**

1. Install [Docker Desktop for Mac](https://docs.docker.com/desktop/install/mac-install/).
2. In Docker Desktop → Settings → Resources → set Memory to at least **4 GB**.
3. Add the site hostname to `/etc/hosts`:
   ```bash
   sudo sh -c 'echo "127.0.0.1 dev.localhost" >> /etc/hosts'
   ```
4. Clone the repo and run:
   ```bash
   cd platform
   cp .env.example .env
   # edit .env to set your passwords
   make dev-start
   ```

The output will print:
```
  Web:       http://dev.localhost
  Adminer:   http://localhost:8081  (root / <your password>)
  Mailpit:   http://localhost:8025
  Traefik:   http://localhost:8082
```

**IDE configuration for Approach A:**

Since the Python environment lives inside the container (not on your Mac), IDE features
like IntelliSense and "Go to Definition" for Frappe imports require pointing your IDE at
the container's interpreter.

**VSCode on macOS:**

Install the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
or the [Remote — SSH extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-ssh).
Then attach to the running `frappe-web` container:

1. Command Palette (`Cmd+Shift+P`) → **Dev Containers: Attach to Running Container**
2. Select `platform-frappe-web-1`
3. Open folder `/workspace/development/frappe-bench/apps/nusakura_app`

VSCode now runs inside the container — IntelliSense, imports, and the debugger all work
against the real Python environment.

Alternatively, configure the Python interpreter path in `.vscode/settings.json` in your
app directory:

```json
{
  "python.defaultInterpreterPath": "/workspace/development/frappe-bench/env/bin/python"
}
```

Then start a remote tunnel with `code --remote` or use the Docker extension to exec into
the container.

**JetBrains IDEs (PyCharm, IntelliJ) on macOS:**

Option 1 — **Docker interpreter** (simplest):

1. Preferences → Project → Python Interpreter → Add Interpreter → **On Docker**
2. Image: leave empty (use existing container)
3. Container: `platform-frappe-web-1`
4. Interpreter path: `/workspace/development/frappe-bench/env/bin/python`

Option 2 — **SSH into container** (more stable for large projects):

1. Add `ports: ["2222:22"]` to the `frappe-web` service and install openssh-server in the
   container, then configure a Remote SSH interpreter.

Option 3 — Just edit on host, run via terminal:

Most day-to-day work (writing Python, Jinja, JS) does not require the IDE to resolve
Frappe imports. Use the terminal for `make dev-migrate`, `make dev-console`, etc.
Reserve the Docker interpreter setup for debugging sessions.

---

### Approach B — Devcontainer (upstream repo approach)

The upstream `frappe_docker` repo ships a devcontainer config in `devcontainer-example/`.
In this approach the **container is the development environment** — your IDE attaches to it
and runs inside it. Bench is set up manually inside the container.

**When to use:**
- You want full Python debugging with breakpoints out of the box
- You prefer the IDE to manage container lifecycle
- You are contributing to the upstream repo itself

**When NOT to use:**
- You want automated bootstrap (Approach A does this)
- You are running our custom apps (`nusakura_app`, `nusakura_waha_app`) with our full stack
- You need Traefik, adminer, or mailpit alongside

**Setup (VSCode on macOS):**

1. Install the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers).
2. Copy the devcontainer config:
   ```bash
   cp -R devcontainer-example .devcontainer
   ```
3. Open the repo in VSCode (`code .`).
4. Command Palette → **Dev Containers: Reopen in Container**.
   VSCode rebuilds the container and attaches to it. This takes a few minutes on first run.
5. Inside the container terminal, set up the bench manually:
   ```bash
   bench init --skip-redis-config-generation --frappe-branch version-16 frappe-bench
   cd frappe-bench
   bench set-config -g db_host mariadb
   bench set-config -g redis_cache redis://redis-cache:6379
   bench set-config -g redis_queue redis://redis-queue:6379
   bench set-config -g redis_socketio redis://redis-queue:6379
   bench new-site --db-root-password 123 --admin-password admin \
       --mariadb-user-host-login-scope=% dev.localhost
   bench --site dev.localhost set-config developer_mode 1
   bench get-app --branch main https://github.com/thinkspedia/nusakura_app
   bench --site dev.localhost install-app nusakura_app
   bench build
   bench start
   ```
6. The site is accessible at **http://dev.localhost:8000** (note: port 8000, not port 80).

**Setup (JetBrains on macOS):**

JetBrains IDEs support devcontainers via the **Dev Containers plugin**:

1. Install plugin: Preferences → Plugins → search **Dev Containers** → Install.
2. From the welcome screen: **Remote Development → Dev Containers → Open Project in Dev Container**.
3. Point it at the repo root — JetBrains reads `.devcontainer/devcontainer.json` automatically.
4. The IDE opens inside the container with full Python interpreter access.

Alternatively use **JetBrains Gateway** for a fully remote experience (the heavy IDE
components run on the container, only the thin client runs on your Mac).

---

### Comparison

| | Approach A (Platform stack) | Approach B (Devcontainer) |
|---|---|---|
| Setup time | ~1 min (`make dev-start`) | ~10 min (manual bench init) |
| Bootstrap | Automatic | Manual |
| Site URL | `http://dev.localhost` (port 80) | `http://dev.localhost:8000` |
| Adminer / Mailpit | Included | Not included (add manually) |
| Python IntelliSense | Requires IDE → container config | Works out of the box |
| Python debugger | Requires IDE → container config | Works out of the box |
| Platform | macOS / Linux / WSL2 identical | macOS / Linux / WSL2 identical |
| Recommended for | All team developers | Developers who need Python debugging |

---

### Optimized setup for WSL2 + VSCode (recommended)

This is the recommended path if you already use **VSCode → Connect to WSL → Open Folder**.
All steps below are one-time, per machine.

**Why this setup is needed:**

There are two path problems on WSL2 that break IntelliSense:

1. The bench venv's `.pth` files use `/workspace/...` — a container-absolute path that
   doesn't exist on WSL2. Fix: symlink `/workspace` → your repo root.
2. The bench venv's `python` binary is a symlink to `/home/frappe/.pyenv/...` — a path
   that only exists inside the container (user `frappe`). Fix: install pyenv + Python
   3.14.2 on WSL2 so VSCode has a real local interpreter.

The `.vscode/settings.json` committed to each app repo already sets
`python.defaultInterpreterPath` to `~/.pyenv/versions/3.14.2/bin/python3` and
`python-envs.defaultEnvManager` to `pyenv` — so once pyenv is installed, everything
is auto-configured with no manual VSCode steps.

---

**Step 1 — Install pyenv and Python 3.14.2 on WSL2:**

```bash
# Install build dependencies first (required — pyenv compiles Python from source)
sudo apt-get update && sudo apt-get install -y \
  libbz2-dev libncurses-dev libreadline-dev libsqlite3-dev \
  libssl-dev liblzma-dev libffi-dev zlib1g-dev tk-dev

# Install pyenv
curl https://pyenv.run | bash

# Add to ~/.zshrc (or ~/.bashrc):
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

# Reload shell, then install the same Python version used in the container:
source ~/.zshrc
pyenv install 3.14.2

# Verify no missing modules:
~/.pyenv/versions/3.14.2/bin/python3 -c "import bz2, sqlite3, readline, lzma; print('all good')"
```

---

**Step 2 — Create a `/workspace` symlink:**

```bash
# Replace with wherever you cloned the repo:
sudo ln -sf /path/to/frappe_builder /workspace

# Typical example:
# sudo ln -sf /home/<your-username>/workspaces/frappe_builder /workspace
```

After this, `/workspace/development/frappe-bench/apps/frappe` resolves correctly on WSL2
and the venv's `.pth` files find all Frappe source paths.

---

**Step 3 — Verify imports work:**

```bash
~/.pyenv/versions/3.14.2/bin/python3 \
  -c "import sys; sys.path.insert(0, '/workspace/development/frappe-bench/apps/frappe'); import frappe; print(frappe.__version__)"
```

You should see the Frappe version number, not an ImportError.

---

**Step 4 — Open your app in VSCode:**

Option A — `make code` shortcut (fastest):

```bash
cd /workspace/platform
make code APP=nusakura_app
# or: make code APP=nusakura_waha_app
```

This opens VSCode directly to `/workspace/development/frappe-bench/apps/<APP>`.
IntelliSense and Go-to-Definition work immediately — no further configuration needed.

Option B — manually:

1. VSCode → **Connect to WSL**
2. **File → Open Folder** → `/workspace/development/frappe-bench/apps/nusakura_app`

---

**What is auto-configured on first open:**

```
.vscode/settings.json     ← interpreter (~/.pyenv/versions/3.14.2/bin/python3)
                             + pyenv env manager + Pylance extra paths + Ruff formatter
.vscode/extensions.json   ← recommends Python, Pylance, Ruff, SQLTools
.vscode/launch.json       ← debugger attach config (port 5678)
```

VSCode prompts **"Do you want to install the recommended extensions?"** on first open.
No manual interpreter selection is needed — `settings.json` sets it automatically.

---

### Recommended setup for macOS team developers

**Option A — `/workspace` symlink (same as WSL2):**

```bash
sudo ln -sf /path/to/frappe_builder /workspace
```

macOS may require disabling System Integrity Protection (SIP) to create symlinks in `/`.
Once done, use `make code APP=nusakura_app` from `platform/` to open the app folder.

**Option B — Attach to Running Container (no SIP change needed):**

1. `make dev-start`
2. `Cmd+Shift+P` → **Dev Containers: Attach to Running Container**
3. Select `platform-frappe-web-1`
4. Open `/workspace/development/frappe-bench/apps/nusakura_app`

Inside the container `/workspace` is real, so all imports resolve with no symlink needed.

---

## Local Dev Environment

### Start the stack

You can start the stack from either the **app directory** (recommended) or the `platform/` directory:

```bash
# From app directory (e.g. development/frappe-bench/apps/nusakura_app/)
make start

# From platform/ directory
make dev-start
```

On first run, bootstrap will:
1. Run `bench init` (5–10 min)
2. Clone all apps from `apps.json`
3. Create the site and install all apps
4. Compile JS/CSS assets

Subsequent starts are instant — bootstrap detects an existing site and exits immediately.

Access the site at **http://dev.localhost** (no port number).

### Useful daily commands

Run these from **your app directory** — no need to switch to `platform/`:

```bash
make start                  # start the full dev stack
make stop                   # stop (data preserved)
make logs                   # follow all logs
make restart                # restart all services

make sync                   # git pull upstream + migrate + clear-cache (one-shot)
make dev-migrate            # bench migrate (after schema changes)
make dev-clear-cache        # clear Frappe cache
make dev-build              # build JS/CSS assets for this app
make dev-console            # Frappe Python console (bench console)
make dev-shell              # bash shell in frappe-web container
make dev-export-fixtures    # export fixtures for this app
```

From the `platform/` directory only:

```bash
make dev-mariadb            # MariaDB SQL console
make dev-ps                 # show service status
make dev-destroy            # FULL RESET — wipes bench + DB
make code APP=nusakura_app  # open app folder in VSCode
```

### Where your app code lives

App source code lives on your **host filesystem** at:

```
frappe_builder/
└── development/
    └── frappe-bench/
        └── apps/
            ├── nusakura_app/        ← edit this directly
            └── nusakura_waha_app/   ← edit this directly
```

Changes you make on the host are reflected immediately inside the container — no restart needed for Python changes (Frappe runs in developer mode with auto-reload).

For JS/CSS changes, run inside the container:

```bash
bench build --app nusakura_app
```

---

## Scenario A — New Feature

Use this for any new functionality that did not exist before.

### 1. Sync your local main

```bash
cd development/frappe-bench/apps/nusakura_app  # or nusakura_waha_app
git checkout main
git pull --ff-only upstream main
```

### 2. Create a feature branch

```bash
git checkout -b feat/leave-encashment-policy
```

### 3. Develop

- Write code, doctypes, fixtures, custom fields.
- Commit early and often using Conventional Commits.

```bash
git add <files>
git commit -m "feat(leave): add leave encashment policy doctype"
git commit -m "feat(leave): wire encashment calculation to payroll entry"
```

### 4. Test locally

See [Testing Locally](#testing-locally) section.

### 5. Push and open a PR

```bash
git push upstream feat/leave-encashment-policy
```

Open a Pull Request on GitHub targeting `main`.

- Title: use the Conventional Commit format, e.g. `feat(leave): add leave encashment policy`
- Description: what changed, why, and how to test it
- Assign at least one reviewer

### 6. Address review feedback

```bash
git add <files>
git commit -m "fix(leave): handle zero-balance edge case in encashment"
git push upstream feat/leave-encashment-policy
```

### 7. Merge the PR

Once approved, merge via GitHub (prefer **Squash and merge** for clean history, or **Merge commit** if preserving commit details matters). Delete the remote branch after merging.

### 8. Bump the version on main

```bash
git checkout main
git pull --ff-only upstream main

cd development/frappe-bench/apps/nusakura_app
make version-current        # confirm current version
make version-next           # preview next version (auto-detects feat → minor bump)
make release-version        # bumps __init__.py, commits, tags
git push upstream main --tags
```

### 9. Delete local branch

```bash
git branch -d feat/leave-encashment-policy
```

---

## Scenario B — Bug Fix

Use this for any defect reported by users or found during testing.

### 1. Sync main and branch

```bash
git checkout main
git pull --ff-only upstream main
git checkout -b fix/overtime-rounding-error
```

### 2. Reproduce the bug locally

- Use `make dev-shell` to open a container shell.
- Use `make dev-console` to run Python diagnostics.
- Use `make dev-mariadb` to inspect DB state if needed.

### 3. Fix and commit

```bash
git add <files>
git commit -m "fix(overtime): correct rounding for half-day OT calculation

Fixes rounding to nearest 0.5h instead of floor.
Refs #42"
```

### 4. Test the fix

See [Testing Locally](#testing-locally).

### 5. Push, PR, merge

Same as Scenario A steps 5–7.

### 6. Bump version (patch)

```bash
git checkout main
git pull --ff-only upstream main
make release-version VERSION_BUMP=patch
git push upstream main --tags
```

### 7. Cleanup

```bash
git branch -d fix/overtime-rounding-error
```

---

## Scenario C — Hotfix (urgent fix on main)

Use this when a critical bug is discovered in production that cannot wait for a normal PR cycle.
A hotfix is still branched — never commit directly to main.

### 1. Branch from main

```bash
git checkout main
git pull --ff-only upstream main
git checkout -b hotfix/login-broken-after-v1.4.0
```

### 2. Apply the fix

Keep the change minimal — only fix the critical defect, nothing else.

```bash
git add <files>
git commit -m "fix(auth): restore login redirect broken by #89

Regression introduced in v1.4.0 — session cookie domain was unset."
```

### 3. Test immediately

Focus only on the broken scenario plus the surrounding happy path.

### 4. Fast-track PR

Open the PR with `[HOTFIX]` in the title. Tag the team lead / on-call reviewer for expedited review.
Merge as soon as one approval is received.

### 5. Bump patch version immediately after merge

```bash
git checkout main
git pull --ff-only upstream main
make release-version VERSION_BUMP=patch
git push upstream main --tags
```

### 6. Cleanup

```bash
git branch -d hotfix/login-broken-after-v1.4.0
```

---

## Scenario D — Enhancement (improve existing feature)

An enhancement modifies existing behaviour in a backward-compatible way — no new doctype, but
improved logic, UI, or performance.

Treat it identically to **Scenario A** (new feature) with these differences:

- Branch prefix: `feat/` if it adds capability, `refactor/` if it only improves internal structure.
- Commit type: `feat` for user-visible improvements, `refactor` or `perf` for internal improvements.
- Version bump: `minor` for `feat`, `patch` for `refactor`/`perf`.

Example:

```bash
git checkout -b feat/attendance-dashboard-summary
git commit -m "feat(attendance): add weekly summary widget to attendance dashboard"
make release-version VERSION_BUMP=minor
```

---

## Scenario E — Chore / Refactor / Dependency update

Use for dependency upgrades, tooling changes, code cleanup, or build changes that
have no direct user impact.

```bash
git checkout -b chore/upgrade-ruff-linter
git commit -m "chore(deps): upgrade ruff to 0.4.x"
```

Version bump policy:
- If the change affects runtime behaviour (even indirectly), do a `patch` bump.
- If it is purely build/tooling with zero runtime impact, no version bump is needed.

For dependency upgrades that change Frappe behaviour, always bump + test locally before merging.

---

## Scenario F — Documentation only

```bash
git checkout -b docs/update-custom-field-guide
git commit -m "docs: clarify custom field ownership resolution steps"
```

No version bump needed. PR → merge → done.

---

## Version Bump Rules

Version is stored in `<app_name>/__init__.py` as `__version__`.

| Trigger | Bump | Command |
|---------|------|---------|
| New feature (`feat:`) | minor | `make release-version VERSION_BUMP=minor` |
| Breaking change (`feat!:` / `BREAKING CHANGE:`) | major | `make release-version VERSION_BUMP=major` |
| Bug fix, perf, refactor (`fix:` / `perf:` / `refactor:`) | patch | `make release-version VERSION_BUMP=patch` |
| Auto-detect from commits | auto | `make release-version` |
| Docs / chore only | none | skip |

Auto-detect reads commits since the last git tag and picks the highest applicable bump.
It is safe to use when you follow Conventional Commits consistently.

Preview without writing:

```bash
make version-current        # current: 1.3.19
make version-next           # next (auto): 1.4.0
make version-next VERSION_BUMP=patch   # next (patch): 1.3.20
```

Bump, commit, and tag in one step:

```bash
make release-version                      # auto
make release-version VERSION_BUMP=minor   # force minor
```

Then push:

```bash
git push upstream main --tags
```

> For the full release-to-production flow (Docker image build, staging deploy, production deploy),
> see `nusakura_app/docs/RELEASE_WORKFLOW.md`.

---

## Testing Locally

### Run bench migrate after schema changes

Any change to DocType, custom fields, or patch files requires a migration:

```bash
make dev-migrate
```

Or inside the container shell:

```bash
bench --site dev.localhost migrate
```

### Clear cache after config / hook changes

```bash
make dev-clear-cache
```

### Open the Python console for quick checks

```bash
make dev-console
```

```python
# Example: verify a custom field was applied
import frappe
frappe.get_meta("Employee").has_field("custom_attendance_approver")

# Example: trigger a background job manually
from nusakura_app.tasks import run_something
run_something()
```

### Test from the browser

Open **http://dev.localhost** in Chrome or Firefox.
Open DevTools → Console and Network tabs to observe errors.

> WebSocket "Invalid origin" errors in the browser console are a known dev-only quirk
> (Frappe bug, not fixable without touching Frappe source). They do not affect staging or production.

### Export fixtures after data model changes

If you changed roles, workflows, print formats, or other configuration documents:

```bash
make dev-export-fixtures app=nusakura_app
```

Commit the exported JSON files along with your code changes.

---

## Dev Tools Setup

The dev stack ships with two optional tools enabled by default: **Adminer** (database UI)
and **Mailpit** (email trap). Both start automatically with `make dev-start` as long as
`COMPOSE_PROFILES=tools` is set in `platform/.env` (it is, by default).

After `make dev-start` the terminal prints their URLs and credentials:

```
  Web:       http://dev.localhost
  Adminer:   http://localhost:8081  (root / <your DB_ROOT_PASSWORD>)
  Mailpit:   http://localhost:8025
  Traefik:   http://localhost:8082
  Logs:      docker compose -f platform/docker-compose.dev.yml logs -f
```

To disable the tools, set `COMPOSE_PROFILES=` (empty) in `platform/.env` and restart.

---

### Adminer — database UI

Adminer gives you a web-based SQL console for MariaDB.

**Access:** http://localhost:8081

**Login credentials:**

| Field | Value |
|-------|-------|
| System | MySQL |
| Server | `mariadb` |
| Username | `root` |
| Password | value of `DB_ROOT_PASSWORD` in `platform/.env` (default: `changeme`) |
| Database | *(leave blank to browse all, or enter site DB name)* |

The site database name is typically the same as your `FRAPPE_SITE_NAME` with hyphens
replaced by underscores (e.g. `dev_localhost`). You can confirm it from the MariaDB console:

```bash
make dev-mariadb
# then inside MySQL:
SHOW DATABASES;
```

**Common uses:**
- Inspect table contents without writing Python
- Run ad-hoc SQL queries during debugging
- Check migration results

---

### Mailpit — email trap

Mailpit intercepts all outgoing email from Frappe so nothing is delivered for real during development.

**Access:** http://localhost:8025

#### One-time setup in ERPNext

This only needs to be done once after the site is created (or after `make dev-destroy`).

1. Open **http://dev.localhost** and log in as Administrator.
2. Search for **Email Account** in the top bar → click **New**.
3. Fill in the form:

   **Basic settings:**

   | Field | Value |
   |-------|-------|
   | Email Account Name | `Mailpit` |
   | Email ID | `notifications@dev.localhost` |
   | Default Outgoing | ✅ checked |
   | Send Notifications From | `notifications@dev.localhost` |

   **Outgoing Mail Settings:**

   | Field | Value |
   |-------|-------|
   | SMTP Server | `mailpit` |
   | Port | `1025` |
   | Use TLS | ❌ unchecked |
   | Use SSL | ❌ unchecked |
   | Login ID | `test` |
   | Password | `mailpit` |

   > Mailpit accepts any username/password (`MP_SMTP_AUTH_ACCEPT_ANY=1` is set in the
   > compose file). Use dummy credentials — do not leave them blank, as Frappe will
   > raise "Password not found" when attempting to send.

4. Click **Save**.
5. Click **Send Test Email** → enter any address → confirm the email appears at
   **http://localhost:8025**.

#### Verify email delivery

After setup, any Frappe action that triggers an email (workflow notifications, password reset,
welcome email, scheduled digests) will appear in Mailpit instead of being sent.

To manually trigger a test:

1. Go to **Email Queue** (search in top bar).
2. Find a queued email → click **Send Now**.
3. Open **http://localhost:8025** — the email should appear within seconds.

If you see **"Password not found for Email Account Mailpit"** in the email queue error,
the Email Account was saved with **Awaiting Password** checked instead of real credentials.
Go back to the Email Account, uncheck Awaiting Password, and set Login ID + Password as above.

---

## Branch Cleanup

### Delete local branch after merge

```bash
git branch -d feat/my-feature      # safe delete (fails if unmerged)
git branch -D feat/my-feature      # force delete
```

### Delete remote branch (if not auto-deleted by GitHub)

```bash
git push upstream --delete feat/my-feature
```

### List all local branches

```bash
git branch
```

### Prune remote-tracking refs

After remote branches are deleted, clean up local refs:

```bash
git fetch --prune
```

### Check for stale branches

```bash
git branch -vv | grep ': gone]'   # branches whose remote is deleted
```

---

## PR Guidelines

### Title

Use Conventional Commit format:

```
feat(leave): add leave encashment policy
fix(overtime): correct rounding for half-day OT
```

### Description template

```markdown
## What changed
Brief summary of the change.

## Why
The reason / linked issue.

## How to test
Step-by-step instructions to verify the change locally.

## Checklist
- [ ] `make dev-migrate` run successfully
- [ ] Fixtures exported (if applicable)
- [ ] `make dev-clear-cache` run after config changes
- [ ] No unrelated changes included
```

### Review expectations

- All PRs must have at least **one approval** before merge.
- Hotfixes may be merged with one approval from any senior developer.
- Never merge your own PR without a review (except for `docs/` and `chore/` trivial changes).
- Resolve all reviewer comments before merging.

### Merge strategy

| Scenario | Strategy |
|----------|----------|
| Feature / fix (single commit) | Squash and merge |
| Feature with meaningful commit history | Merge commit |
| Hotfix | Merge commit (preserve the fix commit as-is) |
| Docs / chore | Squash and merge |

---

## Workflow Diagram

```
                        ┌─────────────────────────────────────────┐
                        │           New work arrives               │
                        └─────────────────┬───────────────────────┘
                                          │
              ┌───────────────────────────┼───────────────────────────────┐
              │                           │                               │
        New feature                   Bug fix                     Hotfix (critical)
       feat/<name>                  fix/<name>                  hotfix/<name>
              │                           │                               │
              └───────────────────────────┼───────────────────────────────┘
                                          │
                                  ┌───────▼────────┐
                                  │  git checkout  │
                                  │  -b <branch>   │
                                  └───────┬────────┘
                                          │
                                  ┌───────▼────────┐
                                  │  Code + commit  │
                                  │  (Conv. Commits)│
                                  └───────┬────────┘
                                          │
                                  ┌───────▼────────┐
                                  │  Test locally   │
                                  │  make dev-*     │
                                  └───────┬────────┘
                                          │
                                  ┌───────▼────────┐
                                  │  Push + open PR │
                                  └───────┬────────┘
                                          │
                                  ┌───────▼────────┐
                                  │  Code review    │
                                  │  ≥ 1 approval   │
                                  └───────┬────────┘
                                          │
                                  ┌───────▼────────┐
                                  │  Merge to main  │
                                  │  Delete branch  │
                                  └───────┬────────┘
                                          │
                                  ┌───────▼────────┐
                                  │  Version bump   │
                                  │  make release-  │
                                  │  version        │
                                  └───────┬────────┘
                                          │
                                  ┌───────▼────────┐
                                  │  git push       │
                                  │  upstream main  │
                                  │  --tags         │
                                  └───────┬────────┘
                                          │
                                  ┌───────▼────────────────────────────┐
                                  │  Production release flow            │
                                  │  → see RELEASE_WORKFLOW.md          │
                                  └────────────────────────────────────┘
```

---

## Troubleshooting

Known issues and their fixes. If you hit a problem not listed here, fix it and add it.

---

### Email links contain `:8000` (e.g. `http://dev.localhost:8000/Email Account/...`)

**Symptom:** Emails sent by Frappe (workflow notifications, password reset, etc.) contain
URLs with an unexpected `:8000` port suffix instead of plain `http://dev.localhost`.

**Root cause:** Frappe appends `webserver_port` from `common_site_config.json` to `host_name`
when building email URLs. If `webserver_port=8000` and the public entry point is Traefik on
port 80, every generated URL will include the wrong port.

**Fix (running site — no destroy needed):**

```bash
make dev-shell
bench set-config -gp webserver_port 80
exit
docker compose -f platform/docker-compose.dev.yml restart frappe-web websocket
```

Verify by sending a test email from **Email Account → Send Test Email** and checking
**http://localhost:8025** — links should now read `http://dev.localhost/...`.

**Why `webserver_port=80` still works for socketio:**
The `dev.localhost` Docker network alias is placed on the Traefik container (port 80),
not on nginx. So when the websocket service internally resolves `dev.localhost:80`, it
reaches Traefik → nginx → frappe-web. Both email URL generation and socketio internal
API calls use the same port.

---

### Email Account save fails: "Password is required or select Awaiting Password"

**Symptom:** Saving the Mailpit Email Account in ERPNext shows a validation error.

**Fix:** Frappe requires either a real password or the **Awaiting Password** checkbox.
Do not use Awaiting Password — Mailpit accepts any credentials. Instead set:

- Login ID: `test`
- Password: `mailpit`

Mailpit is configured with `MP_SMTP_AUTH_ACCEPT_ANY=1` so it will accept these dummy
values without complaint.

---

### Email Queue error: "Password not found for Email Account Mailpit"

**Symptom:** Forcing an email from the Email Queue raises this error even though the
Email Account was saved successfully.

**Root cause:** The Email Account was saved with **Awaiting Password** checked instead
of real credentials. Frappe skips the save validation but still fails at send time.

**Fix:** Open the Email Account, uncheck **Awaiting Password**, set Login ID to `test`
and Password to `mailpit`, then save and retry.

---

### WebSocket "Invalid origin" in browser console

**Symptom:** Browser DevTools shows `socketio_client.js: Error connecting to socket.io:
Invalid origin` on every page load.

**Root cause:** A bug in Frappe's `authenticate.js` — it has a missing `return` after the
namespace check, causing it to fall through to an origin check that fails when the browser
omits the `Origin` header on same-origin HTTP polling requests.

**Status: Waived for development.** This does not affect staging or production. Do not
patch `apps/frappe/` or `apps/erpnext/` source files to work around it.

---

### `make dev-start` bootstrap re-runs from scratch after `make dev-stop`

**Symptom:** After a normal `dev-stop` / `dev-start` cycle, bootstrap runs `bench init`
again instead of detecting the existing site.

**Root cause:** `make dev-destroy` was run (or `development/frappe-bench/` was deleted
manually) without also wiping the MariaDB Docker volume, or vice versa.

**Fix:** Always use `make dev-destroy` for a full reset — it removes both the bench
directory and the MariaDB volume together, keeping them in sync.

```bash
make dev-destroy   # wipes bench dir + DB volume
make dev-start     # clean bootstrap from scratch
```

---

### Assets return 404 (`/assets/frappe/dist/...` not found)

**Symptom:** The browser loads the Frappe login page but JS/CSS assets return 404.

**Root cause:** `bench build` did not run during bootstrap, or nvm was not initialised
before running it (Node.js not in PATH in non-interactive shells).

**Fix:** Run bench build manually inside the container:

```bash
make dev-shell
export NVM_DIR="/home/frappe/.nvm"
source "$NVM_DIR/nvm.sh"
bench build
```

If the issue persists after a destroy/start cycle, check the bootstrap logs:

```bash
make dev-logs-bootstrap
```

---

### pyenv Python install warns about missing modules (bz2, sqlite3, readline, lzma)

**Symptom:** After `pyenv install 3.14.2`, warnings like:

```
WARNING: The Python bz2 extension was not compiled. Missing the bzip2 lib?
WARNING: The Python sqlite3 extension was not compiled. Missing the SQLite3 lib?
WARNING: The Python readline extension was not compiled. Missing the GNU readline lib?
WARNING: The Python lzma extension was not compiled. Missing the lzma lib?
```

**Root cause:** pyenv builds Python from source. The C extension libraries must be
installed on the system **before** running `pyenv install`.

**Fix:**

```bash
# 1. Install all required build dependencies
sudo apt-get update && sudo apt-get install -y \
  libbz2-dev libncurses-dev libreadline-dev libsqlite3-dev \
  libssl-dev liblzma-dev libffi-dev zlib1g-dev tk-dev

# 2. Remove the broken build
pyenv uninstall 3.14.2

# 3. Reinstall cleanly
pyenv install 3.14.2

# 4. Verify
~/.pyenv/versions/3.14.2/bin/python3 -c "import bz2, sqlite3, readline, lzma; print('all good')"
```

---

### VSCode Python interpreter shows "could not be resolved" / `import frappe` fails on WSL2

**Symptom A:** VSCode warning: `Default interpreter path '/workspace/.../python' could not
be resolved`.

**Symptom B:** Red underlines under `import frappe` / `import erpnext` in all Python files.

**Root cause:** Two separate issues compound on WSL2:

1. `/workspace` doesn't exist — the bench venv `.pth` files can't find Frappe source paths.
2. The bench venv `python` is a symlink to `/home/frappe/.pyenv/...` — a path that only
   exists inside the Docker container, not on the WSL2 host.

**Fix:** Follow the full [Optimized setup for WSL2 + VSCode](#optimized-setup-for-wsl2--vscode-recommended) steps above. In short:

```bash
# 1. Install build deps + pyenv + Python 3.14.2 on WSL2
sudo apt-get install -y libbz2-dev libncurses-dev libreadline-dev libsqlite3-dev \
  libssl-dev liblzma-dev libffi-dev zlib1g-dev tk-dev
curl https://pyenv.run | bash
# add pyenv init to ~/.zshrc, reload, then:
pyenv install 3.14.2

# 2. Create /workspace symlink
sudo ln -sf /path/to/frappe_builder /workspace
```

After this, open the app folder via `make code APP=nusakura_app` from `platform/` — the
`.vscode/settings.json` committed to each app already sets `python.defaultInterpreterPath`
to `~/.pyenv/versions/3.14.2/bin/python3`, so no manual interpreter selection is needed.

---

## Related Documents

| Document | Location | Purpose |
|----------|----------|---------|
| Release Workflow | `nusakura_app/docs/RELEASE_WORKFLOW.md` | Full release-to-production flow, custom field gate |
| Platform .env | `platform/.env.example` | All environment variables |
| Platform Makefile | `platform/Makefile` | All dev commands |
| Apps Registry | `platform/apps.json` | App URLs and branches |
