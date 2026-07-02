#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ./install-framework-offline.sh <ubuntu-version> <package-set> <target-path>

Example:
  ./install-framework-offline.sh ubuntu-22.04 react-vite /home/user/my-react-app

Put the downloaded release files in this same directory first:
  npm-offline-repository-ubuntu-22.04.tar.gz
  react-vite-node_modules-ubuntu-22.04.tar.gz

If GitHub split a large asset, keep all .part-* files in this directory too.
USAGE
}

if [ $# -ne 3 ]; then
  usage
  exit 1
fi

VARIANT="$1"
PACKAGE_SET="$2"
TARGET_PATH="$3"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_TARBALL="npm-offline-repository-${VARIANT}.tar.gz"
MODULE_TARBALL="${PACKAGE_SET}-node_modules-${VARIANT}.tar.gz"

cd "$SCRIPT_DIR"

assemble_if_split() {
  local output="$1"
  if [ -f "$output" ]; then
    return
  fi

  if compgen -G "${output}.part-*" >/dev/null; then
    echo "Reassembling ${output}..."
    cat "${output}".part-* > "$output"
    return
  fi
}

assemble_if_split "$REPO_TARBALL"
assemble_if_split "$MODULE_TARBALL"

if [ ! -f "install-from-offline-repo.sh" ]; then
  if [ ! -f "$REPO_TARBALL" ]; then
    echo "Error: missing ${REPO_TARBALL}" >&2
    echo "Download it from the GitHub release, or provide split ${REPO_TARBALL}.part-* files." >&2
    exit 1
  fi

  echo "Extracting ${REPO_TARBALL}..."
  tar -xzf "$REPO_TARBALL"
fi

mkdir -p node_modules_by_framework
if [ -f "$MODULE_TARBALL" ]; then
  cp "$MODULE_TARBALL" "node_modules_by_framework/${PACKAGE_SET}-node_modules.tar.gz"
else
  echo "Warning: ${MODULE_TARBALL} not found. Falling back to npm ci from the offline registry/cache." >&2
  export USE_PREBUILT=0
fi

./install-node-offline.sh
# shellcheck disable=SC1091
source ./node-env.sh

if ! command -v verdaccio >/dev/null 2>&1; then
  npm install -g verdaccio --offline --cache ./npm-cache
fi

REGISTRY_URL="${REGISTRY_URL:-http://127.0.0.1:4873}"
REGISTRY_LOG="${REGISTRY_LOG:-${SCRIPT_DIR}/offline-registry.log}"
REGISTRY_STARTED=0

if ! npm ping --registry "$REGISTRY_URL" >/dev/null 2>&1; then
  echo "Starting local offline registry at ${REGISTRY_URL}..."
  ./start-offline-registry.sh > "$REGISTRY_LOG" 2>&1 &
  REGISTRY_PID=$!
  REGISTRY_STARTED=1

  for _ in $(seq 1 60); do
    if npm ping --registry "$REGISTRY_URL" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  if ! npm ping --registry "$REGISTRY_URL" >/dev/null 2>&1; then
    echo "Error: offline registry did not start. See ${REGISTRY_LOG}" >&2
    exit 1
  fi
fi

./install-from-offline-repo.sh "$PACKAGE_SET" "$TARGET_PATH"

echo ""
echo "Installed ${PACKAGE_SET} into ${TARGET_PATH}"
if [ "$REGISTRY_STARTED" = "1" ]; then
  echo "Offline registry is still running in the background, PID ${REGISTRY_PID}."
  echo "Stop it later with: kill ${REGISTRY_PID}"
fi
