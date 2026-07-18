#!/bin/bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <app-bundle> <codesign-identity-or-dash>" >&2
  exit 64
fi

app_path="$1"
identity="$2"
sparkle="$app_path/Contents/Frameworks/Sparkle.framework"

if [[ ! -d "$app_path" || ! -f "$app_path/Contents/Info.plist" ]]; then
  echo "App bundle not found: $app_path" >&2
  exit 1
fi

if [[ ! -d "$sparkle" ]]; then
  echo "Embedded Sparkle framework not found: $sparkle" >&2
  exit 1
fi

sparkle_version="$sparkle/Versions/B"
autoupdate="$sparkle_version/Autoupdate"

verify_autoupdate_entitlement() {
  local entitlements
  entitlements="$(/usr/bin/codesign --display --entitlements - "$autoupdate" 2>/dev/null)"
  if ! /usr/bin/grep -Fq 'com.apple.application-identifier' <<< "$entitlements" || \
     ! /usr/bin/grep -Fq 'org.sparkle-project.Sparkle.Autoupdate' <<< "$entitlements"; then
    echo "Sparkle Autoupdate lost its application-identifier entitlement." >&2
    exit 1
  fi
}

if [[ "$identity" == "-" ]]; then
  # Sparkle ships its helpers with valid ad-hoc signatures and Hardened
  # Runtime enabled. Retain those signatures and seal them into the app.
  verify_autoupdate_entitlement
  /usr/bin/codesign --force --sign - "$app_path"
  verify_autoupdate_entitlement
else
  required_nested_code=(
    "$sparkle_version/XPCServices/Installer.xpc"
    "$sparkle_version/XPCServices/Downloader.xpc"
    "$sparkle_version/Autoupdate"
    "$sparkle_version/Updater.app"
  )

  for nested_path in "${required_nested_code[@]}"; do
    if [[ ! -e "$nested_path" ]]; then
      echo "Required Sparkle component not found: $nested_path" >&2
      exit 1
    fi
  done

  common_args=(
    --force
    --options runtime
    --timestamp
    --sign "$identity"
  )

  # Sign explicitly from the deepest code outward, following Sparkle's manual
  # distribution-signing sequence. Only Downloader.xpc keeps its shipped
  # entitlements; carrying Autoupdate's ad-hoc application identifier into a
  # Developer ID signature would bind it to the wrong signing context.
  /usr/bin/codesign "${common_args[@]}" \
    "$sparkle_version/XPCServices/Installer.xpc"
  /usr/bin/codesign "${common_args[@]}" \
    --preserve-metadata=entitlements \
    "$sparkle_version/XPCServices/Downloader.xpc"
  /usr/bin/codesign "${common_args[@]}" \
    "$sparkle_version/Autoupdate"
  /usr/bin/codesign "${common_args[@]}" \
    "$sparkle_version/Updater.app"
  /usr/bin/codesign "${common_args[@]}" "$sparkle"
  /usr/bin/codesign "${common_args[@]}" "$app_path"
fi

# --deep is intentionally verification-only. It mirrors Gatekeeper's recursive
# validation without mutating nested signatures or entitlements.
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app_path"

runtime_code=(
  "$sparkle_version/XPCServices/Installer.xpc"
  "$sparkle_version/XPCServices/Downloader.xpc"
  "$sparkle_version/Autoupdate"
  "$sparkle_version/Updater.app"
  "$sparkle"
)
if [[ "$identity" != "-" ]]; then
  runtime_code+=("$app_path")
fi

for code_path in "${runtime_code[@]}"; do
  signing_details="$(/usr/bin/codesign --display --verbose=4 "$code_path" 2>&1)"
  if ! /usr/bin/grep -Eq 'flags=.*runtime' <<< "$signing_details"; then
    echo "Hardened Runtime is missing from signed code: $code_path" >&2
    exit 1
  fi
done
