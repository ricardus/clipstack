#!/usr/bin/env bash
# Builds Clipstack.app from the SwiftPM executable.
#
# Usage:
#   ./build.sh              # release build into ./dist/Clipstack.app
#   ./build.sh --install    # also copy it to /Applications and relaunch
#
# Signing: ad-hoc by default. Set CLIPSTACK_SIGN_IDENTITY to a self-signed
# certificate in your keychain to keep a stable code identity, otherwise macOS
# treats every rebuild as a new app and re-asks for Accessibility permission.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Clipstack"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
IDENTITY="${CLIPSTACK_SIGN_IDENTITY:--}"

echo "==> Building release binary"
swift build -c release --package-path "$ROOT"
BINARY="$(swift build -c release --package-path "$ROOT" --show-bin-path)/$APP_NAME"

# The icon is rendered once and cached in dist/ (rm it to redraw).
ICNS="$DIST/Clipstack.icns"
if [[ ! -f "$ICNS" ]]; then
    echo "==> Rendering app icon"
    mkdir -p "$DIST"
    swift "$ROOT/Tools/MakeIcons.swift" "$DIST"
    iconutil -c icns "$DIST/Clipstack.iconset" -o "$ICNS"
fi

echo "==> Assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ICNS" "$APP/Contents/Resources/Clipstack.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Signing with identity: $IDENTITY"
codesign --force --deep --options runtime --sign "$IDENTITY" "$APP"

if [[ "${1:-}" == "--install" ]]; then
    echo "==> Installing to /Applications"
    pkill -x "$APP_NAME" 2>/dev/null || true
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" "/Applications/$APP_NAME.app"
    open "/Applications/$APP_NAME.app"
else
    echo "==> Built $APP"
    echo "    Run it with: open \"$APP\""
fi
