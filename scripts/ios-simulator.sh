#!/usr/bin/env bash
# Boots an iOS Simulator and prints its UDID on the last line of stdout. macOS only (runs in CI).
#
# Device: prefers the owner's iPhone 12 Pro Max, then other large iPhones, then any iPhone.
# Runtime: prefers iOS $IOS_RUNTIME_MAJOR (default 18, a mature runtime); falls back to the newest.
#   scripts/ios-simulator.sh
#   IOS_RUNTIME_MAJOR=26 DEVICE_NAME="iPhone 17 Pro" scripts/ios-simulator.sh
set -euo pipefail

export IOS_RUNTIME_MAJOR="${IOS_RUNTIME_MAJOR:-18}"
export DEVICE_PREFERENCE="${DEVICE_NAME:-iPhone 12 Pro Max|iPhone 16 Pro Max|iPhone 15 Pro Max|iPhone 16 Plus|iPhone 16 Pro|iPhone 16}"

{
  echo "Xcode: $(xcodebuild -version | tr '\n' ' ')"
  echo "Available iOS runtimes:"
  xcrun simctl list runtimes available | grep "^iOS" || true
} >&2

UDID="$(xcrun simctl list devices available -j | python3 -c '
import json, os, sys

data = json.load(sys.stdin)["devices"]
major = os.environ["IOS_RUNTIME_MAJOR"]
preferences = os.environ["DEVICE_PREFERENCE"].split("|")


def version(key):
    tail = key.rsplit("iOS-", 1)[-1]
    return tuple(int(p) for p in tail.split("-") if p.isdigit())


runtimes = sorted((k for k in data if "SimRuntime.iOS-" in k), key=version, reverse=True)
preferred = [k for k in runtimes if version(k)[:1] == (int(major),)]
# Try the preferred major first, then everything else (newest first).
for runtime in preferred + [k for k in runtimes if k not in preferred]:
    devices = [d for d in data[runtime] if d.get("isAvailable", True)]
    for name in preferences:
        for device in devices:
            if device["name"] == name:
                print(device["udid"], file=sys.stdout)
                print(f"Selected {name} on {runtime}", file=sys.stderr)
                sys.exit(0)
for runtime in preferred + [k for k in runtimes if k not in preferred]:
    phones = [d for d in data[runtime] if d["name"].startswith("iPhone") and d.get("isAvailable", True)]
    if phones:
        print(phones[-1]["udid"], file=sys.stdout)
        print(f"Selected fallback {phones[-1]['"'"'name'"'"']} on {runtime}", file=sys.stderr)
        sys.exit(0)
sys.exit(1)
')"

echo "Using simulator $UDID" >&2
xcrun simctl boot "$UDID" 2>/dev/null || true   # already booted is fine
xcrun simctl bootstatus "$UDID" -b >&2
echo "$UDID"
