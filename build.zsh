#!/bin/zsh

set -euo pipefail

if [[ -f "$HOME/.toolbox" ]]; then
    source "$HOME/.toolbox"
fi

PROJECT_DIR="${0:A:h}"
APP_NAME="1thing"
VERSION="$(
    /usr/libexec/PlistBuddy \
        -c 'Print :CFBundleShortVersionString' \
        "$PROJECT_DIR/Info.plist"
)"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"
SIGN_IDENTITY="${APPLE_SIGN_IDENTITY:--}"

print -- "Building $APP_NAME $VERSION \"Taarnet\" for Apple Silicon..."

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$PROJECT_DIR/Info.plist" "$CONTENTS/Info.plist"
cp "$PROJECT_DIR/Resources/1thing.icns" "$RESOURCES_DIR/1thing.icns"

swiftc \
    "$PROJECT_DIR/1thing.swift" \
    -O \
    -target arm64-apple-macosx13.0 \
    -framework AppKit \
    -framework ServiceManagement \
    -o "$MACOS_DIR/$APP_NAME"

chmod +x "$MACOS_DIR/$APP_NAME"
plutil -lint "$CONTENTS/Info.plist"

codesign \
    --force \
    --deep \
    --options runtime \
    --sign "$SIGN_IDENTITY" \
    "$APP_BUNDLE"

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

print
print -- "✓ Build complete"
print -- "  $APP_BUNDLE"
print -- "  Signing identity: $SIGN_IDENTITY"
print
print -- "Run with:"
print -- "  open '$APP_BUNDLE'"
