#!/bin/bash
set -euo pipefail

if [[ $# -ne 7 ]]; then
  echo "Usage: $0 <signed> <notarization-configured> <sparkle-key-configured> <require-developer-id> <app-slug> <version> <architecture>" >&2
  exit 64
fi

signed="$1"
notarization_configured="$2"
sparkle_key_configured="$3"
require_developer_id="${4:-false}"
app_slug="$5"
version="$6"
architecture="$7"

for value in "$signed" "$notarization_configured" "$sparkle_key_configured" "$require_developer_id"; do
  if [[ "$value" != "true" && "$value" != "false" ]]; then
    echo "Release capability values must be either true or false." >&2
    exit 64
  fi
done

if [[ ! "$app_slug" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "App slug contains unsafe characters." >&2
  exit 64
fi
if [[ ! "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo "Version must use MAJOR.MINOR.PATCH." >&2
  exit 64
fi
if [[ ! "$architecture" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "Architecture label contains unsafe characters." >&2
  exit 64
fi

publish_stable="false"
publish_prerelease="false"

if [[ "$signed" == "true" && "$notarization_configured" == "true" ]]; then
  mode="notarized"
  if [[ "$sparkle_key_configured" == "true" ]]; then
    publish_stable="true"
    dmg_name="$app_slug-$version-macOS-$architecture.dmg"
  else
    publish_prerelease="true"
    dmg_name="$app_slug-$version-macOS-$architecture-notarized-no-update-key.dmg"
  fi
elif [[ "$signed" == "true" ]]; then
  mode="signed-unnotarized"
  publish_prerelease="true"
  dmg_name="$app_slug-$version-macOS-$architecture-signed-unnotarized.dmg"
elif [[ "$require_developer_id" == "true" ]]; then
  mode="missing-developer-id"
  dmg_name="$app_slug-$version-macOS-$architecture-missing-developer-id.dmg"
else
  mode="developer-preview"
  publish_prerelease="true"
  dmg_name="$app_slug-$version-macOS-$architecture-developer-preview.dmg"
fi

printf 'mode=%s\n' "$mode"
printf 'publish_stable=%s\n' "$publish_stable"
printf 'publish_prerelease=%s\n' "$publish_prerelease"
printf 'dmg_name=%s\n' "$dmg_name"
