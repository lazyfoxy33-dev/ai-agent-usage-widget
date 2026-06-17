#!/bin/bash
# Build, Developer ID-sign, notarize and package QuotaWidget as a distributable
# .dmg. Unlike install.sh (which uses development signing for your own machine),
# this produces an artifact other people can download and run.
#
# Requirements (one-time, see README "Distribution"):
#   - A "Developer ID Application" certificate in your keychain.
#   - The two App IDs (dev.lazyfoxy.QuotaWidget and .extension) with the App
#     Groups capability enabled (same as for development).
#   - Stored notarization credentials (xcrun notarytool store-credentials).
#
# Usage:
#   export QUOTAWIDGET_TEAM="YOUR_TEAM_ID"
#   export QUOTAWIDGET_NOTARY_PROFILE="your-notary-profile"   # optional but recommended
#   ./distribute.sh
set -euo pipefail
cd "$(dirname "$0")"

: "${QUOTAWIDGET_TEAM:?Set QUOTAWIDGET_TEAM to your Apple Developer Team ID}"
APP_GROUP="${QUOTAWIDGET_APP_GROUP:-group.dev.lazyfoxy.QuotaWidget}"
NOTARY_PROFILE="${QUOTAWIDGET_NOTARY_PROFILE:-}"

DERIVED="build/DerivedData"
APP="$DERIVED/Build/Products/Release/QuotaWidgetApp.app"
DIST="build/dist"
DMG="$DIST/QuotaWidget.dmg"

echo "› building Release with Developer ID + hardened runtime…"
rm -rf "$DERIVED" "$DIST"
xcodebuild \
    -project QuotaWidget.xcodeproj \
    -scheme QuotaWidget \
    -configuration Release \
    -derivedDataPath "$DERIVED" \
    APP_GROUP_ID="$APP_GROUP" \
    DEVELOPMENT_TEAM="$QUOTAWIDGET_TEAM" \
    CODE_SIGN_STYLE=Automatic \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    ENABLE_HARDENED_RUNTIME=YES \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    -allowProvisioningUpdates \
    build

test -d "$APP"

echo "› verifying signature…"
codesign --verify --deep --strict --verbose=2 "$APP"

mkdir -p "$DIST"

if [[ -n "$NOTARY_PROFILE" ]]; then
    echo "› notarizing (profile: $NOTARY_PROFILE)…"
    ZIP="$DIST/QuotaWidget-notarize.zip"
    ditto -c -k --keepParent "$APP" "$ZIP"
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    rm -f "$ZIP"
    echo "› stapling the app…"
    xcrun stapler staple "$APP"
else
    echo "⚠ QUOTAWIDGET_NOTARY_PROFILE not set — building an UNNOTARIZED .dmg."
    echo "  Recipients will see a Gatekeeper warning. To notarize, store credentials once:"
    echo "    xcrun notarytool store-credentials <name> --apple-id <id> --team-id $QUOTAWIDGET_TEAM --password <app-specific-password>"
    echo "  then re-run with QUOTAWIDGET_NOTARY_PROFILE=<name>."
fi

echo "› building dmg…"
STAGING="$DIST/staging"
rm -rf "$STAGING"; mkdir -p "$STAGING"
ditto "$APP" "$STAGING/QuotaWidget.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "QuotaWidget" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

if [[ -n "$NOTARY_PROFILE" ]]; then
    echo "› stapling the dmg…"
    xcrun stapler staple "$DMG"
fi

echo "✓ done: $DMG"
