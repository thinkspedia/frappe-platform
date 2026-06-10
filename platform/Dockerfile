# =============================================================================
# Frappe Platform — Layered Dockerfile
#
# Builds on top of the upstream frappe/build and frappe/base images so we
# don't have to manage Python, Node, gcc, MariaDB headers, or any other
# system dependency ourselves. Frappe's published images handle all of that.
#
# Stages:
#   development  — FROM frappe/build: bench already installed, apps bind-mounted
#   prod-builder — FROM frappe/build: installs org apps + compiles assets
#   production   — FROM frappe/base:  minimal runtime, copied from prod-builder
#
# Required upstream images (pulled automatically):
#   frappe/build:${FRAPPE_BRANCH}  — has Python, Node, bench CLI, all build deps
#   frappe/base:${FRAPPE_BRANCH}   — has runtime deps only (no build tools)
#
# Build args: set defaults here or override via platform/.env → docker-compose.
# NEVER hardcode versions — change the ARG defaults or pass at build time.
# =============================================================================

ARG FRAPPE_BRANCH=version-16
ARG FRAPPE_IMAGE_PREFIX=frappe

# =============================================================================
# STAGE 1 — development
# Uses frappe/erpnext directly (frappe + erpnext pre-installed by upstream).
# Scripts are bind-mounted by docker-compose.dev.yml so no rebuild is needed
# when bootstrap.sh or configure-site.sh change.
# This stage exists only to document the dev base — the compose file uses
# the upstream image directly and bind-mounts scripts at runtime.
# =============================================================================
FROM ${FRAPPE_IMAGE_PREFIX}/erpnext:${FRAPPE_BRANCH} AS development

ENV DEVELOPER_MODE=1

USER frappe
WORKDIR /home/frappe/frappe-bench

VOLUME ["/home/frappe/frappe-bench/sites"]
EXPOSE 8000 9000

# =============================================================================
# STAGE 2 — prod-builder
# Installs all apps from apps.json (private repos via GITHUB_TOKEN secret),
# runs asset compilation, then strips build caches.
# The GITHUB_TOKEN BuildKit secret is never written to an image layer.
# =============================================================================
FROM ${FRAPPE_IMAGE_PREFIX}/build:${FRAPPE_BRANCH} AS prod-builder

ARG FRAPPE_BRANCH
ARG CACHE_BUST=""

USER frappe

# apps.json lists all apps to install (public + private repos)
COPY platform/apps.json /opt/frappe/apps.json

RUN --mount=type=secret,id=github_token \
    : "${CACHE_BUST}" \
    && GITHUB_TOKEN=$(cat /run/secrets/github_token 2>/dev/null || echo "") \
    && python3 - <<'PYEOF'
import json, subprocess, os

token    = os.environ.get("GITHUB_TOKEN", "")
apps     = json.load(open("/opt/frappe/apps.json"))
bench    = "/home/frappe/frappe-bench"

for app in apps:
    url    = app["url"]
    branch = app.get("branch", "main")
    name   = url.rstrip("/").split("/")[-1].replace(".git", "")

    # Inject token for private GitHub repos — never logged or cached
    auth_url = url
    if token and "github.com" in url and "https://" in url:
        auth_url = url.replace("https://", f"https://{token}@")

    print(f"[prod-builder] bench get-app {name} @ {branch}", flush=True)
    subprocess.run(
        ["bench", "get-app", "--branch", branch, auth_url],
        cwd=bench, check=True,
    )
PYEOF

# Compile production JS/CSS assets and strip caches to keep layer small
RUN cd /home/frappe/frappe-bench \
    && bench build --production \
    && find . -path "*/.cache" -type d -exec rm -rf {} + 2>/dev/null || true \
    && find . -name "*.map" -delete 2>/dev/null || true \
    && find apps -mindepth 1 -path "*/.git" -type d | xargs rm -rf

# =============================================================================
# STAGE 3 — production
# Minimal runtime image: frappe/base (no build tools) + bench from prod-builder.
# Reuses upstream entrypoint scripts from resources/core/ exactly as the
# layered Containerfile does.
# =============================================================================
FROM ${FRAPPE_IMAGE_PREFIX}/base:${FRAPPE_BRANCH} AS production

USER frappe

# Copy fully-built bench from prod-builder (no build tools travel with it)
COPY --from=prod-builder --chown=frappe:frappe \
    /home/frappe/frappe-bench /home/frappe/frappe-bench

WORKDIR /home/frappe/frappe-bench

# Move compiled assets out of sites/ so they survive volume mounts.
# main-entrypoint.sh symlinks them back at container start.
RUN cp -r sites/assets assets && rm -rf sites/assets

VOLUME ["/home/frappe/frappe-bench/sites", "/home/frappe/frappe-bench/logs"]

USER root

# Reuse upstream entrypoint scripts verbatim
COPY resources/core/main-entrypoint.sh /usr/local/bin/entrypoint.sh
COPY resources/core/start.sh /usr/local/bin/start.sh
COPY platform/scripts/configure-site.sh /usr/local/bin/configure-site.sh
RUN chmod 755 \
    /usr/local/bin/entrypoint.sh \
    /usr/local/bin/start.sh \
    /usr/local/bin/configure-site.sh

USER frappe

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["start.sh"]
