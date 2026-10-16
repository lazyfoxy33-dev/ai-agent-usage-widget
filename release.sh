#!/usr/bin/env bash
# One-shot update & publish for the macOS menu-bar app.
#
#   ./release.sh                 # rebuild + notarize the dmg, refresh the release asset
#
# Required (Developer ID notarization):
#   export QUOTAWIDGET_TEAM="YOUR_TEAM_ID"
#   export QUOTAWIDGET_NOTARY_PROFILE="quotawidget-notary"
#
# Optional:
#   RELEASE_TAG=macwidget-v1.5.0                   (GitHub Release tag to update)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
RELEASE_TAG="${RELEASE_TAG:-macwidget-v1.5.0}"

if [[ $# -gt 0 ]]; then
    echo "unknown flag: $1"; exit 2
fi

echo "==> macwidget: build + notarize…"
( cd "$ROOT/macwidget" && ./distribute.sh )
DMG="$ROOT/macwidget/build/dist/QuotaWidget.dmg"
if gh release view "$RELEASE_TAG" >/dev/null 2>&1; then
    echo "==> macwidget: updating release asset on $RELEASE_TAG…"
    gh release upload "$RELEASE_TAG" "$DMG" --clobber
else
    echo "  ⚠ release $RELEASE_TAG not found — dmg built at $DMG (create the release or set RELEASE_TAG)."
fi

echo "✓ release.sh done"
