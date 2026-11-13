#!/usr/bin/env bash
# One-time setup of the bundled Garage: cluster layout, bucket and the API's access key. Safe to re-run.
set -euo pipefail
cd "$(dirname "$0")"
set -a; source .env; set +a
g() { docker compose --profile storage exec -T garage /garage "$@"; }
NODE_ID="$(g status | awk '/^[0-9a-f]{16}/ {print $1; exit}')"
g status | grep -q "NO ROLE ASSIGNED" && { g layout assign -z dc1 -c 1G "$NODE_ID"; g layout apply --version 1; } || true
g bucket info "${S3_BUCKET:-doro-media}" >/dev/null 2>&1 || g bucket create "${S3_BUCKET:-doro-media}"
g key info "$S3_ACCESS_KEY_ID" >/dev/null 2>&1 || g key import --yes -n doro "$S3_ACCESS_KEY_ID" "$S3_SECRET_ACCESS_KEY"
g bucket allow --read --write --owner "${S3_BUCKET:-doro-media}" --key "$S3_ACCESS_KEY_ID"
echo "Garage ready: bucket ${S3_BUCKET:-doro-media}"
