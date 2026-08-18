#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#  DAHOOM · List all licenses and their state
#  Usage:  ./tools/list-clients.sh
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f tools/.worker.env ] || { echo "[ERROR] tools/.worker.env not found"; exit 1; }
set -a; . tools/.worker.env; set +a
: "${WORKER_URL:?}"; : "${ADMIN_TOKEN:?}"

curl -fsS "$WORKER_URL/admin/list" -H "Authorization: Bearer $ADMIN_TOKEN" \
  | python3 -c '
import sys, json
d = json.load(sys.stdin)
lic = d.get("licenses", [])
print(f"{len(lic)} license(s):\n")
print(f"{\"ID\":<24} {\"STATUS\":<10} {\"BOUND IP\":<18} CREATED")
for l in sorted(lic, key=lambda x: x.get("created") or ""):
    st = "REVOKED" if l["revoked"] else ("bound" if l["ip"] else "unused")
    print(f"{l[\"id\"]:<24} {st:<10} {(l[\"ip\"] or \"-\"):<18} {(l.get(\"created\") or \"\")[:10]}")
' 2>/dev/null || { echo "[ERROR] could not reach Worker or parse response"; exit 1; }
