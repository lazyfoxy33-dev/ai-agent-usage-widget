#!/bin/bash
# Build, Developer ID-sign, notarize and package QuotaBar (the Touch Bar app) as a
# distributable .dmg. Unlike install.sh (which ad-hoc signs a copy for your own
# machine), this produces an artifact other people can download and run without a
# Gatekeeper warning.
#
# QuotaBar has no App Groups / sandbox entitlements, so — unlike the desktop widget —
# Developer ID distribution needs NO App IDs or provisioning profiles. You only need:
#   - A "Developer ID Application" certificate in your keychain
#       (Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates ▸ + ▸ Developer ID Application).
#   - Stored notarization credentials, created once with:
#       xcrun notarytool store-credentials <profile> \
#         --apple-id <your-apple-id> --team-id <TEAMID> \
#         --password <app-specific-password>      # from appleid.apple.com
#
# Usage:
#   export QUOTABAR_TEAM="YOUR_TEAM_ID"
#   export QUOTABAR_NOTARY_PROFILE="your-notary-profile"      # required to notarize
#   # optional: full identity if you have more than one Developer ID cert
#   # export QUOTABAR_SIGN_ID="Developer ID Application: Name (TEAMID)"
#   ./distribute.sh
set -euo pipefail
cd "$(dirname "$0")"

: "${QUOTABAR_TEAM:?Set QUOTABAR_TEAM to your Apple Developer Team ID}"
NOTARY_PROFILE="${QUOTABAR_NOTARY_PROFILE:-}"
SIGN_ID="${QUOTABAR_SIGN_ID:-Developer ID Application}"

DIST="build/dist"
DMG="$DIST/QuotaBar.dmg"

# 1) Compile + bundle the shared core data layer (build.sh ad-hoc signs; we re-sign below).
echo "› building QuotaBar.app…"
./build.sh >/dev/null

# 2) Stage in a non-iCloud temp dir. Signing in ~/Documents fails intermittently because
#    the iCloud file provider keeps re-adding com.apple.FinderInfo to the bundle.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
APP="$WORK/QuotaBar.app"
ditto --norsrc --noextattr QuotaBar.app "$APP"
xattr -cr "$APP"

echo "› Developer ID signing (hardened runtime)…"
codesign --force --options runtime --timestamp \
    --sign "$SIGN_ID" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

mkdir -p "$DIST"

# 3) Notarize the app (required before stapling). The bundle must be zipped for submission.
if [[ -n "$NOTARY_PROFILE" ]]; then
    echo "› notarizing the app (profile: $NOTARY_PROFILE)…"
    ZIP="$WORK/QuotaBar-notarize.zip"
    ditto -c -k --keepParent "$APP" "$ZIP"
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    echo "› stapling the app…"
    xcrun stapler staple "$APP"
else
    echo "⚠ QUOTABAR_NOTARY_PROFILE not set — building an UNNOTARIZED .dmg."
    echo "  Recipients will see a Gatekeeper warning. Store credentials once, then re-run:"
    echo "    xcrun notarytool store-credentials <name> --apple-id <id> \\"
    echo "      --team-id $QUOTABAR_TEAM --password <app-specific-password>"
fi

# 4) Build the .dmg with the customary drag-to-Applications layout.
echo "› building dmg…"
STAGING="$WORK/staging"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/QuotaBar.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "QuotaBar" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null

# 5) Notarize + staple the dmg itself so the download is Gatekeeper-clean offline.
if [[ -n "$NOTARY_PROFILE" ]]; then
    echo "› notarizing the dmg…"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    echo "› stapling the dmg…"
    xcrun stapler staple "$DMG"
fi

echo "✓ done: touchbar/$DMG"
