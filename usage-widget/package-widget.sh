#!/usr/bin/env bash
# Package the Übersicht widget as a self-contained <name>.widget bundle and zip,
# generated from the canonical monorepo source (index.jsx + assets + shared core).
# Output is what the Übersicht gallery expects; develop here, publish the zip.
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
CORE="$(cd "$SRC/../core" && pwd)"

NAME="ai-agent-usage"
OUT="$SRC/dist"
BUNDLE="$OUT/$NAME.widget"
ZIP="$OUT/$NAME.widget.zip"

rm -rf "$OUT"
mkdir -p "$BUNDLE"

cp "$SRC/index.jsx" "$BUNDLE/"
cp "$CORE/fetch_usage.py" "$BUNDLE/"
cp -R "$CORE/usage" "$BUNDLE/"
cp -R "$SRC/assets" "$BUNDLE/"
find "$BUNDLE" -type d -name __pycache__ -prune -exec rm -rf {} +
find "$BUNDLE" -type f -name '*.pyc' -delete

# Zip with the .widget folder at the archive root (what users drop into Übersicht).
( cd "$OUT" && zip -qr "$ZIP" "$NAME.widget" )

echo "Built: $BUNDLE"
echo "Zipped: $ZIP"
