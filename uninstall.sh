#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if command -v ai >/dev/null 2>&1; then
  exec ai uninstall "$@"
fi

exec "$SCRIPT_DIR/bin/ai" uninstall "$@"
