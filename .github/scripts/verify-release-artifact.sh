#!/usr/bin/env bash
set -euo pipefail

: "${IPA_PATH:?IPA_PATH is required}"
: "${CHECKSUM_PATH:?CHECKSUM_PATH is required}"
: "${EXPECTED_VERSION:?EXPECTED_VERSION is required}"
: "${APP_IDENTIFIER:?APP_IDENTIFIER is required}"

expected_hash="$(awk 'NF { print $1; exit }' "$CHECKSUM_PATH")"
actual_hash="$(shasum -a 256 "$IPA_PATH" | awk '{ print $1 }')"
if [[ ! "$expected_hash" =~ ^[0-9a-fA-F]{64}$ ]]; then
  echo "Invalid SHA-256 manifest: $CHECKSUM_PATH" >&2
  exit 1
fi
if [[ "$actual_hash" != "$expected_hash" ]]; then
  echo "Release IPA checksum mismatch: expected $expected_hash, got $actual_hash" >&2
  exit 1
fi

artifact_tmp="$(mktemp -d "${RUNNER_TEMP:-/tmp}/cadence-release-artifact.XXXXXX")"
trap 'rm -rf -- "$artifact_tmp"' EXIT
unzip -q "$IPA_PATH" -d "$artifact_tmp"

app="$artifact_tmp/Payload/Cadence.app"
widget="$app/PlugIns/CadenceWidgets.appex"
if [[ ! -d "$app" || ! -d "$widget" ]]; then
  echo "Release IPA is missing Cadence.app or its widget extension" >&2
  exit 1
fi

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1/Info.plist"
}

app_version="$(plist_value "$app" CFBundleShortVersionString)"
widget_version="$(plist_value "$widget" CFBundleShortVersionString)"
app_id="$(plist_value "$app" CFBundleIdentifier)"
widget_id="$(plist_value "$widget" CFBundleIdentifier)"

[[ "$app_version" == "$EXPECTED_VERSION" ]] || {
  echo "App version is $app_version; expected $EXPECTED_VERSION" >&2
  exit 1
}
[[ "$widget_version" == "$EXPECTED_VERSION" ]] || {
  echo "Widget version is $widget_version; expected $EXPECTED_VERSION" >&2
  exit 1
}
[[ "$app_id" == "$APP_IDENTIFIER" ]] || {
  echo "App identifier is $app_id; expected $APP_IDENTIFIER" >&2
  exit 1
}
[[ "$widget_id" == "$APP_IDENTIFIER.Widgets" ]] || {
  echo "Widget identifier is $widget_id; expected $APP_IDENTIFIER.Widgets" >&2
  exit 1
}

codesign --verify --deep --strict --verbose=2 "$app"
echo "Verified signed release artifact $actual_hash (Cadence $EXPECTED_VERSION)"
