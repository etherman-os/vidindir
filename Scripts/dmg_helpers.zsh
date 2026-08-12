#!/bin/zsh

# Detaching a just-customized DMG can briefly fail with EBUSY (exit 16),
# especially on headless Intel runners while Finder releases the volume.
detach_disk_image() {
  emulate -L zsh

  local device="$1"
  local hdiutil_bin="${HDIUTIL_BIN:-/usr/bin/hdiutil}"
  local max_attempts="${DMG_DETACH_MAX_ATTEMPTS:-5}"
  local retry_delay="${DMG_DETACH_RETRY_DELAY_SECONDS:-1}"
  local attempt=1
  local detach_status=0

  while true; do
    if "$hdiutil_bin" detach "$device" -quiet; then
      return 0
    else
      detach_status=$?
    fi

    if (( detach_status != 16 || attempt >= max_attempts )); then
      return "$detach_status"
    fi

    print -u2 -- "Disk image $device is busy; retrying detach ($attempt/$max_attempts)."
    attempt=$((attempt + 1))
    /bin/sleep "$retry_delay"
  done
}
