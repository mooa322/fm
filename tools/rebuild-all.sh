#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#  DAHOOM · Re-encrypt the current payload for every active client
#  Run this after you change menu.sh / panel / any protected file, so
#  all existing clients get the new version on their next update.
#
#  Usage:  ./tools/rebuild-all.sh
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail
cd "$(dirname "$0")/.."
. tools/_fmcrypto.sh

Rc='\033[1;31m'; Gc='\033[1;32m'; Yc='\033[1;33m'; Nc='\033[0m'
DB="tools/.clients.db"
[ -f "$DB" ] || { echo -e "${Rc}[ERROR]${Nc} no tools/.clients.db — issue a client first."; exit 1; }
command -v openssl >/dev/null || { echo -e "${Rc}[ERROR]${Nc} openssl required"; exit 1; }
for f in "${FM_PAYLOAD[@]}"; do [ -f "$FM_SRC_DIR/$f" ] || { echo -e "${Rc}[ERROR]${Nc} payload missing: $FM_SRC_DIR/$f"; exit 1; }; done

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
tar -czf "$TMP/bundle.tgz" -C "$FM_SRC_DIR" "${FM_PAYLOAD[@]}"
mkdir -p clients

n=0; skipped=0
while IFS=$'\t' read -r id key _; do
    [ -z "${id:-}" ] && continue
    case "$id" in \#*|*'#REVOKED') skipped=$((skipped+1)); continue;; esac
    # shellcheck disable=SC2086
    openssl enc $FM_CIPHER -in "$TMP/bundle.tgz" -out "clients/${id}.enc" -pass "pass:${key}"
    n=$((n+1)); echo -e "  ${Gc}✓${Nc} ${id}"
done < "$DB"

echo
echo -e "${Gc}✅ Re-encrypted for ${n} active client(s)${Nc} (${skipped} revoked, skipped)."
echo -e "   ${Yc}push:${Nc} git add clients/ && git commit -m 'release: re-encrypt payload' && git push"
