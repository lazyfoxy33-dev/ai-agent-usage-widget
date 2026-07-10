#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
./build.sh

source_app="build/DerivedData/Build/Products/Release/QuotaWidgetApp.app"
destination="/Applications/QuotaWidget.app"

if pgrep -fq "$destination/Contents/MacOS/QuotaWidgetApp"; then
  osascript -e 'tell application id "dev.lazyfoxy.QuotaWidget" to quit' >/dev/null 2>&1 || true
  for _ in {1..20}; do
    if ! pgrep -fq "$destination/Contents/MacOS/QuotaWidgetApp"; then
      break
    fi
    sleep 0.25
  done
  if pgrep -fq "$destination/Contents/MacOS/QuotaWidgetApp"; then
    pkill -f "$destination/Contents/MacOS/QuotaWidgetApp"
  fi
fi

rm -rf "$destination"
ditto "$source_app" "$destination"
find "$destination" -name "*.xctest" -type d -prune -exec rm -rf {} +

if [[ "${QUOTAWIDGET_UNSIGNED:-0}" == "1" ]]; then
  app_group="${QUOTAWIDGET_APP_GROUP:-group.dev.lazyfoxy.QuotaWidget}"
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT
  app_entitlements="$tmp_dir/app.entitlements"
  widget_entitlements="$tmp_dir/widget.entitlements"
  cat > "$app_entitlements" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.application-groups</key>
  <array>
    <string>$app_group</string>
  </array>
</dict>
</plist>
EOF
  cat > "$widget_entitlements" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key>
  <true/>
  <key>com.apple.security.application-groups</key>
  <array>
    <string>$app_group</string>
  </array>
</dict>
</plist>
EOF
  for appex in "$destination"/Contents/PlugIns/*.appex; do
    [[ -d "$appex" ]] || continue
    codesign --force --sign - --entitlements "$widget_entitlements" "$appex"
  done
  codesign --force --sign - --entitlements "$app_entitlements" "$destination"
fi

open "$destination"

echo "Installed: $destination"
echo "Add AI Agent Usage from the macOS widget gallery."
