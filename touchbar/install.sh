#!/bin/bash
# Install QuotaBar as a login agent so the Touch Bar readout is always present.
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

BUILD_APP="$PWD/QuotaBar.app"
INSTALL_APP="$HOME/Applications/QuotaBar.app"
PLIST="$HOME/Library/LaunchAgents/com.quotabar.app.plist"
LABEL="com.quotabar.app"
GUI_DOMAIN="gui/$(id -u)"

echo "› installing to ${INSTALL_APP}…"
mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents"
rm -rf "$INSTALL_APP"
ditto --norsrc --noextattr "$BUILD_APP" "$INSTALL_APP"
./sign_bundle.sh "$INSTALL_APP"

sed "s#__APP_PATH__#$INSTALL_APP#g" com.quotabar.app.plist > "$PLIST"

echo "› registering login agent…"
if launchctl print "$GUI_DOMAIN/$LABEL" >/dev/null 2>&1; then
    launchctl bootout "$GUI_DOMAIN/$LABEL"
fi
pkill -x QuotaBar 2>/dev/null || true
launchctl bootstrap "$GUI_DOMAIN" "$PLIST"
launchctl kickstart -k "$GUI_DOMAIN/$LABEL"

echo "✓ installed to $INSTALL_APP and launched."
echo "  A Keychain prompt may appear once (Claude reads its login read-only) —"
echo "  click “Always Allow”. Claude is never written; current Kimi credentials"
echo "  refresh only under the official lock."
echo "  已安装并启动。Claude 凭据只读；当前 Kimi 凭据仅在官方锁内安全续期。"
echo
echo "  uninstall:  launchctl bootout \"$GUI_DOMAIN/$LABEL\""
echo "              rm -rf \"$INSTALL_APP\" \"$PLIST\""
