#!/bin/bash
# =============================================================================
# Dokploy deployment helper
#
# Usage:
#   dokploy-deploy.sh <server> <token> <project-name> <tag> [--status]
#
# What it does:
#   1. Finds the Compose service in Dokploy matching <project-name>
#   2. Updates IMAGE_TAG environment variable to <tag>
#   3. Triggers a redeploy
#   4. Polls deployment status until done or timeout
# =============================================================================
set -euo pipefail

SERVER="${1:?Usage: $0 <server> <token> <project-name> <tag>}"
TOKEN="${2:?Missing token}"
PROJECT_NAME="${3:?Missing project name}"
TAG="${4:-}"
STATUS_ONLY="${5:-}"

API="${SERVER%/}/api"
AUTH=(-H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json")

# ---------------------------------------------------------------------------
# Helper: call Dokploy API
# ---------------------------------------------------------------------------
api_get() {
  curl -sf "${AUTH[@]}" "${API}/$1"
}

api_post() {
  local endpoint="$1"
  local body="$2"
  curl -sf -X POST "${AUTH[@]}" -d "$body" "${API}/$endpoint"
}

# ---------------------------------------------------------------------------
# Find compose project by name
# ---------------------------------------------------------------------------
echo "[dokploy] Looking up project '${PROJECT_NAME}'..."

PROJECTS=$(api_get "compose.all" 2>/dev/null || echo "[]")
COMPOSE_ID=$(echo "$PROJECTS" | python3 -c "
import json, sys
projects = json.load(sys.stdin)
for p in projects:
    if p.get('name') == '${PROJECT_NAME}':
        print(p['composeId'])
        sys.exit(0)
print('')
" 2>/dev/null || echo "")

if [ -z "$COMPOSE_ID" ]; then
  echo "[dokploy] ERROR: Compose project '${PROJECT_NAME}' not found."
  echo "[dokploy] Available projects:"
  echo "$PROJECTS" | python3 -c "
import json, sys
for p in json.load(sys.stdin): print(f\"  - {p.get('name', '?')} ({p.get('composeId','?')})\")
" 2>/dev/null || true
  exit 1
fi

echo "[dokploy] Found composeId: ${COMPOSE_ID}"

# ---------------------------------------------------------------------------
# Status only mode
# ---------------------------------------------------------------------------
if [ "${STATUS_ONLY}" = "--status" ]; then
  STATUS=$(api_get "compose.one?composeId=${COMPOSE_ID}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(f\"Name:   {data.get('name')}\")
print(f\"Status: {data.get('composeStatus')}\")
" 2>/dev/null)
  echo "$STATUS"
  exit 0
fi

# ---------------------------------------------------------------------------
# Update IMAGE_TAG environment variable in Dokploy
# ---------------------------------------------------------------------------
echo "[dokploy] Updating IMAGE_TAG to '${TAG}'..."

CURRENT_ENV=$(api_get "compose.one?composeId=${COMPOSE_ID}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
env = data.get('env', '')
lines = [l for l in env.splitlines() if not l.startswith('IMAGE_TAG=')]
lines.append('IMAGE_TAG=${TAG}')
print('\n'.join(lines))
" 2>/dev/null)

api_post "compose.update" "{\"composeId\":\"${COMPOSE_ID}\",\"env\":$(python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))" <<< "$CURRENT_ENV")}" > /dev/null

# ---------------------------------------------------------------------------
# Trigger redeploy
# ---------------------------------------------------------------------------
echo "[dokploy] Triggering redeploy..."
api_post "compose.redeploy" "{\"composeId\":\"${COMPOSE_ID}\"}" > /dev/null

# ---------------------------------------------------------------------------
# Poll until done (max 10 min)
# ---------------------------------------------------------------------------
echo "[dokploy] Waiting for deployment to complete..."
TIMEOUT=600
ELAPSED=0
INTERVAL=10

while [ $ELAPSED -lt $TIMEOUT ]; do
  sleep $INTERVAL
  ELAPSED=$((ELAPSED + INTERVAL))

  STATUS=$(api_get "compose.one?composeId=${COMPOSE_ID}" | python3 -c "
import json, sys
print(json.load(sys.stdin).get('composeStatus', 'unknown'))
" 2>/dev/null || echo "unknown")

  echo "[dokploy] Status after ${ELAPSED}s: ${STATUS}"

  case "$STATUS" in
    done|running)
      echo "[dokploy] Deployment successful — ${PROJECT_NAME}:${TAG}"
      exit 0
      ;;
    error|failed)
      echo "[dokploy] Deployment FAILED — check Dokploy UI for logs"
      exit 1
      ;;
  esac
done

echo "[dokploy] Timed out after ${TIMEOUT}s — check Dokploy UI for status"
exit 1
