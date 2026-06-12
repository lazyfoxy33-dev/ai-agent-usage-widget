#!/bin/bash
# Install QuotaBar as a login agent so the Touch Bar readout is always present.
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

APP_PATH="$(cd QuotaBar.app && pwd)"
PLIST="$HOME/Library/LaunchAgents/com.quotabar.app.plist"
mkdir -p "$HOME/Library/LaunchAgents"

sed "s#__APP_PATH__#$APP_PATH#g" com.quotabar.app.plist > "$PLIST"

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"

echo "✓ installed & launched."
echo "  A Keychain prompt may appear once (Claude reads its login read-only) —"
echo "  click “Always Allow”. Claude is never written; current Kimi credentials"
echo "  refresh only under the official lock."
echo "  已安装并启动。Claude 凭据只读；当前 Kimi 凭据仅在官方锁内安全续期。"
echo
echo "  uninstall:  launchctl unload \"$PLIST\" && rm \"$PLIST\""
