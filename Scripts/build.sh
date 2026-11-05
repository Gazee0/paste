#!/bin/bash
#
# Builds Paste.app into dist/.
#
#   1. swift build -c release --product Paste
#   2. assemble dist/Paste.app/Contents/{MacOS,Resources}
#   3. copy Info.plist, AppIcon.icns and PkgInfo
#   4. codesign with a stable local identity when one exists, otherwise ad-hoc
#
# The script only ever deletes inside <repo>/dist/. Environment overrides:
#   PASTE_SIGN_IDENTITY   force a codesigning identity ("-" forces ad-hoc)
#   PASTE_CONFIGURATION   build configuration (default: release)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="Paste"
CONFIGURATION="${PASTE_CONFIGURATION:-release}"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
INFO_PLIST="$ROOT_DIR/Resources/Info.plist"
ICON_SOURCE="$ROOT_DIR/Resources/AppIcon.icns"
ICON_SCRIPT="$SCRIPT_DIR/make_icon.swift"

log()  { printf '[build] %s\n' "$*"; }
warn() { printf '[build] warning: %s\n' "$*" >&2; }
die()  { printf '[build] error: %s\n' "$*" >&2; exit 1; }

# MARK: - Preflight

command -v swift >/dev/null 2>&1 || die "swift not found in PATH"
command -v codesign >/dev/null 2>&1 || die "codesign not found in PATH"
[ -f "$INFO_PLIST" ] || die "missing Resources/Info.plist"

if [ ! -f "$ICON_SOURCE" ]; then
    log "Resources/AppIcon.icns is missing, regenerating it with Scripts/make_icon.swift"
    swift "$ICON_SCRIPT" "$ICON_SOURCE"
fi
[ -f "$ICON_SOURCE" ] || die "missing Resources/AppIcon.icns (run: swift Scripts/make_icon.swift)"

# MARK: - Compile

log "swift build -c $CONFIGURATION --product $APP_NAME"
swift build -c "$CONFIGURATION" --product "$APP_NAME"

BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
BINARY="$BIN_DIR/$APP_NAME"
[ -x "$BINARY" ] || die "expected release binary at $BINARY"

# MARK: - Assemble bundle

# Guard: only clean the app bundle we own, directly inside <repo>/dist/.
case "$APP_BUNDLE" in
    "$DIST_DIR"/*) ;;
    *) die "refusing to remove unexpected path: $APP_BUNDLE" ;;
esac

log "assembling $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

install -m 755 "$BINARY" "$MACOS_DIR/$APP_NAME"
install -m 644 "$INFO_PLIST" "$CONTENTS_DIR/Info.plist"
install -m 644 "$ICON_SOURCE" "$RESOURCES_DIR/AppIcon.icns"
printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"
chmod 644 "$CONTENTS_DIR/PkgInfo"

# MARK: - Codesign

IDENTITY="${PASTE_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
    for candidate in "Paste Local Signing" "Clipboard Local Signing"; do
        if printf '%s\n' "$IDENTITIES" | grep -Fq "\"$candidate\""; then
            IDENTITY="$candidate"
            break
        fi
    done
fi

if [ "$IDENTITY" = "-" ]; then
    log "codesigning ad-hoc (PASTE_SIGN_IDENTITY=-)"
    codesign --force --sign - "$APP_BUNDLE"
elif [ -n "$IDENTITY" ]; then
    log "codesigning with stable identity: $IDENTITY"
    codesign --force --sign "$IDENTITY" "$APP_BUNDLE"
else
    warn "no 'Paste Local Signing' / 'Clipboard Local Signing' identity found; using ad-hoc signing"
    warn "Accessibility/LaunchServices permissions will not survive rebuilds without a stable identity"
    codesign --force --sign - "$APP_BUNDLE"
fi

codesign --verify --strict --verbose=2 "$APP_BUNDLE" || die "codesign verification failed"
log "codesign details:"
codesign -dv "$APP_BUNDLE" 2>&1 | sed 's/^/[build]   /' || true

log "built $APP_BUNDLE"
log "launch with: open \"$APP_BUNDLE\"  (or Scripts/run.sh)"
