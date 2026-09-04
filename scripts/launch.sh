#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/余核.app"
if [[ ! -d "$APP" ]]; then
    echo "App not built. Run scripts/package.sh first." >&2
    exit 1
fi
xattr -cr "$APP" 2>/dev/null || true
open "$APP"
