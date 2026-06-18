#!/usr/bin/env bash
# Render the gallery screenshot (516x320, the hi-res spec) from the committed
# HTML template via headless Chrome. Re-run when the widget design changes.
# Output: usage-widget/dist/screenshot.png
#
# Note: gallery-screenshot.html holds a representative data snapshot; edit the
# numbers/colors there if you want the promo image to reflect different values.
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
OUT="$SRC/dist"
mkdir -p "$OUT"

[ -x "$CHROME" ] || { echo "Chrome not found at: $CHROME (set CHROME=...)"; exit 1; }

"$CHROME" --headless=new --disable-gpu --no-sandbox --hide-scrollbars \
    --force-device-scale-factor=1 --window-size=516,320 \
    --screenshot="$OUT/screenshot.png" "file://$SRC/gallery-screenshot.html" >/dev/null 2>&1

echo "Rendered: $OUT/screenshot.png"
