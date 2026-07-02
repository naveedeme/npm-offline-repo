#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY_URL="${REGISTRY_URL:-http://127.0.0.1:4873}"
CACHE_DIR="${CACHE_DIR:-${SCRIPT_DIR}/npm-cache}"
TMP_DIR="${TMP_DIR:-$(mktemp -d)}"

cleanup() {
  if [ -n "${VERDACCIO_PID:-}" ] && kill -0 "$VERDACCIO_PID" >/dev/null 2>&1; then
    kill "$VERDACCIO_PID" >/dev/null 2>&1 || true
    wait "$VERDACCIO_PID" 2>/dev/null || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

"${SCRIPT_DIR}/start-offline-registry.sh" > "${TMP_DIR}/registry.log" 2>&1 &
VERDACCIO_PID=$!

for _ in $(seq 1 60); do
  if npm ping --registry "$REGISTRY_URL" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! npm ping --registry "$REGISTRY_URL" >/dev/null 2>&1; then
  echo "Error: offline registry did not start. Log: ${TMP_DIR}/registry.log" >&2
  exit 1
fi

for set_dir in "${SCRIPT_DIR}/package-sets"/*; do
  [ -d "$set_dir" ] || continue
  set_name="$(basename "$set_dir")"
  target="${TMP_DIR}/${set_name}"
  mkdir -p "$target"
  cp "${set_dir}/package.json" "${target}/package.json"
  cp "${set_dir}/package-lock.json" "${target}/package-lock.json"
  echo "Verifying ${set_name}..."
  (
    cd "$target"
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 \
    PUPPETEER_SKIP_DOWNLOAD=1 \
    CYPRESS_INSTALL_BINARY=0 \
    ELECTRON_SKIP_BINARY_DOWNLOAD=1 \
    npm ci --offline --ignore-scripts --legacy-peer-deps --replace-registry-host=always --registry "$REGISTRY_URL" --cache "$CACHE_DIR"
  )
done

echo "Offline repository verification passed."
