#!/usr/bin/env bash
# Layout parsing tests for the Touch Bar agent.
#
# The agent is built with swiftc and has no Xcode test bundle, so this compiles
# the layout source together with the checks and runs them directly.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

# Top-level statements must live in main.swift when several files are compiled.
cp tests/layout_test.swift "$OUT/main.swift"
swiftc -O -o "$OUT/layout-tests" \
    Sources/TouchBarLayout.swift Sources/TrayGlance.swift Sources/TouchBarMetrics.swift \
    Sources/DataSource.swift \
    "$OUT/main.swift"
"$OUT/layout-tests"
