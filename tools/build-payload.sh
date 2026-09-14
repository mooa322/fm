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

# المفتاح يُقرأ من ملف محلي غير مرفوع للمستودع العام — راجع _fmcrypto.sh.
# أول مرة؟ شغّل ./tools/gen-payload-key.sh لتوليد مفتاح وحفظه محليًا.
PAYLOAD_KEY="$(_fm_payload_key)" || exit 1

command -v openssl >/dev/null || { echo "[ERROR] openssl required"; exit 1; }
for f in "${FM_PAYLOAD[@]}"; do [ -f "$FM_SRC_DIR/$f" ] || { echo "[ERROR] missing $FM_SRC_DIR/$f"; exit 1; }; done

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
tar -czf "$TMP/bundle.tgz" -C "$FM_SRC_DIR" "${FM_PAYLOAD[@]}"
# shellcheck disable=SC2086
openssl enc $FM_CIPHER -in "$TMP/bundle.tgz" -out menu.enc -pass "pass:${PAYLOAD_KEY}"

echo "✅ menu.enc built ($(du -h menu.enc | cut -f1))."
echo "   publish it:  git add menu.enc && git commit -m 'release' && git push"
