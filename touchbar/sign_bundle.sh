#!/bin/bash
set -u

sign_bundle() {
    local app="$1"
    local attempt

    for attempt in 1 2 3 4 5; do
        xattr -cr "$app"
        if codesign --force --deep --sign - "$app" &&
            codesign --verify --deep --strict --verbose=2 "$app"; then
            return 0
        fi
        sleep 0.1
    done

    echo "Failed to sign and verify $app after 5 attempts." >&2
    return 1
}

sign_bundle "$1"
