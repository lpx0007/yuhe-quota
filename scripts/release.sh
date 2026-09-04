#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-1.8.0}"
REPO="${GITHUB_REPO:-lpx0007/yuhe-quota}"
NOTES="${RELEASE_NOTES:-余核 ${VERSION}}"

export VERSION
bash "$ROOT/scripts/dist.sh"

ZIP="$ROOT/dist/余核-${VERSION}-macos-arm64.zip"
if [[ ! -f "$ZIP" ]]; then
    echo "missing $ZIP" >&2
    exit 1
fi

if ! gh release view "v${VERSION}" --repo "$REPO" >/dev/null 2>&1; then
    gh release create "v${VERSION}" "$ZIP" \
        --repo "$REPO" \
        --title "余核 ${VERSION}" \
        --notes "$NOTES"
else
    gh release upload "v${VERSION}" "$ZIP" --repo "$REPO" --clobber
fi

echo "Released https://github.com/${REPO}/releases/tag/v${VERSION}"
