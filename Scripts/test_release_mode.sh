#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
selector="$script_dir/select_release_mode.sh"

assert_case() {
  local expected_mode="$1"
  local expected_stable="$2"
  local expected_prerelease="$3"
  local expected_dmg="$4"
  shift 4

  local output
  output="$($selector "$@" Vidindir 1.2.3 universal2)"
  /usr/bin/grep -Fqx "mode=$expected_mode" <<< "$output"
  /usr/bin/grep -Fqx "publish_stable=$expected_stable" <<< "$output"
  /usr/bin/grep -Fqx "publish_prerelease=$expected_prerelease" <<< "$output"
  /usr/bin/grep -Fqx "dmg_name=$expected_dmg" <<< "$output"
}

assert_case notarized true false \
  Vidindir-1.2.3-macOS-universal2.dmg \
  true true true false
assert_case notarized false true \
  Vidindir-1.2.3-macOS-universal2-notarized-no-update-key.dmg \
  true true false false
assert_case signed-unnotarized false true \
  Vidindir-1.2.3-macOS-universal2-signed-unnotarized.dmg \
  true false true false
assert_case missing-developer-id false false \
  Vidindir-1.2.3-macOS-universal2-missing-developer-id.dmg \
  false false true true
assert_case developer-preview false true \
  Vidindir-1.2.3-macOS-universal2-developer-preview.dmg \
  false false false false

if "$selector" maybe false false false Vidindir 1.2.3 universal2 >/dev/null 2>&1; then
  echo "Invalid boolean input was accepted." >&2
  exit 1
fi
if "$selector" false false false false Vidindir 1.2 universal2 >/dev/null 2>&1; then
  echo "Invalid version input was accepted." >&2
  exit 1
fi

echo "Release mode tests passed."
