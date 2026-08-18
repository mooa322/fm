#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#  DAHOOM · Issue a license to one client
#  Run this on YOUR machine (the seller). Never on a client's server.
#
#  Usage:  ./tools/issue-client.sh <client-id> [passphrase]
#          client-id : short name, letters/digits/dash only (e.g. ahmed-vps1)
#          passphrase: optional; a strong one is generated if omitted.
#
#  It encrypts the current payload for this client and writes
#  clients/<id>.enc into the repo. Commit & push that file, then hand
#  the client the printed install command.
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail
cd "$(dirname "$0")/.."
. tools/_fmcrypto.sh

Rc='\033[1;31m'; Gc='\033[1;32m'; Yc='\033[1;33m'; Cc='\033[1;36m'; Nc='\033[0m'
die(){ echo -e "${Rc}[ERROR]${Nc} $1" >&2; exit 1; }

ID="${1:-}"
[ -n "$ID" ] || die "give a client id, e.g. ./tools/issue-client.sh ahmed-vps1"
[[ "$ID" =~ ^[A-Za-z0-9_-]+$ ]] || die "client id may only contain letters, digits, - and _"
command -v openssl >/dev/null || die "openssl is required"

KEY="${2:-$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 28)}"
[ ${#KEY} -ge 12 ] || die "passphrase too short (>=12 chars)"

DB="tools/.clients.db"; touch "$DB"; chmod 600 "$DB"
if grep -q "^${ID}	" "$DB" 2>/dev/null; then
    echo -e "${Yc}[WARN]${Nc} '$ID' already exists — its key will be reused (re-encrypting current payload)."
    KEY="$(awk -F'\t' -v id="$ID" '$1==id{print $2; exit}' "$DB")"
fi

# ── build the plaintext payload bundle from the private source tree ──
for f in "${FM_PAYLOAD[@]}"; do [ -f "$FM_SRC_DIR/$f" ] || die "payload file missing: $FM_SRC_DIR/$f (run from repo root)"; done
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
tar -czf "$TMP/bundle.tgz" -C "$FM_SRC_DIR" "${FM_PAYLOAD[@]}"

mkdir -p clients
# shellcheck disable=SC2086
openssl enc $FM_CIPHER -in "$TMP/bundle.tgz" -out "clients/${ID}.enc" -pass "pass:${KEY}"

# record id -> key (local only, gitignored). needed to re-issue updates later.
grep -v "^${ID}	" "$DB" > "$DB.tmp" 2>/dev/null || true
printf '%s\t%s\t%s\n' "$ID" "$KEY" "$(date +%F)" >> "$DB.tmp"
mv "$DB.tmp" "$DB"; chmod 600 "$DB"

SZ="$(du -h "clients/${ID}.enc" | cut -f1)"
echo
echo -e "${Gc}✅ License issued for '${ID}'${Nc}  (clients/${ID}.enc, ${SZ})"
echo -e "   ${Yc}1.${Nc} commit & push:  ${Cc}git add clients/${ID}.enc && git commit -m 'license: ${ID}' && git push${Nc}"
echo -e "   ${Yc}2.${Nc} give the client these two lines:"
echo
echo -e "${Cc}export FM_ID=${ID} FM_KEY='${KEY}'${Nc}"
echo -e "${Cc}bash <(curl -sL https://raw.githubusercontent.com/mooa322/fm/main/install.sh)${Nc}"
echo
echo -e "   ${Yc}keep tools/.clients.db safe & backed up${Nc} — you need it to push updates to existing clients."
