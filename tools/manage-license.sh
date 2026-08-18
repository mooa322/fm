#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#  DAHOOM · Manage licenses.json (no live server — plain GitHub file)
#
#  Usage:
#    ./tools/manage-license.sh issue  <id> [ip]     add/update a license
#    ./tools/manage-license.sh revoke <id>          block it everywhere
#    ./tools/manage-license.sh unbind <id>          clear its IP lock
#    ./tools/manage-license.sh list                 show all licenses
#
#  Every command edits licenses.json locally. YOU commit & push it
#  yourself (or ask the assistant to), since that's what makes the
#  change take effect — nothing here talks to a server.
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail
cd "$(dirname "$0")/.."
FILE="licenses.json"
[ -f "$FILE" ] || echo '{}' > "$FILE"

cmd="${1:-}"; id="${2:-}"

case "$cmd" in
  issue)
    [ -n "$id" ] || { echo "usage: $0 issue <id> [ip]"; exit 1; }
    ip="${3:-null}"
    [ "$ip" != "null" ] && ip="\"$ip\""
    python3 - "$FILE" "$id" "$ip" <<'PY'
import json, sys, datetime
f, id, ip = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(f))
d[id] = {
    "ip": None if ip == "null" else ip.strip('"'),
    "issued": datetime.date.today().isoformat(),
    "revoked": False,
}
json.dump(d, open(f, "w"), indent=2, ensure_ascii=False)
print(f"issued '{id}'" + (f" (locked to IP {d[id]['ip']})" if d[id]['ip'] else " (open — will accept any IP until you set one)"))
PY
    echo "give the client this ONE code: ${id}"
    echo "push it:  git add licenses.json && git commit -m 'license: issue ${id}' && git push"
    ;;
  revoke)
    [ -n "$id" ] || { echo "usage: $0 revoke <id>"; exit 1; }
    python3 - "$FILE" "$id" <<'PY'
import json, sys
f, id = sys.argv[1], sys.argv[2]
d = json.load(open(f))
if id not in d: print(f"'{id}' not found"); sys.exit(1)
d[id]["revoked"] = True
json.dump(d, open(f, "w"), indent=2, ensure_ascii=False)
print(f"revoked '{id}'")
PY
    echo "push it:  git add licenses.json && git commit -m 'license: revoke ${id}' && git push"
    ;;
  unbind)
    [ -n "$id" ] || { echo "usage: $0 unbind <id>"; exit 1; }
    python3 - "$FILE" "$id" <<'PY'
import json, sys
f, id = sys.argv[1], sys.argv[2]
d = json.load(open(f))
if id not in d: print(f"'{id}' not found"); sys.exit(1)
d[id]["ip"] = None
json.dump(d, open(f, "w"), indent=2, ensure_ascii=False)
print(f"'{id}' unbound — next install can set a new IP")
PY
    echo "push it:  git add licenses.json && git commit -m 'license: unbind ${id}' && git push"
    ;;
  list)
    python3 - "$FILE" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
if not d: print("no licenses yet"); sys.exit(0)
print(f"{'ID':<20} {'STATUS':<10} {'IP':<16} ISSUED")
for id, rec in sorted(d.items()):
    st = "REVOKED" if rec.get("revoked") else "active"
    print(f"{id:<20} {st:<10} {(rec.get('ip') or '-'):<16} {rec.get('issued','')}")
PY
    ;;
  *)
    echo "usage: $0 {issue|revoke|unbind|list} ..."
    exit 1
    ;;
esac
