#!/usr/bin/env bash
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/Library/Application Support/Übersicht/widgets/usage-widget"
mkdir -p "$DEST"
cp "$SRC/index.jsx" "$SRC/fetch_usage.py" "$DEST/"
cp -R "$SRC/usage" "$DEST/"
echo "Installed to: $DEST"
echo "打开（或重启）Übersicht 即可看到组件。"
