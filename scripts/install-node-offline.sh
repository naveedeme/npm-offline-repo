#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NODE_RUNTIME_DIR="${NODE_RUNTIME_DIR:-${SCRIPT_DIR}/runtimes/node}"
NVM_RUNTIME_DIR="${NVM_RUNTIME_DIR:-${SCRIPT_DIR}/runtimes/nvm}"
NVM_DIR="${NVM_DIR:-${HOME}/.nvm}"
ENV_FILE="${ENV_FILE:-${SCRIPT_DIR}/node-env.sh}"

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "x64" ;;
    aarch64|arm64) echo "arm64" ;;
    armv7l) echo "armv7l" ;;
    ppc64le) echo "ppc64le" ;;
    s390x) echo "s390x" ;;
    *)
      echo "Error: unsupported CPU architecture: $(uname -m)" >&2
      exit 1
      ;;
  esac
}

ARCH="${NODE_RUNTIME_ARCH:-$(detect_arch)}"
PLATFORM="${NODE_RUNTIME_PLATFORM:-linux}"

if [ ! -d "$NODE_RUNTIME_DIR" ]; then
  echo "Error: missing Node.js runtime directory: $NODE_RUNTIME_DIR" >&2
  exit 1
fi

if [ ! -d "$NVM_RUNTIME_DIR" ]; then
  echo "Error: missing nvm runtime directory: $NVM_RUNTIME_DIR" >&2
  exit 1
fi

mapfile -t NODE_MATCHES < <(find "$NODE_RUNTIME_DIR" -maxdepth 1 -type f -name "node-v*-${PLATFORM}-${ARCH}.tar.xz" | sort -V)
mapfile -t NVM_MATCHES < <(find "$NVM_RUNTIME_DIR" -maxdepth 1 -type f -name "nvm-v*.tar.gz" | sort -V)

if [ "${#NODE_MATCHES[@]}" -eq 0 ]; then
  echo "Error: no Node.js runtime found for ${PLATFORM}-${ARCH}." >&2
  echo "Available runtimes:" >&2
  find "$NODE_RUNTIME_DIR" -maxdepth 1 -type f -name "node-v*.tar.xz" -printf '  %f\n' >&2 || true
  exit 1
fi

if [ "${#NVM_MATCHES[@]}" -eq 0 ]; then
  echo "Error: no nvm archive found in ${NVM_RUNTIME_DIR}." >&2
  exit 1
fi

NODE_TARBALL="${NODE_MATCHES[-1]}"
NVM_TARBALL="${NVM_MATCHES[-1]}"
NODE_SLUG="$(basename "$NODE_TARBALL" .tar.xz)"
NODE_VERSION="$(echo "$NODE_SLUG" | sed -E "s/^node-(v[0-9][0-9.]*)-${PLATFORM}-${ARCH}$/\1/")"

if [ "$NODE_VERSION" = "$NODE_SLUG" ]; then
  echo "Error: could not parse Node.js version from ${NODE_SLUG}." >&2
  exit 1
fi

if [ -f "${NODE_RUNTIME_DIR}/SHASUMS256.txt" ] && command -v sha256sum >/dev/null 2>&1; then
  (
    cd "$NODE_RUNTIME_DIR"
    grep " $(basename "$NODE_TARBALL")$" SHASUMS256.txt | sha256sum -c -
  )
fi

if [ -f "${NVM_RUNTIME_DIR}/SHASUMS256.txt" ] && command -v sha256sum >/dev/null 2>&1; then
  (
    cd "$NVM_RUNTIME_DIR"
    grep " $(basename "$NVM_TARBALL")$" SHASUMS256.txt | sha256sum -c -
  )
fi

mkdir -p "$NVM_DIR"

if [ ! -f "${NVM_DIR}/nvm.sh" ]; then
  tar -xzf "$NVM_TARBALL" -C "$NVM_DIR" --strip-components=1
fi

mkdir -p "${NVM_DIR}/.cache/bin/${NODE_SLUG}"
cp "$NODE_TARBALL" "${NVM_DIR}/.cache/bin/${NODE_SLUG}/${NODE_SLUG}.tar.xz"

set +u
. "${NVM_DIR}/nvm.sh"
set -u

nvm install --offline "$NODE_VERSION" --default
nvm use "$NODE_VERSION"

cat > "$ENV_FILE" <<ENV
export NVM_DIR="${NVM_DIR}"
[ -s "\$NVM_DIR/nvm.sh" ] && . "\$NVM_DIR/nvm.sh"
nvm use --silent default >/dev/null
ENV

echo "nvm installed at: $NVM_DIR"
node -v
npm -v
echo ""
echo "Use Node.js and npm in this shell with:"
echo "  source \"${ENV_FILE}\""
