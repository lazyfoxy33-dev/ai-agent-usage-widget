#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

if [[ "${QUOTAWIDGET_UNSIGNED:-0}" != "1" ]]; then
  : "${QUOTAWIDGET_TEAM:?Set QUOTAWIDGET_TEAM to your Apple Developer Team ID}"
  : "${QUOTAWIDGET_APP_GROUP:?Set QUOTAWIDGET_APP_GROUP to your registered App Group ID}"
fi

args=(
  -project QuotaWidget.xcodeproj
  -scheme QuotaWidget
  -configuration Release
  -derivedDataPath build/DerivedData
  APP_GROUP_ID="${QUOTAWIDGET_APP_GROUP:-group.dev.lazyfoxy.QuotaWidget}"
)

if [[ "${QUOTAWIDGET_UNSIGNED:-0}" == "1" ]]; then
  args+=(CODE_SIGNING_ALLOWED=NO)
else
  args+=(DEVELOPMENT_TEAM="$QUOTAWIDGET_TEAM" CODE_SIGN_STYLE=Automatic)
fi

xcodebuild "${args[@]}" build

app="build/DerivedData/Build/Products/Release/QuotaWidgetApp.app"
test -d "$app"
echo "Built: $app"
