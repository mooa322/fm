#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#  DAHOOM · Unbind a license from its server
#  Use when a client legitimately moves to a new server — this clears
#  the IP lock so their next install binds to the new server.
#  Usage:  ./tools/unbind-client.sh <client-id>
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f tools/.worker.env ] || { echo "[ERROR] tools/.worker.env not found"; exit 1; }
set -a; . tools/.worker.env; set +a
: "${WORKER_URL:?}"; : "${ADMIN_TOKEN:?}"
Gc='\033[1;32m'; Rc='\033[1;31m'; Nc='\033[0m'
ID="${1:-}"; [ -n "$ID" ] || { echo "usage: ./tools/unbind-client.sh <id>"; exit 1; }

resp="$(curl -fsS -X POST "$WORKER_URL/admin/unbind" \
        -H "Authorization: Bearer $ADMIN_TOKEN" -H 'content-type: application/json' \
        -d "{\"id\":\"$ID\"}" 2>/dev/null || true)"
if echo "$resp" | grep -q '"ok":true'; then
    echo -e "${Gc}✅ '${ID}' unbound.${Nc} Its next install will bind to the new server."
else
    echo -e "${Rc}[ERROR]${Nc} ${resp:-<no response>}"; exit 1
fi
