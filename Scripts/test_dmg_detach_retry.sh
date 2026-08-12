#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
source "$ROOT_DIR/Scripts/dmg_helpers.zsh"

TMP_BASE="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/dmg-detach-test.XXXXXX")"
trap '/bin/rm -rf "$TMP_BASE"' EXIT
COUNT_FILE="$TMP_BASE/count"
FAKE_HDIUTIL="$TMP_BASE/hdiutil"

cat > "$FAKE_HDIUTIL" <<'FAKE'
#!/bin/zsh
count_file="${DMG_TEST_COUNT_FILE:?}"
count=0
[[ -f "$count_file" ]] && count="$(cat "$count_file")"
count=$((count + 1))
print -r -- "$count" > "$count_file"
if (( count < 3 )); then
  exit 16
fi
exit 0
FAKE
chmod +x "$FAKE_HDIUTIL"

export HDIUTIL_BIN="$FAKE_HDIUTIL"
export DMG_TEST_COUNT_FILE="$COUNT_FILE"
export DMG_DETACH_MAX_ATTEMPTS=5
export DMG_DETACH_RETRY_DELAY_SECONDS=0

detach_disk_image /dev/disk-test

attempts="$(cat "$COUNT_FILE")"
if [[ "$attempts" != "3" ]]; then
  print -u2 -- "Expected detach to succeed on attempt 3; got $attempts attempts."
  exit 1
fi

print -r -- "DMG detach retry test passed."
