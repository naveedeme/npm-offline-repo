#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY_URL="${REGISTRY_URL:-http://127.0.0.1:4873}"
CACHE_DIR="${CACHE_DIR:-${SCRIPT_DIR}/npm-cache}"

usage() {
  echo "Usage: $0 <package-set> <target-path>"
  echo ""
  echo "Available package sets:"
  find "${SCRIPT_DIR}/package-sets" -mindepth 1 -maxdepth 1 -type d -printf '  - %f\n' 2>/dev/null || true
}

if [ $# -ne 2 ]; then
  usage
  exit 1
fi

SET_NAME="$1"
TARGET_PATH="$2"
SET_DIR="${SCRIPT_DIR}/package-sets/${SET_NAME}"
PREBUILT_TARBALL="${SCRIPT_DIR}/node_modules_by_framework/${SET_NAME}-node_modules.tar.gz"
USE_PREBUILT="${USE_PREBUILT:-1}"

if [ ! -f "${SET_DIR}/package.json" ] || [ ! -f "${SET_DIR}/package-lock.json" ]; then
  echo "Error: unknown package set '${SET_NAME}'." >&2
  usage
  exit 1
fi

mkdir -p "$TARGET_PATH"
cp "${SET_DIR}/package.json" "${TARGET_PATH}/package.json"
cp "${SET_DIR}/package-lock.json" "${TARGET_PATH}/package-lock.json"

cat > "${TARGET_PATH}/.npmrc" <<NPMRC
registry=${REGISTRY_URL}
cache=${CACHE_DIR}
offline=true
prefer-offline=true
legacy-peer-deps=true
audit=false
fund=false
update-notifier=false
replace-registry-host=always
NPMRC

if [ "$USE_PREBUILT" = "1" ] && [ -f "$PREBUILT_TARBALL" ]; then
  tar -xzf "$PREBUILT_TARBALL" -C "$TARGET_PATH"
else
  (
    cd "$TARGET_PATH"
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD="${PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD:-1}" \
    PUPPETEER_SKIP_DOWNLOAD="${PUPPETEER_SKIP_DOWNLOAD:-1}" \
    CYPRESS_INSTALL_BINARY="${CYPRESS_INSTALL_BINARY:-0}" \
    ELECTRON_SKIP_BINARY_DOWNLOAD="${ELECTRON_SKIP_BINARY_DOWNLOAD:-1}" \
    npm ci --offline --legacy-peer-deps --replace-registry-host=always --registry "$REGISTRY_URL" --cache "$CACHE_DIR"
  )
fi

echo "Installed '${SET_NAME}' into ${TARGET_PATH}"
