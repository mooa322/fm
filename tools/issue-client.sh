#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#  DAHOOM · Issue a license to a client
#  Registers a new license id on the activation Worker. The client only
#  needs this ONE code to install; the decryption key is released by the
#  Worker automatically, and bound to the first server that uses it.
#
#  Usage:  ./tools/issue-client.sh [client-id]
#          If no id is given, a random one is generated.
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f tools/.worker.env ] || { echo "[ERROR] tools/.worker.env not found (copy .worker.env.example and fill it)"; exit 1; }
set -a; . tools/.worker.env; set +a
: "${WORKER_URL:?set WORKER_URL in tools/.worker.env}"
: "${ADMIN_TOKEN:?set ADMIN_TOKEN in tools/.worker.env}"

Gc='\033[1;32m'; Rc='\033[1;31m'; Yc='\033[1;33m'; Cc='\033[1;36m'; Nc='\033[0m'

ID="${1:-DAHOOM-$(openssl rand -hex 5)}"
[[ "$ID" =~ ^[A-Za-z0-9_-]+$ ]] || { echo -e "${Rc}id may only contain letters, digits, - and _${Nc}"; exit 1; }

resp="$(curl -fsS -X POST "$WORKER_URL/admin/issue" \
        -H "Authorization: Bearer $ADMIN_TOKEN" \
        -H 'content-type: application/json' \
        -d "{\"id\":\"$ID\"}" 2>/dev/null || true)"

if echo "$resp" | grep -q '"ok":true'; then
    echo -e "${Gc}✅ License issued: ${ID}${Nc}"
    echo -e "   Give the client this ONE line:"
    echo
    echo -e "${Cc}FM_ID=${ID} bash <(curl -sL https://raw.githubusercontent.com/mooa322/fm/main/install.sh)${Nc}"
    echo
    echo -e "   ${Yc}It binds to the first server it installs on; any other server is refused.${Nc}"
elif echo "$resp" | grep -q 'already exists'; then
    echo -e "${Yc}[WARN] '${ID}' already exists.${Nc}"
else
    echo -e "${Rc}[ERROR] could not issue. Worker said:${Nc} ${resp:-<no response>}"
    exit 1
fi
