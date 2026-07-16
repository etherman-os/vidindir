#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"

if [[ -z "${APP_PATH:-}" ]]; then
  APP_CANDIDATES=("$DIST_DIR"/*.app(N))
  if (( ${#APP_CANDIDATES[@]} != 1 )); then
    print -u2 -- "Expected exactly one app bundle in $DIST_DIR; found ${#APP_CANDIDATES[@]}."
    print -u2 -- "Run Scripts/package_app.sh first, or set APP_PATH explicitly."
    exit 1
  fi
  APP_PATH="${APP_CANDIDATES[1]}"
fi

if [[ ! -d "$APP_PATH" || ! -f "$APP_PATH/Contents/Info.plist" ]]; then
  print -u2 -- "App bundle not found: $APP_PATH"
  print -u2 -- "Run Scripts/package_app.sh first, or set APP_PATH."
  exit 1
fi

APP_BUNDLE_NAME="${APP_PATH:t}"
APP_DISPLAY_NAME="${APP_BUNDLE_NAME%.app}"
APP_FILE_STEM="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' \
  "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
APP_FILE_STEM="${APP_FILE_STEM:-$APP_DISPLAY_NAME}"
SAFE_APP_NAME="${APP_FILE_STEM//[^A-Za-z0-9._-]/-}"
SAFE_APP_NAME="${SAFE_APP_NAME:-App}"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
APP_VERSION="${VERSION:-${APP_VERSION:-dev}}"
SAFE_VERSION="${APP_VERSION//[^A-Za-z0-9._-]/-}"
VOLUME_NAME="${VOLUME_NAME:-$APP_DISPLAY_NAME $APP_VERSION}"
OUTPUT_DMG="${OUTPUT_DMG:-$DIST_DIR/$SAFE_APP_NAME-$SAFE_VERSION-macOS.dmg}"

/bin/mkdir -p "$DIST_DIR" "${OUTPUT_DMG:h}"

TMP_BASE="${TMPDIR:-/tmp}"
TMP_BASE="${TMP_BASE%/}"
WORK_DIR="$(/usr/bin/mktemp -d "$TMP_BASE/app-dmg.XXXXXX")"
STAGING_DIR="$WORK_DIR/staging"
MOUNT_DIR=""
RW_DMG="$WORK_DIR/app-rw.dmg"
MOUNT_DEVICE=""

cleanup() {
  if [[ -n "$MOUNT_DEVICE" ]]; then
    /usr/bin/hdiutil detach "$MOUNT_DEVICE" -quiet >/dev/null 2>&1 || true
  fi

  case "$WORK_DIR" in
    "$TMP_BASE"/app-dmg.*) /bin/rm -rf "$WORK_DIR" ;;
    *) print -u2 -- "Refusing to remove unexpected temporary path: $WORK_DIR" ;;
  esac
}
trap cleanup EXIT INT TERM

/bin/mkdir -p "$STAGING_DIR"
/usr/bin/ditto "$APP_PATH" "$STAGING_DIR/$APP_BUNDLE_NAME"
/bin/chmod -R go-w "$STAGING_DIR"
/bin/ln -s /Applications "$STAGING_DIR/Applications"

STAGING_KB="$(/usr/bin/du -sk "$STAGING_DIR" | /usr/bin/awk '{ print $1 }')"
IMAGE_SIZE_MB="$(( (STAGING_KB / 1024) + 32 ))"

/usr/bin/hdiutil create \
  -volname "$VOLUME_NAME" \
  -fs HFS+ \
  -size "${IMAGE_SIZE_MB}m" \
  -ov \
  "$RW_DMG" >/dev/null

ATTACH_OUTPUT="$(/usr/bin/hdiutil attach \
  -readwrite \
  -noverify \
  -noautoopen \
  "$RW_DMG")"
MOUNT_DEVICE="$(print -r -- "$ATTACH_OUTPUT" | /usr/bin/awk '/^\/dev\// { print $1; exit }')"
MOUNT_DIR="$(print -r -- "$ATTACH_OUTPUT" | /usr/bin/awk '
  index($0, "/Volumes/") { print substr($0, index($0, "/Volumes/")); exit }
')"

if [[ -z "$MOUNT_DEVICE" || -z "$MOUNT_DIR" ]]; then
  print -u2 -- "Unable to determine the mounted disk image device or path."
  exit 1
fi

/usr/bin/ditto "$STAGING_DIR/" "$MOUNT_DIR/"

# Finder metadata is cosmetic. A headless runner may not allow Finder automation,
# so the DMG remains usable even if this layout step is unavailable.
if ! /usr/bin/osascript - "$VOLUME_NAME" "$APP_BUNDLE_NAME" <<'APPLESCRIPT'
on run argv
    set volumeName to item 1 of argv
    set appName to item 2 of argv

    tell application "Finder"
        tell disk volumeName
            open
            delay 1
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set pathbar visible of container window to false
            set bounds of container window to {120, 120, 760, 540}
            set viewOptions to icon view options of container window
            set arrangement of viewOptions to not arranged
            set icon size of viewOptions to 112
            set text size of viewOptions to 14
            set background color of viewOptions to {61680, 63222, 65535}
            set position of item appName to {175, 205}
            set position of item "Applications" to {465, 205}
            update without registering applications
            delay 2
            close
        end tell
    end tell
end run
APPLESCRIPT
then
  print -u2 -- "Warning: Finder layout could not be applied; continuing with a standard icon view."
fi

/bin/sync
/usr/bin/hdiutil detach "$MOUNT_DEVICE" -quiet
MOUNT_DEVICE=""

if [[ -e "$OUTPUT_DMG" ]]; then
  /bin/rm -f "$OUTPUT_DMG"
fi

/usr/bin/hdiutil convert \
  "$RW_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  -o "$OUTPUT_DMG" >/dev/null

/usr/bin/hdiutil verify "$OUTPUT_DMG" >/dev/null
print -r -- "$OUTPUT_DMG"
