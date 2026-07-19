#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "usage: $0 <v1.29 checkout> <PR72 checkout> <PR73 checkout> <fixture output>" >&2
  exit 64
fi

v129_source="$1"
pr72_source="$2"
pr73_source="$3"
fixture_root="$4"

device_id="$({ xcrun simctl list devices available -j; } | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
for runtime in sorted(devices, reverse=True):
    for device in devices[runtime]:
        if device.get("isAvailable") and device.get("name", "").startswith("iPhone"):
            print(device["udid"])
            raise SystemExit(0)
raise SystemExit("No available iPhone simulator")
')"

xcrun simctl boot "$device_id" 2>/dev/null || true
xcrun simctl bootstatus "$device_id" -b
mkdir -p "$fixture_root"

build_app() {
  local label="$1"
  local source="$2"
  local derived="$RUNNER_TEMP/cadence-$label-derived"

  (cd "$source" && xcodegen generate)
  xcodebuild build \
    -project "$source/Cadence.xcodeproj" \
    -scheme Cadence \
    -configuration Release \
    -destination "platform=iOS Simulator,id=$device_id" \
    -derivedDataPath "$derived" \
    CODE_SIGNING_ALLOWED=NO
  built_app="$derived/Build/Products/Release-iphonesimulator/Cadence.app"
}

launch_app() {
  xcrun simctl install "$device_id" "$built_app"
  xcrun simctl launch "$device_id" com.madhakish.Cadence
  sleep 5
  xcrun simctl terminate "$device_id" com.madhakish.Cadence 2>/dev/null || true
}

copy_store() {
  local label="$1"
  local output="$fixture_root/$label"

  local container
  container="$(xcrun simctl get_app_container "$device_id" com.madhakish.Cadence data)"
  local store_dir="$container/Library/Application Support"
  test -f "$store_dir/default.store"
  mkdir -p "$output"
  cp "$store_dir"/default.store* "$output/"
}

build_app "v129" "$v129_source"
xcrun simctl uninstall "$device_id" com.madhakish.Cadence 2>/dev/null || true
launch_app
copy_store "v129"

# Reproduce the owner's exact failed-upgrade lineage: a healthy v1.29 store,
# followed by the incompatible #72 launch and then the unsuccessful #73
# recovery launch. Neither failed build is allowed to erase the source store.
build_app "pr72" "$pr72_source"
launch_app
build_app "pr73" "$pr73_source"
launch_app
copy_store "v129-after-failed-upgrades"

# Also cover a store first created by #72, whose advertised version is V1 but
# whose model checksum differs from v1.29.
xcrun simctl uninstall "$device_id" com.madhakish.Cadence 2>/dev/null || true
build_app "pr72" "$pr72_source"
launch_app
copy_store "pr72"
xcrun simctl shutdown "$device_id" 2>/dev/null || true
