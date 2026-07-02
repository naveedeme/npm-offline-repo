#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 3 ]; then
  echo "Usage: $0 <ubuntu-version> <package-set> <output-file>" >&2
  exit 1
fi

VARIANT="$1"
PACKAGE_SET="$2"
OUTPUT_FILE="$3"

mkdir -p "$(dirname "$OUTPUT_FILE")"

cat > "$OUTPUT_FILE" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail

VARIANT="${VARIANT}"
PACKAGE_SET="${PACKAGE_SET}"
DEFAULT_TARGET="\${HOME}/\${PACKAGE_SET}-offline-app"

usage() {
  cat <<USAGE
Usage:
  ./install-\${PACKAGE_SET}-\${VARIANT}-offline.sh [target-path]

Example:
  ./install-\${PACKAGE_SET}-\${VARIANT}-offline.sh /home/user/myapp

Keep these release files in this same directory:
  \${PACKAGE_SET}-offline-repository-\${VARIANT}.tar.gz
  \${PACKAGE_SET}-node_modules-\${VARIANT}.tar.gz   optional, but recommended

If GitHub split a large asset, keep all .part-* files in this directory too.
When target-path is omitted, this installs into:
  \${DEFAULT_TARGET}
USAGE
}

if [ "\${1:-}" = "-h" ] || [ "\${1:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ "\$#" -gt 1 ]; then
  usage >&2
  exit 1
fi

TARGET_PATH="\${1:-\$DEFAULT_TARGET}"
SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
REPO_TARBALL="\${PACKAGE_SET}-offline-repository-\${VARIANT}.tar.gz"
MODULE_TARBALL="\${PACKAGE_SET}-node_modules-\${VARIANT}.tar.gz"

cd "\$SCRIPT_DIR"

assemble_if_split() {
  local output="\$1"
  if [ -f "\$output" ]; then
    return
  fi

  if compgen -G "\${output}.part-*" >/dev/null; then
    echo "Reassembling \${output}..."
    cat "\${output}".part-* > "\$output"
  fi
}

assemble_if_split "\$REPO_TARBALL"
assemble_if_split "\$MODULE_TARBALL"

if [ ! -f install-framework-offline.sh ]; then
  if [ ! -f "\$REPO_TARBALL" ]; then
    echo "Error: missing \${REPO_TARBALL}" >&2
    echo "Download it from the GitHub release, or provide split \${REPO_TARBALL}.part-* files." >&2
    exit 1
  fi

  echo "Extracting \${REPO_TARBALL}..."
  tar -xzf "\$REPO_TARBALL"
fi

exec ./install-framework-offline.sh "\$VARIANT" "\$PACKAGE_SET" "\$TARGET_PATH"
SCRIPT

chmod +x "$OUTPUT_FILE"
