#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#  DAHOOM · Revoke a client
#  Removes clients/<id>.enc so that client can no longer install or
#  self-update. Other clients are untouched.
#
#  Usage:  ./tools/revoke-client.sh <client-id>
#
#  NOTE: this stops future installs/updates for that client. A server
#  where the tool is ALREADY running keeps running until it next tries
#  to update (then it fails to refresh and stays on its current copy).
#  True remote kill requires the activation-server model.
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail
cd "$(dirname "$0")/.."

Rc='\033[1;31m'; Gc='\033[1;32m'; Cc='\033[1;36m'; Nc='\033[0m'
ID="${1:-}"
[ -n "$ID" ] || { echo -e "${Rc}usage:${Nc} ./tools/revoke-client.sh <client-id>"; exit 1; }

[ -f "clients/${ID}.enc" ] || { echo -e "${Rc}[ERROR]${Nc} no license file clients/${ID}.enc"; exit 1; }
git rm -q "clients/${ID}.enc" 2>/dev/null || rm -f "clients/${ID}.enc"

DB="tools/.clients.db"
if [ -f "$DB" ] && grep -q "^${ID}	" "$DB"; then
    awk -F'\t' -v id="$ID" 'BEGIN{OFS="\t"} $1==id{$1=$1"#REVOKED"} {print}' "$DB" > "$DB.tmp"
    mv "$DB.tmp" "$DB"; chmod 600 "$DB"
fi

echo -e "${Gc}✅ Revoked '${ID}'.${Nc} clients/${ID}.enc removed."
echo -e "   push the removal:  ${Cc}git commit -am 'revoke: ${ID}' && git push${Nc}"
