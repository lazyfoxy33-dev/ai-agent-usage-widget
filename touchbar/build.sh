#!/bin/bash
# Build QuotaBar.app — a Touch Bar agent for Claude / Codex / Kimi usage.
# It bundles the shared core/ data layer and runs it via python3 at runtime.
set -euo pipefail
cd "$(dirname "$0")"

APP="QuotaBar.app"
BIN="$APP/Contents/MacOS/QuotaBar"
RES="$APP/Contents/Resources"
CORE="../core"

echo "› compiling…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$RES"
swiftc -swift-version 5 -O \
    -framework AppKit \
    Sources/*.swift -o "$BIN"

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
    <key>CFBundleVersion</key>         <string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleExecutable</key>      <string>QuotaBar</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>NSPrincipalClass</key>        <string>NSApplication</string>
    <key>LSUIElement</key>             <true/>
    <key>LSMinimumSystemVersion</key>  <string>11.0</string>
</dict>
</plist>
PLIST

echo "› ad-hoc signing…"
./sign_bundle.sh "$APP"

echo "✓ built $APP"
echo "  run:   open $APP    (or ./$BIN --once to print usage)"
