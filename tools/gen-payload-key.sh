#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#  DAHOOM · توليد/تدوير مفتاح تشفير الحمولة (menu.enc)
#
#  يولّد مفتاحًا عشوائيًا جديدًا ويحفظه محليًا بـ tools/.payload_key
#  (ملف لا يُرفع للمستودع العام — راجع .gitignore). نفس هذي القيمة
#  لازم تُنسخ أيضًا لملف payload.key على سيرفر الترخيص الحقيقي
#  (راجع tools/license-key-server/DEPLOY.md) — هو من يتحقق من
#  الترخيص فعليًا قبل ما يسلّم المفتاح لـinstall.sh/src/menu.sh وقت
#  التشغيل عند العميل (دالة _fm_pkey)، بدل الاعتماد على ملف عام بلا
#  أي تحقق كما كان سابقًا.
#
#  الاستخدام:
#    ./tools/gen-payload-key.sh            → يولّد مفتاحًا جديدًا
#                                             (يرفض الكتابة فوق موجود)
#    ./tools/gen-payload-key.sh --force     → يستبدل المفتاح الحالي
#    ./tools/gen-payload-key.sh --show      → يطبع فقط المفتاح المحلي
#                                             الحالي (بلا توليد جديد)
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail
cd "$(dirname "$0")/.."
. tools/_fmcrypto.sh

if [[ "${1:-}" == "--show" ]]; then
    echo "المفتاح المحلي الحالي:  $(_fm_payload_key)"
    exit 0
fi

if [[ -f "$FM_PAYLOAD_KEY_FILE" && "${1:-}" != "--force" ]]; then
    echo "[ERROR] فيه مفتاح موجود أصلًا بـ $FM_PAYLOAD_KEY_FILE" >&2
    echo "        استخدم --force إذا تبي تستبدله (يتطلب إعادة تشفير menu.enc" >&2
    echo "        وتحديث payload.key على سيرفر الترخيص بعدها، وإلا العملاء" >&2
    echo "        ما راح يقدرون يشغّلون التطبيق)." >&2
    exit 1
fi

NEW_KEY="$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 42)"
printf '%s\n' "$NEW_KEY" > "$FM_PAYLOAD_KEY_FILE"
chmod 600 "$FM_PAYLOAD_KEY_FILE"

echo "✅ مفتاح جديد تولّد وتخزّن بـ $FM_PAYLOAD_KEY_FILE"
echo
echo "الخطوات الباقية عشان يشتغل مع العملاء فعليًا:"
echo
echo "1) شفّر الحمولة بالمفتاح الجديد:"
echo "     ./tools/build-payload.sh"
echo
echo "2) حدّث /opt/fm-key-server/payload.key على سيرفر الترخيص بهذي"
echo "   القيمة بالضبط (سطر واحد، بلا مسافات زائدة):"
echo
echo "     $NEW_KEY"
echo
echo "3) أعد تشغيل الخدمة هناك: sudo systemctl restart fm-key-server"
echo
echo "   ⚠️  إلى أن تسوي الخطوتين 2 و3، أي menu.enc جديد تبنيه بالمفتاح"
echo "       الجديد ما راح يقدر عملاء install.sh يفكّون تشفيره — لأن"
echo "       سيرفر الترخيص بيرجّع المفتاح القديم لسا."
