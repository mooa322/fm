#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#  DAHOOM · Seed bot_node_accounts.db — one-time cutover helper
#
#  Run on a VPN NODE server (e.g. Germany) that already has real
#  bot-issued customer accounts in its local users.db, AFTER that box
#  is registered as a node on the bot's controller (e.g. France) — see
#  the "عقد VPN" section of the panel. It extracts every bot-issued
#  account's owner tag and prints ready-to-use bot_node_accounts.db
#  lines to stdout.
#
#  Why this is needed at all: the bot's owner→node index normally gets
#  written the moment an account is created through the node-aware
#  flow (region picked with mode=node). Accounts that already existed
#  BEFORE that node was ever registered never went through that step,
#  so without this, their /myaccount, renewal and HWID-change would
#  come back empty on the controller until the customer somehow picks
#  that region again — which the "renew" flow never even asks for.
#  This backfills exactly that gap, once, for existing customers only.
#
#  This does NOT move, copy, or touch users.db or any customer data —
#  Germany's accounts stay on Germany. It only tells France's bot
#  which node already owns each existing customer.
#
#  Usage (on the NODE server, e.g. Germany):
#      bash seed-node-accounts.sh <node-slug> [users.db path] > accounts.txt
#      # node-slug must be the EXACT slug this node was registered
#      # under on the controller (see the "عقد VPN" panel section —
#      # same slug used for both the node entry and its region row).
#
#  Then, on the CONTROLLER server (e.g. France):
#      cat accounts.txt >> /etc/firewallfalcon/bot_node_accounts.db
#      # (create the file first with `touch` + `chmod 600` if it
#      # doesn't exist yet — it's created automatically on first
#      # write by the bot otherwise, but chmod it 600 either way since
#      # it ties telegram IDs to server accounts)
#
#  Safe to re-run: it only ever prints the CURRENT owner of an account,
#  so re-appending later just adds a second, identical line — reading
#  code always takes the freshest match, and a stray duplicate line
#  changes nothing. It does not delete or rewrite anything on either
#  server.
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

NODE_SLUG="${1:-}"
USERS_DB="${2:-/etc/firewallfalcon/users.db}"

if [[ -z "$NODE_SLUG" ]]; then
    echo "الاستخدام: $0 <node-slug> [مسار users.db]" >&2
    echo "مثال:      $0 germany /etc/firewallfalcon/users.db > accounts.txt" >&2
    exit 1
fi
if [[ ! "$NODE_SLUG" =~ ^[A-Za-z0-9_-]+$ ]]; then
    echo "[ERROR] معرّف العقدة (slug) يجب أن يكون إنجليزيًا/أرقامًا/-/_ فقط، بلا نقطتين أو مسافات: $NODE_SLUG" >&2
    exit 1
fi
if [[ ! -f "$USERS_DB" ]]; then
    echo "[ERROR] لا يوجد ملف حسابات هنا: $USERS_DB" >&2
    exit 1
fi

# نفس منطق إعادة تجميع حقل owner المستخدم في _fm_bot_accounts_for_
# owner_dispatch (menu.sh) — الحقل قد يحوي نقطتين خاصة به (tg:123456)
# فيُعاد لصقه من كل ما تبقّى من الحقول بدل أخذ الحقل الثامن وحده، وإلا
# بُتر إلى "tg" فقط وضاع رقم الشات كليًا.
count=0
while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    username="${line%%:*}"
    owner=$(awk -F: '
        NF==7 { print $7; next }
        NF>=8 { o=$8; for(i=9;i<=NF;i++) o=o ":" $i; print o }
    ' <<< "$line")
    [[ "$owner" == tg:* ]] || continue
    [[ -n "$username" ]] || continue
    printf '%s:%s:%s\n' "$username" "$NODE_SLUG" "$owner"
    count=$((count + 1))
done < "$USERS_DB"

echo "[✓] $count حساب بوت مُستخرَج من $USERS_DB بعقدة \"$NODE_SLUG\" — الصقها في bot_node_accounts.db على سيرفر البوت." >&2
