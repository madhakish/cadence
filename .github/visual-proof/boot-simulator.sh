#!/usr/bin/env bash
# Boot a simulator and prove it is usable before xcodebuild targets it.
# `simctl bootstatus -b` exits 0 even when the boot ends in a terminal
# error (Status=4294967295 after a stalled data migration), and the next
# step then fails with "Unable to find a device matching the provided
# destination specifier". Check the device state, retry once from an
# erased device, and fail here with the real reason otherwise.
set -euo pipefail

udid="$1"

state() {
  xcrun simctl list devices available -j | python3 -c '
import json, sys
udid = sys.argv[1]
for group in json.load(sys.stdin)["devices"].values():
    for device in group:
        if device["udid"] == udid:
            print(device["state"])
            sys.exit(0)
print("Unavailable")
' "$udid"
}

boot() {
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b || true
}

boot
if [[ "$(state)" != "Booted" ]]; then
  echo "::warning::Simulator $udid is '$(state)' after boot; erasing and booting again"
  xcrun simctl shutdown "$udid" 2>/dev/null || true
  xcrun simctl erase "$udid" || true
  boot
fi

final="$(state)"
if [[ "$final" != "Booted" ]]; then
  echo "::error::Simulator $udid is '$final', not Booted"
  xcrun simctl list devices "$udid" || true
  exit 1
fi
