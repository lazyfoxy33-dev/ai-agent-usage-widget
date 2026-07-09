#!/usr/bin/env bash
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
CORE="$(cd "$SRC/../core" && pwd)"   # shared data layer

BASE_DIRS=(
  "$HOME/Library/Application Support/Übersicht/widgets"
  "$HOME/Library/Application Support/Übersicht/widgets"
)

DESTS=()
for BASE in "${BASE_DIRS[@]}"; do
  if [[ -d "$BASE" ]]; then
    DESTS+=("$BASE/usage-widget")
  fi
done

if [[ "${#DESTS[@]}" -eq 0 ]]; then
  DESTS+=("${BASE_DIRS[0]}/usage-widget")
fi

for DEST in "${DESTS[@]}"; do
  mkdir -p "$DEST"
  rm -f "$DEST/codex-refresh.sh"
  cp "$SRC/index.jsx" "$DEST/"
  cp "$CORE/fetch_usage.py" "$DEST/"
  cp -R "$CORE/usage" "$DEST/"
  rm -rf "$DEST/assets"
  cp -R "$SRC/assets" "$DEST/"
  echo "Installed to: $DEST"
done

mkdir -p "$HOME/.config/ai-agent-usage-widget/display-layers"
: > "$HOME/.config/ai-agent-usage-widget/display-layers/ubersicht.installed"

echo "打开（或重启）Übersicht 即可看到组件。"
