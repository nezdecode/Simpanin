#!/bin/bash
# Builds the app for a real iPhone and installs it, but only after a successful build: a failed build's
# half-built app once got installed, and iOS refused it as unverifiable.
#   scripts/install-device.sh
# SIMPANIN_DEVICE names the iPhone by its UDID; otherwise the one paired physical iPhone is used.
set -euo pipefail
cd "$(dirname "$0")/.."

device="${SIMPANIN_DEVICE:-}"
if [ -z "$device" ]; then
  list="$(mktemp)"
  xcrun devicectl list devices --json-output "$list" > /dev/null
  # devicectl lists simulators too; only a physical, paired iPhone will do. With several, the connected one.
  device="$(python3 -B - "$list" <<'PY'
import json, sys
devices = [d for d in json.load(open(sys.argv[1]))['result']['devices']
           if d.get('hardwareProperties', {}).get('reality') == 'physical'
           and d.get('hardwareProperties', {}).get('deviceType') == 'iPhone'
           and d.get('connectionProperties', {}).get('pairingState') == 'paired']
if len(devices) > 1:
    devices = [d for d in devices if d['connectionProperties'].get('tunnelState') == 'connected']
if len(devices) == 1:
    print(devices[0]['hardwareProperties']['udid'])
PY
)"
  rm -f "$list"
fi
if [ -z "$device" ]; then
  echo "install-device.sh: found no paired iPhone, or several and none connected; set SIMPANIN_DEVICE to its UDID" >&2
  exit 1
fi

mkdir -p build
log="build/install-$(date +%Y%m%d-%H%M%S).log"
echo "install-device.sh: building for $device (log: $log)"
# -allowProvisioningUpdates lets Xcode renew a provisioning profile or register this iPhone in your developer
# account without asking, so a build doesn't stop at an expired profile.
xcodebuild build -project Simpanin.xcodeproj -scheme Simpanin -destination "id=$device" \
  -derivedDataPath build/DerivedData-device -allowProvisioningUpdates > "$log" 2>&1 || true

if ! grep -q "BUILD SUCCEEDED" "$log"; then
  echo "install-device.sh: the build failed, nothing installed" >&2
  if ! grep -E " error:" "$log" | head -5 >&2; then
    echo "  No error: line. It may be a compiler crash: look for \"Assertion failed\" or \"Stack dump\" in $log" >&2
  fi
  exit 1
fi
xcrun devicectl device install app --device "$device" \
  build/DerivedData-device/Build/Products/Debug-iphoneos/Simpanin.app
echo "install-device.sh: installed"
