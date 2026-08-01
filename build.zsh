#!/bin/zsh

set -euo pipefail

PROJECT_DIR="${0:A:h}"
APP_NAME="1thing"
RELEASE_NAME="Taarnet"

INFO_PLIST="$PROJECT_DIR/Info.plist"
ICON="$PROJECT_DIR/Resources/1thing.icns"

VERSION="$(
    /usr/libexec/PlistBuddy \
        -c 'Print :CFBundleShortVersionString' \
        "$INFO_PLIST"
)"

APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
TMP_APP="${APP_BUNDLE}.new"
OLD_APP="${APP_BUNDLE}.old"

CONTENTS="$TMP_APP/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

SIGNING_IDENTITY="${APPLE_SIGN_IDENTITY:--}"

print -- "Building $APP_NAME $VERSION \"$RELEASE_NAME\" for Apple Silicon..."

[[ -f "$INFO_PLIST" ]] || {
    print -u2 -- "Error: Info.plist not found:"
    print -u2 -- "  $INFO_PLIST"
    exit 1
}

[[ -f "$ICON" ]] || {
    print -u2 -- "Error: App icon not found:"
    print -u2 -- "  $ICON"
    exit 1
}

killall "$APP_NAME" 2>/dev/null || true

rm -rf "$TMP_APP" "$OLD_APP"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$INFO_PLIST" "$CONTENTS/Info.plist"
cp "$ICON" "$RESOURCES_DIR/1thing.icns"

swiftc \
    "$PROJECT_DIR/1thing.swift" \
    -O \
    -target arm64-apple-macosx13.0 \
    -framework AppKit \
    -framework ServiceManagement \
    -o "$MACOS_DIR/$APP_NAME"

chmod +x "$MACOS_DIR/$APP_NAME"

plutil -lint "$CONTENTS/Info.plist"

test -x "$MACOS_DIR/$APP_NAME"
test -f "$RESOURCES_DIR/1thing.icns"

xattr -cr "$TMP_APP"

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    print -- "Signing ad hoc..."
else
    if ! security find-identity -v -p codesigning \
        | grep -Fq "$SIGNING_IDENTITY"; then
        print -u2 -- "Error: Code-signing identity not found:"
        print -u2 -- "  $SIGNING_IDENTITY"
        print -u2
        print -u2 -- "Available identities:"
        security find-identity -v -p codesigning >&2
        exit 1
    fi

    print -- "Signing with: $SIGNING_IDENTITY"
fi

codesign \
    --force \
    --deep \
    --options runtime \
    --sign "$SIGNING_IDENTITY" \
    "$TMP_APP"

codesign \
    --verify \
    --deep \
    --strict \
    --verbose=2 \
    "$TMP_APP"

if [[ -d "$APP_BUNDLE" ]]; then
    mv "$APP_BUNDLE" "$OLD_APP"
fi

if ! mv "$TMP_APP" "$APP_BUNDLE"; then
    print -u2 -- "Error: Could not install the new app bundle."

    if [[ -d "$OLD_APP" ]]; then
        mv "$OLD_APP" "$APP_BUNDLE"
        print -u2 -- "Restored the previous app bundle."
    fi

    exit 1
fi

rm -rf "$OLD_APP"

touch "$APP_BUNDLE"

print
print -- "✓ Build complete"
print -- "  $APP_BUNDLE"

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    print -- "  Signing: ad hoc"
else
    print -- "  Signing: $SIGNING_IDENTITY"
fi

print
print -- "Run with:"
print -- "  open '$APP_BUNDLE'"