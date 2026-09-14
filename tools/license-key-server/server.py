#!/usr/bin/env python3
"""
DAHOOM · سيرفر مفتاح الترخيص (fm-key-server)
═══════════════════════════════════════════════════════════════════
يتحقق من ترخيص العميل فعليًا — قبل ما يسلّمه مفتاح فك تشفير
menu.enc — بدل الآلية القديمة (قراءة ملف عام من GitHub بلا أي
تحقق، أي شخص يقدر يشتقه). هذا السيرفر يرفض التسليم لأي أحد ما
عنده ترخيص صالح فعليًا، بغض النظر عمّا إذا كان قرأ كود install.sh
أو لا.

يعمل محليًا على 127.0.0.1:PORT، خلف Caddy (أو أي reverse proxy)
يوفّر HTTPS الحقيقي على الدومين العام. راجع Caddyfile وDEPLOY.md
بنفس المجلد.

الإعداد المطلوب قبل التشغيل:
  - ملف payload.key بجانب هذا السكربت: سطر واحد فيه مفتاح التشفير
    الفعلي (نفس القيمة اللي بنيت فيها menu.enc عبر
    tools/build-payload.sh). لا يُرفع هذا الملف لأي مستودع أبدًا.

مصدر الحقيقة للتراخيص: يُجلب حيًا من GitHub (نفس ملف reg.json اللي
تديره tools/license-panel.sh) — أي تعديل/إلغاء ترخيص من هناك ينعكس
فورًا هنا، بلا أي إعادة تشغيل أو إعداد إضافي.

التشغيل المباشر (للاختبار فقط؛ للإنتاج استخدم systemd — راجع
fm-key-server.service):
    python3 server.py [--port 8420]
"""
import json
import os
import re
import sys
import time
import threading
import urllib.request
from collections import defaultdict, deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
KEY_FILE = os.path.join(HERE, "payload.key")
LOG_FILE = os.path.join(HERE, "access.log")

# نفس مصدر reg.json اللي يقرأه install.sh وsrc/menu.sh حاليًا —
# Contents API أولًا (يدعم رؤوس raw)، وraw.githubusercontent.com
# احتياطًا إذا الأول محظور/بطيء على شبكة معيّنة.
LICENSES_URL = "https://api.github.com/repos/mooa322/instalasi/contents/config/reg.json?ref=main"
LICENSES_URL_FALLBACK = "https://raw.githubusercontent.com/mooa322/instalasi/main/config/reg.json"

_ID_RE = re.compile(r"^[A-Za-z0-9_-]+$")

RATE_LIMIT_WINDOW = 60   # ثانية
RATE_LIMIT_MAX = 10      # طلبات لكل IP خلال النافذة أعلاه

_rate_lock = threading.Lock()
_rate_buckets = defaultdict(deque)

_log_lock = threading.Lock()


def _log(event: dict) -> None:
    event = dict(event)
    event["ts"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    line = json.dumps(event, ensure_ascii=False)
    with _log_lock:
        try:
            with open(LOG_FILE, "a", encoding="utf-8") as f:
                f.write(line + "\n")
        except OSError:
            pass
    print(line, flush=True)


def _rate_limited(ip: str) -> bool:
    now = time.time()
    with _rate_lock:
        bucket = _rate_buckets[ip]
        while bucket and now - bucket[0] > RATE_LIMIT_WINDOW:
            bucket.popleft()
        if len(bucket) >= RATE_LIMIT_MAX:
            return True
        bucket.append(now)
        return False


def _fetch_licenses() -> dict:
    req = urllib.request.Request(
        LICENSES_URL, headers={"Accept": "application/vnd.github.raw"}
    )
    try:
        with urllib.request.urlopen(req, timeout=8) as r:
            return json.loads(r.read().decode("utf-8"))
    except Exception:
        pass
    try:
        with urllib.request.urlopen(LICENSES_URL_FALLBACK, timeout=8) as r:
            return json.loads(r.read().decode("utf-8"))
    except Exception:
        return {}


def _payload_key() -> str:
    with open(KEY_FILE, encoding="utf-8") as f:
        return f.read().strip()


def _validate(license_id: str, client_ip: str):
    """يرجّع (ok: bool, reason: str). reason دايمًا موجود، حتى مع ok=True ('ok')."""
    if not license_id or not _ID_RE.match(license_id):
        return False, "invalid_format"
    licenses = _fetch_licenses()
    if not licenses:
        # فشل الوصول لسجل التراخيص نفسه — نرفض بدل ما نسمح افتراضيًا
        # (خلافًا لفحص install.sh القديم اللي كان "يفشل مفتوحًا")، لأن
        # هذا هو الحارس الحقيقي الوحيد الآن، لا مجرد طبقة UX إضافية.
        return False, "registry_unreachable"
    block = licenses.get(license_id)
    if block is None:
        return False, "not_found"
    if block.get("revoked"):
        return False, "revoked"
    bound_ip = block.get("ip")
    if bound_ip and bound_ip != client_ip:
        return False, "ip_mismatch"
    return True, "ok"


class Handler(BaseHTTPRequestHandler):
    server_version = "FMKeyServer/1.0"
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):  # noqa: A002 - نستخدم _log() بدل سجل الأساس
        pass

    def _client_ip(self) -> str:
        # Caddy (reverse_proxy) يضيف هذي الترويسة تلقائيًا بعنوان العميل
        # الحقيقي؛ لو ما وصلت (اتصال مباشر بدون بروكسي) نرجع لعنوان
        # الاتصال الخام.
        fwd = self.headers.get("X-Forwarded-For", "")
        if fwd:
            return fwd.split(",")[0].strip()
        return self.client_address[0]

    def _send_json(self, status: int, obj: dict) -> None:
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_GET(self):
        if self.path == "/v1/health":
            return self._send_json(200, {"status": "ok"})
        self._send_json(404, {"error": "not_found"})

    def do_POST(self):
        if self.path != "/v1/key":
            return self._send_json(404, {"error": "not_found"})

        ip = self._client_ip()
        if _rate_limited(ip):
            _log({"event": "rate_limited", "ip": ip})
            return self._send_json(429, {"error": "rate_limited"})

        try:
            length = int(self.headers.get("Content-Length", "0") or "0")
            raw = self.rfile.read(length) if length else b""
            body = json.loads(raw or b"{}")
        except Exception:
            return self._send_json(400, {"error": "bad_request"})

        license_id = str(body.get("license", "")).strip()
        ok, reason = _validate(license_id, ip)
        _log({"event": "key_request", "license": license_id, "ip": ip, "ok": ok, "reason": reason})

        if not ok:
            return self._send_json(403, {"error": reason})

        try:
            key = _payload_key()
        except OSError:
            _log({"event": "server_misconfigured", "detail": "payload.key missing"})
            return self._send_json(500, {"error": "server_misconfigured"})

        self._send_json(200, {"key": key})


def main() -> None:
    port = 8420
    args = sys.argv[1:]
    for i, a in enumerate(args):
        if a == "--port" and i + 1 < len(args):
            port = int(args[i + 1])

    if not os.path.exists(KEY_FILE):
        print(f"[FATAL] {KEY_FILE} غير موجود — أنشئه أولًا بمفتاح التشفير قبل التشغيل.", file=sys.stderr)
        sys.exit(1)

    httpd = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"fm-key-server listening on 127.0.0.1:{port}", flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
