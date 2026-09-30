#!/usr/bin/env bash
# Proves the synthetic test camera (ADR-0013) is in debug builds and NOT in release builds, by scanning
# a build artifact for its unique marker string. Both directions are checked in CI so the check cannot
# pass vacuously: if the debug artifact did not contain the marker, scanning release would prove nothing.
#
#   scripts/check-synthetic-camera.sh --expect-present build/app/outputs/flutter-apk/app-debug.apk
#   scripts/check-synthetic-camera.sh --expect-absent  build/app/outputs/flutter-apk/app-release.apk
#   scripts/check-synthetic-camera.sh --expect-absent  build/ios/iphoneos/Runner.app
#
# The artifact can be an APK/AAB/zip (every entry is scanned, decompressed), a directory such as an
# iOS .app bundle (every file is scanned), or a single file. Optional 3rd argument overrides the marker.
# Exit codes: 0 expectation met, 1 expectation violated, 2 usage error or missing artifact.
set -euo pipefail

MARKER_DEFAULT="dorocam.synthetic-camera.v1"
PYTHON="${PYTHON:-python3}"

usage() {
  echo "usage: $0 --expect-present|--expect-absent <apk|aab|zip|dir|file> [marker]" >&2
  exit 2
}

[ $# -ge 2 ] || usage
MODE="$1"
ARTIFACT="$2"
MARKER="${3:-$MARKER_DEFAULT}"
case "$MODE" in
  --expect-present | --expect-absent) ;;
  *) usage ;;
esac

if [ ! -e "$ARTIFACT" ]; then
  echo "error: artifact not found: $ARTIFACT" >&2
  exit 2
fi

FOUND_IN="$(MARKER="$MARKER" ARTIFACT="$ARTIFACT" "$PYTHON" - <<'PY'
import os
import sys
import zipfile

marker = os.environ["MARKER"].encode("utf-8")
artifact = os.environ["ARTIFACT"]
hits = []


def scan(label, data):
    if marker in data:
        hits.append(label)


if os.path.isdir(artifact):
    for root, _dirs, files in os.walk(artifact):
        for name in files:
            path = os.path.join(root, name)
            try:
                with open(path, "rb") as handle:
                    scan(os.path.relpath(path, artifact), handle.read())
            except OSError:
                pass
elif zipfile.is_zipfile(artifact):
    with zipfile.ZipFile(artifact) as archive:
        for info in archive.infolist():
            if info.is_dir():
                continue
            scan(info.filename, archive.read(info))
else:
    with open(artifact, "rb") as handle:
        scan(os.path.basename(artifact), handle.read())

print("\n".join(hits))
PY
)"

if [ "$MODE" = "--expect-present" ]; then
  if [ -n "$FOUND_IN" ]; then
    echo "ok: the synthetic camera marker is present in $ARTIFACT (as expected for a debug build)" >&2
    exit 0
  fi
  echo "error: the synthetic camera marker '$MARKER' was NOT found in $ARTIFACT, but this build must contain it" >&2
  exit 1
fi

if [ -z "$FOUND_IN" ]; then
  echo "ok: no synthetic camera marker in $ARTIFACT (as expected for a release build)" >&2
  exit 0
fi
echo "error: the synthetic camera marker '$MARKER' leaked into $ARTIFACT, found in:" >&2
echo "$FOUND_IN" | sed 's/^/  - /' >&2
exit 1
