#!/usr/bin/env bash
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/Library/Application Support/Übersicht/widgets/usage-widget"
mkdir -p "$DEST"
rm -f "$DEST/codex-refresh.sh"
cp "$SRC/index.jsx" "$SRC/fetch_usage.py" "$DEST/"
cp -R "$SRC/usage" "$DEST/"
rm -rf "$DEST/assets"
cp -R "$SRC/assets" "$DEST/"
echo "Installed to: $DEST"
echo "打开（或重启）Übersicht 即可看到组件。"
