#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-4873}"
CONFIG="${SCRIPT_DIR}/verdaccio/config.yaml"

if ! command -v verdaccio >/dev/null 2>&1; then
  echo "Error: verdaccio is not installed." >&2
  echo "Install it from this offline repository first:" >&2
  echo "  npm install -g verdaccio --offline --cache \"${SCRIPT_DIR}/npm-cache\"" >&2
  exit 1
fi

if [ ! -f "$CONFIG" ]; then
  echo "Error: missing Verdaccio config: $CONFIG" >&2
  exit 1
fi

cd "${SCRIPT_DIR}/verdaccio"
echo "Starting offline npm registry at http://${HOST}:${PORT}"
echo "Use from this machine: npm set registry http://127.0.0.1:${PORT}"
verdaccio --config "$CONFIG" --listen "${HOST}:${PORT}"
