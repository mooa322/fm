# Shared crypto parameters for DAHOOM licensing.
# Keep these identical in the builder tools and in the client loader.
FM_CIPHER="-aes-256-cbc -pbkdf2 -iter 200000 -salt"
# Where the plaintext master source lives (private, gitignored, never pushed).
FM_SRC_DIR="src"
# Files inside FM_SRC_DIR that make up the protected payload (the seller's IP).
FM_PAYLOAD=(menu.sh ssh update_panel.sh npvt_edit.py npvs_edit.py nm_edit.py ziv_edit.py v2box_edit.py xui_ctl.py panel/panel.py panel/index.html panel/reseller.html panel/v2ray_manager.py panel/bandwidth_link.py panel/connlog.py)

# ── مفتاح التشفير: لا يُكتب هنا ولا في أي ملف يُرفع للمستودع العام ──
# يُقرأ من tools/.payload_key (محلي، Git-ignored). نفس القيمة يجب أن
# تكون منسوخة أيضًا لملف payload.key على سيرفر الترخيص الحقيقي
# (tools/license-key-server/) — هو من يتحقق من الترخيص فعليًا قبل ما
# يسلّم هذا المفتاح لـinstall.sh/src/menu.sh وقت التشغيل عند العميل،
# عبر _fm_pkey(). راجع tools/license-key-server/DEPLOY.md للنشر.
FM_PAYLOAD_KEY_FILE="tools/.payload_key"

# يطبع المفتاح الحالي، أو يفشل برسالة واضحة إذا ما كان موجودًا بعد.
_fm_payload_key() {
    if [ ! -f "$FM_PAYLOAD_KEY_FILE" ]; then
        echo "[ERROR] ما فيه مفتاح تشفير محلي بعد: $FM_PAYLOAD_KEY_FILE" >&2
        echo "        شغّل أول مرة:  ./tools/gen-payload-key.sh" >&2
        return 1
    fi
    tr -d '[:space:]' < "$FM_PAYLOAD_KEY_FILE"
}
