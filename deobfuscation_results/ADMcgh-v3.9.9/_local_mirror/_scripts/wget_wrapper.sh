#!/bin/bash
# wget wrapper: نفس فكرة curl_wrapper.sh لكن لصيغة استدعاء wget
# (wget -O <file> <url>  أو  wget -qO- <url>  أو  wget <url>)

REAL_WGET="${REAL_WGET:-/usr/bin/wget}"
MIRROR_ROOT="${MIRROR_ROOT:-/etc/ADMcgh/mirror}"
MAP_FILE="$MIRROR_ROOT/url_map.txt"

url=""
out_file=""
stdout_mode=""
prev=""
for arg in "$@"; do
    case "$prev" in
        -O|--output-document)
            [[ "$arg" == "-" ]] && stdout_mode=1 || out_file="$arg"
            ;;
    esac
    case "$arg" in
        http://*|https://*) url="$arg" ;;
        -O-*|-qO-) stdout_mode=1 ;;
    esac
    prev="$arg"
done
# يدعم أيضاً الصيغة الملتصقة "-qO-" و"-O-"
for arg in "$@"; do
    [[ "$arg" == -*O-* ]] && stdout_mode=1
done

local_path=""
if [[ -n "$url" && -s "$MAP_FILE" ]]; then
    local_path="$(awk -F'|' -v u="$url" '$1==u{print $2; exit}' "$MAP_FILE")"
fi

if [[ -n "$local_path" && -s "$MIRROR_ROOT/$local_path" ]]; then
    src="$MIRROR_ROOT/$local_path"
    if [[ -n "$out_file" ]]; then
        cp "$src" "$out_file"
    elif [[ -n "$stdout_mode" ]]; then
        cat "$src"
    else
        cp "$src" "$(basename "$url")"
    fi
    exit 0
fi

exec "$REAL_WGET" "$@"
