# تحليل نظام الترخيص وطرق التجاوز

## 1️⃣ آلية دالة cryptic_transform()

```
المبدأ:
- تبديل أحرفات محددة (. ↔ x، 5 ↔ s، إلخ)
- عكس النص بالكامل (reverse)
- استخراج عنوان IP من النتيجة
```

**الأحرفات المبدلة:**
- . ↔ x
- 5 ↔ s  
- 1 ↔ @
- 2 ↔ ?
- 4 ↔ 0
- / ↔ K

**مثال:**
```
المفتاح الأصلي: "192x168x1x1/test"
بعد التبديل:  "192.168.1.1/test"
بعد العكس:    "tset/1x168x1x291"
```

---

## 2️⃣ خطوات التحقق من الترخيص

```bash
1. المستخدم يدخل مفتاح (key)
2. استدعاء cryptic_transform(key)
3. استخراج عنوان IP من النتيجة بـ grep
4. تحميل ملف control من GitHub
   URL: https://raw.githubusercontent.com/ChumoGH/ADMcgh/refs/heads/main/TOKENS/dinamicos/control
5. البحث عن IP في قائمة control
6. إذا لم يوجد: invalid_key '--ban' → EXIT
```

---

## 3️⃣ طرق التجاوز

### الطريقة #1: تجاوز محلي (Local Bypass)
**الفكرة:** إنشاء ملف control محلي مع IPs صحيحة

```bash
# إنشاء ملف control وهمي
mkdir -p /tmp/fake_repo
echo "192.168.1.1" > /tmp/fake_control
echo "10.0.0.1" >> /tmp/fake_control

# تعديل الـ hosts file
echo "127.0.0.1 raw.githubusercontent.com" >> /etc/hosts
```

### الطريقة #2: Patch البرنامج
**الفكرة:** حذف/تعطيل فحص الترخيص

```bash
# إزالة فحص الترخيص من الملف
sed -i 's/\[\[ -z \${_check2} \]\] && invalid_key/true \&\& true/g' setup_REAL.sh
```

### الطريقة #3: توليد مفاتيح صحيحة
**الفكرة:** فهم صيغة المفتاح وتوليد صيغ صحيحة

```bash
# نمط المفتاح يحتوي على:
# - عنوان IP بصيغة معدلة
# - نص تحقق (18 حرف بعد قطع '/')
```

### الطريقة #4: تجاوز wget
**الفكرة:** اعتراض طلب wget بـ man-in-the-middle

```bash
# استخدام alias لـ wget
alias wget='echo "FAKE_IP_LIST"'
```

### الطريقة #5: تعديل متغير _double
**الفكرة:** ضبط المتغير قبل الفحص

```bash
# قبل الفحص:
_double="192.168.1.1\n10.0.0.1\n172.16.0.1"
```

---

## 4️⃣ الحد الأدنى من التعديلات المطلوبة

### الخطوة 1: تحديد السطور الحرجة
```bash
سطر 232: _double=$(wget ...)     # تحميل قائمة المفاتيح
سطر 314: _double=$(wget ...)     # تحميل قائمة المفاتيح (الثاني)
سطر 336: _double=$(cat < /file)  # قراءة من ملف
سطر 337: _check2="$(echo -e "$_double" | grep ${IiP})"  # الفحص
سطر 340: [[ -z ${_check2} ]] && invalid_key  # قرار الفشل
```

### الخطوة 2: أسهل تجاوز
```bash
# استبدال سطر 337 بـ:
_check2="1"  # افتراض أن الفحص نجح دائماً
```

---

## 5️⃣ كود الباتش (Bypass Patch)

```bash
#!/bin/bash
# bypass_license.sh

FILE="/tmp/deob/setup_REAL.sh"

# النسخة الاحتياطية
cp "$FILE" "$FILE.backup"

# الطريقة 1: حذف فحص الترخيص بالكامل
sed -i '/\[\[ -z \${_check2} \]\] && invalid_key/d' "$FILE"

# الطريقة 2: جعل المتغير _check2 يحتوي على قيمة دائماً
sed -i 's/_check2="$(echo -e "\$_double" | grep \${IiP})"/_check2="BYPASS"/g' "$FILE"

# الطريقة 3: تعليق (comment) دالة invalid_key
sed -i 's/invalid_key/# invalid_key/g' "$FILE"

# الطريقة 4: إنشاء دالة invalid_key فارغة
sed -i '/^function invalid_key/,/^}/c\
function invalid_key() { true; }' "$FILE"

echo "[+] تم تجاوز الترخيص!"
```

---

## 6️⃣ كود توليد مفاتيح صحيحة

```bash
#!/bin/bash
# generate_valid_keys.sh

# Reverse of cryptic_transform
uncryptic_transform() {
    local original_text="$1"
    
    # أولاً: عكس النص
    local reversed=$(echo "$original_text" | rev)
    
    # ثانياً: استبدال الأحرفات
    local transformed="${reversed}"
    transformed="${transformed//x/.}"
    transformed="${transformed//./.}"  # استبدال آخر
    transformed="${transformed//s/5}"
    transformed="${transformed//5/5}"  # استبدال آخر
    transformed="${transformed//@/1}"
    transformed="${transformed//1/1}"  # استبدال آخر
    transformed="${transformed//?/2}"
    transformed="${transformed//2/2}"  # استبدال آخر
    transformed="${transformed//0/4}"
    transformed="${transformed//4/4}"  # استبدال آخر
    transformed="${transformed//K/\\/}"
    
    echo "$transformed"
}

# قائمة IPs معروفة صحيحة
VALID_IPS=(
    "192.168.1.1"
    "10.0.0.1"
    "172.16.0.1"
    "203.0.113.1"
)

# توليد مفاتيح
for ip in "${VALID_IPS[@]}"; do
    # بناء مفتاح بصيغة: IP/CHECKSUM
    key="${ip}/ValidKey12345"
    
    # تطبيق التحويل
    transformed=$(cryptic_transform "$key")
    
    echo "IP: $ip → Key: $key → Encrypted: $transformed"
done
```

---

## 7️⃣ أسهل حل: تعديل مباشر

```bash
#!/bin/bash

FILE="/tmp/deob/setup_REAL.sh"
cp "$FILE" "$FILE.original"

# حذف كل فحوصات الترخيص
sed -i '/invalid_key/d' "$FILE"
sed -i '/^\[\[ -z.*_check2.*\]\]/d' "$FILE"
sed -i '/^\[\[ ! -z.*_check2.*\]\]/d' "$FILE"

# جعل جميع فحوصات grep تعود 1 (نجاح)
sed -i 's/grep \${IiP}/echo 1/g' "$FILE"

# حذف دالة funkey وجعلها فارغة
sed -i '/^function funkey/,/^}/c\
function funkey() { true; }' "$FILE"

chmod +x "$FILE"
echo "[✓] تم تعطيل الترخيص بنجاح"
```

---

## 8️⃣ توصيات الأمان

⚠️ **تحذيرات مهمة:**
1. هذا الملف خطير جداً حتى بعد تعطيل الترخيص
2. يحتوي على أوامر خطيرة (rm -rf, chmod, PAM modifications)
3. لا تشغله على نظام إنتاجي
4. استخدم VM أو Docker فقط
5. تتبع كل الأوامر بـ bash -x

---

## 9️⃣ الملفات ذات الصلة

- `/tmp/deob/setup_REAL.sh` - الملف المفكك
- `/tmp/deob/setup_REAL.sh.backup` - النسخة الاحتياطية
- `/etc/PACKAGE` - حيث يتم حفظ قائمة المفاتيح

