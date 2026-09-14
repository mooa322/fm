#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#  DAHOOM · توليد/تدوير مفتاح تشفير الحمولة (menu.enc)
#
#  يولّد مفتاحًا عشوائيًا جديدًا ويحفظه محليًا بـ tools/.payload_key
#  (ملف لا يُرفع للمستودع العام — راجع .gitignore). المفتاح نفسه
#  لازم يكون محفوظًا أيضًا بصيغة "معكوس + base64" داخل ملف
#  files/syscache بمستودع instalasi، لأن install.sh وsrc/menu.sh
#  يجلبانه منه وقت التشغيل الفعلي عند العميل (دالة _fm_pkey).
#
#  الاستخدام:
#    ./tools/gen-payload-key.sh            → يولّد مفتاحًا جديدًا
#                                             (يرفض الكتابة فوق موجود)
#    ./tools/gen-payload-key.sh --force     → يستبدل المفتاح الحالي
#    ./tools/gen-payload-key.sh --show      → يطبع فقط قيمة syscache
#                                             للمفتاح المحلي الحالي
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail
cd "$(dirname "$0")/.."
. tools/_fmcrypto.sh

if [[ "${1:-}" == "--show" ]]; then
    KEY="$(_fm_payload_key)"
    echo "المفتاح المحلي الحالي:  $KEY"
    echo "قيمة files/syscache المطابقة له:"
    echo "$(_fm_payload_key_to_syscache "$KEY")"
    exit 0
fi

if [[ -f "$FM_PAYLOAD_KEY_FILE" && "${1:-}" != "--force" ]]; then
    echo "[ERROR] فيه مفتاح موجود أصلًا بـ $FM_PAYLOAD_KEY_FILE" >&2
    echo "        استخدم --force إذا تبي تستبدله (يتطلب إعادة تشفير menu.enc" >&2
    echo "        وتحديث files/syscache بعدها، وإلا العملاء ما راح يقدرون يشغّلون التطبيق)." >&2
    exit 1
fi

NEW_KEY="$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 42)"
printf '%s\n' "$NEW_KEY" > "$FM_PAYLOAD_KEY_FILE"
chmod 600 "$FM_PAYLOAD_KEY_FILE"

SYSCACHE_VALUE="$(_fm_payload_key_to_syscache "$NEW_KEY")"

echo "✅ مفتاح جديد تولّد وتخزّن بـ $FM_PAYLOAD_KEY_FILE"
echo
echo "الخطوات الباقية عشان يشتغل مع العملاء فعليًا:"
echo
echo "1) شفّر الحمولة بالمفتاح الجديد:"
echo "     ./tools/build-payload.sh"
echo
echo "2) حدّث ملف files/syscache بمستودع instalasi بهذي القيمة بالضبط"
echo "   (استبدل محتواه بالكامل بها، بدون أي مسافات أو أسطر إضافية):"
echo
echo "     $SYSCACHE_VALUE"
echo
echo "3) commit + push لملف files/syscache على فرع main بمستودع instalasi."
echo
echo "   ⚠️  إلى أن تسوي الخطوتين 2 و3، أي menu.enc جديد تبنيه بالمفتاح"
echo "       الجديد ما راح يقدر عملاء install.sh يفكّون تشفيره — لأنهم"
echo "       بيجيبون المفتاح القديم لسا من instalasi."
