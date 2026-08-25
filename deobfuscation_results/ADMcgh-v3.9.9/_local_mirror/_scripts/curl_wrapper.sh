#!/bin/bash
# curl wrapper: يعترض طلبات الروابط التي لدينا نسخة محلية منها
# ويُعيد محتواها المحلي بدلاً من الاتصال بالإنترنت. أي رابط غير
# موجود في القائمة يمر بشكل طبيعي إلى curl الحقيقي (fallback آمن).
#
# التركيب: انسخه إلى /usr/local/bin/curl (يسبق /usr/bin/curl في PATH)
# مع تعيين REAL_CURL و PROJECT_ROOT كمتغيرين بيئيين، أو عدّلهما أدناه.

REAL_CURL="${REAL_CURL:-/usr/bin/curl}"
MIRROR_ROOT="${MIRROR_ROOT:-/etc/ADMcgh/mirror}"
MAP_FILE="$MIRROR_ROOT/url_map.txt"

# استخرج آخر معامل لا يبدأ بـ - كرابط الطلب (نمط curl الشائع)
url=""
out_file=""
use_O=""
prev=""
for arg in "$@"; do
    case "$prev" in
        -o|--output) out_file="$arg" ;;
    esac
    case "$arg" in
        http://*|https://*) url="$arg" ;;
        -O|--remote-name) use_O=1 ;;
    esac
    prev="$arg"
done

local_path=""
if [[ -n "$url" && -s "$MAP_FILE" ]]; then
    local_path="$(awk -F'|' -v u="$url" '$1==u{print $2; exit}' "$MAP_FILE")"
fi

if [[ -n "$local_path" && -s "$MIRROR_ROOT/$local_path" ]]; then
    src="$MIRROR_ROOT/$local_path"
    if [[ -n "$out_file" ]]; then
        cp "$src" "$out_file"
    elif [[ -n "$use_O" ]]; then
        cp "$src" "$(basename "$url")"
    else
        cat "$src"
    fi
    exit 0
fi

exec "$REAL_CURL" "$@"
