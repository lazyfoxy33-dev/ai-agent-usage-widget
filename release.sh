#!/usr/bin/env bash
# One-shot update & publish for the distributable frontends.
#
#   ./release.sh                 # do both: Übersicht widget + macwidget dmg
#   ./release.sh --ubersicht     # only repackage + publish the Übersicht widget
#   ./release.sh --macwidget     # only rebuild + notarize the macwidget dmg
#   ./release.sh --screenshot    # also re-render the gallery screenshot
#
# Required for the macwidget part (Developer ID notarization):
#   export QUOTAWIDGET_TEAM="9AVXU7V6Q8"
#   export QUOTAWIDGET_NOTARY_PROFILE="quotawidget-notary"
#
# Optional:
#   GALLERY_REPO=/path/to/quotawidget-ubersicht   (default: sibling of this repo)
#   RELEASE_TAG=macwidget-v1.0.0                   (GitHub Release tag to update)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
GALLERY_REPO="${GALLERY_REPO:-$(dirname "$ROOT")/quotawidget-ubersicht}"
RELEASE_TAG="${RELEASE_TAG:-macwidget-v1.0.0}"

DO_UBER=1; DO_MAC=1; DO_SHOT=0
for a in "$@"; do
    case "$a" in
        --ubersicht) DO_MAC=0 ;;
        --macwidget) DO_UBER=0 ;;
        --screenshot) DO_SHOT=1 ;;
        *) echo "unknown flag: $a"; exit 2 ;;
    esac
done

if [[ $DO_UBER == 1 ]]; then
    echo "==> Übersicht: packaging widget…"
    bash "$ROOT/usage-widget/package-widget.sh"

    if [[ $DO_SHOT == 1 ]]; then
        echo "==> Übersicht: rendering gallery screenshot…"
        bash "$ROOT/usage-widget/render-screenshot.sh"
    fi

    if [[ -d "$GALLERY_REPO/.git" ]]; then
        echo "==> Übersicht: syncing to gallery repo ($GALLERY_REPO)…"
        cp "$ROOT/usage-widget/dist/ai-agent-usage.widget.zip" "$GALLERY_REPO/"
        rm -rf "$GALLERY_REPO/ai-agent-usage.widget"
        cp -R "$ROOT/usage-widget/dist/ai-agent-usage.widget" "$GALLERY_REPO/"
        [[ $DO_SHOT == 1 && -f "$ROOT/usage-widget/dist/screenshot.png" ]] && \
            cp "$ROOT/usage-widget/dist/screenshot.png" "$GALLERY_REPO/screenshot.png"
        (
            cd "$GALLERY_REPO"
            if [[ -n "$(git status --porcelain)" ]]; then
                git add -A
                git commit -qm "Update widget package ($(date +%Y-%m-%d))"
                git push -q
                echo "    pushed gallery repo update"
            else
                echo "    gallery repo already up to date"
            fi
        )
    else
        echo "  ⚠ gallery repo not found at $GALLERY_REPO — skipped publish."
        echo "    Set GALLERY_REPO=/path/to/quotawidget-ubersicht. Zip is in usage-widget/dist/."
    fi
fi

if [[ $DO_MAC == 1 ]]; then
    echo "==> macwidget: build + notarize…"
    ( cd "$ROOT/macwidget" && ./distribute.sh )
    DMG="$ROOT/macwidget/build/dist/QuotaWidget.dmg"
    if gh release view "$RELEASE_TAG" >/dev/null 2>&1; then
        echo "==> macwidget: updating release asset on $RELEASE_TAG…"
        gh release upload "$RELEASE_TAG" "$DMG" --clobber
    else
        echo "  ⚠ release $RELEASE_TAG not found — dmg built at $DMG (create the release or set RELEASE_TAG)."
    fi
fi

echo "✓ release.sh done"
