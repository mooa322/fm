#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#  DAHOOM · تصحيح haproxy لتمرير طلبات سيرفر الترخيص صح + عنوان IP
#  الحقيقي للعميل (PROXY protocol)
#
#  ينطبق فقط على VPS يستضيف سيرفر الترخيص (fm-key-server) وفي نفس
#  الوقت يشغّل منتج DAHOOM/firewallfalcon نفسه (haproxy TCP-mode
#  multiplexer لتقنية SSH/V2Ray على منفذ الويب) — وهو غالبًا نفس
#  سيرفر البائع. أغلب عملائك العاديين لا يحتاجون هذا السكربت إطلاقًا
#  (هم عملاء يتصلون بسيرفر الترخيص من الخارج، لا يستضيفونه).
#
#  ⚠️ مهم جدًا: قائمة "Connection Modes" بالبانل على هذا الـVPS
#  (أي استدعاء لـ write_haproxy_edge_config) تعيد توليد
#  /etc/haproxy/haproxy.cfg من الصفر وتمسح هذا التصحيح. أعد تشغيل
#  هذا السكربت بعد أي استخدام لتلك القائمة.
#
#  آمن لإعادة التشغيل أي وقت (idempotent) — لا يكرر الإضافة لو
#  موجودة أصلًا.
#
#  الاستخدام:
#    sudo ./patch-haproxy-sni.sh [الدومين] [منفذ nginx الداخلي]
#    (افتراضيًا: de.dahoom.de5.net و8444)
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] شغّله بصلاحية root: sudo $0" >&2
    exit 1
fi

DOMAIN="${1:-de.dahoom.de5.net}"
NGINX_PORT="${2:-8444}"
CFG="/etc/haproxy/haproxy.cfg"

[ -f "$CFG" ] || { echo "[ERROR] $CFG غير موجود"; exit 1; }

cp "$CFG" "${CFG}.bak-$(date +%s)"

python3 - "$DOMAIN" "$NGINX_PORT" "$CFG" << 'PYEOF'
import re
import sys

domain, port, path = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f:
    content = f.read()

acl_line = f"    acl is_license_domain req.ssl_sni -i {domain}\n"
use_line = f"    use_backend license_server_tls if is_license_domain\n"
backend_block = (
    f"\nbackend license_server_tls\n"
    f"    mode tcp\n"
    f"    server license_nginx 127.0.0.1:{port} send-proxy\n"
)

changed = False

if acl_line not in content:
    anchor1 = "    acl has_web_alpn req.ssl_alpn -m sub h2 http/1.1\n"
    n1 = content.count(anchor1)
    if n1 != 1:
        print(f"[STOP] لم ألقَ سطر acl has_web_alpn مرة واحدة بالضبط (وجدت {n1}) — "
              f"الملف مختلف عن المتوقَّع، لم أعدّل شي.", file=sys.stderr)
        sys.exit(1)
    content = content.replace(anchor1, anchor1 + acl_line)
    changed = True

if use_line not in content:
    anchor2 = "    use_backend nginx_tls if is_tls has_web_alpn\n"
    n2 = content.count(anchor2)
    if n2 != 1:
        print(f"[STOP] لم ألقَ سطر use_backend nginx_tls مرة واحدة بالضبط (وجدت {n2}) — "
              f"لم أعدّل شي.", file=sys.stderr)
        sys.exit(1)
    content = content.replace(anchor2, use_line + anchor2)
    changed = True

if not re.search(r'^backend license_server_tls$', content, re.MULTILINE):
    content = content.rstrip("\n") + "\n" + backend_block
    changed = True

if changed:
    with open(path, "w") as f:
        f.write(content)
    print("✅ تم تطبيق/تأكيد التصحيح")
else:
    print("ℹ️ التصحيح موجود أصلًا بالكامل، ما غيّرت شي")
PYEOF

echo "── التحقق من الصياغة ──"
haproxy -c -f "$CFG"
echo "── إعادة التحميل (بلا انقطاع) ──"
systemctl reload haproxy
echo "✅ تم — تأكد الآن إن nginx يستمع على 127.0.0.1:${NGINX_PORT} بـproxy_protocol (راجع nginx-behind-haproxy.conf.example)"
