# نشر سيرفر مفتاح الترخيص (fm-key-server)

خطوات كاملة تنسخها وتشغّلها بالـSSH على الـVPS. مبنية لأوبنتو/دبيان
(apt) — عدّل أوامر التثبيت إذا نظامك مختلف.

**قبل البدء:** وجّه سجل DNS من نوع A لدومينك (مثال يُستخدم أدناه:
`de.dahoom.de5.net`) لعنوان IP هذا الـVPS. تحقق بـ:
`dig +short de.dahoom.de5.net`

## أي إعداد HTTPS أمامي أستخدم؟

هذا السيرفر يحتاج شهادة HTTPS حقيقية أمامه. فيه احتمالان:

- **VPS نظيف** (لا شي يستخدم المنفذين 80/443 بعد) → استخدم **Caddy**
  (القسم أ أدناه) — أبسط، شهادة تلقائية بلا أي إعداد يدوي.
- **VPS مثبّت عليه منتج DAHOOM/firewallfalcon نفسه بالفعل** (الحالة
  الأشيع فعليًا — أي سيرفر تبيع منه تراخيص) → عنده `haproxy` أصلًا
  يملك المنفذين 80/443 لتقنية "SSH على منفذ الويب"، ولازم نستخدم
  **nginx خلفه** على المنافذ الداخلية اللي يتوقعها (القسم ب) — Caddy
  ما يقدر ياخذ 80/443 لأنها مشغولة أصلًا.

للتأكد أي حالة عندك:
```bash
sudo ss -tlnp | grep -E ':80|:443'
```
لو طلعت `haproxy` → اذهب للقسم ب مباشرة.

---

## 1) نسخ الملفات للسيرفر (لكلا الحالتين)

من جهازك (مو من الـVPS)، بمجلد `tools/license-key-server/` بمستودع fm:

```bash
scp server.py fm-key-server.service patch-haproxy-sni.sh root@YOUR_VPS_IP:/tmp/
```
(`patch-haproxy-sni.sh` يُستخدم فقط لو دخلت القسم ب أدناه — انسخه
لجذر الـVPS مثلًا `/opt/fm-key-server/` بالخطوة التالية.)

## 2) إعداد مستخدم مخصّص وملفات الخدمة (على الـVPS)

```bash
sudo useradd --system --no-create-home --shell /usr/sbin/nologin fmkeysrv
sudo mkdir -p /opt/fm-key-server
sudo mv /tmp/server.py /opt/fm-key-server/
sudo mv /tmp/patch-haproxy-sni.sh /opt/fm-key-server/ 2>/dev/null
sudo chmod +x /opt/fm-key-server/patch-haproxy-sni.sh 2>/dev/null
sudo chown -R fmkeysrv:fmkeysrv /opt/fm-key-server
```

## 3) مفتاح التشفير الفعلي

**هذا أهم خطوة** — بدونها السيرفر يرفض يشتغل. القيمة هي نفس محتوى
`tools/.payload_key` عندك محليًا بمستودع fm (نفس المفتاح اللي بُني
فيه `menu.enc` الحالي):

```bash
echo "ضع_المفتاح_هنا_بالضبط" | sudo tee /opt/fm-key-server/payload.key
sudo chown fmkeysrv:fmkeysrv /opt/fm-key-server/payload.key
sudo chmod 600 /opt/fm-key-server/payload.key
```

## 4) تشغيل الخدمة عبر systemd

```bash
sudo mv /tmp/fm-key-server.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now fm-key-server
sudo systemctl status fm-key-server   # لازم "active (running)"
```

تحقق سريع محلي (قبل ما نضيف HTTPS):

```bash
curl -s http://127.0.0.1:8420/v1/health
# → {"status": "ok"}
```

---

## القسم أ) VPS نظيف — Caddy

```bash
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update
sudo apt install -y caddy
```

انسخ `Caddyfile` من نفس المجلد لـ`/etc/caddy/Caddyfile` (عدّل
الدومين بداخله إذا مختلف)، ثم:
```bash
sudo systemctl reload caddy
```
Caddy يصدر شهادة Let's Encrypt تلقائيًا أول ما يستقبل طلب — لا حاجة
لأي إعداد شهادات يدوي. تأكد إن 80 و443 مفتوحين بالجدار الناري إن وجد:
```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```
بعدها اذهب مباشرة لقسم "الاختبار النهائي" بالأسفل.

---

## القسم ب) VPS عنده haproxy أصلًا (منتج DAHOOM مثبّت) — nginx خلفه

هذا هو الوضع **الأشيع فعليًا** (مُختبر ومؤكَّد يعمل بالكامل). `haproxy`
يملك `*:80` و`*:443` ويفحص أول بايتات كل اتصال (SSH مقابل HTTP/TLS
عادي). يمرّر HTTP الصافي لـ`127.0.0.1:8880`، وTLS العادي (بقية
النطاقات) لـ`127.0.0.1:8443` — راجع `/etc/haproxy/haproxy.cfg`
(backends `nginx_cleartext` وnginx_tls`). دومينك تحديدًا يحتاج قاعدة
توجيه إضافية بـhaproxy (بالـSNI) + PROXY protocol، وإلا عنوان IP
العميل الحقيقي يضيع بالكامل (كل الطلبات تبدو من 127.0.0.1 لسيرفر
الترخيص — يكسر أي ترخيص مربوط بـIP).

**ب-1) مجلد تحدي ACME + vhost مؤقت على 8880:**
```bash
sudo mkdir -p /var/www/de-dahoom/.well-known/acme-challenge
sudo tee /etc/nginx/sites-available/de.dahoom.de5.net > /dev/null << 'EOF'
server {
    listen 127.0.0.1:8880;
    server_name de.dahoom.de5.net;

    location /.well-known/acme-challenge/ { root /var/www/de-dahoom; }
    location / { return 200 "ok\n"; }
}
EOF
sudo ln -sf /etc/nginx/sites-available/de.dahoom.de5.net /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

**ب-2) اطلب الشهادة بوضع webroot** (بلا ما يلمس certbot إعداد nginx تلقائيًا —
مهم، لأن الإضافة الافتراضية `--nginx` تضيف `listen 443` اللي يتعارض مع haproxy):
```bash
sudo apt install -y certbot
sudo certbot certonly --webroot -w /var/www/de-dahoom -d de.dahoom.de5.net
```

**ب-3) استبدل الإعداد بالصيغة النهائية** — 8880 يعيد التوجيه، **8444**
(لا 8443 — هذا منفذ مخصَّص لدومينك وحده، منفصل تمامًا عن `nginx_tls`
اللي يخدم بقية نطاقاتك، حتى ما نتعارض معها) بـPROXY protocol لحفظ
عنوان IP الحقيقي:
```bash
sudo tee /etc/nginx/sites-available/de.dahoom.de5.net > /dev/null << 'EOF'
server {
    listen 127.0.0.1:8880;
    server_name de.dahoom.de5.net;
    location /.well-known/acme-challenge/ { root /var/www/de-dahoom; }
    location / { return 301 https://$host$request_uri; }
}
server {
    listen 127.0.0.1:8444 ssl proxy_protocol;
    server_name de.dahoom.de5.net;
    ssl_certificate     /etc/letsencrypt/live/de.dahoom.de5.net/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/de.dahoom.de5.net/privkey.pem;
    location / {
        proxy_pass http://127.0.0.1:8420;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $proxy_protocol_addr;
        proxy_set_header X-Forwarded-For $proxy_protocol_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF
sudo nginx -t && sudo systemctl reload nginx
```

(نفس هذا الإعداد موجود جاهز كقالب بملف
`nginx-behind-haproxy.conf.example` — بدّل `DOMAIN` بدومينك.)

**ب-4) وجّه haproxy لدومينك تحديدًا (خطوة إلزامية — بدونها الطلبات
تروح لـ`nginx_tls` العادي وتفشل):** شغّل السكربت الجاهز، آمن للتكرار:
```bash
sudo /opt/fm-key-server/patch-haproxy-sni.sh de.dahoom.de5.net 8444
```
يتحقق من صياغة haproxy قبل أي تحميل، ولا يوقف الخدمة القائمة لو فشل
التحقق (haproxy يرفض إعداد خاطئ ويبقي القديم شغّال).

**⚠️ تحذير مهم ودائم:** لو استخدمت قائمة **"Connection Modes"**
بالبانل على هذا الـVPS (أي شي يستدعي `write_haproxy_edge_config`)،
تنعاد كتابة `/etc/haproxy/haproxy.cfg` بالكامل من الصفر وتُمحى قاعدة
التوجيه هذي. **أعد تشغيل `patch-haproxy-sni.sh` بعد أي استخدام لتلك
القائمة.** ملف nginx الخاص بدومينك (`sites-available/de.dahoom.de5.net`)
غير متأثر — فقط haproxy.cfg.

لا حاجة لأي تعديل بالجدار الناري — المنافذ 8880/8444 مربوطة
بـ`127.0.0.1` فقط، وhaproxy أصلًا يتحكّم بما يدخل من الإنترنت على
80/443.

**تجديد الشهادة لاحقًا** (كل ~90 يوم، certbot يضيف مهمة تلقائية
افتراضيًا، لكن تأكد إنها تعيد تحميل nginx بعد التجديد):
```bash
echo '#!/bin/sh
systemctl reload nginx' | sudo tee /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
```

---

## الاختبار النهائي (من أي جهاز، حتى جهازك الشخصي)

```bash
# فحص الصحة
curl -s https://de.dahoom.de5.net/v1/health
# → {"status": "ok"}

# طلب مفتاح بترخيص صالح فعليًا (بدّل بترخيص حقيقي من reg.json)
curl -s -X POST https://de.dahoom.de5.net/v1/key \
     -H 'Content-Type: application/json' \
     -d '{"license":"REPLACE_ME"}'
# ترخيص صالح  → {"key": "..."}
# ترخيص وهمي → {"error": "not_found"}  (HTTP 403)
```

ثم تجربة حقيقية كاملة: `curl -fsSL https://raw.githubusercontent.com/mooa322/fm/main/install.sh | bash`
على سيرفر عميل، وتأكد إن فك التشفير ينجح.

## المراقبة والصيانة

- سجل الطلبات: `/opt/fm-key-server/access.log` (سطر JSON لكل طلب —
  ترخيص، IP، نجح/فشل، السبب).
- سجل مباشر: `sudo journalctl -u fm-key-server -f`
- إعادة تشغيل بعد أي تعديل: `sudo systemctl restart fm-key-server`
- **تدوير المفتاح لاحقًا**: بعد ما تولّد مفتاحًا جديدًا محليًا (عبر
  `tools/gen-payload-key.sh --force` وإعادة `build-payload.sh`)، حدّث
  `/opt/fm-key-server/payload.key` بنفس القيمة الجديدة بالضبط، ثم
  `sudo systemctl restart fm-key-server`. بدون هذي الخطوة، أي `menu.enc`
  جديد يفشل فكّه لكل العملاء (السيرفر بيرجّع المفتاح القديم).
- **(القسم ب فقط) بعد أي استخدام لقائمة "Connection Modes" بالبانل**:
  أعد تشغيل `sudo /opt/fm-key-server/patch-haproxy-sni.sh de.dahoom.de5.net 8444`
  — تلك القائمة تعيد كتابة haproxy.cfg وتمحو قاعدة التوجيه.
