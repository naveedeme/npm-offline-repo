#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGES_DIR="${PACKAGES_DIR:-${ROOT_DIR}/packages}"
BUILD_DIR="${BUILD_DIR:-${ROOT_DIR}/artifacts/offline-repository}"
BUILD_PARENT="$(dirname "$BUILD_DIR")"
mkdir -p "$BUILD_PARENT"
BUILD_DIR="$(cd "$BUILD_PARENT" && pwd)/$(basename "$BUILD_DIR")"
if [[ "$BUILD_DIR" != "${ROOT_DIR}/artifacts/"* ]]; then
  echo "Error: BUILD_DIR must resolve under ${ROOT_DIR}/artifacts." >&2
  exit 1
fi

REGISTRY_PORT="${REGISTRY_PORT:-4873}"
REGISTRY_HOST="${REGISTRY_HOST:-127.0.0.1}"
REGISTRY_LISTEN="${REGISTRY_LISTEN:-${REGISTRY_HOST}:${REGISTRY_PORT}}"
REGISTRY_URL="${REGISTRY_URL:-http://${REGISTRY_HOST}:${REGISTRY_PORT}}"
NODE_VERSION_REQUIRED="${NODE_VERSION_REQUIRED:-}"
BUILD_VARIANT="${BUILD_VARIANT:-unknown-linux}"
PACKAGE_SET="${PACKAGE_SET:-}"
NPM_CACHE_DIR="${BUILD_DIR}/npm-cache"
VERDACCIO_STORAGE_DIR="${BUILD_DIR}/verdaccio/storage"
PACKAGE_SETS_DIR="${BUILD_DIR}/package-sets"
NODE_MODULES_DIR="${BUILD_DIR}/node_modules_by_framework"
NODE_RUNTIME_DIR="${BUILD_DIR}/runtimes/node"
NVM_RUNTIME_DIR="${BUILD_DIR}/runtimes/nvm"
REPORTS_DIR="${BUILD_DIR}/reports"
LOG_DIR="${BUILD_DIR}/logs"

if ! command -v node >/dev/null 2>&1; then
  echo "Error: node is required." >&2
  exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "Error: npm is required." >&2
  exit 1
fi

if ! command -v verdaccio >/dev/null 2>&1; then
  echo "Error: verdaccio is required. Install it first: npm install -g verdaccio@latest" >&2
  exit 1
fi

if ! command -v tar >/dev/null 2>&1; then
  echo "Error: tar is required." >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "Error: curl is required to download the Node.js runtime." >&2
  exit 1
fi

if [ -n "$NODE_VERSION_REQUIRED" ] && [ "$(node -v)" != "$NODE_VERSION_REQUIRED" ]; then
  echo "Error: expected Node.js ${NODE_VERSION_REQUIRED}, found $(node -v)." >&2
  exit 1
fi

rm -rf "$BUILD_DIR"
mkdir -p "$NPM_CACHE_DIR" "$VERDACCIO_STORAGE_DIR" "$PACKAGE_SETS_DIR" "$NODE_MODULES_DIR" "$NODE_RUNTIME_DIR" "$NVM_RUNTIME_DIR" "$REPORTS_DIR" "$LOG_DIR"

ONLINE_CONFIG="${BUILD_DIR}/verdaccio-online.yaml"
OFFLINE_CONFIG="${BUILD_DIR}/verdaccio-offline.yaml"

cat > "$ONLINE_CONFIG" <<YAML
storage: ${VERDACCIO_STORAGE_DIR}
uplinks:
  npmjs:
    url: https://registry.npmjs.org/
packages:
  '@*/*':
    access: \$all
    proxy: npmjs
  '**':
    access: \$all
    proxy: npmjs
server:
  keepAliveTimeout: 60
logs:
  - {type: stdout, format: pretty, level: warn}
YAML

cat > "$OFFLINE_CONFIG" <<'YAML'
storage: ./storage
uplinks: {}
packages:
  '@*/*':
    access: $all
  '**':
    access: $all
server:
  keepAliveTimeout: 60
logs:
  - {type: stdout, format: pretty, level: warn}
YAML

cleanup() {
  if [ -n "${VERDACCIO_PID:-}" ] && kill -0 "$VERDACCIO_PID" >/dev/null 2>&1; then
    kill "$VERDACCIO_PID" >/dev/null 2>&1 || true
    wait "$VERDACCIO_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

verdaccio --config "$ONLINE_CONFIG" --listen "$REGISTRY_LISTEN" > "${LOG_DIR}/verdaccio.log" 2>&1 &
VERDACCIO_PID=$!

echo "Waiting for Verdaccio at ${REGISTRY_URL}..."
for _ in $(seq 1 60); do
  if npm ping --registry "$REGISTRY_URL" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! npm ping --registry "$REGISTRY_URL" >/dev/null 2>&1; then
  echo "Error: Verdaccio did not start. See ${LOG_DIR}/verdaccio.log" >&2
  exit 1
fi

export npm_config_registry="$REGISTRY_URL"
export npm_config_cache="$NPM_CACHE_DIR"
export npm_config_legacy_peer_deps=true
export npm_config_fund=false
export npm_config_audit=false
export npm_config_update_notifier=false
export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD="${PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD:-1}"
export PUPPETEER_SKIP_DOWNLOAD="${PUPPETEER_SKIP_DOWNLOAD:-1}"
export CYPRESS_INSTALL_BINARY="${CYPRESS_INSTALL_BINARY:-0}"
export ELECTRON_SKIP_BINARY_DOWNLOAD="${ELECTRON_SKIP_BINARY_DOWNLOAD:-1}"

NODE_RUNTIME_VERSION="${NODE_RUNTIME_VERSION:-$(node -v | sed 's/^v//')}"
NODE_RUNTIME_PLATFORM="${NODE_RUNTIME_PLATFORM:-linux}"
NODE_RUNTIME_ARCH="${NODE_RUNTIME_ARCH:-$(node -p 'process.arch')}"
NODE_RUNTIME_NAME="node-v${NODE_RUNTIME_VERSION}-${NODE_RUNTIME_PLATFORM}-${NODE_RUNTIME_ARCH}"
NODE_RUNTIME_TARBALL="${NODE_RUNTIME_NAME}.tar.xz"
NODE_DIST_URL="https://nodejs.org/dist/v${NODE_RUNTIME_VERSION}"
NVM_VERSION="${NVM_VERSION:-0.40.5}"
NVM_TARBALL="nvm-v${NVM_VERSION}.tar.gz"

echo "Downloading Node.js runtime ${NODE_RUNTIME_NAME}..."
curl -fsSLo "${NODE_RUNTIME_DIR}/${NODE_RUNTIME_TARBALL}" "${NODE_DIST_URL}/${NODE_RUNTIME_TARBALL}"
curl -fsSLo "${NODE_RUNTIME_DIR}/SHASUMS256.txt" "${NODE_DIST_URL}/SHASUMS256.txt"
if command -v sha256sum >/dev/null 2>&1; then
  (
    cd "$NODE_RUNTIME_DIR"
    grep " ${NODE_RUNTIME_TARBALL}$" SHASUMS256.txt | sha256sum -c -
  )
fi

echo "Downloading nvm ${NVM_VERSION}..."
curl -fsSLo "${NVM_RUNTIME_DIR}/${NVM_TARBALL}" "https://github.com/nvm-sh/nvm/archive/refs/tags/v${NVM_VERSION}.tar.gz"
if command -v sha256sum >/dev/null 2>&1; then
  (
    cd "$NVM_RUNTIME_DIR"
    sha256sum "$NVM_TARBALL" > SHASUMS256.txt
  )
fi

npm cache add verdaccio@latest --registry "$REGISTRY_URL" --cache "$NPM_CACHE_DIR" \
  > "${LOG_DIR}/verdaccio-cache-add.log" 2>&1

MANIFEST="${BUILD_DIR}/manifest.json"
printf '{\n' > "$MANIFEST"
printf '  "builtAt": "%s",\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "$MANIFEST"
printf '  "node": "%s",\n' "$(node -v)" >> "$MANIFEST"
printf '  "npm": "%s",\n' "$(npm -v)" >> "$MANIFEST"
printf '  "buildVariant": "%s",\n' "$BUILD_VARIANT" >> "$MANIFEST"
if [ -r /etc/os-release ]; then
  os_pretty_name="$(. /etc/os-release && printf '%s' "${PRETTY_NAME:-unknown}")"
else
  os_pretty_name="unknown"
fi
printf '  "os": "%s",\n' "$os_pretty_name" >> "$MANIFEST"
printf '  "platform": "%s",\n' "$(node -p 'process.platform')" >> "$MANIFEST"
printf '  "arch": "%s",\n' "$(node -p 'process.arch')" >> "$MANIFEST"
printf '  "nodeRuntime": "%s",\n' "$NODE_RUNTIME_TARBALL" >> "$MANIFEST"
printf '  "nvm": "%s",\n' "$NVM_VERSION" >> "$MANIFEST"
printf '  "registry": "%s",\n' "$REGISTRY_URL" >> "$MANIFEST"
printf '  "packageSets": [\n' >> "$MANIFEST"

FIRST_SET=true
for package_json in "$PACKAGES_DIR"/*/package.json; do
  [ -f "$package_json" ] || continue

  set_name="$(basename "$(dirname "$package_json")")"
  if [ -n "$PACKAGE_SET" ] && [ "$set_name" != "$PACKAGE_SET" ]; then
    continue
  fi

  work_dir="${BUILD_DIR}/work/${set_name}"
  set_out="${PACKAGE_SETS_DIR}/${set_name}"
  mkdir -p "$work_dir" "$set_out"
  cp "$package_json" "$work_dir/package.json"

  echo "Resolving and caching ${set_name}..."
  (
    cd "$work_dir"
    npm install --legacy-peer-deps --registry "$REGISTRY_URL" --cache "$NPM_CACHE_DIR" \
      > "${LOG_DIR}/${set_name}-install.log" 2>&1 || {
        echo "npm install failed for ${set_name}. Last 200 log lines:" >&2
        tail -n 200 "${LOG_DIR}/${set_name}-install.log" >&2
        exit 1
      }
    npm ls --all --json > "${REPORTS_DIR}/${set_name}-tree.json" 2>/dev/null || true
  )

  node - "$work_dir/package-lock.json" "$REGISTRY_URL" <<'NODE'
const fs = require('fs');
const lockPath = process.argv[2];
const buildRegistry = process.argv[3].replace(/\/$/, '');
const canonicalRegistry = 'https://registry.npmjs.org';
const lock = JSON.parse(fs.readFileSync(lockPath, 'utf8'));

function rewrite(value) {
  if (typeof value === 'string') {
    return value.replaceAll(buildRegistry, canonicalRegistry);
  }

  if (Array.isArray(value)) {
    return value.map(rewrite);
  }

  if (value && typeof value === 'object') {
    for (const key of Object.keys(value)) {
      value[key] = rewrite(value[key]);
    }
  }

  return value;
}

fs.writeFileSync(lockPath, JSON.stringify(rewrite(lock), null, 2) + '\n');
NODE

  cp "$work_dir/package.json" "$set_out/package.json"
  cp "$work_dir/package-lock.json" "$set_out/package-lock.json"
  tar -czf "${NODE_MODULES_DIR}/${set_name}-node_modules.tar.gz" -C "$work_dir" node_modules

  dep_count="$(node -e "const lock=require(process.argv[1]); console.log(Object.keys(lock.packages || {}).length)" "$set_out/package-lock.json")"
  if [ "$FIRST_SET" = false ]; then
    printf ',\n' >> "$MANIFEST"
  fi
  FIRST_SET=false
  printf '    {"name": "%s", "lockfilePackages": %s}' "$set_name" "$dep_count" >> "$MANIFEST"

  rm -rf "$work_dir"
  if command -v df >/dev/null 2>&1; then
    df -h "$BUILD_DIR"
  fi
done

if [ "$FIRST_SET" = true ]; then
  echo "Error: no package sets were built. PACKAGE_SET='${PACKAGE_SET}'" >&2
  exit 1
fi

printf '\n  ]\n' >> "$MANIFEST"
printf '}\n' >> "$MANIFEST"

cp "$OFFLINE_CONFIG" "${BUILD_DIR}/verdaccio/config.yaml"
cp "${ROOT_DIR}/scripts/install-node-offline.sh" "${BUILD_DIR}/install-node-offline.sh"
cp "${ROOT_DIR}/scripts/install-framework-offline.sh" "${BUILD_DIR}/install-framework-offline.sh"
cp "${ROOT_DIR}/scripts/start-offline-registry.sh" "${BUILD_DIR}/start-offline-registry.sh"
cp "${ROOT_DIR}/scripts/install-from-offline-repo.sh" "${BUILD_DIR}/install-from-offline-repo.sh"
cp "${ROOT_DIR}/scripts/verify-offline-repo.sh" "${BUILD_DIR}/verify-offline-repo.sh"
chmod +x "${BUILD_DIR}/"*.sh

tar -czf "${ROOT_DIR}/artifacts/npm-offline-repository.tar.gz" -C "$BUILD_DIR" \
  manifest.json npm-cache package-sets reports runtimes verdaccio install-node-offline.sh install-framework-offline.sh start-offline-registry.sh install-from-offline-repo.sh verify-offline-repo.sh

if command -v sha256sum >/dev/null 2>&1; then
  (
    cd "${ROOT_DIR}/artifacts"
    sha256sum npm-offline-repository.tar.gz offline-repository/node_modules_by_framework/*.tar.gz > SHA256SUMS.txt
  )
fi

echo "Offline repository built at ${BUILD_DIR}"
echo "Release artifact: ${ROOT_DIR}/artifacts/npm-offline-repository.tar.gz"
