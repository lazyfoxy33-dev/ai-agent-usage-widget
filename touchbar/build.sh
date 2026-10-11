#!/bin/bash
# Build QuotaBar.app — a Touch Bar agent for Claude / Codex / Kimi usage.
# It bundles the shared core/ data layer and runs it via python3 at runtime.
set -euo pipefail
cd "$(dirname "$0")"

# Build next to the sources by default (convenient in a checkout). When called
# from QuotaWidget.app the caller points QUOTABAR_BUILD_DIR elsewhere, so nothing
# is written inside the signed bundle — that would break its code signature.
BUILD_ROOT="${QUOTABAR_BUILD_DIR:-$(pwd)}"
[[ -d "$BUILD_ROOT" ]] || mkdir -p "$BUILD_ROOT"
APP="$BUILD_ROOT/QuotaBar.app"
BIN="$APP/Contents/MacOS/QuotaBar"
RES="$APP/Contents/Resources"

# The shared data layer sits next to the sources in a checkout, but inside
# QuotaWidget.app the installer is copied to Contents/Resources/display-layers/
# while core/ lives at Contents/Resources/core. Look in both places so the same
# script works from a checkout and from the bundled installer.
CORE=""
for candidate in "../core" "../../core"; do
    if [[ -f "$candidate/fetch_usage.py" ]]; then
        CORE="$candidate"
        break
    fi
done
if [[ -z "$CORE" ]]; then
    echo "✗ cannot find the shared core/ data layer (looked in ../core and ../../core)" >&2
    exit 1
fi

echo "› compiling…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$RES"
swiftc -swift-version 5 -O \
    -framework AppKit \
    Sources/*.swift -o "$BIN"

echo "› bundling provider icons…"
# The settings window and the strip should show the same brand icons. In a
# checkout they live in macwidget/App/Resources; inside QuotaWidget.app they are
# copied to Contents/Resources, i.e. two levels above display-layers/touchbar.
ICON_SRC=""
for candidate in "../macwidget/App/Resources" "../../"; do
    if [[ -f "$candidate/claude-app.png" ]]; then
        ICON_SRC="$candidate"
        break
    fi
done
if [[ -n "$ICON_SRC" ]]; then
    mkdir -p "$RES/icons"
    for name in claude-app codex-app kimi-code deepseek siliconflow openrouter; do
        cp "$ICON_SRC/$name.png" "$RES/icons/" 2>/dev/null || true
    done
    echo "  ($(ls "$RES/icons" | wc -l | tr -d ' ') icons from $ICON_SRC)"
else
    echo "  (no icons found — the gauges fall back to their letter badges)"
fi

echo "› bundling shared core data layer…"
rm -rf "$RES/core"
mkdir -p "$RES/core"
cp "$CORE/fetch_usage.py" "$RES/core/"
cp -R "$CORE/usage" "$RES/core/usage"
# Drop bytecode caches if any slipped in.
find "$RES/core" -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null || true

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>QuotaBar</string>
    <key>CFBundleDisplayName</key>     <string>QuotaBar</string>
    <key>CFBundleIdentifier</key>      <string>com.quotabar.app</string>
    <key>CFBundleVersion</key>         <string>3</string>
    <key>CFBundleShortVersionString</key><string>1.2</string>
    <key>CFBundleExecutable</key>      <string>QuotaBar</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>NSPrincipalClass</key>        <string>NSApplication</string>
    <key>LSUIElement</key>             <true/>
    <key>LSMinimumSystemVersion</key>  <string>11.0</string>
</dict>
</plist>
PLIST

echo "› ad-hoc signing…"
# Signing can fail when the repo lives in an iCloud-synced folder (e.g.
# ~/Documents): the file provider keeps re-adding com.apple.FinderInfo to the
# bundle, which the ad-hoc signer rejects as "resource fork / detritus". Keep
# this non-fatal — install.sh re-signs the installed copy under ~/Applications,
# which is not synced, so installation still succeeds. (A dev `open $APP` from a
# synced dir may be unsigned; build from a non-synced location if you need that.)
if ! ./sign_bundle.sh "$APP"; then
    echo "  ⚠️  in-repo signing failed (expected in an iCloud-synced folder);"
    echo "     install.sh will sign the installed copy under ~/Applications."
fi

echo "✓ built $APP"
echo "  run:   open \"$APP\"    (or \"$BIN\" --once to print usage)"
