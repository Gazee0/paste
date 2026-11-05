#!/bin/bash
#
# Builds (unless --no-build) and launches Paste.app.
#
# Usage:
#   Scripts/run.sh              build, then open dist/Paste.app
#   Scripts/run.sh --no-build   just open the existing bundle
#   Scripts/run.sh --foreground build, then run the binary in this terminal

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/Paste.app"

BUILD=1
FOREGROUND=0
for arg in "$@"; do
    case "$arg" in
        --no-build) BUILD=0 ;;
        --foreground) FOREGROUND=1 ;;
        -h|--help)
            sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) printf '[run] error: unknown argument %s\n' "$arg" >&2; exit 1 ;;
    esac
done

if [ "$BUILD" -eq 1 ]; then
    "$SCRIPT_DIR/build.sh"
fi

[ -d "$APP_BUNDLE" ] || {
    printf '[run] error: %s does not exist (run Scripts/build.sh first)\n' "$APP_BUNDLE" >&2
    exit 1
}

if [ "$FOREGROUND" -eq 1 ]; then
    printf '[run] launching in foreground: %s\n' "$APP_BUNDLE/Contents/MacOS/Paste"
    exec "$APP_BUNDLE/Contents/MacOS/Paste"
else
    printf '[run] opening %s\n' "$APP_BUNDLE"
    open "$APP_BUNDLE"
fi
