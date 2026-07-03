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
open "$destination"

echo "Installed: $destination"
echo "Add AI Agent Usage from the macOS widget gallery."
