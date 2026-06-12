#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
./build.sh

source_app="build/DerivedData/Build/Products/Release/QuotaWidgetApp.app"
destination="/Applications/QuotaWidget.app"
rm -rf "$destination"
ditto "$source_app" "$destination"
open "$destination"

echo "Installed: $destination"
echo "Add AI Agent Usage from the macOS widget gallery."
