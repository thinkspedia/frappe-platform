#!/bin/bash
set -e

ASSETS_PATH="/home/frappe/frappe-bench/sites/assets"
BAKED_PATH="/home/frappe/frappe-bench/assets"

# Copy assets into the shared sites volume so the frontend (nginx) container
# can serve them directly. A symlink won't work because the frontend is a
# different image and the symlink target path resolves to its own filesystem.
echo "Copying fresh assets to volume..."
rm -rf "$ASSETS_PATH"
cp -r "$BAKED_PATH" "$ASSETS_PATH"

exec "$@"
