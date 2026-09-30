#!/usr/bin/env bash
# Boots an iOS Simulator and prints its UDID on the last line of stdout. macOS only (runs in CI).
# Prefers the iPhone 12 Pro Max profile (the owner's device); falls back to the newest available iPhone.
#   scripts/ios-simulator.sh                # prefer iPhone 12 Pro Max
#   DEVICE_NAME="iPhone 16" scripts/ios-simulator.sh
set -euo pipefail

PREFERRED="${DEVICE_NAME:-iPhone 12 Pro Max}"

echo "Xcode: $(xcodebuild -version | tr '\n' ' ')" >&2
echo "Available runtimes:" >&2
xcrun simctl list runtimes available >&2

pick_udid() {
  # Prints "UDID" for the first available device whose name matches $1 exactly.
  xcrun simctl list devices available -j | python3 -c '
import json, sys
name = sys.argv[1]
data = json.load(sys.stdin)["devices"]
# Newest runtime first: keys look like com.apple.CoreSimulator.SimRuntime.iOS-18-2
def version(key):
    tail = key.rsplit("iOS-", 1)[-1]
    return tuple(int(p) for p in tail.split("-") if p.isdigit())
for runtime in sorted((k for k in data if "SimRuntime.iOS-" in k), key=version, reverse=True):
    for device in data[runtime]:
        if device["name"] == name and device.get("isAvailable", True):
            print(device["udid"])
            sys.exit(0)
sys.exit(1)
' "$1"
}

UDID="$(pick_udid "$PREFERRED" || true)"
if [ -z "$UDID" ]; then
  echo "No available '$PREFERRED' simulator; falling back to the newest iPhone." >&2
  UDID="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
data = json.load(sys.stdin)["devices"]
def version(key):
    tail = key.rsplit("iOS-", 1)[-1]
    return tuple(int(p) for p in tail.split("-") if p.isdigit())
for runtime in sorted((k for k in data if "SimRuntime.iOS-" in k), key=version, reverse=True):
    phones = [d for d in data[runtime] if d["name"].startswith("iPhone") and d.get("isAvailable", True)]
    if phones:
        print(phones[-1]["udid"])
        sys.exit(0)
sys.exit(1)
')"
fi

echo "Using simulator $UDID" >&2
xcrun simctl boot "$UDID" 2>/dev/null || true   # already booted is fine
xcrun simctl bootstatus "$UDID" -b >&2
echo "$UDID"
