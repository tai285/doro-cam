#!/usr/bin/env bash
# Boots the Android emulator headless and waits until Android has finished booting.
#   scripts/emulator-start.sh                 # AVD doro_api35
#   scripts/emulator-start.sh my_other_avd
# Environment:
#   BOOT_TIMEOUT    seconds to wait for boot (default 300)
#   POLL_INTERVAL   seconds between boot checks (default 3)
#   EMULATOR_ARGS   extra emulator flags (default: headless, no audio, no snapshot save, software GPU)
# Needs `emulator` and `adb` on PATH (source scripts/dev-env.sh first). Stop it with `adb emu kill`.
# On success prints the emulator serial (for example emulator-5554) on the last line of stdout.
set -euo pipefail

AVD="${1:-doro_api35}"
BOOT_TIMEOUT="${BOOT_TIMEOUT:-300}"
POLL_INTERVAL="${POLL_INTERVAL:-3}"
EMULATOR_ARGS="${EMULATOR_ARGS:--no-window -no-audio -no-snapshot-save -gpu swiftshader_indirect}"

for tool in emulator adb; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "error: '$tool' not found on PATH (run: source scripts/dev-env.sh)" >&2
    exit 127
  fi
done

if adb devices 2>/dev/null | grep -q '^emulator-[0-9]*[[:space:]]*device'; then
  SERIAL="$(adb devices | grep '^emulator-' | head -1 | cut -f1)"
  echo "An emulator is already running ($SERIAL); reusing it." >&2
  echo "$SERIAL"
  exit 0
fi

echo "Starting emulator '$AVD' (timeout ${BOOT_TIMEOUT}s)..." >&2
# shellcheck disable=SC2086  # EMULATOR_ARGS is intentionally word-split
emulator -avd "$AVD" $EMULATOR_ARGS >/dev/null 2>&1 &
EMULATOR_PID=$!

# Stops the emulator we started and waits for it to exit, so no orphaned process is left behind.
stop_emulator() {
  kill "$EMULATOR_PID" 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    kill -0 "$EMULATOR_PID" 2>/dev/null || return 0
    sleep 0.5
  done
  kill -9 "$EMULATOR_PID" 2>/dev/null || true
}

adb start-server >/dev/null 2>&1 || true

START=$SECONDS
while true; do
  if ! kill -0 "$EMULATOR_PID" 2>/dev/null; then
    echo "error: the emulator process exited before Android booted" >&2
    exit 1
  fi
  BOOTED="$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)"
  if [ "$BOOTED" = "1" ]; then
    break
  fi
  if [ $((SECONDS - START)) -ge "$BOOT_TIMEOUT" ]; then
    echo "error: Android did not finish booting within ${BOOT_TIMEOUT}s" >&2
    stop_emulator
    exit 1
  fi
  sleep "$POLL_INTERVAL"
done

# Dismiss the lock screen and let the UI settle.
adb shell input keyevent 82 >/dev/null 2>&1 || true
SERIAL="$(adb devices | grep '^emulator-' | head -1 | cut -f1)"
echo "Booted in $((SECONDS - START))s as $SERIAL." >&2
echo "${SERIAL:-emulator-5554}"
