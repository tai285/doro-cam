#!/usr/bin/env bash
# Run inside WSL: mirror the Windows tree to ~/doro-cam, run a command there, then copy dependency
# manifests and the lockfile back so `pnpm add` in WSL is reflected in the Windows (committed) tree.
#   wsl -e bash "/mnt/c/Users/yying/dev/scratch/Doro Cam/Doro Cam/scripts/wsl-run.sh" 'pnpm --filter @doro/api test'
set -uo pipefail
WIN="${DORO_WIN_TREE:-/mnt/c/Users/yying/dev/scratch/Doro Cam/Doro Cam}"
WSL_TREE="${DORO_WSL_TREE:-$HOME/doro-cam}"
# shellcheck disable=SC1091
source "$HOME/.doro-env" 2>/dev/null || true
export DORO_WIN_TREE="$WIN" DORO_WSL_TREE="$WSL_TREE"
tr -d '\r' < "$WIN/scripts/wsl-sync.sh" > "$HOME/wsl-sync.sh"
bash "$HOME/wsl-sync.sh" > /dev/null
cd "$WSL_TREE" || exit 1
bash -lc "$1"
rc=$?
for f in pnpm-lock.yaml package.json services/api/package.json apps/web/package.json; do
  if [ -f "$f" ] && ! cmp -s "$f" "$WIN/$f"; then cp "$f" "$WIN/$f"; fi
done
if [ -d services/api/migrations ]; then rsync -a services/api/migrations/ "$WIN/services/api/migrations/"; fi
exit $rc
