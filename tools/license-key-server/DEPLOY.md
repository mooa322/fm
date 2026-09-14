# نشر سيرفر مفتاح الترخيص (fm-key-server)

خطوات كاملة تنسخها وتشغّلها بالـSSH على الـVPS. مبنية لأوبنتو/دبيان
(apt) — عدّل أوامر التثبيت إذا نظامك مختلف.

**قبل البدء:** وجّه سجل DNS من نوع A لـ `de.dahoom.de5.net` لعنوان IP
تبع هذا الـVPS (من لوحة تحكم مزوّد الدومين تبعك). انتظر حتى ينتشر
(عادة دقائق، أحيانًا أطول) قبل خطوة Caddy — تقدر تتحقق بـ:
`dig +short de.dahoom.de5.net`

## 1) نسخ الملفات للسيرفر

من جهازك (مو من الـVPS)، بمجلد `tools/license-key-server/` بمستودع fm:

```bash
scp server.py fm-key-server.service Caddyfile root@YOUR_VPS_IP:/tmp/
```

## 2) إعداد مستخدم مخصّص وملفات الخدمة (على الـVPS)

```bash
sudo useradd --system --no-create-home --shell /usr/sbin/nologin fmkeysrv
sudo mkdir -p /opt/fm-key-server
sudo mv /tmp/server.py /opt/fm-key-server/
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

تحقق سريع محلي (على نفس الـVPS، قبل ما نضيف HTTPS):

```bash
curl -s http://127.0.0.1:8420/v1/health
# → {"status": "ok"}
```

## 5) تثبيت Caddy (إذا مو مثبّت أصلًا)

```bash
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update
sudo apt install -y caddy
```

## 6) إعداد Caddy

```bash
sudo mv /tmp/Caddyfile /etc/caddy/Caddyfile
sudo systemctl reload caddy
```

Caddy يصدر شهادة Let's Encrypt تلقائيًا أول ما يستقبل طلب على
الدومين — لا حاجة لأي إعداد شهادات يدوي.

## 7) الاختبار النهائي (من أي جهاز، حتى جهازك الشخصي)

```bash
# فحص الصحة
curl -s https://de.dahoom.de5.net/v1/health
# → {"status": "ok"}

# طلب مفتاح بترخيص صالح فعليًا (بدّل owner بترخيص حقيقي من reg.json)
curl -s -X POST https://de.dahoom.de5.net/v1/key \
     -H 'Content-Type: application/json' \
     -d '{"license":"owner"}'
# ترخيص صالح  → {"key": "..."}
# ترخيص وهمي → {"error": "not_found"}  (HTTP 403)
```

## 8) الجدار الناري (إن وجد)

المنفذ 8420 مربوط بـ`127.0.0.1` فقط أصلًا (Caddy وحده يوصله) — لا
حاجة لفتحه بالجدار الناري. تأكد فقط إن 80 و443 مفتوحين (Caddy
يحتاجهم لـHTTP→HTTPS ولإصدار الشهادة):

```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

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
