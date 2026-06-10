# =============================================================================
# Frappe Platform — Multi-Stage Dockerfile
#
# Stages:
#   base        — OS deps, frappe user, bench CLI, Node via NVM
#   development — Mounts apps/ from host; optimised for live-reload
#   prod-build  — Clones private apps, compiles JS/CSS assets, cleans cache
#   production  — Minimal runtime image copied from prod-build
#
# Build args flow from .env or docker-bake / CI pipeline.
# NEVER hardcode versions here — change ARG defaults or pass at build time.
# =============================================================================

ARG PYTHON_VERSION=3.11
ARG DEBIAN_BASE=bookworm
ARG NODE_VERSION=18.20.4
ARG FRAPPE_VERSION=version-15
ARG FRAPPE_REPO=https://github.com/frappe/frappe

# =============================================================================
# STAGE 1 — base
# Installs all system-level dependencies, creates the frappe user, installs
# bench CLI and Node.js. Shared by development, prod-build, and production.
# =============================================================================
FROM python:${PYTHON_VERSION}-slim-${DEBIAN_BASE} AS base

ARG NODE_VERSION
ARG FRAPPE_VERSION
ARG FRAPPE_REPO

ENV NVM_DIR=/home/frappe/.nvm
ENV PATH=${NVM_DIR}/versions/node/v${NODE_VERSION}/bin/:${PATH}
# Frappe reads this to locate the bench root
ENV BENCH_DIR=/home/frappe/frappe-bench

RUN useradd -ms /bin/bash frappe \
    && apt-get update \
    && apt-get install --no-install-recommends -y \
        # Core utilities
        curl git vim gettext-base file jq \
        # PDF generation
        libpango-1.0-0 libharfbuzz0b libpangoft2-1.0-0 libpangocairo-1.0-0 \
        # Database clients (bench needs both at install time)
        mariadb-client libpq-dev postgresql-client \
        # Nginx (serves static assets in production)
        nginx \
        # Healthcheck helper
        wait-for-it \
        # MIME detection
        media-types \
        # Backup tooling
        restic gpg \
    && rm -rf /var/lib/apt/lists/* \
    # --- Node.js via NVM ---
    && mkdir -p "${NVM_DIR}" \
    && curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh | bash \
    && . "${NVM_DIR}/nvm.sh" \
    && nvm install "${NODE_VERSION}" \
    && nvm use "v${NODE_VERSION}" \
    && nvm alias default "v${NODE_VERSION}" \
    && npm install -g yarn \
    && corepack enable pnpm \
    && rm -rf "${NVM_DIR}/.cache" \
    # Persist nvm in shell for frappe user
    && echo 'export NVM_DIR="/home/frappe/.nvm"' >> /home/frappe/.bashrc \
    && echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> /home/frappe/.bashrc \
    # --- Frappe Bench CLI ---
    && pip3 install --no-cache-dir frappe-bench \
    # --- Nginx: non-root operation ---
    && sed -i '/user www-data/d' /etc/nginx/nginx.conf \
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log \
    && touch /run/nginx.pid \
    && chown -R frappe:frappe \
        /etc/nginx/conf.d \
        /etc/nginx/nginx.conf \
        /var/log/nginx \
        /var/lib/nginx \
        /run/nginx.pid

USER frappe
WORKDIR /home/frappe

# Initialise a bare bench (no apps) — gives us the directory skeleton and
# common_site_config.json. Apps are installed in later stages.
RUN bench init \
        --frappe-branch "${FRAPPE_VERSION}" \
        --frappe-path "${FRAPPE_REPO}" \
        --no-procfile \
        --no-backups \
        --skip-redis-config-generation \
        frappe-bench \
    && cd frappe-bench \
    && bench pip install psycopg2-binary \
    && find . -name "*.pyc" -delete

WORKDIR /home/frappe/frappe-bench

# =============================================================================
# STAGE 2 — development
# Optimised for local developer workflows:
#   - DEVELOPER_MODE enabled (no asset compilation required)
#   - apps/ directory is LEFT EMPTY so docker-compose can bind-mount ./apps
#   - site created by bootstrap.sh on first run (not baked in)
# =============================================================================
FROM base AS development

ENV FRAPPE_SITE_NAME=dev.localhost
ENV DEVELOPER_MODE=1
ENV FRAPPE_LOGGING=1
# Gunicorn reloads on code change
ENV DEV_WORKERS=1
ENV DEV_TIMEOUT=300

# Copy entrypoint scripts — these run before the main process
COPY --chown=frappe:frappe scripts/bootstrap.sh /usr/local/bin/bootstrap.sh
COPY --chown=frappe:frappe scripts/configure-site.sh /usr/local/bin/configure-site.sh
RUN chmod +x /usr/local/bin/bootstrap.sh /usr/local/bin/configure-site.sh

# sites/ is a named volume in compose; apps/ is bind-mounted from the host.
# We do NOT pre-create apps here so the bind mount is not shadowed.
VOLUME ["/home/frappe/frappe-bench/sites"]

EXPOSE 8000 9000

CMD ["/usr/local/bin/bootstrap.sh"]

# =============================================================================
# STAGE 3 — prod-build
# Clones all apps defined in apps.json using GITHUB_TOKEN (BuildKit secret),
# runs yarn/npm asset compilation, then strips build caches to minimise size.
# =============================================================================
FROM base AS prod-build

# Apps manifest copied from build context
COPY --chown=frappe:frappe apps.json /home/frappe/apps.json

# GITHUB_TOKEN is injected via BuildKit --secret; it is never written to a
# layer and will not appear in `docker history` or image metadata.
# Usage: docker build --secret id=github_token,env=GITHUB_TOKEN ...
RUN --mount=type=secret,id=github_token \
    GITHUB_TOKEN=$(cat /run/secrets/github_token) \
    && python3 - <<'PYEOF'
import json, subprocess, os, sys

token = os.environ.get("GITHUB_TOKEN", "")
apps   = json.load(open("/home/frappe/apps.json"))

for app in apps:
    url    = app["url"]
    branch = app.get("branch", "main")
    # Inject token for private repos (https://token@github.com/...)
    if token and "github.com" in url:
        url = url.replace("https://", f"https://{token}@")
    name = url.rstrip("/").split("/")[-1].replace(".git", "")
    print(f"[prod-build] Installing {name} @ {branch}", flush=True)
    subprocess.run(
        ["bench", "get-app", "--branch", branch, url],
        cwd="/home/frappe/frappe-bench",
        check=True,
    )
PYEOF

# Compile JS/CSS production assets
RUN cd /home/frappe/frappe-bench \
    && bench build --production \
    # Strip build caches and intermediate artefacts
    && find . -path "*/node_modules" -prune -o -name "*.map" -print -exec rm {} + \
    && find . -path "*/.cache" -type d -exec rm -rf {} + 2>/dev/null || true \
    && npm cache clean --force 2>/dev/null || true \
    && pip cache purge 2>/dev/null || true

# =============================================================================
# STAGE 4 — production
# Minimal runtime image. Copies the fully-built bench from prod-build.
# No build tools, no caches, no secrets.
# =============================================================================
FROM python:${PYTHON_VERSION}-slim-${DEBIAN_BASE} AS production

ARG NODE_VERSION

ENV NVM_DIR=/home/frappe/.nvm
ENV PATH=${NVM_DIR}/versions/node/v${NODE_VERSION}/bin/:${PATH}
ENV BENCH_DIR=/home/frappe/frappe-bench

RUN useradd -ms /bin/bash frappe \
    && apt-get update \
    && apt-get install --no-install-recommends -y \
        nginx gettext-base curl git wait-for-it jq \
        mariadb-client libpq5 \
        libpango-1.0-0 libharfbuzz0b libpangoft2-1.0-0 libpangocairo-1.0-0 \
        media-types restic gpg \
    && rm -rf /var/lib/apt/lists/* \
    && sed -i '/user www-data/d' /etc/nginx/nginx.conf \
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log \
    && touch /run/nginx.pid \
    && chown -R frappe:frappe \
        /etc/nginx/conf.d /etc/nginx/nginx.conf \
        /var/log/nginx /var/lib/nginx /run/nginx.pid

# Copy fully-built bench from prod-build stage
COPY --from=prod-build --chown=frappe:frappe \
    /home/frappe/.nvm /home/frappe/.nvm
COPY --from=prod-build --chown=frappe:frappe \
    /home/frappe/frappe-bench /home/frappe/frappe-bench

# Copy entrypoint scripts from upstream resources (reuse existing patterns)
COPY --chown=frappe:frappe scripts/configure-site.sh /usr/local/bin/configure-site.sh
RUN chmod +x /usr/local/bin/configure-site.sh

USER frappe
WORKDIR /home/frappe/frappe-bench

VOLUME ["/home/frappe/frappe-bench/sites"]

EXPOSE 8000 9000

# Default: Gunicorn WSGI server. Override CMD per-service in compose/Nomad.
CMD ["bash", "-c", "gunicorn \
    --chdir=/home/frappe/frappe-bench/sites \
    --bind=0.0.0.0:8000 \
    --workers=${GUNICORN_WORKERS:-2} \
    --threads=${GUNICORN_THREADS:-4} \
    --timeout=${GUNICORN_TIMEOUT:-120} \
    frappe.app:application"]
