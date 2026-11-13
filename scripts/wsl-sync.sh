#!/usr/bin/env bash
# Run inside WSL. Mirrors the Windows working tree into ~/doro-cam (ext4) so installs and tests are fast.
# node_modules, build outputs and .git are never copied; WSL builds its own.
set -euo pipefail
SRC="${DORO_WIN_TREE:-/mnt/c/Users/yying/dev/scratch/Doro Cam/Doro Cam}"
DST="${DORO_WSL_TREE:-$HOME/doro-cam}"
mkdir -p "$DST"
rsync -a --delete \
  --exclude '.git' --exclude 'node_modules' --exclude '.dart_tool' --exclude 'build' \
  --exclude 'coverage' --exclude 'dist' --exclude '.gradle' --exclude 'playwright-report' \
  --exclude 'test-results' --exclude '.env' --exclude 'Pods' \
  "$SRC/" "$DST/"
find "$DST" -path '*/node_modules' -prune -o -type f \( -name '*.sh' -o -name '*.ts' -o -name '*.dart' \) -print0 | xargs -0 sed -i 's/\r$//' 2>/dev/null || true
echo "synced to $DST"
