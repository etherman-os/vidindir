#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
CONFIGURATION="${CONFIGURATION:-release}"
ARCHITECTURES="${ARCHITECTURES:-}"
APP_NAME="Vidindir"
EXECUTABLE_NAME="Vidindir"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
ICONSET="$ROOT_DIR/.build/Vidindir.iconset"
ICON_FILE="$ROOT_DIR/.build/AppIcon.icns"
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-}"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"

if [[ -n "$SPARKLE_FEED_URL" && -z "$SPARKLE_PUBLIC_ED_KEY" ]] || \
   [[ -z "$SPARKLE_FEED_URL" && -n "$SPARKLE_PUBLIC_ED_KEY" ]]; then
  echo "SPARKLE_FEED_URL and SPARKLE_PUBLIC_ED_KEY must be provided together." >&2
  exit 1
fi

if [[ -n "$SPARKLE_FEED_URL" && "$SPARKLE_FEED_URL" != https://* ]]; then
  echo "SPARKLE_FEED_URL must use HTTPS." >&2
  exit 1
fi

cd "$ROOT_DIR"
BUILD_ARGUMENTS=(-c "$CONFIGURATION")
if [[ -n "$ARCHITECTURES" ]]; then
  for architecture in ${(z)ARCHITECTURES}; do
    BUILD_ARGUMENTS+=(--arch "$architecture")
  done
fi
swift build "${BUILD_ARGUMENTS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGUMENTS[@]}" --show-bin-path)"

case "$APP_BUNDLE" in
  "$ROOT_DIR"/dist/*.app) /bin/rm -rf "$APP_BUNDLE" ;;
  *) echo "Refusing unsafe app bundle path: $APP_BUNDLE" >&2; exit 1 ;;
esac

/bin/mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$CONTENTS/Frameworks" "$DIST_DIR"
/bin/cp "$BIN_DIR/$EXECUTABLE_NAME" "$CONTENTS/MacOS/$EXECUTABLE_NAME"
/bin/cp "$ROOT_DIR/Support/Info.plist" "$CONTENTS/Info.plist"
/bin/cp "$ROOT_DIR/LICENSE" "$CONTENTS/Resources/LICENSE.txt"
/bin/cp "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$CONTENTS/Resources/THIRD_PARTY_NOTICES.md"

if [[ ! -d "$BIN_DIR/Sparkle.framework" ]]; then
  echo "Sparkle.framework was not produced by SwiftPM." >&2
  exit 1
fi
if [[ ! -f "$ROOT_DIR/.build/artifacts/sparkle/Sparkle/LICENSE" ]]; then
  echo "Sparkle license was not found in the resolved SwiftPM artifact." >&2
  exit 1
fi

# ditto preserves the framework's symlinks and executable permissions.
/usr/bin/ditto "$BIN_DIR/Sparkle.framework" "$CONTENTS/Frameworks/Sparkle.framework"
/bin/cp "$ROOT_DIR/.build/artifacts/sparkle/Sparkle/LICENSE" "$CONTENTS/Resources/SPARKLE_LICENSE.txt"
/usr/bin/install_name_tool \
  -add_rpath "@executable_path/../Frameworks" \
  "$CONTENTS/MacOS/$EXECUTABLE_NAME"

if [[ -n "$SPARKLE_FEED_URL" ]]; then
  /usr/libexec/PlistBuddy -c "Set :SUFeedURL $SPARKLE_FEED_URL" "$CONTENTS/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $SPARKLE_PUBLIC_ED_KEY" "$CONTENTS/Info.plist"
fi

/bin/rm -rf "$ICONSET"
/bin/mkdir -p "$ICONSET"
/usr/bin/swift "$ROOT_DIR/Scripts/generate_icon.swift" "$ICONSET"
/usr/bin/iconutil -c icns "$ICONSET" -o "$ICON_FILE"
/bin/cp "$ICON_FILE" "$CONTENTS/Resources/AppIcon.icns"

/bin/bash "$ROOT_DIR/Scripts/sign_app.sh" "$APP_BUNDLE" -

echo "$APP_BUNDLE"
