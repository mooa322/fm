#!/usr/bin/env bash
# DAHOOM Web Panel One-Click Installer & Updater (new_panel branch)

set -e

BRANCH="${1:-new_panel}"
PANEL_DIR="/etc/firewallfalcon/panel"
PANEL_CONF="/etc/firewallfalcon/panel.conf"
PANEL_SCRIPT="/usr/local/bin/firewallfalcon-panel.py"
PANEL_SERVICE="/etc/systemd/system/firewallfalcon-panel.service"
_FM_GH_RAW_B64="aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL21vb2EzMjIvZm0="
_fm_gh_raw() { printf '%s' "$_FM_GH_RAW_B64" | base64 -d 2>/dev/null; }
REPO_BASE="$(_fm_gh_raw)/$BRANCH"

# ── Licensed payload source ──────────────────────────────────────────
# Panel files ship inside the single encrypted bundle (menu.enc), gated
# by licenses.json on the same repo (id must exist, not be revoked, and
# match its registered IP if the seller bound one). If a decrypted
# source tree is already present, reuse it.
FM_LICENSE="/etc/firewallfalcon/.license"
FM_SRC="/etc/firewallfalcon/.src"
FM_PAYLOAD_URL="$(_fm_gh_raw)/main/menu.enc"
_FM_LIC_B64="aHR0cHM6Ly9hcGkuZ2l0aHViLmNvbS9yZXBvcy9tb29hMzIyL2luc3RhbGFzaS9jb250ZW50cy9jb25maWcvcmVnLmpzb24/cmVmPW1haW4="
_FM_LIC_FALLBACK_B64="aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL21vb2EzMjIvaW5zdGFsYXNpL21haW4vY29uZmlnL3JlZy5qc29u"
_fm_licenses_url() { printf '%s' "$_FM_LIC_B64" | base64 -d 2>/dev/null; }
_fm_licenses_url_fallback() { printf '%s' "$_FM_LIC_FALLBACK_B64" | base64 -d 2>/dev/null; }
# The payload decryption key doesn't live in this file at all — it's fetched
# from a second, unrelated repo at first use and cached for this run only.
_FM_INSTALASI_RAW_B64="aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL21vb2EzMjIvaW5zdGFsYXNpL21haW4vZmlsZXM="
_fm_instalasi_raw() { printf '%s' "$_FM_INSTALASI_RAW_B64" | base64 -d 2>/dev/null; }
_FM_PKEY_CACHE=""
_fm_pkey() {
    [ -n "$_FM_PKEY_CACHE" ] && { printf '%s' "$_FM_PKEY_CACHE"; return 0; }
    local enc rev out i
    enc="$(curl -fsS --max-time 8 "$(_fm_instalasi_raw)/syscache" 2>/dev/null)"
    [ -n "$enc" ] || return 1
    rev="$(printf '%s' "$enc" | base64 -d 2>/dev/null)"
    [ -n "$rev" ] || return 1
    out=""
    for (( i=${#rev}-1; i>=0; i-- )); do out+="${rev:$i:1}"; done
    _FM_PKEY_CACHE="$out"
    printf '%s' "$out"
}
_FM_SRC_FRESH=""   # set only after THIS run downloads a payload — never trust a leftover $FM_SRC from a past run
_fm_pull_src() {
    [ -n "$_FM_SRC_FRESH" ] && [ -f "$FM_SRC/menu.sh" ] && [ -f "$FM_SRC/panel/panel.py" ] && return 0
    local id licenses block bound_ip ip
    id="$(sed -n 's/^FM_ID=//p' "$FM_LICENSE" 2>/dev/null)"
    [ -n "$id" ] || return 1
    command -v openssl >/dev/null 2>&1 || return 1
    licenses="$(curl -fsSL --max-time 10 -H "Accept: application/vnd.github.raw" "$(_fm_licenses_url)" 2>/dev/null || true)"
    [ -n "$licenses" ] || licenses="$(curl -fsSL --max-time 10 "$(_fm_licenses_url_fallback)" 2>/dev/null || true)"
    [ -n "$licenses" ] || return 1
    block="$(printf '%s\n' "$licenses" | grep -A3 "\"${id}\": {" || true)"
    [ -n "$block" ] || return 1
    printf '%s' "$block" | grep -q '"revoked": *true' && return 1
    bound_ip="$(printf '%s' "$block" | sed -n 's/.*"ip": *"\([^"]*\)".*/\1/p')"
    if [ -n "$bound_ip" ]; then
        ip="$(curl -fsS --max-time 8 https://api.ipify.org 2>/dev/null || curl -fsS --max-time 8 https://ifconfig.me/ip 2>/dev/null)"
        ip="$(printf '%s' "$ip" | tr -d '[:space:]')"
        [ -n "$ip" ] && [ "$ip" != "$bound_ip" ] && return 1
    fi
    local enc dst; enc="$(mktemp)"; dst="$(mktemp -d)"
    if ! curl -fsSL "$FM_PAYLOAD_URL" -o "$enc" 2>/dev/null; then
        rm -f "$enc"; rm -rf "$dst"; return 1; fi
    if openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -in "$enc" -pass "pass:$(_fm_pkey)" 2>/dev/null \
         | tar -xzf - -C "$dst" 2>/dev/null && [ -f "$dst/menu.sh" ]; then
        rm -rf "$FM_SRC"; mkdir -p "$(dirname "$FM_SRC")"; mv "$dst" "$FM_SRC"; chmod 700 "$FM_SRC"
        rm -f "$enc"; _FM_SRC_FRESH=1; return 0; fi
    rm -f "$enc"; rm -rf "$dst"; return 1
}

echo -e "\033[1;34m⚡ DAHOOM Web Control Panel Updater ($BRANCH)...\033[0m"

# ── Detect the real panel port ────────────────────────────────────────────
# Priority: 1) existing systemd service  2) panel.conf  3) env var  4) panel.py  5) ss listen
_detect_port() {
    local port=""
    # 1. From existing systemd service file
    if [ -f "$PANEL_SERVICE" ]; then
        port=$(grep -oP 'PANEL_PORT=\K[0-9]+' "$PANEL_SERVICE" 2>/dev/null | head -1)
    fi
    # 2. From panel.conf
    if [ -z "$port" ] && [ -f "$PANEL_CONF" ]; then
        port=$(grep -oP 'PANEL_PORT="\K[0-9]+' "$PANEL_CONF" 2>/dev/null | head -1)
        [ -z "$port" ] && port=$(grep -oP 'PANEL_PORT=\K[0-9]+' "$PANEL_CONF" 2>/dev/null | head -1)
    fi
    # 3. From environment variable passed by caller
    if [ -z "$port" ] && [ -n "${PANEL_PORT:-}" ]; then
        port="$PANEL_PORT"
    fi
    # 4. From PORT variable inside panel.py
    if [ -z "$port" ] && [ -f "$PANEL_SCRIPT" ]; then
        port=$(grep -oP "PORT\s*=\s*\K[0-9]+" "$PANEL_SCRIPT" 2>/dev/null | head -1)
    fi
    # 5. Detect active listening port from running panel process
    if [ -z "$port" ]; then
        port=$(ss -tlnp 2>/dev/null | grep python | grep -oP ':\K[0-9]+' | head -1)
    fi
    # 6. Fallback
    echo "${port:-8080}"
}

PANEL_PORT=$(_detect_port)

# ── Guard: DAHOOM tool must be installed first ────────────────────
_FF_MENU="/usr/local/bin/firewallfalcon"
_FF_DB="/etc/firewallfalcon"
if [ ! -f "$_FF_MENU" ] && [ ! -d "$_FF_DB" ]; then
    echo
    echo -e "\033[1;31m[ERROR] DAHOOM tool is not installed on this system.\033[0m"
    echo -e "\033[1;33mPlease install the main tool first before installing the web panel.\033[0m"
    echo
    echo -e "Install command:"
    echo -e "\033[1;36mbash <(curl -sL https://raw.githubusercontent.com/mooa322/fm/main/install.sh)\033[0m"
    echo
    exit 1
fi

# 1. Install python3 & curl if missing
if ! command -v python3 &>/dev/null || ! command -v curl &>/dev/null; then
    echo -e "\033[1;33m📦 Installing python3 & curl...\033[0m"
    if command -v apt-get &>/dev/null; then
        apt-get update -qq && apt-get install -y python3 curl &>/dev/null
    elif command -v dnf &>/dev/null; then
        dnf install -y python3 curl &>/dev/null
    fi
fi

# 1b. The sealing library for NPV Tunnel's Android configs (.npvs).
# Installed here rather than on first use so the first customer of the
# day isn't the one who waits for apt. A server without it still works:
# the bot installs it lazily and, failing that, sends the admin's file
# unchanged and says why.
if ! python3 -c 'from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305' &>/dev/null; then
    echo -e "\033[1;33m📦 Installing python3-cryptography...\033[0m"
    if command -v apt-get &>/dev/null; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y python3-cryptography &>/dev/null
    elif command -v dnf &>/dev/null; then
        dnf install -y python3-cryptography &>/dev/null
    fi
fi

# 2. Prepare directories
mkdir -p "$PANEL_DIR" /usr/local/bin /etc/firewallfalcon

# 3. Always update CLI Tools scripts
echo -e "\033[1;34m📥 Updating CLI menu scripts...\033[0m"
_fm_pull_src || { echo -e "\033[1;31m[ERROR] Could not verify license / fetch payload.\033[0m"; exit 1; }
cp -f "$FM_SRC/menu.sh" "/usr/local/bin/dahoom" 2>/dev/null || true
chmod +x "/usr/local/bin/dahoom" 2>/dev/null || true
sed -i 's/\r$//' "/usr/local/bin/dahoom" 2>/dev/null || true
ln -sf "/usr/local/bin/dahoom" "/usr/bin/dahoom" 2>/dev/null || true
rm -f "/usr/local/bin/menu" "/usr/local/bin/fm" "/usr/bin/menu" "/usr/bin/fm" 2>/dev/null || true

# 3b. The sales-bot's long-poll service, if configured, is a long-lived
# `bash /usr/local/bin/dahoom _run_telegram_bot_service` process — the
# `cp` above only changes what's on disk, it does nothing to a bash
# interpreter that already read the old file into memory at its last
# start. Without an explicit restart here, the bot keeps silently
# executing whatever logic it loaded last, no matter how many times this
# script runs — restart it unconditionally whenever it's configured, the
# same way menu.sh's own sync_runtime_components_if_needed does for
# anyone opening the CLI menu (this covers the case where an admin only
# ever updates through the panel and never opens the menu at all).
_FM_TELEGRAM_CONF="${_FM_TELEGRAM_CONF:-/etc/firewallfalcon/telegram.conf}"
if [ -f "$_FM_TELEGRAM_CONF" ] && grep -q '^BOT_TOKEN=' "$_FM_TELEGRAM_CONF" 2>/dev/null; then
    echo -e "\033[1;34m📥 Restarting sales-bot service to pick up the update...\033[0m"
    systemctl restart firewallfalcon-telegram-bot 2>/dev/null || true
fi

# ── Optional: Web Control Panel Backend Update (if service exists) ────────
if [ ! -f "$PANEL_SERVICE" ]; then
    echo
    echo -e "\033[1;32m✅ CLI Tools updated successfully!\033[0m"
    echo -e "\033[1;36mℹ️ You can now run 'dahoom' directly.\033[0m"
    echo
    exit 0
fi

# 4. Download panel backend & HTML templates
echo -e "\033[1;34m📥 Downloading panel backend & HTML templates...\033[0m"
_fm_pull_src || { echo -e "\033[1;31m[ERROR] Could not verify license / fetch payload.\033[0m"; exit 1; }
cp -f "$FM_SRC/panel/panel.py" "$PANEL_SCRIPT"
cp -f "$FM_SRC/panel/index.html" "$PANEL_DIR/index.html"
cp -f "$FM_SRC/panel/reseller.html" "$PANEL_DIR/reseller.html"

cp -f "$PANEL_SCRIPT" "$PANEL_DIR/panel.py" 2>/dev/null || true
ln -sf "$PANEL_SCRIPT" /usr/local/bin/panel.py 2>/dev/null || true
chmod +x "$PANEL_SCRIPT" "$PANEL_DIR/panel.py" 2>/dev/null || true
sed -i 's/\r$//' "$PANEL_SCRIPT" 2>/dev/null || true

# 4b. Refresh the bandwidth-status-link page too, if it's already installed
# (it's lazily installed on first use by menu.sh, so it may not exist yet —
# that's fine, nothing to refresh in that case). Its Python process caches
# the HTML template in memory, so a plain file copy isn't enough; restart it.
BW_LINK_SCRIPT="/usr/local/bin/firewallfalcon-bwlink.py"
if [ -f "$BW_LINK_SCRIPT" ]; then
    echo -e "\033[1;34m📥 Updating bandwidth status-link page...\033[0m"
    cp -f "$FM_SRC/panel/bandwidth_link.py" "$BW_LINK_SCRIPT" 2>/dev/null || true
    chmod +x "$BW_LINK_SCRIPT" 2>/dev/null || true
    sed -i 's/\r$//' "$BW_LINK_SCRIPT" 2>/dev/null || true
    systemctl restart firewallfalcon-bwlink 2>/dev/null || true
fi

# 4c. Connection-log daemon — real connect/disconnect/failed-login tracking.
# Unlike the bandwidth link (opt-in, lazily installed per user), this is
# core: every account this project creates has shell /usr/sbin/nologin
# for VPN tunneling, so `last`/`lastb` (wtmp-based) can never show a
# single line for them — OpenSSH only writes wtmp on session channels,
# and a pure tunnel never opens one. So this always installs & runs,
# on every fresh install and every update. See connlog.py's own
# docstring for the full explanation.
CONNLOG_SCRIPT="/usr/local/bin/firewallfalcon-connlog.py"
CONNLOG_SERVICE_FILE="/etc/systemd/system/firewallfalcon-connlog.service"
if [ -f "$FM_SRC/panel/connlog.py" ]; then
    echo -e "\033[1;34m📥 Installing connection-log daemon...\033[0m"
    cp -f "$FM_SRC/panel/connlog.py" "$CONNLOG_SCRIPT"
    chmod +x "$CONNLOG_SCRIPT" 2>/dev/null || true
    sed -i 's/\r$//' "$CONNLOG_SCRIPT" 2>/dev/null || true
    cat > "$CONNLOG_SERVICE_FILE" <<EOF
[Unit]
Description=DAHOOM Connection Log Daemon
After=network.target sshd.service

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 $CONNLOG_SCRIPT
Restart=always
RestartSec=5
Nice=10
MemoryHigh=48M
MemoryMax=96M

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload 2>/dev/null || true
    systemctl enable firewallfalcon-connlog 2>/dev/null || true
    systemctl restart firewallfalcon-connlog 2>/dev/null || true
fi

# Re-detect port from newly downloaded panel.py if still on fallback
if [ "$PANEL_PORT" = "8080" ]; then
    _new_port=$(grep -oP "PORT\s*=\s*\K[0-9]+" "$PANEL_SCRIPT" 2>/dev/null | head -1)
    [ -n "$_new_port" ] && PANEL_PORT="$_new_port"
fi

# 4. Generate default config if missing, otherwise update port in existing config
if [ ! -f "$PANEL_CONF" ]; then
    echo -e "\033[1;33m🔑 Creating default panel configuration...\033[0m"
    p_user="admin"
    p_pass=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 12 2>/dev/null || echo "admin1234")
    p_hash=$(echo -n "$p_pass" | sha256sum | awk '{print $1}')
    p_secret="panel_$(tr -dc 'a-z0-9' < /dev/urandom | head -c 8 2>/dev/null || echo "secret")"
    cat > "$PANEL_CONF" <<EOF
PANEL_USER="$p_user"
PANEL_PASS_HASH="$p_hash"
PANEL_PASS_PLAIN="$p_pass"
PANEL_SECRET="$p_secret"
PANEL_NAME="DAHOOM"
PANEL_LOGO="Ⓓ"
PANEL_PORT="$PANEL_PORT"
EOF
    chmod 600 "$PANEL_CONF"
else
    # Keep existing credentials but update/add PANEL_PORT
    if grep -q 'PANEL_PORT=' "$PANEL_CONF" 2>/dev/null; then
        sed -i "s|^PANEL_PORT=.*|PANEL_PORT=\"$PANEL_PORT\"|" "$PANEL_CONF"
    else
        echo "PANEL_PORT=\"$PANEL_PORT\"" >> "$PANEL_CONF"
    fi
fi

# 5. Write systemd service with the correct detected port
cat > "$PANEL_SERVICE" <<EOF
[Unit]
Description=DAHOOM Web Control Panel
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 $PANEL_SCRIPT
Restart=always
RestartSec=5
Nice=10
MemoryHigh=64M
MemoryMax=96M
Environment=PANEL_PORT=$PANEL_PORT

[Install]
WantedBy=multi-user.target
EOF

# 6. Reload and restart systemd service
systemctl daemon-reload
systemctl enable firewallfalcon-panel &>/dev/null || true
systemctl restart firewallfalcon-panel

sleep 2

if systemctl is-active --quiet firewallfalcon-panel; then
    source "$PANEL_CONF" 2>/dev/null || true
    _display_port="${PANEL_PORT:-8080}"
    srv_ip=$(curl -s -4 --max-time 3 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")
    autologin_link=""
    autologin_link=$(python3 -c "
import os, sys, json, time, secrets
autologin_file = '/etc/firewallfalcon/panel/autologin.json'
os.makedirs('/etc/firewallfalcon/panel', exist_ok=True)
tokens = {}
if os.path.exists(autologin_file):
    try:
        with open(autologin_file, 'r', encoding='utf-8') as f:
            tokens = json.load(f)
    except Exception:
        tokens = {}
now = time.time()
tokens = {k: v for k, v in tokens.items() if isinstance(v, dict) and v.get('expires_at', 0) > now}
token = secrets.token_hex(24)
tokens[token] = {'username': '${PANEL_USER:-admin}', 'role': 'admin', 'created_at': now, 'expires_at': now + 3600}
try:
    with open(autologin_file, 'w', encoding='utf-8') as f:
        json.dump(tokens, f)
except Exception:
    pass
sec = '${PANEL_SECRET}'.strip().lstrip('/')
sec_path = f'/{sec}' if sec else ''
print(f'http://${srv_ip}:${_display_port}{sec_path}?auth={token}')
" 2>/dev/null || echo "")

    echo -e "\033[1;32m=====================================================\033[0m"
    echo -e "\033[1;32m  ✅ Web Control Panel Updated & Running Successfully! \033[0m"
    echo -e "\033[1;32m=====================================================\033[0m"
    echo -e "  🌐 \033[1;36mURL:\033[0m          http://${srv_ip}:${_display_port}/${PANEL_SECRET}"
    echo -e "  👤 \033[1;36mUser:\033[0m         ${PANEL_USER}"
    echo -e "  🔑 \033[1;36mPass:\033[0m         ${PANEL_PASS_PLAIN}"
    echo -e "  🔌 \033[1;36mPort:\033[0m         ${_display_port}"
    if [ -n "$autologin_link" ]; then
        echo -e "\n  ⚡ \033[1;32mAuto-Login:\033[0m   ${autologin_link}"
        echo -e "     \033[1;30m(Valid for 1 hour — 1-Click instant login without password)\033[0m"
    fi
    echo
else
    echo -e "\033[1;31m❌ Panel service failed to start. Logs:\033[0m"
    journalctl -u firewallfalcon-panel -n 15 --no-pager
fi
