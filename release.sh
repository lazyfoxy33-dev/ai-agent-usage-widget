#!/usr/bin/env bash
# One-shot update & publish for the macOS frontends.
#
#   ./release.sh                 # rebuild + notarize the macwidget dmg
#   ./release.sh --touchbar      # only rebuild + notarize the Touch Bar dmg
#
# Required for the macwidget part (Developer ID notarization):
#   export QUOTAWIDGET_TEAM="9AVXU7V6Q8"
#   export QUOTAWIDGET_NOTARY_PROFILE="quotawidget-notary"
#
# Required for the Touch Bar part:
#   export QUOTABAR_TEAM="9AVXU7V6Q8"
#   export QUOTABAR_NOTARY_PROFILE="quotabar-notary"
#
# Optional:
#   RELEASE_TAG=macwidget-v1.2.0                   (GitHub Release tag to update)
#   TOUCHBAR_RELEASE_TAG=touchbar-v1.1.0           (GitHub Release tag to update)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
RELEASE_TAG="${RELEASE_TAG:-macwidget-v1.2.0}"
TOUCHBAR_RELEASE_TAG="${TOUCHBAR_RELEASE_TAG:-touchbar-v1.1.0}"

DO_MAC=1; DO_TOUCHBAR=0
for a in "$@"; do
    case "$a" in
        --macwidget) DO_TOUCHBAR=0 ;;
        --touchbar) DO_MAC=0; DO_TOUCHBAR=1 ;;
        *) echo "unknown flag: $a"; exit 2 ;;
    esac
done

if [[ $DO_MAC == 1 ]]; then
    echo "==> macwidget: build + notarize…"
    ( cd "$ROOT/macwidget" && ./distribute.sh )
    DMG="$ROOT/macwidget/build/dist/QuotaWidget.dmg"
    if gh release view "$RELEASE_TAG" >/dev/null 2>&1; then
        echo "==> macwidget: updating release asset on $RELEASE_TAG…"
        gh release upload "$RELEASE_TAG" "$DMG" --clobber
    else
        echo "  ⚠ release $RELEASE_TAG not found — dmg built at $DMG (create the release or set RELEASE_TAG)."
    fi
fi

if [[ $DO_TOUCHBAR == 1 ]]; then
    echo "==> Touch Bar: build + notarize…"
    ( cd "$ROOT/touchbar" && ./distribute.sh )
    TOUCHBAR_DMG="$ROOT/touchbar/build/dist/QuotaBar.dmg"
    if [[ ! -f "$TOUCHBAR_DMG" ]]; then
        echo "  ⚠ no Touch Bar dmg found at $TOUCHBAR_DMG — check distribute.sh output."
    elif gh release view "$TOUCHBAR_RELEASE_TAG" >/dev/null 2>&1; then
        echo "==> Touch Bar: updating release asset on $TOUCHBAR_RELEASE_TAG…"
        gh release upload "$TOUCHBAR_RELEASE_TAG" "$TOUCHBAR_DMG" --clobber
    else
        echo "  ⚠ release $TOUCHBAR_RELEASE_TAG not found — dmg built at $TOUCHBAR_DMG (create the release or set TOUCHBAR_RELEASE_TAG)."
    fi
fi

echo "✓ release.sh done"
