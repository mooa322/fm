#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#  DAHOOM · Build the encrypted payload (menu.enc)
#  Encrypts the current src/ and writes menu.enc into the repo root.
#  Run after editing anything in src/.
#
#  Usage:  ./tools/build-payload.sh
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail
cd "$(dirname "$0")/.."
. tools/_fmcrypto.sh

# Must match FM_PKEY in install.sh, src/menu.sh and src/update_panel.sh —
# it's embedded there since there's no live server to hold it secretly.
PAYLOAD_KEY="5YgZ9dsnTEKkBgehniA2lYGEuV90wZ2LKmu5okur4"

command -v openssl >/dev/null || { echo "[ERROR] openssl required"; exit 1; }
for f in "${FM_PAYLOAD[@]}"; do [ -f "$FM_SRC_DIR/$f" ] || { echo "[ERROR] missing $FM_SRC_DIR/$f"; exit 1; }; done

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
tar -czf "$TMP/bundle.tgz" -C "$FM_SRC_DIR" "${FM_PAYLOAD[@]}"
# shellcheck disable=SC2086
openssl enc $FM_CIPHER -in "$TMP/bundle.tgz" -out menu.enc -pass "pass:${PAYLOAD_KEY}"

echo "✅ menu.enc built ($(du -h menu.enc | cut -f1))."
echo "   publish it:  git add menu.enc && git commit -m 'release' && git push"
