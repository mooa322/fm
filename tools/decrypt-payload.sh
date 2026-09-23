#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#  DAHOOM · فك تشفير الحمولة (menu.enc) للفحص أو الاسترجاع
#  عكس تمامًا لـ build-payload.sh — بنفس المفتاح المحلي.
#
#  الاستخدام:
#    ./tools/decrypt-payload.sh                 → يفك menu.enc إلى
#                                                   ./menu_decrypted/
#    ./tools/decrypt-payload.sh <مجلد الوجهة>    → يفك إلى مجلد تحدده
#    ./tools/decrypt-payload.sh --into-src       → يفك مباشرة فوق src/
#                                                   (يستبدل كل ملف من
#                                                   ملفات الحمولة هناك —
#                                                   استخدمه فقط إذا كنت
#                                                   قاصد استرجاع src/
#                                                   من menu.enc نفسه)
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail
cd "$(dirname "$0")/.."
. tools/_fmcrypto.sh

[ -f menu.enc ] || { echo "[ERROR] menu.enc غير موجود بجذر المشروع"; exit 1; }
command -v openssl >/dev/null || { echo "[ERROR] openssl required"; exit 1; }

PAYLOAD_KEY="$(_fm_payload_key)" || exit 1

if [[ "${1:-}" == "--into-src" ]]; then
    OUT="$FM_SRC_DIR"
    mkdir -p "$OUT"
else
    OUT="${1:-./menu_decrypted}"
    if [[ -e "$OUT" ]]; then
        echo "[ERROR] المجلد $OUT موجود أصلًا — احذفه أو اختر اسمًا آخر عشان ما نستبدل شي بالغلط." >&2
        exit 1
    fi
    mkdir -p "$OUT"
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
# shellcheck disable=SC2086
if ! openssl enc -d $FM_CIPHER -in menu.enc -out "$TMP/bundle.tgz" -pass "pass:${PAYLOAD_KEY}" 2>/dev/null; then
    echo "[ERROR] فشل فك التشفير — المفتاح المحلي (tools/.payload_key) لا يطابق المفتاح اللي شُفّر فيه menu.enc." >&2
    exit 1
fi
tar -xzf "$TMP/bundle.tgz" -C "$OUT"

echo "✅ تم فك التشفير إلى: $OUT"
echo "   الملفات:"
find "$OUT" -type f | sed 's/^/     /'
