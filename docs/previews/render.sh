#!/usr/bin/env bash
# Render the per-frontend preview mocks to docs/*.png via headless Chrome (@2x).
# Re-run when the design changes. Sources are the committed *.html in this dir;
# edit the numbers/colors there to change the promo values.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
DOCS="$(cd "$DIR/.." && pwd)"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
[ -x "$CHROME" ] || { echo "Chrome not found at: $CHROME (set CHROME=...)"; exit 1; }

render() { # <html> <w> <h> <out>
  "$CHROME" --headless=new --disable-gpu --no-sandbox --hide-scrollbars \
    --force-device-scale-factor=2 --window-size="$2,$3" \
    --screenshot="$DOCS/$4" "file://$DIR/$1" >/dev/null 2>&1
  echo "Rendered: docs/$4"
}

render widget.html   600 240 preview-widget.png
render touchbar.html 660  96 preview-touchbar.png
