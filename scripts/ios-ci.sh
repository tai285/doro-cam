#!/usr/bin/env bash
# Runs the iOS workflow on cloud macOS for a branch and waits for the result (ADR-0013).
#   scripts/ios-ci.sh                 # current branch
#   scripts/ios-ci.sh feature/x       # named branch
# On failure, prints the failing step logs. Requires the GitHub CLI (`gh`), logged in.
set -euo pipefail

REF="${1:-$(git rev-parse --abbrev-ref HEAD)}"
GH="${GH:-gh}"
command -v "$GH" >/dev/null 2>&1 || GH="/c/Program Files/GitHub CLI/gh.exe"

"$GH" workflow run ios.yml --ref "$REF"
echo "Triggered ios.yml on $REF; waiting for the run to appear..."
sleep 8
RUN_ID="$("$GH" run list --workflow ios.yml --branch "$REF" --limit 1 --json databaseId --jq '.[0].databaseId')"
echo "Run $RUN_ID"
if "$GH" run watch "$RUN_ID" --exit-status; then
  echo "iOS CI passed."
else
  echo "iOS CI failed. Failing logs:" >&2
  "$GH" run view "$RUN_ID" --log-failed >&2 || true
  exit 1
fi
