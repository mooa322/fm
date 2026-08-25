#!/bin/bash
# download_dropbox_files.sh
# شغّله على أي سيرفر أوبنتو عنده إنترنت كامل - يُحمّل كل روابط Dropbox
# التي وجدناها داخل menu، يضعها في مجلد واحد، ثم يضغط المجلد بصيغة zip.
#
# الاستخدام:
#   chmod +x download_dropbox_files.sh
#   ./download_dropbox_files.sh
#
# النتيجة: مجلد dropbox_files/ يحتوي كل الملفات، وأرشيف dropbox_files.zip جاهز للإرسال.

set -uo pipefail

OUTDIR="dropbox_files"
mkdir -p "$OUTDIR"

# تثبيت unzip/zip إن لم تكن موجودة
command -v zip >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y zip; }

# الروابط (اسم الملف المحلي | الرابط الأصلي)
URLS=(
"zerossl.sh|https://www.dropbox.com/s/0s2uamltufhfusl/zerossl.sh"
"budp.sh|https://www.dropbox.com/s/0stqb3dzm47kky6/budp.sh"
"rm-rf-bin.sh|https://www.dropbox.com/s/3htxupvkm1si9g5/rm-rf-bin.sh"
"stunnel.zip|https://www.dropbox.com/s/3u29bb5o38cmfa3/stunnel.zip"
"_multiK.sh|https://www.dropbox.com/s/4jpdbr02nd413i1/_multiK.sh"
"chekuser.py|https://www.dropbox.com/s/636hdjb1tw43uws/chekuser.py"
"certificadossl.sh|https://www.dropbox.com/s/839d3q8kh72ujr0/certificadossl.sh"
"brook.sh|https://www.dropbox.com/s/bphl0io0xn7u37g/brook.sh"
"socks5.sh|https://www.dropbox.com/s/etvd71wl749kv7f/socks5.sh"
"root-pass.sh|https://www.dropbox.com/s/hl9vyo8mf94z0h5/root-pass.sh"
"v2ray1.sh|https://www.dropbox.com/s/id3llagyfvwceyr/v2ray1.sh"
"ws-java.sh|https://www.dropbox.com/s/k3sozjz9bzmucag/ws-java.sh"
"dnsNN.sh|https://www.dropbox.com/s/l1hjn77fp0cywsl/dnsNN.sh"
"x-ui.sh|https://www.dropbox.com/s/lf2b5rhkasgjr8g/x-ui.sh"
"sslh-back3.sh|https://www.dropbox.com/s/m3qm4ekjbf2fg5m/sslh-back3.sh"
"front.sh|https://www.dropbox.com/s/ooe74y69nm89da9/front.sh"
"SockPython.sh|https://www.dropbox.com/s/oqtcyg8r9v2zulu/SockPython.sh"
"openvpn.sh|https://www.dropbox.com/s/q5kvrcbjwcmcsut/openvpn.sh"
"v2ray.sh|https://www.dropbox.com/s/q6mpwhfgt1665pl/v2ray.sh"
"check.sh|https://www.dropbox.com/s/r2madnleejjqhw1/check.sh"
"tumbs.sh|https://www.dropbox.com/s/t4mfqdepbqg3a4i/tumbs.sh"
"h_beta.sh|https://www.dropbox.com/s/ud4ux8kt4cgrljj/h_beta.sh"
"update.txt|https://www.dropbox.com/s/uyyme71yu6942vb/update.txt"
"clash-beta.sh|https://www.dropbox.com/s/uz3s8keszpdwx0y/clash-beta.sh"
"autoconfig.sh|https://www.dropbox.com/s/vi96sjxiqwdibo5/autoconfig.sh"
"gnula.sh|https://www.dropbox.com/s/x6fp9f14ob1i5ez/gnula.sh"
"onlineapp.sh|https://www.dropbox.com/s/x8wcrnj5gho4d39/onlineapp.sh"
"adduser.sh|https://www.dropbox.com/s/z6txyjygpri7ede/adduser.sh"
"telebot.sh.sh|https://www.dropbox.com/s/zvn8naajedzldno/telebot.sh.sh"
"killSSH.sh|https://www.dropbox.com/scl/fi/cx7t2bt22fm0gx6uxq5da/killSSH.sh?rlkey=4h8pbxug705gv7pvv2e40jjnf"
)

ok=0
fail=0
> "$OUTDIR/_download_report.txt"

for entry in "${URLS[@]}"; do
    fname="${entry%%|*}"
    url="${entry#*|}"
    # إجبار Dropbox على تحميل مباشر بدل صفحة المعاينة
    if [[ "$url" == *"?"* ]]; then
        dl_url="${url}&dl=1"
    else
        dl_url="${url}?dl=1"
    fi

    echo -n "تحميل ${fname} ... "
    if curl -fsSL --max-time 30 -o "$OUTDIR/$fname" "$dl_url" && [[ -s "$OUTDIR/$fname" ]]; then
        echo "OK ($(stat -c%s "$OUTDIR/$fname") bytes)"
        echo "OK|$fname|$url" >> "$OUTDIR/_download_report.txt"
        ok=$((ok+1))
    else
        echo "فشل"
        rm -f "$OUTDIR/$fname"
        echo "FAIL|$fname|$url" >> "$OUTDIR/_download_report.txt"
        fail=$((fail+1))
    fi
done

echo ""
echo "===================================="
echo "نجح: $ok  |  فشل: $fail"
echo "===================================="

# الضغط
ZIPNAME="dropbox_files.zip"
rm -f "$ZIPNAME"
zip -r -q "$ZIPNAME" "$OUTDIR"
echo "تم إنشاء الأرشيف: $(pwd)/$ZIPNAME"
echo ""
echo "أرسل لي ملف $ZIPNAME (أو ارفعه على رابط تحميل وأرسل لي الرابط)."
