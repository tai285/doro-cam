#!/usr/bin/env bash
# The full-stack scenario: the real Android app on the emulator, the real API + worker + storage, and the real
# web dashboard in a browser, all against ONE database. Run inside WSL from the repo (a WSL-side tree is fine):
#
#   bash scripts/e2e-fullstack.sh            # from the repo root; or via the Windows tree:
#   wsl -e bash "/mnt/c/Users/yying/dev/scratch/Doro Cam/Doro Cam/scripts/wsl-run.sh" 'bash scripts/e2e-fullstack.sh'
#
# What happens (docs/development/testing-strategy.md, "Full-stack scenario"):
#   1. pnpm infra:up must already be running (Postgres + Garage S3).
#   2. services/api/test/fullstack-server.ts starts the worker and two API listeners on a private database
#      (10.0.2.2 for the phone, 127.0.0.1 for the browser; only mail is replaced by a readable outbox).
#   3. The web app is built against the browser-side API and served.
#   4. apps/mobile/integration_test/fullstack_test.dart drives the app on the emulator: offline photo, sign-up,
#      mailed confirmation, sign-in, Motion Memory, back-up. Camera and microphone are pre-granted.
#   5. apps/web/e2e-fullstack runs Playwright against the same stack: the app's Memories are in the dashboard,
#      the motion clip is a real MP4 and plays, an album is shared with a second account, a caption is edited.
#   6. apps/mobile/integration_test/fullstack_restore_test.dart reinstalls the app, signs in and gets both
#      Memories back, with the caption and favorite set on the web.
# Skip a half with FULLSTACK_SKIP_MOBILE=1 or FULLSTACK_SKIP_WEB=1 while debugging the other.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$HOME/.doro-env" 2>/dev/null || true
export pnpm_config_minimum_release_age="${pnpm_config_minimum_release_age:-0}"
export GRADLE_OPTS="${GRADLE_OPTS:--Xmx2g}"

DEVICE_PORT="${FULLSTACK_DEVICE_PORT:-4310}"
WEB_API_PORT="${FULLSTACK_WEB_PORT:-4311}"
WEB_PORT="${FULLSTACK_WEB_APP_PORT:-4174}"
LOGS="${FULLSTACK_LOGS:-$ROOT/.fullstack-logs}"
EMAIL="fullstack-$(date +%s)@example.test"
PASSWORD="fullstack-correct-horse-battery"
mkdir -p "$LOGS"
rm -f "$LOGS/.gradle-warm"

pids=()
cleanup() {
  for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done
  # the server drops its private database on SIGTERM; give it a moment
  sleep 2
  for pid in "${pids[@]}"; do kill -9 "$pid" 2>/dev/null || true; done
}
trap cleanup EXIT

wait_for() { # url, seconds
  for _ in $(seq 1 "$2"); do
    if curl -fsS -o /dev/null "$1" 2>/dev/null; then return 0; fi
    sleep 1
  done
  echo "timed out waiting for $1" >&2
  return 1
}

cd "$ROOT" || exit 1

echo "== infra"
S3_PORT="${FULLSTACK_S3_PORT:-9000}"
if ! (echo > "/dev/tcp/127.0.0.1/${S3_PORT}") 2> /dev/null; then
  echo "Garage S3 is not reachable on 127.0.0.1:${S3_PORT}: run 'pnpm infra:up' first" >&2
  exit 2
fi

echo "== api + worker"
(cd services/api && FULLSTACK_DEVICE_PORT="$DEVICE_PORT" FULLSTACK_WEB_PORT="$WEB_API_PORT" FULLSTACK_WEB_ORIGIN="http://127.0.0.1:${WEB_PORT}" exec node test/fullstack-server.ts) > "$LOGS/server.log" 2>&1 &
pids+=($!)
for _ in $(seq 1 90); do
  grep -q '^READY' "$LOGS/server.log" 2>/dev/null && break
  kill -0 "${pids[0]}" 2>/dev/null || { cat "$LOGS/server.log"; exit 1; }
  sleep 1
done
grep -q '^READY' "$LOGS/server.log" || { echo "server did not start"; cat "$LOGS/server.log"; exit 1; }
wait_for "http://127.0.0.1:${WEB_API_PORT}/healthz" 10 || exit 1

status=0

# Installs the app fresh (clean data), pre-grants camera and microphone as soon as it exists, runs one test file.
run_device_test() { # test file, log name
  (
    cd apps/mobile || exit 1
    # Warm the Gradle and Dart caches while the emulator is still off: an emulator booting while Gradle runs
    # starves QEMU on a laptop (hung QEMU threads, even a crashed WSL VM). `flutter test` then only builds
    # incrementally.
    if [ ! -f "$LOGS/.gradle-warm" ]; then
      flutter build apk --debug --target="integration_test/$1" > "$LOGS/build.log" 2>&1 && touch "$LOGS/.gradle-warm"
    fi
    # A starved emulator (Gradle and QEMU compete for memory) can die while the app builds: restart it once.
    for attempt in 1 2; do
      bash "$ROOT/scripts/emulator-start.sh" > /dev/null || exit 1
      adb uninstall com.dorocam.app > /dev/null 2>&1
      (
        for _ in $(seq 1 240); do
          if adb shell pm list packages 2> /dev/null | grep -q com.dorocam.app; then
            adb shell pm grant com.dorocam.app android.permission.CAMERA
            adb shell pm grant com.dorocam.app android.permission.RECORD_AUDIO
            break
          fi
          sleep 1
        done
      ) > /dev/null 2>&1 &
      granter=$!
      flutter test "integration_test/$1" -d emulator-5554 \
        --dart-define=API_URL="http://10.0.2.2:${DEVICE_PORT}" \
        --dart-define=E2E_EMAIL="$EMAIL" --dart-define=E2E_PASSWORD="$PASSWORD" 2>&1 | tee "$LOGS/$2.log"
      code="${PIPESTATUS[0]}"
      kill "$granter" 2> /dev/null
      if [ "$code" -eq 0 ] || ! grep -q "Unable to start the app on the device" "$LOGS/$2.log"; then exit "$code"; fi
      echo "device went away (attempt $attempt); restarting the emulator"
      adb emu kill > /dev/null 2>&1; sleep 5
    done
    exit 1
  )
}

if [ -z "${FULLSTACK_SKIP_MOBILE:-}" ]; then
  echo "== android app on the emulator: capture, sign up, back up"
  run_device_test fullstack_test.dart mobile || status=1
  adb logcat -d -s flutter 2> /dev/null | tail -200 > "$LOGS/logcat.log" || true
else
  echo "== android app skipped (FULLSTACK_SKIP_MOBILE)"
fi

if [ -z "${FULLSTACK_SKIP_WEB:-}" ] && [ "$status" -eq 0 ]; then
  echo "== web dashboard"
  VITE_API_URL="http://127.0.0.1:${WEB_API_PORT}" pnpm --filter @doro/web build > "$LOGS/web-build.log" 2>&1 || { cat "$LOGS/web-build.log"; exit 1; }
  (cd apps/web && exec pnpm preview --host 127.0.0.1 --port "${WEB_PORT}" --strictPort) > "$LOGS/web.log" 2>&1 &
  pids+=($!)
  wait_for "http://127.0.0.1:${WEB_PORT}/" 30 || exit 1
  FULLSTACK_API="http://127.0.0.1:${WEB_API_PORT}" FULLSTACK_WEB="http://127.0.0.1:${WEB_PORT}" \
    FULLSTACK_EMAIL="$EMAIL" FULLSTACK_PASSWORD="$PASSWORD" \
    pnpm --filter @doro/web test:e2e:fullstack || status=1
fi

if [ -z "${FULLSTACK_SKIP_MOBILE:-}" ] && [ "$status" -eq 0 ]; then
  echo "== android app on a fresh install: sign in and get everything back"
  run_device_test fullstack_restore_test.dart mobile-restore || status=1
  adb logcat -d -s flutter 2> /dev/null | tail -200 > "$LOGS/logcat-restore.log" || true
fi

echo "== done (status ${status}); logs in $LOGS"
exit "$status"
