#!/usr/bin/env bash
# Runs a command with a per-attempt timeout and retries it when it fails or stalls.
#
#   scripts/run-with-retry.sh [--attempts N] [--timeout SECONDS] -- command [args...]
#
# Why: `flutter test integration_test` on the iOS Simulator sometimes stalls forever at "Waiting for VM
# Service port to be available..." (the app starts, but the tool never sees its connection URL). A stalled
# attempt is killed after the timeout and retried instead of burning the whole job timeout.
#
# Defaults: 3 attempts, 600 s each. macOS has no `timeout` command, so the timeout is implemented here.
# Exit codes: 0 success, the command's own code after the last failed attempt, 124 when the last
# attempt timed out, 2 for usage errors.
set -uo pipefail

ATTEMPTS=3
TIMEOUT=600

usage() {
  echo "usage: $0 [--attempts N] [--timeout SECONDS] -- command [args...]" >&2
  exit 2
}

is_positive_int() {
  [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ]
}

while [ $# -gt 0 ]; do
  case "$1" in
    --attempts)
      [ $# -ge 2 ] || usage
      is_positive_int "$2" || usage
      ATTEMPTS="$2"
      shift 2
      ;;
    --timeout)
      [ $# -ge 2 ] || usage
      is_positive_int "$2" || usage
      TIMEOUT="$2"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *)
      usage
      ;;
  esac
done
[ $# -ge 1 ] || usage

# Terminates a process and everything it started (children first), so a stalled tool cannot leave
# simulators or helper processes running into the next attempt.
kill_tree() {
  local pid="$1" child
  if command -v pgrep >/dev/null 2>&1; then
    for child in $(pgrep -P "$pid" 2>/dev/null || true); do
      kill_tree "$child"
    done
  fi
  kill "$pid" 2>/dev/null || true
}

LAST_CODE=1
for ((attempt = 1; attempt <= ATTEMPTS; attempt++)); do
  echo "--- attempt $attempt of $ATTEMPTS (timeout ${TIMEOUT}s): $*" >&2
  "$@" &
  PID=$!

  START=$SECONDS
  TIMED_OUT=0
  while kill -0 "$PID" 2>/dev/null; do
    if [ $((SECONDS - START)) -ge "$TIMEOUT" ]; then
      TIMED_OUT=1
      break
    fi
    sleep 0.2
  done

  if [ "$TIMED_OUT" -eq 1 ]; then
    echo "--- attempt $attempt of $ATTEMPTS timed out after ${TIMEOUT}s; terminating it" >&2
    kill_tree "$PID"
    sleep 0.5
    kill -9 "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
    LAST_CODE=124
    continue
  fi

  wait "$PID"
  LAST_CODE=$?
  if [ "$LAST_CODE" -eq 0 ]; then
    exit 0
  fi
  echo "--- attempt $attempt of $ATTEMPTS failed with exit code $LAST_CODE" >&2
done

echo "--- all $ATTEMPTS attempts failed (last exit code $LAST_CODE)" >&2
exit "$LAST_CODE"
