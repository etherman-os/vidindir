#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
CONFIGURATION="${CONFIGURATION:-release}"
APP_NAME="Vidindir"
EXECUTABLE_NAME="Vidindir"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
ICONSET="$ROOT_DIR/.build/Vidindir.iconset"
ICON_FILE="$ROOT_DIR/.build/AppIcon.icns"

cd "$ROOT_DIR"
swift build -c "$CONFIGURATION"
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"

case "$APP_BUNDLE" in
  "$ROOT_DIR"/dist/*.app) /bin/rm -rf "$APP_BUNDLE" ;;
  *) echo "Refusing unsafe app bundle path: $APP_BUNDLE" >&2; exit 1 ;;
esac

/bin/mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$DIST_DIR"
/bin/cp "$BIN_DIR/$EXECUTABLE_NAME" "$CONTENTS/MacOS/$EXECUTABLE_NAME"
/bin/cp "$ROOT_DIR/Support/Info.plist" "$CONTENTS/Info.plist"
/bin/cp "$ROOT_DIR/LICENSE" "$CONTENTS/Resources/LICENSE.txt"
/bin/cp "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$CONTENTS/Resources/THIRD_PARTY_NOTICES.md"

/bin/rm -rf "$ICONSET"
/bin/mkdir -p "$ICONSET"
/usr/bin/swift "$ROOT_DIR/Scripts/generate_icon.swift" "$ICONSET"
/usr/bin/iconutil -c icns "$ICONSET" -o "$ICON_FILE"
/bin/cp "$ICON_FILE" "$CONTENTS/Resources/AppIcon.icns"

/usr/bin/codesign --force --deep --sign - "$APP_BUNDLE"

echo "$APP_BUNDLE"
