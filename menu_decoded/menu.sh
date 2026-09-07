#!/bin/bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

C_RESET=$'\033[0m'
C_BOLD=$'\033[1m'
C_DIM=$'\033[2m'
C_UL=$'\033[4m'

# ── Aurora palette · cyan → violet ─────────────────────────────
C_RED=$'\033[38;5;204m'      # Rose
C_GREEN=$'\033[38;5;79m'     # Aqua green
C_YELLOW=$'\033[38;5;222m'   # Soft amber
C_BLUE=$'\033[38;5;67m'      # Steel indigo (frames)
C_PURPLE=$'\033[38;5;141m'   # Violet
C_CYAN=$'\033[38;5;51m'      # Cyan
C_WHITE=$'\033[38;5;255m'    # Bright White
C_GRAY=$'\033[38;5;245m'     # Gray
C_ORANGE=$'\033[38;5;87m'    # Ice cyan (brand accent)
C_VIOLET=$'\033[38;5;177m'   # Light violet
C_FRAME=$'\033[38;5;60m'     # Muted frame rule

# Semantic Aliases
C_TITLE=$C_PURPLE
C_CHOICE=$C_CYAN
C_PROMPT=$C_CYAN
C_WARN=$C_YELLOW
C_DANGER=$C_RED
C_STATUS_A=$C_GREEN
C_STATUS_I=$C_GRAY
C_ACCENT=$C_ORANGE

# ── BETA: NEW feature badge ────────────────────────────────────────────
C_NEW=$'\033[38;5;201m'
NEW_TAG="${C_NEW}${C_BOLD}✦new${C_RESET}"

LOGS_DIR="/etc/firewallfalcon/logs"
ADMIN_LOG="/etc/firewallfalcon/admin_actions.log"
_log_action() {
    local action="$1" target="$2" detail="${3:-}" level="${4:-INFO}" cat="${5:-admin}"
    mkdir -p "$(dirname "$ADMIN_LOG")" "$LOGS_DIR" 2>/dev/null
    local ts; ts=$(date '+%F %T')
    printf "%s | %-10s | %-20s | %s\n" "$ts" "$action" "$target" "$detail" >> "$ADMIN_LOG" 2>/dev/null
    
    local f_map="admin_audit.log"
    case "$cat" in
        services) f_map="service_health.log" ;;
        security) f_map="security_alerts.log" ;;
        clients) f_map="client_connections.log" ;;
        reseller) f_map="reseller_audit.log" ;;
        *) f_map="admin_audit.log" ;;
    esac
    printf "%s | %-4s | %-10s | %-14s | %-15s | %s\n" \
        "$ts" "$level" "admin" "$action" "$target" "$detail" >> "$LOGS_DIR/$f_map" 2>/dev/null
}

# ── BETA: Password strength checker (Relaxed & User-Friendly) ───────
check_password_strength() {
    local p="$1"
    local len=${#p}
    if [[ $len -ge 6 ]]; then
        echo -e "  ${C_GREEN}💪 Password rating: Strong${C_RESET}"
    elif [[ $len -ge 4 ]]; then
        echo -e "  ${C_GREEN}🙂 Password rating: Normal${C_RESET}"
    else
        echo -e "  ${C_YELLOW}ℹ️  Password rating: Short (${len} chars)${C_RESET}"
    fi
}

# ── Smooth, Flicker-Free Interactive Progress Bar Helper ──────────────────
show_progress_bar() {
    local label="$1"
    local steps="${2:-25}"
    local delay="${3:-0.02}"
    local width=28
    local i pct filled empty bar_str f e

    # Hide cursor to eliminate blinking/flickering
    tput civis 2>/dev/null || true

    printf "  ${C_CYAN}${C_BOLD}▸${C_RESET} ${C_WHITE}%s${C_RESET}\n" "$label"
    for ((i=1; i<=steps; i++)); do
        pct=$(( (i * 100) / steps ))
        filled=$(( (pct * width) / 100 ))
        empty=$(( width - filled ))

        bar_str=""
        # leading run in cyan, the last filled cell in violet: a two-tone sweep
        for ((f=0; f<filled; f++)); do bar_str+="━"; done
        e_str=""
        for ((e=0; e<empty; e++)); do e_str+="━"; done

        printf "\r  ${C_CYAN}%s${C_VIOLET}%s${C_FRAME}%s${C_RESET}  ${C_CYAN}${C_BOLD}%3d%%${C_RESET}" \
               "${bar_str:0:$((filled>0?filled-1:0))}" "${bar_str:0:$((filled>0?1:0))}" "$e_str" "$pct"
        sleep "$delay"
    done
    printf " ${C_GREEN}✔ Done${C_RESET}\n\n"

    # Restore cursor
    tput cnorm 2>/dev/null || true
}


DB_DIR="/etc/firewallfalcon"
DB_FILE="$DB_DIR/users.db"
INSTALL_FLAG_FILE="$DB_DIR/.install"
BADVPN_SERVICE_FILE="/etc/systemd/system/badvpn.service"
BADVPN_BUILD_DIR="/root/badvpn-build"
HAPROXY_CONFIG="/etc/haproxy/haproxy.cfg"
NGINX_CONFIG_FILE="/etc/nginx/sites-available/default"
SSL_CERT_DIR="/etc/firewallfalcon/ssl"
SSL_CERT_FILE="$SSL_CERT_DIR/firewallfalcon.pem"
SSL_CERT_CHAIN_FILE="$SSL_CERT_DIR/firewallfalcon.crt"
SSL_CERT_KEY_FILE="$SSL_CERT_DIR/firewallfalcon.key"
EDGE_CERT_INFO_FILE="$DB_DIR/edge_cert.conf"
NGINX_PORTS_FILE="$DB_DIR/nginx_ports.conf"
EDGE_PUBLIC_HTTP_PORT="80"
EDGE_PUBLIC_TLS_PORT="443"
NGINX_INTERNAL_HTTP_PORT="8880"
NGINX_INTERNAL_TLS_PORT="8443"
HAPROXY_INTERNAL_DECRYPT_PORT="10443"
DNSTT_SERVICE_FILE="/etc/systemd/system/dnstt.service"
DNSTT_BINARY="/usr/local/bin/dnstt-server"
DNSTT_KEYS_DIR="/etc/firewallfalcon/dnstt"
DNSTT_CONFIG_FILE="$DB_DIR/dnstt_info.conf"
DNS_INFO_FILE="$DB_DIR/dns_info.conf"
UDP_CUSTOM_DIR="/root/udp"
UDP_CUSTOM_SERVICE_FILE="/etc/systemd/system/udp-custom.service"
UDPGW_BINARY="/usr/local/bin/udpgw"
UDPGW_SERVICE_FILE="/etc/systemd/system/udpgw.service"
SSH_BANNER_FILE="/etc/bannerssh"
FALCONPROXY_SERVICE_FILE="/etc/systemd/system/falconproxy.service"
FALCONPROXY_BINARY="/usr/local/bin/falconproxy"
FALCONPROXY_CONFIG_FILE="$DB_DIR/falconproxy_config.conf"
LIMITER_SCRIPT="/usr/local/bin/firewallfalcon-limiter.sh"
LIMITER_SERVICE="/etc/systemd/system/firewallfalcon-limiter.service"
BANDWIDTH_DIR="$DB_DIR/bandwidth"
BANDWIDTH_SCRIPT="/usr/local/bin/firewallfalcon-bandwidth.sh"
BANDWIDTH_SERVICE="/etc/systemd/system/firewallfalcon-bandwidth.service"
LEGACY_BANDWIDTH_DIR="/usr/local/bin/firewallfalcon-bandwidth"
TRIAL_CLEANUP_SCRIPT="/usr/local/bin/firewallfalcon-trial-cleanup.sh"
LOGIN_INFO_SCRIPT="/usr/local/bin/firewallfalcon-login-info.sh"
SSHD_FF_CONFIG="/etc/ssh/sshd_config.d/firewallfalcon.conf"

# --- Web Panel Variables ---
PANEL_SCRIPT="/usr/local/bin/firewallfalcon-panel.py"
PANEL_HTML_DIR="$DB_DIR/panel"
PANEL_HTML_FILE="$DB_DIR/panel/index.html"
PANEL_CONF="$DB_DIR/panel.conf"
PANEL_SERVICE_FILE="/etc/systemd/system/firewallfalcon-panel.service"
PANEL_PORT=44380
PANEL_REPO_BASE="https://raw.githubusercontent.com/mooa322/fm/new_panel/panel"

# ── Licensed payload source ──────────────────────────────────────────
# Access is gated by licenses.json on the same public repo: the saved
# license id must exist there, not be revoked, and — if the seller
# pre-registered an IP for it — this server's IP must match. The
# licenses.json URL is base64-obfuscated here so it isn't a plain grep
# hit in the decrypted source; see tools/manage-license.sh on the seller
# side and tools/SELLING.md for the full trade-off this implies.
FM_LICENSE="/etc/firewallfalcon/.license"
FM_SRC="/etc/firewallfalcon/.src"
FM_PAYLOAD_URL="https://raw.githubusercontent.com/mooa322/fm/main/menu.enc"
FM_PKEY="5YgZ9dsnTEKkBgehniA2lYGEuV90wZ2LKmu5okur4"
_FM_LIC_B64="aHR0cHM6Ly9hcGkuZ2l0aHViLmNvbS9yZXBvcy9tb29hMzIyL2ZtL2NvbnRlbnRzL2xpY2Vuc2VzLmpzb24/cmVmPW1haW4="
_fm_licenses_url() { printf '%s' "$_FM_LIC_B64" | base64 -d 2>/dev/null; }

# Re-validates the saved license id against licenses.json: exists, not
# revoked, and IP-matched if the seller bound it. Fails OPEN on network
# errors (so a network hiccup doesn't lock a paying user out), but fails
# CLOSED the moment the list is reachable and says revoked / wrong IP.
_fm_license_check() {
    local id licenses block bound_ip ip
    id="$(sed -n 's/^FM_ID=//p' "$FM_LICENSE" 2>/dev/null)"
    [ -n "$id" ] || return 0
    licenses="$(curl -fsSL --max-time 8 -H "Accept: application/vnd.github.raw" "$(_fm_licenses_url)" 2>/dev/null || true)"
    [ -n "$licenses" ] || return 0
    block="$(printf '%s\n' "$licenses" | grep -A3 "\"${id}\": {" || true)"
    if [ -z "$block" ]; then
        echo -e "\n  ${C_RED}${C_BOLD}✖ License '${id}' is no longer valid.${C_RESET} ${C_GRAY}Contact the provider.${C_RESET}\n"
        exit 1
    fi
    if printf '%s' "$block" | grep -q '"revoked": *true'; then
        echo -e "\n  ${C_RED}${C_BOLD}✖ License '${id}' has been revoked.${C_RESET} ${C_GRAY}Contact the provider.${C_RESET}\n"
        exit 1
    fi
    bound_ip="$(printf '%s' "$block" | sed -n 's/.*"ip": *"\([^"]*\)".*/\1/p')"
    if [ -n "$bound_ip" ]; then
        ip="$(curl -fsS --max-time 6 https://api.ipify.org 2>/dev/null || curl -fsS --max-time 6 https://ifconfig.me/ip 2>/dev/null)"
        ip="$(printf '%s' "$ip" | tr -d '[:space:]')"
        if [ -n "$ip" ] && [ "$ip" != "$bound_ip" ]; then
            echo -e "\n  ${C_RED}${C_BOLD}✖ License '${id}' is registered to a different server.${C_RESET}\n"
            exit 1
        fi
    fi
    return 0
}

_fm_pull_src() {
    local id licenses block bound_ip ip
    id="$(sed -n 's/^FM_ID=//p' "$FM_LICENSE" 2>/dev/null)"
    [ -n "$id" ] || return 1
    command -v openssl >/dev/null 2>&1 || return 1
    licenses="$(curl -fsSL --max-time 10 -H "Accept: application/vnd.github.raw" "$(_fm_licenses_url)" 2>/dev/null || true)"
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
        rm -f "$enc"; rm -rf "$dst"; return 1
    fi
    if openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -in "$enc" -pass "pass:${FM_PKEY}" 2>/dev/null \
         | tar -xzf - -C "$dst" 2>/dev/null && [ -f "$dst/menu.sh" ]; then
        rm -rf "$FM_SRC"; mkdir -p "$(dirname "$FM_SRC")"; mv "$dst" "$FM_SRC"; chmod 700 "$FM_SRC"
        rm -f "$enc"; return 0
    fi
    rm -f "$enc"; rm -rf "$dst"; return 1
}
_fm_panel_file() {   # <name under panel/> <dest>
    _fm_pull_src || return 1
    cp -f "$FM_SRC/panel/$1" "$2"
}

# --- ZiVPN Variables ---
ZIVPN_DIR="/etc/zivpn"
ZIVPN_BIN="/usr/local/bin/zivpn"
ZIVPN_SERVICE_FILE="/etc/systemd/system/zivpn.service"
ZIVPN_CONFIG_FILE="$ZIVPN_DIR/config.json"
ZIVPN_CERT_FILE="$ZIVPN_DIR/zivpn.crt"
ZIVPN_KEY_FILE="$ZIVPN_DIR/zivpn.key"

DESEC_TOKEN="79BLgHoLMdeZeRUnPJeQP3P6hzf9"
DESEC_DOMAIN="aljailane.dedyn.io"
if [ -f "/etc/firewallfalcon/desec.conf" ]; then
    source "/etc/firewallfalcon/desec.conf" 2>/dev/null
fi

SELECTED_USER=""
UNINSTALL_MODE="interactive"
BANNER_CACHE_TTL=15
BANNER_CACHE_TS=0
BANNER_CACHE_OS_NAME=""
BANNER_CACHE_UP_TIME=""
BANNER_CACHE_RAM_USAGE=""
BANNER_CACHE_CPU_LOAD=""
BANNER_CACHE_ONLINE_USERS=0
BANNER_CACHE_TOTAL_USERS=0
SSH_SESSION_CACHE_TTL=10
SSH_SESSION_CACHE_TS=0
SSH_SESSION_CACHE_DB_MTIME=0
SSH_SESSION_TOTAL=0
APT_CACHE_READY=0
FF_USERS_GROUP="ffusers"
declare -A SSH_SESSION_COUNTS=()
declare -A SSH_SESSION_PIDS=()

# --- Package Manager Abstraction ---
FF_PKG_MGR=""
_detect_pkg_manager() {
    if command -v apt-get &>/dev/null; then
        FF_PKG_MGR="apt"
    elif command -v dnf &>/dev/null; then
        FF_PKG_MGR="dnf"
    elif command -v yum &>/dev/null; then
        FF_PKG_MGR="yum"
    elif command -v zypper &>/dev/null; then
        FF_PKG_MGR="zypper"
    elif command -v pacman &>/dev/null; then
        FF_PKG_MGR="pacman"
    else
        echo -e "${C_RED}❌ No supported package manager found (apt/dnf/yum/zypper/pacman).${C_RESET}"
        exit 1
    fi
}
_detect_pkg_manager

_map_pkg_names() {
    local -a result=()
    local pkg
    for pkg in "$@"; do
        case "$FF_PKG_MGR" in
            dnf|yum)
                case "$pkg" in
                    build-essential) result+=(gcc gcc-c++ make) ;;
                    libssl-dev) result+=(openssl-devel) ;;
                    libnspr4-dev) result+=(nspr-devel) ;;
                    libnss3-dev) result+=(nss-devel) ;;
                    nginx-common) result+=(nginx) ;;
                    pkg-config) result+=(pkgconf) ;;
                    *) result+=("$pkg") ;;
                esac ;;
            zypper)
                case "$pkg" in
                    build-essential) result+=(gcc gcc-c++ make) ;;
                    libssl-dev) result+=(libopenssl-devel) ;;
                    libnspr4-dev) result+=(mozilla-nspr-devel) ;;
                    libnss3-dev) result+=(mozilla-nss-devel) ;;
                    nginx-common) result+=(nginx) ;;
                    *) result+=("$pkg") ;;
                esac ;;
            pacman)
                case "$pkg" in
                    build-essential) result+=(base-devel) ;;
                    libssl-dev) result+=(openssl) ;;
                    libnspr4-dev) result+=(nspr) ;;
                    libnss3-dev) result+=(nss) ;;
                    nginx-common) result+=(nginx) ;;
                    bc) result+=(bc) ;;
                    *) result+=("$pkg") ;;
                esac ;;
            *) result+=("$pkg") ;;
        esac
    done
    printf '%s\n' "${result[@]}"
}

if [[ $EUID -ne 0 ]]; then
   echo -e "${C_RED}❌ Error: This script requires root privileges to run.${C_RESET}"
   exit 1
fi

get_ubuntu_codename() {
    local codename=""

    if [[ -r /etc/os-release ]]; then
        codename=$(awk -F= '/^(VERSION_CODENAME|UBUNTU_CODENAME)=/{gsub(/"/, "", $2); if ($2 != "") { print $2; exit }}' /etc/os-release 2>/dev/null)
    fi

    if [[ -z "$codename" ]] && command -v lsb_release &>/dev/null; then
        codename=$(lsb_release -sc 2>/dev/null)
    fi

    echo "$codename"
}

is_known_eol_ubuntu_codename() {
    case "$1" in
        yakkety|zesty|artful|cosmic|disco|eoan|groovy|hirsute|impish|kinetic|lunar|mantic|oracular|plucky)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

rewrite_ubuntu_apt_sources() {
    local mode="$1"
    local os_id=""
    local changed=false
    local file backup_file
    local from_archive to_archive from_security to_security from_ports to_ports
    local -a source_files=("/etc/apt/sources.list" /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources)

    if [[ -r /etc/os-release ]]; then
        os_id=$(awk -F= '/^ID=/{gsub(/"/, "", $2); print $2; exit}' /etc/os-release 2>/dev/null)
    fi
    [[ "$os_id" == "ubuntu" ]] || return 1

    case "$mode" in
        primary)
            from_archive='https?://([A-Za-z0-9-]+\.)?archive\.ubuntu\.com/ubuntu'
            to_archive='http://archive.ubuntu.com/ubuntu'
            from_security='https?://security\.ubuntu\.com/ubuntu'
            to_security='http://security.ubuntu.com/ubuntu'
            from_ports='https?://ports\.ubuntu\.com/ubuntu-ports'
            to_ports='http://ports.ubuntu.com/ubuntu-ports'
            ;;
        old-releases)
            from_archive='https?://([A-Za-z0-9-]+\.)?archive\.ubuntu\.com/ubuntu'
            to_archive='http://old-releases.ubuntu.com/ubuntu'
            from_security='https?://security\.ubuntu\.com/ubuntu'
            to_security='http://old-releases.ubuntu.com/ubuntu'
            from_ports='https?://ports\.ubuntu\.com/ubuntu-ports'
            to_ports='http://old-releases.ubuntu.com/ubuntu'
            ;;
        *)
            return 1
            ;;
    esac

    for file in "${source_files[@]}"; do
        [[ -f "$file" ]] || continue
        if grep -Eq "$from_archive|$from_security|$from_ports" "$file" 2>/dev/null; then
            backup_file="${file}.bak.firewallfalcon"
            [[ -f "$backup_file" ]] || cp "$file" "$backup_file" 2>/dev/null || true
            sed -i -E \
                -e "s|$from_archive|$to_archive|g" \
                -e "s|$from_security|$to_security|g" \
                -e "s|$from_ports|$to_ports|g" \
                "$file" 2>/dev/null
            changed=true
        fi
    done

    $changed
}

repair_ubuntu_apt_mirrors() {
    rewrite_ubuntu_apt_sources "primary"
}

switch_ubuntu_to_old_releases() {
    local codename
    codename=$(get_ubuntu_codename)
    [[ -n "$codename" ]] || return 1
    is_known_eol_ubuntu_codename "$codename" || return 1
    rewrite_ubuntu_apt_sources "old-releases"
}

ff_apt_update() {
    local -a apt_opts=(
        -o Acquire::Retries=3
        -o Acquire::ForceIPv4=true
        -o Acquire::http::Timeout=20
        -o Acquire::https::Timeout=20
        -o Acquire::http::Pipeline-Depth=0
    )

    if (( APT_CACHE_READY == 1 )); then
        return 0
    fi

    if DEBIAN_FRONTEND=noninteractive apt-get "${apt_opts[@]}" update; then
        APT_CACHE_READY=1
        return 0
    fi

    if repair_ubuntu_apt_mirrors; then
        echo -e "${C_YELLOW}⚠️ APT mirror timed out. Switching Ubuntu sources to archive.ubuntu.com and retrying...${C_RESET}"
        apt-get clean >/dev/null 2>&1 || true
        if DEBIAN_FRONTEND=noninteractive apt-get "${apt_opts[@]}" update; then
            APT_CACHE_READY=1
            return 0
        fi
    fi

    if switch_ubuntu_to_old_releases; then
        echo -e "${C_YELLOW}⚠️ Detected an end-of-life Ubuntu release. Switching APT sources to old-releases.ubuntu.com and retrying...${C_RESET}"
        apt-get clean >/dev/null 2>&1 || true
        if DEBIAN_FRONTEND=noninteractive apt-get "${apt_opts[@]}" update; then
            APT_CACHE_READY=1
            return 0
        fi
    fi

    echo -e "${C_RED}❌ Failed to refresh package lists. Please check VPS network, DNS, or blocked Ubuntu mirrors.${C_RESET}"
    return 1
}

ff_apt_install() {
    local -a packages=("$@")
    (( ${#packages[@]} > 0 )) || return 0

    ff_apt_update || return 1
    DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Use-Pty=0 install "${packages[@]}"
}

ff_apt_purge() {
    local -a packages=("$@")
    (( ${#packages[@]} > 0 )) || return 0
    DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Use-Pty=0 purge "${packages[@]}"
}

ff_pkg_install() {
    local -a packages=("$@")
    (( ${#packages[@]} > 0 )) || return 0
    local -a mapped=()
    mapfile -t mapped < <(_map_pkg_names "${packages[@]}")
    case "$FF_PKG_MGR" in
        apt) ff_apt_install "${mapped[@]}" ;;
        dnf) dnf install -y -q "${mapped[@]}" ;;
        yum) yum install -y -q "${mapped[@]}" ;;
        zypper) zypper install -y -q "${mapped[@]}" ;;
        pacman) pacman -S --noconfirm --needed "${mapped[@]}" ;;
        *) echo -e "${C_RED}❌ Unsupported package manager.${C_RESET}"; return 1 ;;
    esac
}

ff_pkg_purge() {
    local -a packages=("$@")
    (( ${#packages[@]} > 0 )) || return 0
    local -a mapped=()
    mapfile -t mapped < <(_map_pkg_names "${packages[@]}")
    case "$FF_PKG_MGR" in
        apt) ff_apt_purge "${mapped[@]}" ;;
        dnf) dnf remove -y -q "${mapped[@]}" ;;
        yum) yum remove -y -q "${mapped[@]}" ;;
        zypper) zypper remove -y "${mapped[@]}" ;;
        pacman) pacman -Rns --noconfirm "${mapped[@]}" 2>/dev/null ;;
        *) echo -e "${C_RED}❌ Unsupported package manager.${C_RESET}"; return 1 ;;
    esac
}

ff_pkg_autoremove() {
    case "$FF_PKG_MGR" in
        apt) apt-get autoremove -y >/dev/null 2>&1 ;;
        dnf) dnf autoremove -y -q >/dev/null 2>&1 ;;
        yum) yum autoremove -y -q >/dev/null 2>&1 ;;
        zypper) zypper packages --unneeded 2>/dev/null | awk -F'|' 'NR>3{print $3}' | xargs -r zypper remove -y >/dev/null 2>&1 ;;
        pacman) pacman -Qdtq 2>/dev/null | xargs -r pacman -Rns --noconfirm >/dev/null 2>&1 ;;
    esac
    return 0
}

ff_pkg_is_installed() {
    local pkg="$1"
    case "$FF_PKG_MGR" in
        apt) dpkg -s "$pkg" &>/dev/null ;;
        dnf|yum) rpm -q "$pkg" &>/dev/null ;;
        zypper) rpm -q "$pkg" &>/dev/null ;;
        pacman) pacman -Q "$pkg" &>/dev/null ;;
    esac
}

# Mandatory Dependency Check (Added jq and curl)
check_environment() {
    local missing_packages=()
    local cmd

    for cmd in bc jq curl wget; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_packages+=("$cmd")
        fi
    done

    if (( ${#missing_packages[@]} > 0 )); then
        echo -e "${C_YELLOW}⚠️ Installing missing dependencies: ${missing_packages[*]}${C_RESET}"
        ff_pkg_install "${missing_packages[@]}" >/dev/null 2>&1 || {
            echo -e "${C_RED}❌ Error: Failed to install required dependencies: ${missing_packages[*]}.${C_RESET}"
            exit 1
        }
    fi
}

ensure_firewallfalcon_dirs() {
    mkdir -p "$DB_DIR" "$SSL_CERT_DIR" "$BANDWIDTH_DIR" /etc/ssh/sshd_config.d
    touch "$DB_FILE"
}

ensure_firewallfalcon_system_group() {
    getent group "$FF_USERS_GROUP" >/dev/null 2>&1 || groupadd "$FF_USERS_GROUP" >/dev/null 2>&1 || true
}

db_has_user() {
    [[ -f "$DB_FILE" ]] || return 1
    awk -F: -v target="$1" '$1 == target { found=1; exit } END { exit(found ? 0 : 1) }' "$DB_FILE"
}

is_firewallfalcon_orphan_user() {
    local username="$1"
    local passwd_line system_user _ uid _ home shell

    passwd_line=$(getent passwd "$username" 2>/dev/null) || return 1
    IFS=: read -r system_user _ uid _ _ home shell <<< "$passwd_line"
    [[ "$uid" =~ ^[0-9]+$ ]] || return 1
    db_has_user "$username" && return 1

    if id -nG "$username" 2>/dev/null | tr ' ' '\n' | grep -Fxq "$FF_USERS_GROUP"; then
        return 0
    fi

    (( uid >= 1000 )) || return 1
    [[ "$home" == "/home/$username" || "$home" == /home/* ]] || return 1

    case "$shell" in
        /usr/sbin/nologin|/usr/bin/false|/bin/false) return 0 ;;
    esac

    return 1
}

get_firewallfalcon_orphan_users() {
    local username
    while IFS=: read -r username _rest; do
        [[ -n "$username" ]] || continue
        if is_firewallfalcon_orphan_user "$username"; then
            echo "$username"
        fi
    done < /etc/passwd
}

get_firewallfalcon_known_users() {
    local username
    local -A seen_users=()

    if [[ -f "$DB_FILE" ]]; then
        while IFS=: read -r username _rest; do
            [[ -n "$username" && "$username" != \#* ]] || continue
            seen_users["$username"]=1
        done < "$DB_FILE"
    fi

    while IFS= read -r username; do
        [[ -n "$username" ]] && seen_users["$username"]=1
    done < <(get_firewallfalcon_orphan_users)

    (( ${#seen_users[@]} > 0 )) || return 0
    printf "%s\n" "${!seen_users[@]}" | sort
}

delete_firewallfalcon_user_accounts() {
    local -a users_to_delete=("$@")
    local username

    [[ ${#users_to_delete[@]} -gt 0 ]] || return 0

    for username in "${users_to_delete[@]}"; do
        [[ -n "$username" ]] || continue
        killall -u "$username" -9 &>/dev/null
        pkill -9 -u "$username" &>/dev/null
        sleep 0.5
        if id "$username" &>/dev/null; then
            if userdel -rf "$username" &>/dev/null; then
                echo -e " ✅ System user '${C_YELLOW}$username${C_RESET}' deleted."
            else
                # Retry after harder kill
                pkill -9 -u "$username" &>/dev/null
                sleep 1
                if userdel -rf "$username" &>/dev/null; then
                    echo -e " ✅ System user '${C_YELLOW}$username${C_RESET}' deleted (retry)."
                else
                    echo -e " ❌ Failed to delete system user '${C_YELLOW}$username${C_RESET}'."
                fi
            fi
        else
            echo -e " ℹ️ System user '${C_YELLOW}$username${C_RESET}' was already missing. Removing manager data only."
        fi
        rm -f "$BANDWIDTH_DIR/${username}.usage"
        rm -f "$BANDWIDTH_DIR/${username}.daily_usage"
        rm -f "$BANDWIDTH_DIR/${username}.conn_locked"
        rm -f "$BANDWIDTH_DIR/${username}.daily_locked"
        rm -rf "$BANDWIDTH_DIR/pidtrack/${username}"
    done

    if [[ -f "$DB_FILE" ]]; then
        local db_tmp
        db_tmp=$(mktemp)
        awk -F: 'NR==FNR { drop[$1]=1; next } !($1 in drop)' <(printf "%s\n" "${users_to_delete[@]}") "$DB_FILE" > "$db_tmp" && mv "$db_tmp" "$DB_FILE"
        rm -f "$db_tmp" 2>/dev/null
    fi

    invalidate_banner_cache
    refresh_dynamic_banner_routing_if_enabled
}

require_interactive_terminal() {
    if [[ ! -t 0 || ! -t 1 ]]; then
        echo -e "${C_RED}❌ Error: The DAHOOM menu must be run from an interactive terminal.${C_RESET}"
        exit 1
    fi
}

initial_setup() {
    echo -e "${C_BLUE}⚙️ Initializing DAHOOM setup...${C_RESET}"
    check_environment
    
    ensure_firewallfalcon_dirs
    ensure_firewallfalcon_system_group
    
    echo -e "${C_BLUE}🔹 Configuring user limiter service...${C_RESET}"
    setup_limiter_service
    
    echo -e "${C_BLUE}🔹 Configuring bandwidth monitoring service...${C_RESET}"
    setup_bandwidth_service
    
    echo -e "${C_BLUE}🔹 Installing trial account cleanup script...${C_RESET}"
    setup_trial_cleanup_script
    
    echo -e "${C_BLUE}🔹 Configuring health guard service...${C_RESET}"
    setup_health_service
    
    echo -e "${C_BLUE}🔹 Deploying dynamic DAHOOM server login banner (MOTD)...${C_RESET}"
    setup_falcon_server_motd

    echo -e "${C_BLUE}🔹 Linking 'fm' and 'menu' command shortcuts...${C_RESET}"
    ln -sf "/usr/local/bin/firewallfalcon" "/usr/local/bin/fm" 2>/dev/null || true
    ln -sf "/usr/local/bin/firewallfalcon" "/usr/bin/fm" 2>/dev/null || true
    ln -sf "/usr/local/bin/firewallfalcon" "/usr/local/bin/menu" 2>/dev/null || true
    ln -sf "/usr/local/bin/firewallfalcon" "/usr/bin/menu" 2>/dev/null || true
    
    echo -e "${C_BLUE}🔹 Cleaning legacy dynamic SSH banner hooks...${C_RESET}"
    disable_dynamic_ssh_banner_system
    systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || true
    
    if [ ! -f "$INSTALL_FLAG_FILE" ]; then
        touch "$INSTALL_FLAG_FILE"
    fi
    echo -e "${C_GREEN}✅ Setup finished.${C_RESET}"
}

_is_valid_ipv4() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    else
        return 1
    fi
}

check_and_open_firewall_port() {
    local port="$1"
    local protocol="${2:-tcp}"
    local firewall_detected=false

    if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
        firewall_detected=true
        if ! ufw status | grep -qw "$port/$protocol"; then
            echo -e "${C_YELLOW}🔥 UFW firewall is active and port ${port}/${protocol} is closed.${C_RESET}"
            read -p "👉 Do you want to open this port now? (y/n): " confirm
            if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                ufw allow "$port/$protocol"
                echo -e "${C_GREEN}✅ Port ${port}/${protocol} has been opened in UFW.${C_RESET}"
            else
                echo -e "${C_RED}❌ Warning: Port ${port}/${protocol} was not opened. The service may not work correctly.${C_RESET}"
                return 1
            fi
        else
             echo -e "${C_GREEN}✅ Port ${port}/${protocol} is already open in UFW.${C_RESET}"
        fi
    fi

    if command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
        firewall_detected=true
        if ! firewall-cmd --list-ports --permanent | grep -qw "$port/$protocol"; then
            echo -e "${C_YELLOW}🔥 firewalld is active and port ${port}/${protocol} is not open.${C_RESET}"
            read -p "👉 Do you want to open this port now? (y/n): " confirm
            if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                firewall-cmd --add-port="$port/$protocol" --permanent
                firewall-cmd --reload
                echo -e "${C_GREEN}✅ Port ${port}/${protocol} has been opened in firewalld.${C_RESET}"
            else
                echo -e "${C_RED}❌ Warning: Port ${port}/${protocol} was not opened. The service may not work correctly.${C_RESET}"
                return 1
            fi
        else
            echo -e "${C_GREEN}✅ Port ${port}/${protocol} is already open in firewalld.${C_RESET}"
        fi
    fi

    if ! $firewall_detected; then
        echo -e "${C_BLUE}ℹ️ No active firewall (UFW or firewalld) detected. Assuming ports are open.${C_RESET}"
    fi
    return 0
}

check_and_open_firewall_port_range() {
    local port_range="$1"
    local protocol="${2:-tcp}"
    local firewall_detected=false

    if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
        firewall_detected=true
        if ! ufw status | grep -Fq "$port_range/$protocol"; then
            echo -e "${C_YELLOW}🔥 UFW firewall is active and range ${port_range}/${protocol} is closed.${C_RESET}"
            read -p "👉 Do you want to open this port range now? (y/n): " confirm
            if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                ufw allow "$port_range/$protocol"
                echo -e "${C_GREEN}✅ Range ${port_range}/${protocol} has been opened in UFW.${C_RESET}"
            else
                echo -e "${C_RED}❌ Warning: Range ${port_range}/${protocol} was not opened. The service may not work correctly.${C_RESET}"
                return 1
            fi
        else
            echo -e "${C_GREEN}✅ Range ${port_range}/${protocol} is already open in UFW.${C_RESET}"
        fi
    fi

    if command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
        firewall_detected=true
        if ! firewall-cmd --quiet --query-port="$port_range/$protocol"; then
            echo -e "${C_YELLOW}🔥 firewalld is active and range ${port_range}/${protocol} is not open.${C_RESET}"
            read -p "👉 Do you want to open this port range now? (y/n): " confirm
            if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                firewall-cmd --add-port="$port_range/$protocol" --permanent
                firewall-cmd --reload
                echo -e "${C_GREEN}✅ Range ${port_range}/${protocol} has been opened in firewalld.${C_RESET}"
            else
                echo -e "${C_RED}❌ Warning: Range ${port_range}/${protocol} was not opened. The service may not work correctly.${C_RESET}"
                return 1
            fi
        else
            echo -e "${C_GREEN}✅ Range ${port_range}/${protocol} is already open in firewalld.${C_RESET}"
        fi
    fi

    if ! $firewall_detected; then
        echo -e "${C_BLUE}ℹ️ No active firewall (UFW or firewalld) detected. Assuming range ${port_range}/${protocol} is open.${C_RESET}"
    fi
    return 0
}

check_and_free_ports() {
    local ports_to_check=("$@")
    for port in "${ports_to_check[@]}"; do
        echo -e "\n${C_BLUE}🔎 Checking if port $port is available...${C_RESET}"
        local conflicting_process_info
        conflicting_process_info=$(
            ss -H -lntp "( sport = :$port )" 2>/dev/null
            ss -H -lunp "( sport = :$port )" 2>/dev/null
        )
        
        if [[ -n "$conflicting_process_info" ]]; then
            local conflicting_pid
            conflicting_pid=$(echo "$conflicting_process_info" | grep -oP 'pid=\K[0-9]+' | head -n 1)
            local conflicting_name
            conflicting_name=$(echo "$conflicting_process_info" | grep -oP 'users:\(\("(\K[^"]+)' | head -n 1)
            
            echo -e "${C_YELLOW}⚠️ Warning: Port $port is in use by process '${conflicting_name:-unknown}' (PID: ${conflicting_pid:-N/A}).${C_RESET}"
            read -p "👉 Do you want to attempt to stop this process? (y/n): " kill_confirm
            if [[ "$kill_confirm" == "y" || "$kill_confirm" == "Y" ]]; then
                if [[ -z "$conflicting_pid" ]]; then
                    echo -e "${C_RED}❌ Could not determine which PID owns port $port. Please free it manually.${C_RESET}"
                    return 1
                fi
                echo -e "${C_GREEN}🛑 Stopping process PID $conflicting_pid...${C_RESET}"
                systemctl stop "$(ps -p "$conflicting_pid" -o comm=)" &>/dev/null || kill -9 "$conflicting_pid"
                sleep 2
                
                if ss -H -lntp "( sport = :$port )" 2>/dev/null | grep -q . || ss -H -lunp "( sport = :$port )" 2>/dev/null | grep -q .; then
                     echo -e "${C_RED}❌ Failed to free port $port. Please handle it manually. Aborting.${C_RESET}"
                     return 1
                else
                     echo -e "${C_GREEN}✅ Port $port has been successfully freed.${C_RESET}"
                fi
            else
                echo -e "${C_RED}❌ Cannot proceed without freeing port $port. Aborting.${C_RESET}"
                return 1
            fi
        else
            echo -e "${C_GREEN}✅ Port $port is free to use.${C_RESET}"
        fi
    done
    return 0
}

setup_limiter_service() {
    # Combined limiter + bandwidth monitoring
    cat > "$LIMITER_SCRIPT" << 'EOF'
#!/bin/bash
# DAHOOM limiter version 2026-07-23.8
DB_FILE="/etc/firewallfalcon/users.db"
BW_DIR="/etc/firewallfalcon/bandwidth"
PID_DIR="$BW_DIR/pidtrack"
BANNER_DIR="/etc/firewallfalcon/banners"
SCAN_INTERVAL=10
CONN_LOCK_DURATION=60

mkdir -p "$BW_DIR" "$PID_DIR"
shopt -s nullglob

write_banner_if_changed() {
    local user="$1"
    local content="$2"
    local banner_file="$BANNER_DIR/${user}.txt"
    local tmp_file="${banner_file}.tmp"

    printf "%s" "$content" > "$tmp_file"
    if ! cmp -s "$tmp_file" "$banner_file" 2>/dev/null; then
        mv "$tmp_file" "$banner_file"
    else
        rm -f "$tmp_file"
    fi
}

# Excess sessions are killed immediately every scan cycle. No account locking.

while true; do
    if [[ ! -s "$DB_FILE" ]]; then
        sleep "$SCAN_INTERVAL"
        continue
    fi
    
    # Daily reset logic
    today=$(date +%Y-%m-%d)
    if [[ ! -f "$BW_DIR/current_date" ]]; then
        echo "$today" > "$BW_DIR/current_date"
    fi
    saved_date=$(cat "$BW_DIR/current_date" 2>/dev/null || echo "$today")
    if [[ "$today" != "$saved_date" ]]; then
        # New day! Reset daily usage and unlock users locked due to daily limit
        rm -f "$BW_DIR/"*.daily_usage 2>/dev/null
        for locked_file in "$BW_DIR/"*.daily_locked; do
            [[ -f "$locked_file" ]] || continue
            locked_user=$(basename "$locked_file" .daily_locked)
            usermod -U "$locked_user" &>/dev/null
            rm -f "$locked_file"
        done
        echo "$today" > "$BW_DIR/current_date"
    fi

    # Connection limit auto-unlock: check marker files and unlock after CONN_LOCK_DURATION seconds
    for conn_lock_file in "$BW_DIR/"*.conn_locked; do
        [[ -f "$conn_lock_file" ]] || continue
        lock_ts=0
        read -r lock_ts < "$conn_lock_file" 2>/dev/null || lock_ts=0
        [[ "$lock_ts" =~ ^[0-9]+$ ]] || lock_ts=0
        printf -v now_ts '%(%s)T' -1
        if (( now_ts - lock_ts >= CONN_LOCK_DURATION )); then
            conn_locked_user=$(basename "$conn_lock_file" .conn_locked)
            usermod -U "$conn_locked_user" &>/dev/null
            rm -f "$conn_lock_file"
        fi
    done

    printf -v current_ts '%(%s)T' -1
    dynamic_banners_enabled=false

    # Reset associative arrays each cycle (unset first to avoid stale data)
    unset session_pids locked_users uid_to_user loginuid_pids
    declare -A session_pids=()
    declare -A locked_users=()
    declare -A uid_to_user=()
    declare -A loginuid_pids=()

    while IFS=: read -r username _ uid _rest; do
        [[ -n "$username" && "$uid" =~ ^[0-9]+$ ]] && uid_to_user["$uid"]="$username"
    done < /etc/passwd

    # Method 1: process owner from ps (primary source for connection counting)
    # sshd-session is the user-owned process on Ubuntu 24.04+ (OpenSSH 9.8+)
    # On Ubuntu 22, the per-session sshd is user-owned instead.
    # Either way, exactly 1 user-owned process exists per SSH session.
    while read -r ssh_pid ssh_owner; do
        [[ "$ssh_pid" =~ ^[0-9]+$ ]] || continue
        if [[ -n "$ssh_owner" && "$ssh_owner" != "root" && "$ssh_owner" != "sshd" ]]; then
            session_pids["$ssh_owner"]+="$ssh_pid "
        fi
    done < <(ps -C sshd,sshd-session -o pid=,user= 2>/dev/null)

    # Method 2: kernel loginuid (reliable even when sshd runs as root)
    for p in /proc/[0-9]*/loginuid; do
        [[ -f "$p" ]] || continue
        login_uid=""
        read -r login_uid < "$p" || login_uid=""
        [[ "$login_uid" =~ ^[0-9]+$ && "$login_uid" != "4294967295" ]] || continue

        session_user="${uid_to_user[$login_uid]}"
        [[ -n "$session_user" ]] || continue

        pid_dir=$(dirname "$p")
        pid_num=$(basename "$pid_dir")
        comm=""
        read -r comm < "$pid_dir/comm" || comm=""
        [[ "$comm" == "sshd" ]] || continue

        ppid_val=""
        while read -r key value; do
            if [[ "$key" == "PPid:" ]]; then
                ppid_val="${value:-}"
                break
            fi
        done < "$pid_dir/status"
        [[ "$ppid_val" == "1" ]] && continue

        loginuid_pids["$session_user"]+="$pid_num "
    done

    # Detect locked users via /etc/shadow (cheaper than passwd -Sa)
    if [[ -r /etc/shadow ]]; then
        while IFS=: read -r shadow_user shadow_hash _rest; do
            [[ -n "$shadow_user" && "${shadow_hash:0:1}" == "!" ]] && locked_users["$shadow_user"]=1
        done < /etc/shadow
    else
        while read -r passwd_user _ passwd_status _rest; do
            [[ "$passwd_status" == "L" ]] && locked_users["$passwd_user"]=1
        done < <(passwd -Sa 2>/dev/null)
    fi

    if [[ -f "/etc/firewallfalcon/banners_enabled" ]]; then
        mkdir -p "$BANNER_DIR"
        dynamic_banners_enabled=true
    fi

    while IFS=: read -r user pass expiry limit bandwidth_gb daily_bandwidth_gb _extra; do
        [[ -z "$user" || "$user" == \#* ]] && continue
        
        [[ ! "$daily_bandwidth_gb" =~ ^[0-9]+\.?[0-9]*$ ]] && daily_bandwidth_gb=0

        # CRITICAL: unset before declare to reset per-user (bash declare is function-scoped)
        unset unique_pids
        declare -A unique_pids=()

        # Use ONLY ps-based session_pids for connection counting.
        # loginuid_pids can double-count (root-owned sshd has user's loginuid on Ubuntu 24)
        for pid in ${session_pids[$user]}; do
            [[ "$pid" =~ ^[0-9]+$ ]] && unique_pids["$pid"]=1
        done

        online_count=${#unique_pids[@]}
        user_locked=false
        if [[ -n "${locked_users[$user]+x}" ]]; then
            user_locked=true
        fi

        expiry_ts=0
        if [[ "$expiry" != "Never" && -n "$expiry" && "$expiry" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
            expiry_ts=$(date -d "$expiry" +%s 2>/dev/null || echo 0)
            if [[ "$expiry_ts" =~ ^[0-9]+$ ]] && (( expiry_ts > 0 && expiry_ts < current_ts )); then
                if ! $user_locked; then
                    usermod -L "$user" &>/dev/null
                    killall -u "$user" -9 &>/dev/null
                    locked_users["$user"]=1
                fi
                continue
            fi
        fi

        [[ "$limit" =~ ^[0-9]+$ ]] || limit=1
        if (( online_count > limit )); then
            # Kill only the EXCESS sessions, keep the oldest ones alive
            sorted_pids=()
            for pid in "${!unique_pids[@]}"; do
                sorted_pids+=("$pid")
            done
            IFS=$'\n' sorted_pids=($(sort -n <<<"${sorted_pids[*]}")); unset IFS

            for (( i=limit; i<${#sorted_pids[@]}; i++ )); do
                kill -9 "${sorted_pids[$i]}" &>/dev/null
            done

            # Remove killed PIDs from unique_pids so bandwidth tracking is correct
            for (( i=limit; i<${#sorted_pids[@]}; i++ )); do
                unset unique_pids["${sorted_pids[$i]}"]
            done
            online_count=${#unique_pids[@]}
        fi

        if $dynamic_banners_enabled; then
            days_left="N/A"
            if [[ "$expiry" != "Never" && -n "$expiry" && "$expiry_ts" =~ ^[0-9]+$ && $expiry_ts -gt 0 ]]; then
                diff_secs=$((expiry_ts - current_ts))
                if (( diff_secs <= 0 )); then
                    days_left="EXPIRED"
                else
                    d_l=$(( diff_secs / 86400 ))
                    h_l=$(( (diff_secs % 86400) / 3600 ))
                    if (( d_l == 0 )); then
                        days_left="${h_l}h left"
                    else
                        days_left="${d_l}d ${h_l}h"
                    fi
                fi
            fi

            bw_info="Unlimited"
            if [[ "$bandwidth_gb" != "0" && -n "$bandwidth_gb" ]]; then
                usagefile="$BW_DIR/${user}.usage"
                accum_disp=0
                if [[ -f "$usagefile" ]]; then
                    read -r accum_disp < "$usagefile"
                    [[ "$accum_disp" =~ ^[0-9]+$ ]] || accum_disp=0
                fi
                used_gb_int=$((accum_disp / 1073741824))
                used_gb_frac=$(( (accum_disp % 1073741824) * 100 / 1073741824 ))
                printf -v used_gb "%d.%02d" "$used_gb_int" "$used_gb_frac"
                quota_b=$(( ${bandwidth_gb%%.*} * 1073741824 ))
                remain_b=$(( quota_b - accum_disp ))
                (( remain_b < 0 )) && remain_b=0
                remain_gb_int=$((remain_b / 1073741824))
                remain_gb_frac=$(( (remain_b % 1073741824) * 100 / 1073741824 ))
                printf -v remain_gb "%d.%02d" "$remain_gb_int" "$remain_gb_frac"
                bw_info="${used_gb}/${bandwidth_gb} GB used | ${remain_gb} GB left"
            fi

            banner_content="<br><font color=\"yellow\"><b>      ✨ ACCOUNT STATUS ✨      </b></font><br><br>"
            banner_content+="<font color=\"white\">👤 <b>Username   :</b> $user</font><br>"
            banner_content+="<font color=\"white\">📅 <b>Expiration :</b> $expiry ($days_left)</font><br>"
            
            if [[ "$bandwidth_gb" != "0" ]]; then
                banner_content+="<font color=\"white\">📊 <b>Total BW   :</b> $bw_info</font><br>"
            fi
            
            if [[ "$daily_bandwidth_gb" != "0" ]]; then
                daily_usagefile="$BW_DIR/${user}.daily_usage"
                accum_disp=0
                if [[ -f "$daily_usagefile" ]]; then
                    read -r accum_disp < "$daily_usagefile"
                    [[ "$accum_disp" =~ ^[0-9]+$ ]] || accum_disp=0
                fi
                used_gb_int=$((accum_disp / 1073741824))
                used_gb_frac=$(( (accum_disp % 1073741824) * 100 / 1073741824 ))
                printf -v used_gb "%d.%02d" "$used_gb_int" "$used_gb_frac"
                quota_b=$(( ${daily_bandwidth_gb%%.*} * 1073741824 ))
                remain_b=$(( quota_b - accum_disp ))
                (( remain_b < 0 )) && remain_b=0
                remain_gb_int=$((remain_b / 1073741824))
                remain_gb_frac=$(( (remain_b % 1073741824) * 100 / 1073741824 ))
                printf -v remain_gb "%d.%02d" "$remain_gb_int" "$remain_gb_frac"
                daily_bw_info="${used_gb}/${daily_bandwidth_gb} GB used | ${remain_gb} GB left"
                banner_content+="<font color=\"white\">📊 <b>Daily BW   :</b> $daily_bw_info</font><br>"
            fi
            
            banner_content+="<font color=\"white\">🔌 <b>Sessions   :</b> $online_count/$limit</font><br><br>"
            write_banner_if_changed "$user" "$banner_content"
        fi

        [[ ( -z "$bandwidth_gb" || "$bandwidth_gb" == "0" ) && ( -z "$daily_bandwidth_gb" || "$daily_bandwidth_gb" == "0" ) ]] && continue

        usagefile="$BW_DIR/${user}.usage"
        accumulated=0
        if [[ -f "$usagefile" ]]; then
            read -r accumulated < "$usagefile"
            [[ "$accumulated" =~ ^[0-9]+$ ]] || accumulated=0
        fi

        if (( ${#unique_pids[@]} == 0 )); then
            for f in "$PID_DIR/${user}__"*.last; do
                [[ -f "$f" ]] || continue
                fpid=${f##*__}
                fpid=${fpid%.last}
                ts=$(date '+%Y-%m-%d %H:%M:%S')
                printf "%s | INFO | system | LOGOUT | %s | PID: %s\n" "$ts" "$user" "$fpid" >> "/etc/firewallfalcon/logs/client_connections.log" 2>/dev/null
                rm -f "$f"
            done
            continue
        fi

        delta_total=0
        for pid in "${!unique_pids[@]}"; do
            io_file="/proc/$pid/io"
            cur=0
            if [[ -r "$io_file" ]]; then
                rchar=0
                wchar=0
                while read -r key value; do
                    case "$key" in
                        rchar:) rchar=${value:-0} ;;
                        wchar:) wchar=${value:-0} ;;
                    esac
                done < "$io_file"
                cur=$((rchar + wchar))
            fi

            pidfile="$PID_DIR/${user}__${pid}.last"
            if [[ ! -f "$pidfile" ]]; then
                ip=$(ss -tp 2>/dev/null | grep -E "\b(pid|ppid)=$pid\b" | awk '{print $5}' | cut -d: -f1 | head -n 1)
                [[ -z "$ip" ]] && ip=$(ss -tp 2>/dev/null | grep -F "$pid" | awk '{print $5}' | cut -d: -f1 | head -n 1)
                [[ -z "$ip" ]] && ip="unknown"
                ts=$(date '+%Y-%m-%d %H:%M:%S')
                printf "%s | INFO | system | LOGIN | %s | PID: %s IP: %s\n" "$ts" "$user" "$pid" "$ip" >> "/etc/firewallfalcon/logs/client_connections.log" 2>/dev/null
            fi

            if [[ -f "$pidfile" ]]; then
                read -r prev < "$pidfile"
                [[ "$prev" =~ ^[0-9]+$ ]] || prev=0
                if (( cur >= prev )); then
                    d=$((cur - prev))
                else
                    d=$cur
                fi
                delta_total=$((delta_total + d))
            fi
            printf "%s\n" "$cur" > "$pidfile"
        done

        for f in "$PID_DIR/${user}__"*.last; do
            [[ -f "$f" ]] || continue
            fpid=${f##*__}
            fpid=${fpid%.last}
            if [[ ! -d "/proc/$fpid" ]]; then
                ts=$(date '+%Y-%m-%d %H:%M:%S')
                printf "%s | INFO | system | LOGOUT | %s | PID: %s\n" "$ts" "$user" "$fpid" >> "/etc/firewallfalcon/logs/client_connections.log" 2>/dev/null
                rm -f "$f"
            fi
        done

        new_total=$((accumulated + delta_total))
        printf "%s\n" "$new_total" > "$usagefile"

        if awk "BEGIN{exit(!($bandwidth_gb > 0))}" 2>/dev/null; then
            quota_bytes=$(awk "BEGIN{printf \"%.0f\", $bandwidth_gb * 1073741824}")
            if [[ "$quota_bytes" =~ ^[0-9]+$ ]] && (( quota_bytes > 0 && new_total >= quota_bytes )); then
                if ! $user_locked; then
                    usermod -L "$user" &>/dev/null
                    locked_users["$user"]=1
                    user_locked=true
                fi
            fi
        fi
        
        daily_usagefile="$BW_DIR/${user}.daily_usage"
        daily_accumulated=0
        if [[ -f "$daily_usagefile" ]]; then
            read -r daily_accumulated < "$daily_usagefile"
            [[ "$daily_accumulated" =~ ^[0-9]+$ ]] || daily_accumulated=0
        fi
        new_daily_total=$((daily_accumulated + delta_total))
        printf "%s\n" "$new_daily_total" > "$daily_usagefile"
        
        if awk "BEGIN{exit(!($daily_bandwidth_gb > 0))}" 2>/dev/null; then
            d_quota_bytes=$(awk "BEGIN{printf \"%.0f\", $daily_bandwidth_gb * 1073741824}")
            if [[ "$d_quota_bytes" =~ ^[0-9]+$ ]] && (( d_quota_bytes > 0 && new_daily_total >= d_quota_bytes )); then
                if ! $user_locked; then
                    usermod -L "$user" &>/dev/null
                    locked_users["$user"]=1
                    user_locked=true
                    touch "$BW_DIR/${user}.daily_locked"
                fi
            fi
        fi
    done < "$DB_FILE"

    sleep "$SCAN_INTERVAL"
done
EOF
    chmod +x "$LIMITER_SCRIPT"
    # Strip DOS line endings in case menu.sh was uploaded from Windows
    sed -i 's/\r$//' "$LIMITER_SCRIPT" 2>/dev/null

    cat > "$LIMITER_SERVICE" << EOF
[Unit]
Description=DAHOOM Active User Limiter
After=network.target

[Service]
Type=simple
ExecStart=$LIMITER_SCRIPT
Restart=always
RestartSec=10
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
MemoryHigh=48M
MemoryMax=64M

[Install]
WantedBy=multi-user.target
EOF
    sed -i 's/\r$//' "$LIMITER_SERVICE" 2>/dev/null

    pkill -f "firewallfalcon-limiter" 2>/dev/null

    if ! systemctl is-active --quiet firewallfalcon-limiter; then
        systemctl daemon-reload
        systemctl enable firewallfalcon-limiter &>/dev/null
        systemctl start firewallfalcon-limiter --no-block &>/dev/null
        
    else
        systemctl restart firewallfalcon-limiter --no-block &>/dev/null
        
    fi
}

sync_runtime_components_if_needed() {
    local limiter_marker="# DAHOOM limiter version 2026-07-23.8"
    cleanup_legacy_bandwidth_runtime
    setup_trial_cleanup_script >/dev/null 2>&1
    setup_falcon_server_motd >/dev/null 2>&1
    # Ensure 'fm' and 'menu' command symlinks are always available
    if [[ -f "/usr/local/bin/firewallfalcon" ]]; then
        ln -sf "/usr/local/bin/firewallfalcon" "/usr/local/bin/fm" 2>/dev/null || true
        ln -sf "/usr/local/bin/firewallfalcon" "/usr/bin/fm" 2>/dev/null || true
        ln -sf "/usr/local/bin/firewallfalcon" "/usr/local/bin/menu" 2>/dev/null || true
        ln -sf "/usr/local/bin/firewallfalcon" "/usr/bin/menu" 2>/dev/null || true
    fi
    if [[ ! -f "$LIMITER_SCRIPT" ]] || ! grep -Fqx "$limiter_marker" "$LIMITER_SCRIPT" 2>/dev/null; then
        setup_limiter_service >/dev/null 2>&1
    fi
    if [[ -f "$BADVPN_SERVICE_FILE" ]]; then
        ensure_badvpn_service_is_quiet
    fi
    if [[ -f "/etc/firewallfalcon/banners_enabled" ]]; then
        update_ssh_banners_config
    elif [[ -f "$SSHD_FF_CONFIG" ]]; then
        disable_dynamic_ssh_banner_system
        systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || true
    fi
}

setup_bandwidth_service() {
    mkdir -p "$BANDWIDTH_DIR"
    # Bandwidth monitoring is now integrated into the limiter service above.
    cleanup_legacy_bandwidth_runtime
}

cleanup_legacy_bandwidth_runtime() {
    local needs_reload=false

    systemctl stop firewallfalcon-bandwidth &>/dev/null || true
    systemctl disable firewallfalcon-bandwidth &>/dev/null || true
    pkill -f "firewallfalcon-bandwidth" &>/dev/null || true

    if [[ -e "$BANDWIDTH_SERVICE" || -e "$BANDWIDTH_SCRIPT" || -e "$LEGACY_BANDWIDTH_DIR" ]]; then
        rm -f "$BANDWIDTH_SERVICE" "$BANDWIDTH_SCRIPT" 2>/dev/null
        rm -rf "$LEGACY_BANDWIDTH_DIR" 2>/dev/null
        needs_reload=true
    fi

    if $needs_reload; then
        systemctl daemon-reload &>/dev/null || true
    fi
}

setup_trial_cleanup_script() {
    cat > "$TRIAL_CLEANUP_SCRIPT" << 'TREOF'
#!/bin/bash
# DAHOOM Trial Account Auto-Cleanup
# Usage: firewallfalcon-trial-cleanup.sh <username>
DB_FILE="/etc/firewallfalcon/users.db"
BW_DIR="/etc/firewallfalcon/bandwidth"

username="$1"
if [[ -z "$username" ]]; then exit 1; fi

db_line=$(grep "^${username}:" "$DB_FILE" 2>/dev/null | head -n 1)
if [[ -z "$db_line" ]]; then exit 0; fi

IFS=: read -r _ _ _ _ _ trial_marker _rest <<< "$db_line"
if [[ "$trial_marker" != "trial" ]]; then
    exit 0
fi

# Kill active sessions
killall -u "$username" -9 &>/dev/null
pkill -9 -u "$username" &>/dev/null
sleep 1

# Delete system user
userdel -rf "$username" &>/dev/null

# Remove from DB
sed -i "/^${username}:/d" "$DB_FILE"

# Remove bandwidth tracking
rm -f "$BW_DIR/${username}.usage"
rm -rf "$BW_DIR/pidtrack/${username}"
TREOF
    chmod +x "$TRIAL_CLEANUP_SCRIPT"
}

setup_health_service() {
    local health_script="/usr/local/bin/firewallfalcon-health.py"
    local health_service="/etc/systemd/system/firewallfalcon-health.service"

    cat > "$health_script" << 'EOF'
#!/usr/bin/env python3
import os
import sys
import time
import subprocess
from datetime import datetime

LOGS_DIR = "/etc/firewallfalcon/logs"
SERVICE_LOG = os.path.join(LOGS_DIR, "service_health.log")

SERVICES = [
    ("badvpn", "BadVPN UDP Gateway"),
    ("udp-custom", "UDP Custom Daemon"),
    ("haproxy", "HAProxy SSL Frontend"),
    ("nginx", "Nginx Web Server"),
    ("dnstt", "SlowDNS Daemon"),
    ("falconproxy", "Falcon HTTP/WS Proxy"),
    ("zivpn", "ZiVPN Service"),
    ("xray", "VLESS Reality Service"),
    ("x-ui", "X-UI Web Panel"),
    ("firewallfalcon-panel", "Web Control Panel")
]

def log_event(level, service, action, details):
    os.makedirs(LOGS_DIR, exist_ok=True)
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"{ts} | {level:<4} | system     | {action:<14} | {service:<15} | {details}\n"
    try:
        with open(SERVICE_LOG, "a", encoding="utf-8") as f:
            f.write(line)
    except Exception:
        pass

def is_service_active(svc_name):
    try:
        res = subprocess.run(["systemctl", "is-active", "--quiet", svc_name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return res.returncode == 0
    except Exception:
        return False

def restart_service(svc_name):
    try:
        res = subprocess.run(["systemctl", "restart", svc_name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return res.returncode == 0
    except Exception:
        return False

def check_resources():
    try:
        df = subprocess.check_output(["df", "-h", "/"]).decode("utf-8").splitlines()
        if len(df) >= 2:
            parts = df[1].split()
            pct_str = parts[4].replace("%", "")
            if pct_str.isdigit() and int(pct_str) >= 90:
                log_event("WARN", "Disk Space", "RESOURCE_ALERT", f"Disk usage critical: {pct_str}% used ({parts[2]}/{parts[1]})")

        mem = subprocess.check_output(["free", "-m"]).decode("utf-8").splitlines()
        if len(mem) >= 2:
            parts = mem[1].split()
            total = float(parts[1]) if parts[1].isdigit() else 1.0
            used = float(parts[2]) if parts[2].isdigit() else 0.0
            pct = (used / total) * 100.0
            if pct >= 90.0:
                log_event("WARN", "RAM Memory", "RESOURCE_ALERT", f"Memory usage critical: {pct:.1f}% used ({int(used)}MB/{int(total)}MB)")
    except Exception:
        pass

def main():
    service_status = {}
    print("DAHOOM Health & Outage Detector started.", flush=True)
    log_event("INFO", "HealthMonitor", "MONITOR_START", "Service Outage & Health Guard active")

    resource_check_counter = 0

    while True:
        try:
            for svc, title in SERVICES:
                svc_path = f"/etc/systemd/system/{svc}.service"
                alt_path = f"/lib/systemd/system/{svc}.service"
                if not os.path.exists(svc_path) and not os.path.exists(alt_path):
                    continue

                active = is_service_active(svc)
                prev_active = service_status.get(svc)

                if prev_active is not None and not active and prev_active:
                    log_event("CRIT", svc, "SERVICE_CRASH", f"CRITICAL: {title} stopped unexpectedly! Attempting auto-healing restart...")
                    restarted = restart_service(svc)
                    if restarted:
                        log_event("INFO", svc, "AUTO_HEAL_OK", f"SUCCESS: {title} auto-restarted and restored successfully.")
                        service_status[svc] = True
                    else:
                        log_event("CRIT", svc, "AUTO_HEAL_FAIL", f"ERROR: Failed to auto-restart {title}. Intervention required.")
                        service_status[svc] = False
                else:
                    service_status[svc] = active

            resource_check_counter += 1
            if resource_check_counter >= 10:
                check_resources()
                resource_check_counter = 0

        except Exception as e:
            print(f"Error in health monitor: {e}", file=sys.stderr)

        time.sleep(30)

if __name__ == "__main__":
    main()
EOF

    chmod +x "$health_script"
    sed -i 's/\r$//' "$health_script" 2>/dev/null

    cat > "$health_service" << EOF
[Unit]
Description=DAHOOM Service Health Guard
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 $health_script
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload &>/dev/null || true
    systemctl enable firewallfalcon-health &>/dev/null || true
    systemctl restart firewallfalcon-health &>/dev/null || true
}

disable_dynamic_ssh_banner_system() {
    rm -f "/etc/firewallfalcon/banners_enabled" "$SSHD_FF_CONFIG" /usr/local/bin/firewallfalcon-login-info.sh 2>/dev/null
    rm -rf "/etc/firewallfalcon/banners" 2>/dev/null
    invalidate_banner_cache
}

setup_falcon_server_motd() {
    mkdir -p "/etc/update-motd.d" "/etc/firewallfalcon" "/etc/profile.d" 2>/dev/null

    # 1. Disable ALL other default Ubuntu / Debian scripts in /etc/update-motd.d/
    if [[ -d "/etc/update-motd.d" ]]; then
        for s in /etc/update-motd.d/*; do
            [[ -e "$s" && "$s" != *"/01-falcon-banner" ]] && chmod -x "$s" 2>/dev/null || true
        done
        chmod -x /etc/update-motd.d/00-header 2>/dev/null || true
        chmod -x /etc/update-motd.d/10-help-text 2>/dev/null || true
        chmod -x /etc/update-motd.d/50-landscape-sysinfo 2>/dev/null || true
        chmod -x /etc/update-motd.d/50-motd-news 2>/dev/null || true
        chmod -x /etc/update-motd.d/85-fwupd 2>/dev/null || true
        chmod -x /etc/update-motd.d/88-esm-announce 2>/dev/null || true
        chmod -x /etc/update-motd.d/90-updates-available 2>/dev/null || true
        chmod -x /etc/update-motd.d/91-contract-ua-esm-status 2>/dev/null || true
        chmod -x /etc/update-motd.d/91-release-upgrade 2>/dev/null || true
        chmod -x /etc/update-motd.d/92-unattended-upgrades 2>/dev/null || true
        chmod -x /etc/update-motd.d/95-hwe-eol 2>/dev/null || true
        chmod -x /etc/update-motd.d/97-overlayroot 2>/dev/null || true
        chmod -x /etc/update-motd.d/98-fsck-at-reboot 2>/dev/null || true
        chmod -x /etc/update-motd.d/98-reboot-required 2>/dev/null || true
    fi

    # 2. Disable Canonical motd-news & Ubuntu Advantage ESM hooks
    if [[ -f "/etc/default/motd-news" ]]; then
        sed -i 's/ENABLED=1/ENABLED=0/' /etc/default/motd-news 2>/dev/null || true
    fi
    chmod -x /usr/lib/ubuntu-advantage/apt-esm-hook 2>/dev/null || true
    chmod -x /usr/share/landscape/landscape-sysinfo.wrapper 2>/dev/null || true

    # 3. Clear dynamic and static motd cache files completely
    > /run/motd.dynamic 2>/dev/null || true
    > /var/run/motd.dynamic 2>/dev/null || true
    > /etc/motd 2>/dev/null || true
    > /etc/legal 2>/dev/null || true
    > /etc/issue.net 2>/dev/null || true

    # 4. Deploy DAHOOM clean dynamic login banner
    cat > "/etc/update-motd.d/01-falcon-banner" << 'EOF'
#!/usr/bin/env bash
# 🦅 DAHOOM Clean Login Banner

C_RESET="\033[0m"
C_BOLD="\033[1m"
C_CYAN="\033[38;5;51m"
C_VIOLET="\033[38;5;177m"
C_GREEN="\033[38;5;79m"
C_YELLOW="\033[38;5;222m"
C_BLUE="\033[38;5;67m"
C_ORANGE="\033[38;5;87m"
C_FRAME="\033[38;5;60m"
C_GRAY="\033[38;5;245m"
C_WHITE="\033[38;5;255m"

# 1. OS & Uptime
os_name="Linux"
if [[ -f /etc/os-release ]]; then
    os_name=$(grep -E '^PRETTY_NAME=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
fi
uptime_str=$(uptime -p 2>/dev/null | sed 's/up //')
[[ -z "$uptime_str" ]] && uptime_str="N/A"

# 2. Hostname & IP
server_ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')
[[ -z "$server_ip" ]] && server_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
[[ -z "$server_ip" ]] && server_ip="127.0.0.1"

# 3. Memory & Load
mem_info=$(free -m 2>/dev/null | awk 'NR==2{printf "%.2f", ($2>0 ? $3*100/$2 : 0) }')
mem_pct="${mem_info:-0.00}%"
load_avg=$(cat /proc/loadavg 2>/dev/null | awk '{print $1}' || echo "0.00")

# 4. Version
ver="4.6.0"
if [[ -f "/etc/firewallfalcon/.version" ]]; then
    ver="4.6.0_$(cat /etc/firewallfalcon/.version 2>/dev/null | tr -d '[:space:]')"
fi

# 5. User statistics
total_u=0 active_u=0 locked_u=0 exp_u=0
if [[ -s "/etc/firewallfalcon/users.db" ]]; then
    now_ts=$(date +%s)
    declare -A s_locked=()
    if [[ -r /etc/shadow ]]; then
        while IFS=: read -r _su _sh_h _r; do
            [[ -n "$_su" && "${_sh_h:0:1}" == "!" ]] && s_locked["$_su"]=1
        done < /etc/shadow
    fi
    while IFS=: read -r _u _p exp _r; do
        [[ -z "$_u" || "$_u" == \#* ]] && continue
        (( total_u++ ))
        e_ts=0
        [[ -n "$exp" && "$exp" != "Never" ]] && e_ts=$(date -d "$exp" +%s 2>/dev/null || echo 0)
        if [[ -n "${s_locked[$_u]+x}" ]]; then
            (( locked_u++ ))
        elif (( e_ts > 0 && e_ts < now_ts )); then
            (( exp_u++ ))
        else
            (( active_u++ ))
        fi
    done < "/etc/firewallfalcon/users.db"
fi

len_title=$(( 13 + ${#ver} ))
pad_title=$(( 58 - len_title ))
[[ $pad_title -lt 1 ]] && pad_title=1

len_badge=$(( 51 + ${#active_u} + ${#locked_u} + ${#exp_u} + ${#total_u} ))
pad_badge=$(( 58 - len_badge ))
[[ $pad_badge -lt 1 ]] && pad_badge=1

echo
echo -e "  ${C_BOLD}${C_BLUE}╭──────────────────────────────────────────────────────────╮${C_RESET}"
echo -e "  ${C_BOLD}${C_BLUE}│${C_RESET}  ${C_BOLD}${C_ORANGE}🦅 DAHOOM${C_RESET}  ${C_GRAY}${ver}${C_RESET}$(printf '%*s' "$pad_title" '')${C_BOLD}${C_BLUE}│${C_RESET}"
echo -e "  ${C_BOLD}${C_BLUE}├──────────────────────────────────────────────────────────┤${C_RESET}"
printf "  ${C_BOLD}${C_BLUE}│${C_RESET}  ${C_GRAY}%-8s${C_RESET} ${C_WHITE}%-17s${C_RESET} ${C_GRAY}│${C_RESET}  ${C_GRAY}%-6s${C_RESET} ${C_WHITE}%-18s${C_RESET} ${C_BOLD}${C_BLUE}│${C_RESET}\n" \
    "OS" "${os_name:0:17}" "Uptime" "${uptime_str:0:18}"
printf "  ${C_BOLD}${C_BLUE}│${C_RESET}  ${C_GRAY}%-8s${C_RESET} ${C_WHITE}%-17s${C_RESET} ${C_GRAY}│${C_RESET}  ${C_GRAY}%-6s${C_RESET} ${C_GREEN}%-18s${C_RESET} ${C_BOLD}${C_BLUE}│${C_RESET}\n" \
    "Memory" "${mem_pct} Used" "Load" "$load_avg"
printf "  ${C_BOLD}${C_BLUE}│${C_RESET}  ${C_GRAY}%-8s${C_RESET} ${C_WHITE}%-17s${C_RESET} ${C_GRAY}│${C_RESET}  ${C_GRAY}%-6s${C_RESET} ${C_CYAN}%-18s${C_RESET} ${C_BOLD}${C_BLUE}│${C_RESET}\n" \
    "IPv4" "${server_ip:0:17}" "Mode" "Multi-Protocol"
echo -e "  ${C_BOLD}${C_BLUE}├──────────────────────────────────────────────────────────┤${C_RESET}"
echo -e "  ${C_BOLD}${C_BLUE}│${C_RESET}  ${C_GREEN}🟢 ${active_u} Active${C_RESET} ${C_GRAY}│${C_RESET} ${C_YELLOW}🟡 ${locked_u} Locked${C_RESET} ${C_GRAY}│${C_RESET} ${C_RED}🔴 ${exp_u} Expired${C_RESET} ${C_GRAY}│${C_RESET} ${C_WHITE}👥 ${total_u} Total${C_RESET}$(printf '%*s' "$pad_badge" '')${C_BOLD}${C_BLUE}│${C_RESET}"
echo -e "  ${C_BOLD}${C_BLUE}╰──────────────────────────────────────────────────────────╯${C_RESET}"
echo -e "  ${C_GRAY}💡 Quick Launch:${C_RESET} Type ${C_GREEN}'menu'${C_RESET} or ${C_GREEN}'fm'${C_RESET} to access DAHOOM.\n"
EOF

    chmod +x "/etc/update-motd.d/01-falcon-banner" 2>/dev/null || true
    sed -i 's/\r$//' "/etc/update-motd.d/01-falcon-banner" 2>/dev/null || true
    ln -sf "/etc/update-motd.d/01-falcon-banner" "/usr/local/bin/falcon-motd" 2>/dev/null || true

    # 5. Multi-Distro profile hook (RHEL, AlmaLinux, RockyLinux, CentOS, Fedora, openSUSE, Arch)
    cat > "/etc/profile.d/falcon_motd.sh" << 'EOF'
# DAHOOM interactive login banner
if [[ $- == *i* ]] && [ -z "$DAHOOM_MOTD_SHOWN" ] && [ -x "/usr/local/bin/falcon-motd" ] && [ ! -d "/etc/update-motd.d" ]; then
    export DAHOOM_MOTD_SHOWN=1
    /usr/local/bin/falcon-motd
fi
EOF
    chmod +x "/etc/profile.d/falcon_motd.sh" 2>/dev/null || true

    touch "/etc/firewallfalcon/.motd_enabled" 2>/dev/null || true
    return 0
}

restore_default_server_motd() {
    if [[ -d "/etc/update-motd.d" ]]; then
        for s in /etc/update-motd.d/*; do
            [[ -e "$s" && "$s" != *"/01-falcon-banner" ]] && chmod +x "$s" 2>/dev/null || true
        done
    fi
    if [[ -f "/etc/default/motd-news" ]]; then
        sed -i 's/ENABLED=0/ENABLED=1/' /etc/default/motd-news 2>/dev/null || true
    fi
    rm -f "/etc/update-motd.d/01-falcon-banner" "/usr/local/bin/falcon-motd" "/etc/profile.d/falcon_motd.sh" "/etc/firewallfalcon/.motd_enabled" 2>/dev/null || true
}

is_falcon_server_motd_enabled() {
    [[ -f "/etc/update-motd.d/01-falcon-banner" && -x "/etc/update-motd.d/01-falcon-banner" ]] || [[ -f "/etc/profile.d/falcon_motd.sh" && -f "/etc/firewallfalcon/.motd_enabled" ]]
}

disable_static_ssh_banner_in_sshd_config() {
    sed -i.bak -E "s|^[[:space:]]*Banner[[:space:]]+$SSH_BANNER_FILE[[:space:]]*$|# Banner $SSH_BANNER_FILE|" /etc/ssh/sshd_config 2>/dev/null
}

is_static_ssh_banner_enabled() {
    grep -q -E "^[[:space:]]*Banner[[:space:]]+$SSH_BANNER_FILE[[:space:]]*$" /etc/ssh/sshd_config 2>/dev/null && [ -f "$SSH_BANNER_FILE" ]
}

is_dynamic_ssh_banner_enabled() {
    [[ -f "/etc/firewallfalcon/banners_enabled" && -f "$SSHD_FF_CONFIG" ]]
}

get_ssh_banner_mode() {
    if is_dynamic_ssh_banner_enabled; then
        echo "dynamic"
    elif is_static_ssh_banner_enabled; then
        echo "static"
    else
        echo "disabled"
    fi
}

refresh_dynamic_banner_routing_if_enabled() {
    if is_dynamic_ssh_banner_enabled; then
        update_ssh_banners_config
    fi
}

update_ssh_banners_config() {
    local tmp_conf

    if [[ ! -f "/etc/firewallfalcon/banners_enabled" ]]; then
        if [[ -f "$SSHD_FF_CONFIG" ]]; then
            rm -f "$SSHD_FF_CONFIG" 2>/dev/null
            systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null
        fi
        return
    fi

    ensure_firewallfalcon_dirs
    tmp_conf="/tmp/ff_banners_new.conf"
    echo "# DAHOOM - Dynamic per-user SSH banners" > "$tmp_conf"

    if [[ -f "$DB_FILE" ]]; then
        while IFS=: read -r u _rest; do
            [[ -z "$u" || "$u" == \#* ]] && continue
            echo "Match User $u" >> "$tmp_conf"
            echo "    Banner /etc/firewallfalcon/banners/${u}.txt" >> "$tmp_conf"
        done < "$DB_FILE"
    fi

    if ! cmp -s "$tmp_conf" "$SSHD_FF_CONFIG" 2>/dev/null; then
        mv "$tmp_conf" "$SSHD_FF_CONFIG"
        if ! grep -q "^Include /etc/ssh/sshd_config.d/" /etc/ssh/sshd_config 2>/dev/null; then
            echo "Include /etc/ssh/sshd_config.d/*.conf" >> /etc/ssh/sshd_config
        fi
        systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null
    else
        rm -f "$tmp_conf"
    fi
}

setup_ssh_login_info() {
    ensure_firewallfalcon_dirs || return 1
    if ! touch "/etc/firewallfalcon/banners_enabled"; then
        echo -e "${C_RED}❌ Failed to enable dynamic SSH banners.${C_RESET}"
        return 1
    fi
    disable_static_ssh_banner_in_sshd_config
    update_ssh_banners_config
    return 0
}


select_free_domain_dialog() {
    echo -e "  ${C_CYAN}Select Free Root Domain:${C_RESET}\n"
    printf "  ${C_CHOICE}%-4s${C_RESET} %-24s %s\n" "[1]" "aljailane.dedyn.io" "${C_STATUS_A}(Default)${C_RESET}"
    printf "  ${C_CHOICE}%-4s${C_RESET} %-24s %s\n" "[2]" "aljvpn.top" "${C_NEW}${C_BOLD}(New)${C_RESET}"
    echo
    printf "  ${C_DANGER}%-4s${C_RESET} %s\n" "[0]" "Cancel"
    echo
    local dom_choice=""
    if ! read -r -p "$(echo -e ${C_PROMPT}"> Select a domain [1]: "${C_RESET})" dom_choice; then
        return 1
    fi
    dom_choice=${dom_choice:-1}
    case "$dom_choice" in
        1)
            CHOSEN_DESEC_DOMAIN="aljailane.dedyn.io"
            CHOSEN_DESEC_TOKEN="79BLgHoLMdeZeRUnPJeQP3P6hzf9"
            ;;
        2)
            CHOSEN_DESEC_DOMAIN="aljvpn.top"
            CHOSEN_DESEC_TOKEN="uSmxiWYW5SB8oQb4ZCBcPwkCWHHh"
            ;;
        0)
            echo -e "\n${C_YELLOW}❌ Operation cancelled.${C_RESET}"
            return 1
            ;;
        *)
            echo -e "\n${C_RED}❌ Invalid selection.${C_RESET}"
            return 1
            ;;
    esac
    return 0
}

generate_dns_record() {
    local target_domain="$1"
    local target_token="$2"

    if [[ -z "$target_domain" || -z "$target_token" ]]; then
        CHOSEN_DESEC_DOMAIN=""
        CHOSEN_DESEC_TOKEN=""
        if ! select_free_domain_dialog; then
            return 1
        fi
        target_domain="$CHOSEN_DESEC_DOMAIN"
        target_token="$CHOSEN_DESEC_TOKEN"
    fi

    echo -e "\n${C_BLUE}⚙️ Generating a random subdomain under ${C_YELLOW}${target_domain}${C_BLUE}...${C_RESET}"
    if ! command -v jq &> /dev/null; then
        echo -e "${C_YELLOW}⚠️ jq not found, attempting to install...${C_RESET}"
        ff_pkg_install jq >/dev/null 2>&1 || {
            echo -e "${C_RED}❌ Failed to install jq. Cannot manage DNS records.${C_RESET}"
            return 1
        }
    fi
    local SERVER_IPV4
    SERVER_IPV4=$(curl -s -4 icanhazip.com)
    if ! _is_valid_ipv4 "$SERVER_IPV4"; then
        echo -e "\n${C_RED}❌ Error: Could not retrieve a valid public IPv4 address from icanhazip.com.${C_RESET}"
        echo -e "${C_YELLOW}ℹ️ Please check your server's network connection and DNS resolver settings.${C_RESET}"
        echo -e "   Output received: '$SERVER_IPV4'"
        return 1
    fi

    local SERVER_IPV6
    SERVER_IPV6=$(curl -s -6 icanhazip.com --max-time 5)

    local RANDOM_SUBDOMAIN="alj-$(tr -dc a-z0-9 < /dev/urandom | head -c 6)"
    local FULL_DOMAIN="$RANDOM_SUBDOMAIN.$target_domain"
    local HAS_IPV6="false"

    local API_DATA
    API_DATA=$(printf '[{"subname": "%s", "type": "A", "ttl": 3600, "records": ["%s"]}]' "$RANDOM_SUBDOMAIN" "$SERVER_IPV4")

    if [[ -n "$SERVER_IPV6" ]]; then
        local aaaa_record
        aaaa_record=$(printf ',{"subname": "%s", "type": "AAAA", "ttl": 3600, "records": ["%s"]}' "$RANDOM_SUBDOMAIN" "$SERVER_IPV6")
        API_DATA="${API_DATA%?}${aaaa_record}]"
        HAS_IPV6="true"
    fi

    local CREATE_RESPONSE
    CREATE_RESPONSE=$(curl -s -w "%{http_code}" -X POST "https://desec.io/api/v1/domains/$target_domain/rrsets/" \
        -H "Authorization: Token $target_token" -H "Content-Type: application/json" \
        --data "$API_DATA")
    
    local HTTP_CODE=${CREATE_RESPONSE: -3}
    local RESPONSE_BODY=${CREATE_RESPONSE:0:${#CREATE_RESPONSE}-3}

    if [[ "$HTTP_CODE" -ne 201 ]]; then
        echo -e "${C_RED}❌ Failed to create DNS records. API returned HTTP $HTTP_CODE.${C_RESET}"
        if [[ -n "$RESPONSE_BODY" ]]; then
            echo -e "${C_YELLOW}Response: $(echo "$RESPONSE_BODY" | jq -r '.detail // .' 2>/dev/null || echo "$RESPONSE_BODY")${C_RESET}"
        fi
        return 1
    fi
    
    cat > "$DNS_INFO_FILE" <<-EOF
SUBDOMAIN="$RANDOM_SUBDOMAIN"
ROOT_DOMAIN="$target_domain"
FULL_DOMAIN="$FULL_DOMAIN"
DESEC_TOKEN="$target_token"
HAS_IPV6="$HAS_IPV6"
EOF
    echo -e "\n${C_GREEN}✅ Successfully created domain: ${C_YELLOW}$FULL_DOMAIN${C_RESET}"
}

delete_dns_record() {
    if [ ! -f "$DNS_INFO_FILE" ]; then
        echo -e "\n${C_YELLOW}ℹ️ No domain to delete.${C_RESET}"
        return
    fi
    echo -e "\n${C_BLUE}🗑️ Deleting DNS records...${C_RESET}"
    local ROOT_DOMAIN="" SUBDOMAIN="" DESEC_TOKEN="" HAS_IPV6="false" FULL_DOMAIN=""
    source "$DNS_INFO_FILE" 2>/dev/null
    ROOT_DOMAIN="${ROOT_DOMAIN:-$DESEC_DOMAIN}"
    DESEC_TOKEN="${DESEC_TOKEN:-79BLgHoLMdeZeRUnPJeQP3P6hzf9}"

    if [[ -z "$SUBDOMAIN" ]]; then
        echo -e "${C_RED}❌ Could not read record details from config file. Skipping deletion.${C_RESET}"
        return
    fi

    curl -s --max-time 4 -X DELETE "https://desec.io/api/v1/domains/$ROOT_DOMAIN/rrsets/$SUBDOMAIN/A/" \
         -H "Authorization: Token $DESEC_TOKEN" > /dev/null 2>&1 || true

    if [[ "$HAS_IPV6" == "true" ]]; then
        curl -s --max-time 4 -X DELETE "https://desec.io/api/v1/domains/$ROOT_DOMAIN/rrsets/$SUBDOMAIN/AAAA/" \
             -H "Authorization: Token $DESEC_TOKEN" > /dev/null 2>&1 || true
    fi

    echo -e "\n${C_GREEN}✅ Deleted domain: ${C_YELLOW}$FULL_DOMAIN${C_RESET}"
    rm -f "$DNS_INFO_FILE"
}

desec_subdomain_menu() {
    clear; show_banner
    echo
    menu_section "FREE SUBDOMAIN (deSEC)" "$C_TITLE"
    echo
    if [ -f "$DNS_INFO_FILE" ]; then
        source "$DNS_INFO_FILE" 2>/dev/null
        local root_show="${ROOT_DOMAIN:-$DESEC_DOMAIN}"
        echo -e "  ${C_CYAN}Active Domain:${C_RESET} ${C_YELLOW}$FULL_DOMAIN${C_RESET} (${C_GRAY}Root: ${root_show}${C_RESET})"
        echo
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[1]" "Delete Free Subdomain"
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[2]" "Generate New Subdomain"
        echo
        printf "  ${C_DANGER}%-4s${C_RESET} %s\n" "[0]" "Return"
        echo
        read -r -p "$(echo -e ${C_PROMPT}"> Select an option: "${C_RESET})" act
        case "$act" in
            1) delete_dns_record; press_enter ;;
            2) generate_dns_record; press_enter ;;
            *) ;;
        esac
    else
        echo -e "  ${C_CYAN}Status:${C_RESET} ${C_RED}No free subdomain configured${C_RESET}"
        echo
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[1]" "Generate Free Subdomain"
        echo
        printf "  ${C_DANGER}%-4s${C_RESET} %s\n" "[0]" "Return"
        echo
        read -r -p "$(echo -e ${C_PROMPT}"> Select an option: "${C_RESET})" act
        if [[ "$act" == "1" ]]; then
            generate_dns_record
            press_enter
        fi
    fi
}

custom_domain_menu() {
    clear; show_banner
    echo
    menu_section "CUSTOM DOMAIN SETUP" "$C_TITLE"
    echo
    local cur_cust=""
    if [ -f "/etc/firewallfalcon/custom_domain.info" ]; then
        source "/etc/firewallfalcon/custom_domain.info" 2>/dev/null
        cur_cust="$CUSTOM_DOMAIN"
        echo -e "  ${C_CYAN}Current Domain:${C_RESET} ${C_YELLOW}$CUSTOM_DOMAIN${C_RESET}"
        echo
    fi
    printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[1]" "Set Custom Domain"
    if [[ -n "$cur_cust" ]]; then
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[2]" "Remove Custom Domain"
    fi
    echo
    printf "  ${C_DANGER}%-4s${C_RESET} %s\n" "[0]" "Return"
    echo
    read -r -p "$(echo -e ${C_PROMPT}"> Select an option: "${C_RESET})" act
    case "$act" in
        1)
            read -r -p "$(echo -e "${C_BLUE}👉 Enter custom domain (e.g. vpn.domain.com): ${C_RESET}")" new_dom
            if [[ -n "$new_dom" ]]; then
                mkdir -p "/etc/firewallfalcon" 2>/dev/null
                echo "CUSTOM_DOMAIN=\"$new_dom\"" > "/etc/firewallfalcon/custom_domain.info"
                echo -e "\n${C_GREEN}✅ Custom domain set to: ${C_YELLOW}$new_dom${C_RESET}"
            fi
            press_enter
            ;;
        2)
            rm -f "/etc/firewallfalcon/custom_domain.info"
            echo -e "\n${C_GREEN}✅ Custom domain removed.${C_RESET}"
            press_enter
            ;;
        *) ;;
    esac
}

update_domain_ip() {
    echo -e "\n${C_BLUE}Updating IP for active domain...${C_RESET}"
    local new_ip; new_ip=$(curl -s -4 icanhazip.com --max-time 5 2>/dev/null)
    if [[ -z "$new_ip" ]]; then
        echo -e "${C_RED}❌ Could not detect server public IP.${C_RESET}"
        press_enter
        return
    fi

    if [ -f "$CLOUDFLARE_INFO_FILE" ]; then
        source "$CLOUDFLARE_INFO_FILE" 2>/dev/null
        if [[ -n "$CF_API_TOKEN" && -n "$CF_ZONE_ID" && -n "$CF_DOMAIN" ]]; then
            local prox_bool="false"
            [[ "$CF_PROXIED" == "1" || "$CF_PROXIED" == "true" ]] && prox_bool="true"
            local rec_check; rec_check=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records?type=A&name=$CF_DOMAIN" \
                -H "Authorization: Bearer $CF_API_TOKEN" \
                -H "Content-Type: application/json" --max-time 10)
            local rec_id; rec_id=$(echo "$rec_check" | grep -Po '"id":"\K[^"]*' | head -1)
            if [[ -n "$rec_id" ]]; then
                curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records/$rec_id" \
                    -H "Authorization: Bearer $CF_API_TOKEN" \
                    -H "Content-Type: application/json" \
                    --data "{\"content\":\"$new_ip\",\"proxied\":$prox_bool}" > /dev/null
                echo -e "${C_GREEN}✅ Cloudflare Domain ($CF_DOMAIN) IP updated to: ${C_CYAN}$new_ip${C_RESET}"
            fi
        fi
    elif [ -f "$DNS_INFO_FILE" ]; then
        local ROOT_DOMAIN="" SUBDOMAIN="" DESEC_TOKEN=""
        source "$DNS_INFO_FILE" 2>/dev/null
        ROOT_DOMAIN="${ROOT_DOMAIN:-$DESEC_DOMAIN}"
        DESEC_TOKEN="${DESEC_TOKEN:-79BLgHoLMdeZeRUnPJeQP3P6hzf9}"
        if [[ -n "$ROOT_DOMAIN" && -n "$SUBDOMAIN" && -n "$DESEC_TOKEN" ]]; then
            curl -s -X PATCH "https://desec.io/api/v1/domains/$ROOT_DOMAIN/rrsets/$SUBDOMAIN/A/" \
                -H "Authorization: Token $DESEC_TOKEN" \
                -H "Content-Type: application/json" \
                --data "{\"records\": [\"$new_ip\"], \"ttl\": 3600}" > /dev/null
            echo -e "${C_GREEN}✅ deSEC Subdomain IP updated to: ${C_CYAN}$new_ip${C_RESET}"
        fi
    else
        echo -e "${C_GREEN}✅ Server IP verified: ${C_CYAN}$new_ip${C_RESET}"
    fi
    press_enter
}

inspect_dns_resolution() {
    clear; show_banner
    echo
    menu_section "DNS RESOLUTION INSPECTOR" "$C_TITLE"
    echo
    local active_domain=""
    if [ -f "$DNS_INFO_FILE" ]; then
        source "$DNS_INFO_FILE" 2>/dev/null
        active_domain="$FULL_DOMAIN"
    elif [ -f "/etc/firewallfalcon/custom_domain.info" ]; then
        source "/etc/firewallfalcon/custom_domain.info" 2>/dev/null
        active_domain="$CUSTOM_DOMAIN"
    fi

    if [[ -z "$active_domain" ]]; then
        echo -e "  ${C_RED}❌ No domain configured to inspect.${C_RESET}"
        press_enter
        return
    fi

    local server_ip; server_ip=$(curl -s -4 icanhazip.com --max-time 5 2>/dev/null)
    echo -e "  ${C_CYAN}Domain   :${C_RESET} ${C_YELLOW}$active_domain${C_RESET}"
    echo -e "  ${C_CYAN}Server IP:${C_RESET} ${C_WHITE}$server_ip${C_RESET}"
    echo
    echo -e "  ${C_BLUE}Inspecting DNS resolution...${C_RESET}"

    local resolved_ip=""
    if command -v getent &>/dev/null; then
        resolved_ip=$(getent ahostsv4 "$active_domain" 2>/dev/null | head -1 | awk '{print $1}')
    fi
    [[ -z "$resolved_ip" ]] && resolved_ip=$(ping -c1 "$active_domain" 2>/dev/null | head -1 | grep -Po '(?<=\().*?(?=\))')

    if [[ "$resolved_ip" == "$server_ip" ]]; then
        echo -e "\n  ${C_GREEN}✅ RESOLVED MATCH:${C_RESET} $active_domain -> ${C_GREEN}$resolved_ip${C_RESET}"
        echo -e "  ${C_DIM}Domain is correctly pointed to this server.${C_RESET}"
    elif [[ -n "$resolved_ip" ]]; then
        echo -e "\n  ${C_RED}⚠️ RESOLVED MISMATCH:${C_RESET} $active_domain -> ${C_RED}$resolved_ip${C_RESET}"
        echo -e "  ${C_DIM}Domain points to $resolved_ip but server IP is $server_ip.${C_RESET}"
    else
        echo -e "\n  ${C_YELLOW}⚠️ RESOLUTION PENDING:${C_RESET} Could not resolve $active_domain yet."
        echo -e "  ${C_DIM}DNS propagation may take a few minutes.${C_RESET}"
    fi
    echo
    press_enter
}

ssl_cert_manager_menu() {
    while true; do
        clear; show_banner
        echo
        menu_section "SSL CERTIFICATE MANAGER" "$C_TITLE"
        echo
        local active_domain=""
        if [ -f "$DNS_INFO_FILE" ]; then
            source "$DNS_INFO_FILE" 2>/dev/null
            active_domain="$FULL_DOMAIN"
        elif [ -f "/etc/firewallfalcon/custom_domain.info" ]; then
            source "/etc/firewallfalcon/custom_domain.info" 2>/dev/null
            active_domain="$CUSTOM_DOMAIN"
        fi

        if [[ -n "$active_domain" && -d "/etc/letsencrypt/live/$active_domain" ]]; then
            echo -e "  ${C_CYAN}Domain    :${C_RESET} ${C_YELLOW}$active_domain${C_RESET}"
            echo -e "  ${C_CYAN}SSL Status:${C_RESET} ${C_GREEN}Active (Let's Encrypt)${C_RESET}"
        else
            echo -e "  ${C_CYAN}Domain    :${C_RESET} ${C_YELLOW}${active_domain:-None}${C_RESET}"
            echo -e "  ${C_CYAN}SSL Status:${C_RESET} ${C_RED}Not Issued${C_RESET}"
        fi
        echo
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[1]" "Issue Let's Encrypt SSL Cert"
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[2]" "View SSL Certificate Details"
        echo
        printf "  ${C_DANGER}%-4s${C_RESET} %s\n" "[0]" "Return"
        echo
        if ! read -r -p "$(echo -e ${C_PROMPT}"> Select an option: "${C_RESET})" ssl_act; then
            return
        fi
        case "$ssl_act" in
            1)
                if [[ -z "$active_domain" ]]; then
                    echo -e "\n${C_RED}❌ Please configure a domain first before issuing SSL.${C_RESET}"
                    press_enter
                    continue
                fi
                echo -e "\n${C_BLUE}Installing Certbot and issuing SSL certificate for $active_domain...${C_RESET}"
                if ! command -v certbot &>/dev/null; then
                    apt-get update &>/dev/null && apt-get install -y certbot &>/dev/null || yum install -y certbot &>/dev/null
                fi
                certbot certonly --standalone --non-interactive --agree-tos --register-unsafely-without-email -d "$active_domain"
                if [[ -d "/etc/letsencrypt/live/$active_domain" ]]; then
                    echo -e "\n${C_GREEN}✅ SSL Certificate issued successfully for $active_domain!${C_RESET}"
                else
                    echo -e "\n${C_RED}❌ Certbot failed to issue certificate. Ensure port 80 is open and domain points to server IP.${C_RESET}"
                fi
                press_enter
                ;;
            2)
                if [[ -n "$active_domain" && -f "/etc/letsencrypt/live/$active_domain/cert.pem" ]]; then
                    echo -e "\n${C_CYAN}Certificate Info:${C_RESET}"
                    openssl x509 -in "/etc/letsencrypt/live/$active_domain/cert.pem" -noout -dates -issuer 2>/dev/null
                else
                    echo -e "\n${C_YELLOW}ℹ️ No SSL certificate active for $active_domain.${C_RESET}"
                fi
                press_enter
                ;;
            0) return ;;
            *) invalid_option ;;
        esac
    done
}

CLOUDFLARE_INFO_FILE="/etc/firewallfalcon/cloudflare.info"

cloudflare_menu() {
    while true; do
        clear; show_banner
        echo
        menu_section "CLOUDFLARE INTEGRATION" "$C_TITLE"
        echo

        local cf_token="" cf_zone="" cf_domain="" cf_proxied="0"
        if [ -f "$CLOUDFLARE_INFO_FILE" ]; then
            source "$CLOUDFLARE_INFO_FILE" 2>/dev/null
            cf_token="$CF_API_TOKEN"
            cf_zone="$CF_ZONE_ID"
            cf_domain="$CF_DOMAIN"
            cf_proxied="${CF_PROXIED:-0}"
        fi

        local masked_token="None"
        if [[ -n "$cf_token" ]]; then
            if [ ${#cf_token} -ge 8 ]; then
                masked_token="${cf_token:0:4}••••••••${cf_token: -4}"
            else
                masked_token="••••••••"
            fi
        fi

        local proxy_badge
        if [[ "$cf_proxied" == "1" || "$cf_proxied" == "true" ]]; then
            proxy_badge="${C_YELLOW}🟠 Proxied (CDN On)${C_RESET}"
        else
            proxy_badge="${C_WHITE}⚪ DNS Only (Direct)${C_RESET}"
        fi

        echo -e "  ${C_CYAN}Active Domain:${C_RESET} ${C_YELLOW}${cf_domain:-Not Set}${C_RESET}"
        echo -e "  ${C_CYAN}Zone ID      :${C_RESET} ${C_WHITE}${cf_zone:-Not Set}${C_RESET}"
        echo -e "  ${C_CYAN}API Token    :${C_RESET} ${C_DIM}${masked_token}${C_RESET}"
        echo -e "  ${C_CYAN}Default Proxy:${C_RESET} ${proxy_badge}"
        echo

        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[1]" "Setup / Update API Token (Auto-Discover Domains)"
        if [[ -n "$cf_token" && -n "$cf_zone" ]]; then
            printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[2]" "Sync Server IP (Create / Update A Record)"
            printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[3]" "Switch Active Domain"
            printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[4]" "Toggle Default Proxy Mode"
            printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[5]" "List & Inspect DNS Records"
            printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[6]" "Remove Cloudflare Configuration"
        fi
        echo
        printf "  ${C_DANGER}%-4s${C_RESET} %s\n" "[0]" "Return"
        echo

        if ! read -r -p "$(echo -e ${C_PROMPT}"> Select an option: "${C_RESET})" cf_act; then
            return
        fi

        case "$cf_act" in
            1|3)
                local in_token="$cf_token"
                if [[ "$cf_act" == "1" || -z "$in_token" ]]; then
                    echo -e "\n${C_BLUE}--- Cloudflare API Setup ---${C_RESET}"
                    echo -e "${C_DIM}• Enter your Cloudflare API Token (with Zone.DNS permissions).${C_RESET}"
                    echo -e "${C_DIM}• All domains linked to your account will be automatically discovered.${C_RESET}"
                    echo -e "${C_DIM}• Enter 0 to cancel and return.${C_RESET}\n"
                    
                    read -r -p "$(echo -e "${C_BLUE}👉 Enter API Token [${masked_token} | 0 to cancel]: ${C_RESET}")" user_token
                    if [[ "$user_token" == "0" || "$user_token" == "q" || "$user_token" == "Q" ]]; then
                        echo -e "\n${C_YELLOW}↩️ Canceled.${C_RESET}"
                        sleep 0.8
                        continue
                    fi
                    user_token=${user_token:-$cf_token}
                    if [[ -z "$user_token" ]]; then
                        echo -e "\n${C_YELLOW}↩️ API Token not provided. Operation canceled.${C_RESET}"
                        press_enter
                        continue
                    fi
                    in_token="$user_token"
                fi

                echo -e "\n${C_BLUE}Connecting to Cloudflare and fetching available domains...${C_RESET}"
                local zones_res; zones_res=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?per_page=50" \
                    -H "Authorization: Bearer $in_token" \
                    -H "Content-Type: application/json" --max-time 12)

                local is_success; is_success=$(echo "$zones_res" | grep -o '"success":true')
                if [[ -z "$is_success" ]]; then
                    echo -e "\n${C_RED}❌ Failed to connect to Cloudflare API.${C_RESET}"
                    local err_msg; err_msg=$(echo "$zones_res" | grep -Po '"message":"\K[^"]*' | head -1)
                    [[ -n "$err_msg" ]] && echo -e "   • Error: ${C_YELLOW}$err_msg${C_RESET}"
                    press_enter
                    continue
                fi

                local NUM_ZONES=0
                if command -v python3 &>/dev/null; then
                    eval "$(python3 -c "
import sys, json
try:
    d = json.loads('''$zones_res''')
    zones = d.get('result', [])
    print(f'NUM_ZONES={len(zones)}')
    for i, z in enumerate(zones):
        zid = z.get('id', '')
        zname = z.get('name', '')
        zst = z.get('status', 'active')
        print(f'Z_ID_{i}=\"{zid}\"')
        print(f'Z_NAME_{i}=\"{zname}\"')
        print(f'Z_STATUS_{i}=\"{zst}\"')
except Exception:
    print('NUM_ZONES=0')
")"
                fi

                if [[ "$NUM_ZONES" -le 0 ]]; then
                    echo -e "\n${C_YELLOW}⚠️ No zones (domains) found in this Cloudflare account.${C_RESET}"
                    press_enter
                    continue
                fi

                echo -e "\n${C_GREEN}✅ Connected successfully! Found $NUM_ZONES domain(s):${C_RESET}\n"
                local idx
                for ((idx=0; idx<NUM_ZONES; idx++)); do
                    local zid_var="Z_ID_$idx"
                    local zname_var="Z_NAME_$idx"
                    local zst_var="Z_STATUS_$idx"
                    local zn="${!zname_var}"
                    local zs="${!zst_var}"
                    local mark=""
                    [[ "$zn" == "$cf_domain" ]] && mark="${C_GREEN} (Current Default)${C_RESET}"
                    printf "  ${C_CHOICE}[%2d]${C_RESET} %-30s ${C_DIM}(%s)${C_RESET}%b\n" "$((idx+1))" "$zn" "$zs" "$mark"
                done
                echo
                printf "  ${C_DANGER}%-4s${C_RESET} %s\n" "[ 0]" "Cancel"
                echo

                read -r -p "$(echo -e ${C_PROMPT}"> Select domain number to set as active default [1]: "${C_RESET})" z_sel
                if [[ "$z_sel" == "0" || "$z_sel" == "q" || "$z_sel" == "Q" ]]; then
                    echo -e "\n${C_YELLOW}↩️ Canceled.${C_RESET}"
                    sleep 0.8
                    continue
                fi
                z_sel=${z_sel:-1}
                if ! [[ "$z_sel" =~ ^[0-9]+$ ]] || [ "$z_sel" -lt 1 ] || [ "$z_sel" -gt "$NUM_ZONES" ]; then
                    echo -e "\n${C_RED}❌ Invalid selection.${C_RESET}"
                    press_enter
                    continue
                fi

                local sel_idx=$((z_sel - 1))
                local zid_var="Z_ID_$sel_idx"
                local zname_var="Z_NAME_$sel_idx"
                local chosen_zone="${!zid_var}"
                local chosen_domain="${!zname_var}"

                mkdir -p "/etc/firewallfalcon" 2>/dev/null
                cat > "$CLOUDFLARE_INFO_FILE" <<EOF
CF_API_TOKEN="$in_token"
CF_ZONE_ID="$chosen_zone"
CF_DOMAIN="$chosen_domain"
CF_PROXIED="${cf_proxied:-0}"
EOF
                chmod 600 "$CLOUDFLARE_INFO_FILE" 2>/dev/null

                echo -e "\n${C_GREEN}✅ Active default domain set to: ${C_YELLOW}$chosen_domain${C_RESET}"
                echo -e "   • Zone ID: ${C_CYAN}$chosen_zone${C_RESET}"
                press_enter
                ;;
            2)
                if [[ -z "$cf_token" || -z "$cf_zone" ]]; then
                    echo -e "\n${C_RED}❌ Please configure API Token first.${C_RESET}"
                    press_enter; continue
                fi
                local server_ip; server_ip=$(curl -s -4 icanhazip.com --max-time 5 2>/dev/null)
                if [[ -z "$server_ip" ]]; then
                    echo -e "\n${C_RED}❌ Could not detect server public IP.${C_RESET}"
                    press_enter; continue
                fi

                read -r -p "$(echo -e "${C_BLUE}👉 Enter record name / subdomain to sync [${cf_domain} | 0 to cancel]: ${C_RESET}")" sync_dom
                if [[ "$sync_dom" == "0" || "$sync_dom" == "q" || "$sync_dom" == "Q" ]]; then
                    echo -e "\n${C_YELLOW}↩️ Canceled.${C_RESET}"
                    sleep 0.8
                    continue
                fi
                sync_dom=${sync_dom:-$cf_domain}

                local prox_bool="false"
                [[ "$cf_proxied" == "1" || "$cf_proxied" == "true" ]] && prox_bool="true"

                echo -e "\n${C_BLUE}Syncing A record '$sync_dom' -> '$server_ip' (Proxy: $prox_bool)...${C_RESET}"
                
                local rec_check; rec_check=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$cf_zone/dns_records?type=A&name=$sync_dom" \
                    -H "Authorization: Bearer $cf_token" \
                    -H "Content-Type: application/json" --max-time 10)
                
                local rec_id; rec_id=$(echo "$rec_check" | grep -Po '"id":"\K[^"]*' | head -1)

                if [[ -n "$rec_id" ]]; then
                    local upd_res; upd_res=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$cf_zone/dns_records/$rec_id" \
                        -H "Authorization: Bearer $cf_token" \
                        -H "Content-Type: application/json" \
                        --data "{\"content\":\"$server_ip\",\"proxied\":$prox_bool}" --max-time 10)
                    if echo "$upd_res" | grep -q '"success":true'; then
                        echo -e "\n${C_GREEN}✅ A Record updated successfully: ${C_YELLOW}$sync_dom${C_RESET} -> ${C_CYAN}$server_ip${C_RESET}"
                    else
                        echo -e "\n${C_RED}❌ Failed to update A record.${C_RESET}"
                    fi
                else
                    local create_res; create_res=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$cf_zone/dns_records" \
                        -H "Authorization: Bearer $cf_token" \
                        -H "Content-Type: application/json" \
                        --data "{\"type\":\"A\",\"name\":\"$sync_dom\",\"content\":\"$server_ip\",\"ttl\":1,\"proxied\":$prox_bool}" --max-time 10)
                    if echo "$create_res" | grep -q '"success":true'; then
                        echo -e "\n${C_GREEN}✅ A Record created successfully: ${C_YELLOW}$sync_dom${C_RESET} -> ${C_CYAN}$server_ip${C_RESET}"
                    else
                        echo -e "\n${C_RED}❌ Failed to create A record.${C_RESET}"
                    fi
                fi
                press_enter
                ;;
            4)
                local new_p="0"
                if [[ "$cf_proxied" == "0" || "$cf_proxied" == "false" ]]; then
                    new_p="1"
                fi
                sed -i "/CF_PROXIED=/d" "$CLOUDFLARE_INFO_FILE" 2>/dev/null
                echo "CF_PROXIED=\"$new_p\"" >> "$CLOUDFLARE_INFO_FILE"
                echo -e "\n${C_GREEN}✅ Default Proxy Mode updated to: $([ "$new_p" == "1" ] && echo "🟠 Proxied" || echo "⚪ DNS Only")${C_RESET}"
                press_enter
                ;;
            5)
                echo -e "\n${C_BLUE}Fetching DNS records from Cloudflare...${C_RESET}\n"
                local recs_json; recs_json=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$cf_zone/dns_records?per_page=50" \
                    -H "Authorization: Bearer $cf_token" \
                    -H "Content-Type: application/json" --max-time 10)
                
                if echo "$recs_json" | grep -q '"success":true'; then
                    echo -e "  ${C_BOLD}${C_CYAN}Type   Proxy   Name                                 Points To${C_RESET}"
                    echo -e "  ${C_DIM}-------------------------------------------------------------------------${C_RESET}"
                    
                    if command -v python3 &>/dev/null; then
                        python3 -c "
import sys, json
try:
    d = json.loads('''$recs_json''')
    for r in d.get('result', []):
        t = r.get('type', '')
        p = '🟠 ON ' if r.get('proxied') else '⚪ OFF'
        n = r.get('name', '')[:35]
        c = r.get('content', '')[:30]
        print(f'  {t:<6} {p:<7} {n:<36} {c}')
except Exception as e:
    print(e)
"
                    else
                        echo "$recs_json" | grep -Po '("type":"[^"]*"|"name":"[^"]*"|"content":"[^"]*")'
                    fi
                else
                    echo -e "${C_RED}❌ Failed to fetch DNS records.${C_RESET}"
                fi
                echo
                press_enter
                ;;
            6)
                read -r -p "$(echo -e "${C_RED}👉 Remove Cloudflare configuration? [y/N | 0 to cancel]: ${C_RESET}")" rm_cf
                if [[ "$rm_cf" == "y" || "$rm_cf" == "Y" ]]; then
                    rm -f "$CLOUDFLARE_INFO_FILE"
                    echo -e "\n${C_GREEN}✅ Cloudflare configuration removed.${C_RESET}"
                else
                    echo -e "\n${C_YELLOW}↩️ Canceled.${C_RESET}"
                fi
                press_enter
                ;;
            0) return ;;
            *) invalid_option ;;
        esac
    done
}

dns_menu() {
    while true; do
        clear; show_banner
        echo
        menu_section "DOMAIN & DNS MANAGEMENT" "$C_TITLE"
        echo
        
        local active_domain="None" provider="None"
        if [ -f "$CLOUDFLARE_INFO_FILE" ]; then
            source "$CLOUDFLARE_INFO_FILE" 2>/dev/null
            active_domain="${CF_DOMAIN:-None}"
            provider="Cloudflare"
        elif [ -f "$DNS_INFO_FILE" ]; then
            source "$DNS_INFO_FILE" 2>/dev/null
            active_domain="${FULL_DOMAIN:-None}"
            provider="deSEC (Free)"
        elif [ -f "/etc/firewallfalcon/custom_domain.info" ]; then
            source "/etc/firewallfalcon/custom_domain.info" 2>/dev/null
            active_domain="${CUSTOM_DOMAIN:-None}"
            provider="Custom Domain"
        fi

        echo -e "  ${C_CYAN}Active Domain:${C_RESET} ${C_YELLOW}${active_domain}${C_RESET}"
        echo -e "  ${C_CYAN}Provider     :${C_RESET} ${C_CYAN}${provider}${C_RESET}"
        echo
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[1]" "Free Subdomain (deSEC)"
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[2]" "Cloudflare Integration"
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[3]" "Custom Domain Setup"
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[4]" "Update IP (DDNS)"
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[5]" "DNS Resolution Inspector"
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[6]" "SSL Certificate Manager"
        echo
        printf "  ${C_DANGER}%-4s${C_RESET} %s\n" "[0]" "Return"
        echo
        if ! read -r -p "$(echo -e ${C_PROMPT}"> Select an option: "${C_RESET})" dns_act; then
            return
        fi
        case "$dns_act" in
            1) desec_subdomain_menu ;;
            2) cloudflare_menu ;;
            3) custom_domain_menu ;;
            4) update_domain_ip ;;
            5) inspect_dns_resolution ;;
            6) ssl_cert_manager_menu ;;
            0) return ;;
            *) invalid_option ;;
        esac
    done
}

_select_user_interface() {
    local title="$1"
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}${title}${C_RESET}\n"
    if [[ ! -s $DB_FILE ]]; then
        echo -e "${C_YELLOW}ℹ️ No users found in the database.${C_RESET}"
        SELECTED_USER="NO_USERS"; return
    fi
    
    mapfile -t all_users < <(cut -d: -f1 "$DB_FILE" | sort)
    local -A all_user_lookup=()
    local username
    for username in "${all_users[@]}"; do
        all_user_lookup["$username"]=1
    done
    
    if [ ${#all_users[@]} -ge 15 ]; then
        read -p "👉 Enter a search term (or press Enter to list all): " search_term
        if [[ -n "$search_term" ]]; then
            mapfile -t users < <(printf "%s\n" "${all_users[@]}" | grep -i "$search_term")
        else
            users=("${all_users[@]}")
        fi
    else
        users=("${all_users[@]}")
    fi

    if [ ${#users[@]} -eq 0 ]; then
        echo -e "\n${C_YELLOW}ℹ️ No users found matching your criteria.${C_RESET}"
        SELECTED_USER="NO_USERS"; return
    fi
    echo -e "\nPlease select a user:\n"
    for i in "${!users[@]}"; do
        printf "  ${C_GREEN}[%2d]${C_RESET} %s\n" "$((i+1))" "${users[$i]}"
    done
    echo -e "\n  ${C_RED} [ 0]${C_RESET} ↩️ Cancel"
    echo -e "${C_CYAN}💡 Tip: you can also type the exact username directly.${C_RESET}"
    echo
    local choice
    while true; do
        if ! read -r -p "👉 Enter the number or exact username (0 to cancel): " choice; then
            echo
            SELECTED_USER=""
            return
        fi
        choice=$(echo "$choice" | xargs 2>/dev/null || echo "$choice")
        if [[ -z "$choice" || "$choice" == "0" || "${choice,,}" == "cancel" || "${choice,,}" == "q" ]]; then
            SELECTED_USER=""
            return
        fi

        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#users[@]}" ]; then
            SELECTED_USER="${users[$((choice-1))]}"
            return
        else
            # Exact username lookup
            local matched=""
            for u in "${all_users[@]}"; do
                if [[ "$u" == "$choice" ]]; then
                    matched="$u"
                    break
                fi
            done
            if [[ -n "$matched" ]]; then
                SELECTED_USER="$matched"
                return
            else
                echo -e "${C_RED}❌ Invalid selection. Please try again or enter 0 to cancel.${C_RESET}"
            fi
        fi
    done
}

_select_multi_user_interface() {
    local title="$1"
    local include_orphan_users="${2:-false}"
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}${title}${C_RESET}\n"
    SELECTED_USERS=()
    local -a all_users=()
    local -a orphan_users=()
    local -A all_user_lookup=()
    local -A orphan_user_lookup=()
    local username

    if [[ -s $DB_FILE ]]; then
        mapfile -t all_users < <(cut -d: -f1 "$DB_FILE" | sort)
    fi

    if [[ "$include_orphan_users" == "true" ]]; then
        mapfile -t orphan_users < <(get_firewallfalcon_orphan_users)
        for username in "${orphan_users[@]}"; do
            orphan_user_lookup["$username"]=1
            if ! printf "%s\n" "${all_users[@]}" | grep -Fxq "$username"; then
                all_users+=("$username")
            fi
        done
        if [[ ${#all_users[@]} -gt 0 ]]; then
            mapfile -t all_users < <(printf "%s\n" "${all_users[@]}" | sort)
        fi
    fi

    if [[ ${#all_users[@]} -eq 0 ]]; then
        echo -e "${C_YELLOW}ℹ️ No users found in the manager database.${C_RESET}"
        if [[ "$include_orphan_users" == "true" ]]; then
            echo -e "${C_DIM}No orphan DAHOOM system users were found either.${C_RESET}"
        fi
        SELECTED_USERS=("NO_USERS"); return
    fi

    for username in "${all_users[@]}"; do
        all_user_lookup["$username"]=1
    done
    
    if [ ${#all_users[@]} -ge 15 ]; then
        read -p "👉 Enter a search term (or press Enter to list all): " search_term
        if [[ -n "$search_term" ]]; then
            mapfile -t users < <(printf "%s\n" "${all_users[@]}" | grep -i "$search_term")
        else
            users=("${all_users[@]}")
        fi
    else
        users=("${all_users[@]}")
    fi

    if [ ${#users[@]} -eq 0 ]; then
        echo -e "\n${C_YELLOW}ℹ️ No users found matching your criteria.${C_RESET}"
        SELECTED_USERS=("NO_USERS"); return
    fi
    echo -e "\nPlease select users:\n"
    for i in "${!users[@]}"; do
        local display_user="${users[$i]}"
        if [[ "$include_orphan_users" == "true" && -n "${orphan_user_lookup[${users[$i]}]+x}" ]]; then
            display_user="${display_user} ${C_DIM}(system-only)${C_RESET}"
        fi
        printf "  ${C_GREEN}[%2d]${C_RESET} %s\n" "$((i+1))" "$display_user"
    done
    echo -e "\n  ${C_GREEN}[all]${C_RESET} Select ALL listed users"
    echo -e "  ${C_RED}  [0]${C_RESET} ↩️ Cancel and return to main menu"
    echo -e "\n${C_CYAN}💡 You can select multiple by number, range, or exact username.${C_RESET}"
    echo -e "${C_CYAN}   Examples: '1 3 5' or '1,3' or '1-4' or 'alice bob'${C_RESET}"
    if [[ "$include_orphan_users" == "true" ]]; then
        echo -e "${C_CYAN}   Users marked '(system-only)' are old accounts still on the VPS but missing from users.db${C_RESET}"
    fi
    echo
    local choice
    while true; do
        if ! read -r -p "👉 Enter user numbers or usernames: " choice; then
            echo
            SELECTED_USERS=()
            return
        fi
        choice=${choice//,/ } # Replace commas with spaces
        
        if [[ -z "$choice" ]]; then
            echo -e "${C_RED}❌ Invalid selection. Please try again.${C_RESET}"
            continue
        fi

        if [[ "$choice" == "0" ]]; then
            SELECTED_USERS=(); return
        fi
        
        if [[ "${choice,,}" == "all" ]]; then
            SELECTED_USERS=("${users[@]}")
            return
        fi
        
        local valid=true
        local selected_indices=()
        local selected_names=()
        for token in $choice; do
            if [[ "$token" =~ ^[0-9]+-[0-9]+$ ]]; then
                local start=${token%-*}
                local end=${token#*-}
                if [ "$start" -le "$end" ]; then
                    for (( idx=start; idx<=end; idx++ )); do
                        if [ "$idx" -ge 1 ] && [ "$idx" -le "${#users[@]}" ]; then
                            selected_indices+=($idx)
                        else
                            valid=false; break
                        fi
                    done
                else
                    valid=false; break
                fi
            elif [[ "$token" =~ ^[0-9]+$ ]]; then
                if [ "$token" -ge 1 ] && [ "$token" -le "${#users[@]}" ]; then
                    selected_indices+=($token)
                else
                    # Check if numeric token is an exact username
                    local matched_num=""
                    for u in "${all_users[@]}"; do
                        if [[ "$u" == "$token" ]]; then matched_num="$u"; break; fi
                    done
                    if [[ -n "$matched_num" ]]; then
                        selected_names+=("$matched_num")
                    else
                        valid=false; break
                    fi
                fi
            else
                local matched_name=""
                for u in "${all_users[@]}"; do
                    if [[ "$u" == "$token" ]]; then matched_name="$u"; break; fi
                done
                if [[ -n "$matched_name" ]]; then
                    selected_names+=("$matched_name")
                else
                    valid=false; break
                fi
            fi
        done
        
        if [[ "$valid" == true && ( ${#selected_indices[@]} -gt 0 || ${#selected_names[@]} -gt 0 ) ]]; then
            mapfile -t unique_indices < <(printf "%s\n" "${selected_indices[@]}" | sort -u -n)
            for idx in "${unique_indices[@]}"; do
                SELECTED_USERS+=("${users[$((idx-1))]}")
            done
            if (( ${#selected_names[@]} > 0 )); then
                mapfile -t unique_names < <(printf "%s\n" "${selected_names[@]}" | sort -u)
                for username in "${unique_names[@]}"; do
                    if [[ -n "$username" ]] && ! printf "%s\n" "${SELECTED_USERS[@]}" | grep -Fxq "$username"; then
                        SELECTED_USERS+=("$username")
                    fi
                done
            fi
            return
        else
            echo -e "${C_RED}❌ Invalid selection. Please check your numbers or usernames.${C_RESET}"
            SELECTED_USERS=()
            selected_indices=()
            selected_names=()
        fi
    done
}

get_user_status() {
    local username="$1"
    if ! id "$username" &>/dev/null; then echo -e "${C_RED}Not Found${C_RESET}"; return; fi
    local expiry_date=$(grep "^$username:" "$DB_FILE" | cut -d: -f3)
    if passwd -S "$username" 2>/dev/null | grep -q " L "; then echo -e "${C_YELLOW}🔒 Locked${C_RESET}"; return; fi
    local expiry_ts=$(date -d "$expiry_date" +%s 2>/dev/null || echo 0)
    local current_ts=$(date +%s)
    if [[ $expiry_ts -lt $current_ts ]]; then echo -e "${C_RED}🗓️ Expired${C_RESET}"; return; fi
    echo -e "${C_GREEN}🟢 Active${C_RESET}"
}

create_user() {
    clear; show_banner
    echo
    menu_section "CREATE SSH USER" "$C_TITLE"
    echo
    read -p "$(echo -e "${C_BLUE}👉 Username (Enter or 0 to cancel): ${C_RESET}")" username
    username=$(echo "$username" | xargs 2>/dev/null || echo "$username")
    local adopt_existing=false
    if [[ -z "$username" || "$username" == "0" || "${username,,}" == "cancel" || "${username,,}" == "q" ]]; then
        echo -e "\n${C_YELLOW}↩️ Creation cancelled.${C_RESET}"
        return
    fi
    if db_has_user "$username"; then
        echo -e "\n${C_RED}❌ Error: User '$username' already exists in database.${C_RESET}"
        return
    fi
    if id "$username" &>/dev/null; then
        if is_firewallfalcon_orphan_user "$username"; then
            echo -e "\n${C_YELLOW}⚠️ User '$username' exists on system (orphan account).${C_RESET}"
            read -p "$(echo -e "${C_BLUE}👉 Adopt and manage this user? (y/n) [y]: ${C_RESET}")" adopt_confirm
            adopt_confirm=${adopt_confirm:-y}
            if [[ "$adopt_confirm" == "y" || "$adopt_confirm" == "Y" ]]; then
                adopt_existing=true
            else
                echo -e "\n${C_YELLOW}❌ Creation cancelled.${C_RESET}"
                return
            fi
        else
            echo -e "\n${C_RED}❌ Error: System user '$username' exists and is not a managed SSH account.${C_RESET}"
            return
        fi
    fi

    local password=""
    while true; do
        read -p "$(echo -e "${C_BLUE}👉 Password (Enter = auto-generate): ${C_RESET}")" password
        if [[ -z "$password" ]]; then
            password=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 8)
            echo -e "   ${C_GREEN}🔑 Auto Password: ${C_YELLOW}$password${C_RESET}"
            break
        else
            check_password_strength "$password"
            break
        fi
    done

    read -p "$(echo -e "${C_BLUE}👉 Duration in days (or 'never') [30]: ${C_RESET}")" days
    local expire_date
    if [[ "${days,,}" == "never" || "$days" == "0" ]]; then
        expire_date="Never"
    else
        days=${days:-30}
        if ! [[ "$days" =~ ^[0-9]+$ ]]; then echo -e "\n${C_RED}❌ Invalid duration number.${C_RESET}"; return; fi
        expire_date=$(date -d "+$days days" +%Y-%m-%d)
    fi

    read -p "$(echo -e "${C_BLUE}👉 Simultaneous Connections [1]: ${C_RESET}")" limit
    limit=${limit:-1}
    if ! [[ "$limit" =~ ^[0-9]+$ ]]; then echo -e "\n${C_RED}❌ Invalid limit number.${C_RESET}"; return; fi

    read -p "$(echo -e "${C_BLUE}👉 Total Bandwidth GB (0 = unlimited) [0]: ${C_RESET}")" bandwidth_gb
    bandwidth_gb=${bandwidth_gb:-0}
    if ! [[ "$bandwidth_gb" =~ ^[0-9]+\.?[0-9]*$ ]]; then echo -e "\n${C_RED}❌ Invalid bandwidth number.${C_RESET}"; return; fi

    read -p "$(echo -e "${C_BLUE}👉 Daily Bandwidth GB (0 = unlimited) [0]: ${C_RESET}")" daily_bandwidth_gb
    daily_bandwidth_gb=${daily_bandwidth_gb:-0}
    if ! [[ "$daily_bandwidth_gb" =~ ^[0-9]+\.?[0-9]*$ ]]; then echo -e "\n${C_RED}❌ Invalid daily bandwidth number.${C_RESET}"; return; fi

    local bw_display="Unlimited"
    if [[ "$bandwidth_gb" != "0" ]]; then bw_display="${bandwidth_gb} GB"; fi
    local daily_bw_display="Unlimited"
    if [[ "$daily_bandwidth_gb" != "0" ]]; then daily_bw_display="${daily_bandwidth_gb} GB/day"; fi

    echo
    echo -e "  ${C_CYAN}┌── Account Summary ─────────────────────────┐${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET}  Username  : ${C_YELLOW}$username${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET}  Password  : ${C_YELLOW}$password${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET}  Expires   : ${C_YELLOW}$expire_date${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET}  Sessions  : ${C_YELLOW}$limit${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET}  Total BW  : ${C_YELLOW}$bw_display${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET}  Daily BW  : ${C_YELLOW}$daily_bw_display${C_RESET}"
    echo -e "  ${C_CYAN}└────────────────────────────────────────────┘${C_RESET}"
    echo
    echo -e "  ${C_GREEN}[1]${C_RESET} Create user now"
    echo -e "  ${C_RED}[0]${C_RESET} Cancel"
    echo
    read -p "$(echo -e "${C_BLUE}👉 Select option [1]: ${C_RESET}")" confirm_create
    confirm_create=${confirm_create:-1}
    if [[ "$confirm_create" != "1" ]]; then
        echo -e "\n${C_YELLOW}❌ Creation cancelled.${C_RESET}"
        return
    fi

    ensure_firewallfalcon_system_group
    if [[ "$adopt_existing" == "true" ]]; then
        usermod -s /usr/sbin/nologin "$username" &>/dev/null
    else
        useradd -m -s /usr/sbin/nologin "$username"
    fi
    usermod -aG "$FF_USERS_GROUP" "$username" 2>/dev/null
    echo "$username:$password" | chpasswd
    [[ "$expire_date" != "Never" ]] && chage -E "$expire_date" "$username"
    echo "$username:$password:$expire_date:$limit:$bandwidth_gb:$daily_bandwidth_gb:trial" >> "$DB_FILE"
    _log_action "CREATE" "$username" "exp=$expire_date conn=$limit bw=$bw_display"
    send_telegram_msg "👤 <b>New User Created</b>%0AUser: <b>$username</b>%0APassword: <b>$password</b>%0AExpires: $expire_date%0ALimit: $limit"

    clear; show_banner
    echo
    if [[ "$adopt_existing" == "true" ]]; then
        echo -e "${C_GREEN}✅ Existing user '$username' imported successfully!${C_RESET}\n"
    else
        echo -e "${C_GREEN}✅ User '$username' created successfully!${C_RESET}\n"
    fi
    echo -e "  ${C_CYAN}┌── Created Account ─────────────────────────┐${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET}  Username  : ${C_YELLOW}$username${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET}  Password  : ${C_YELLOW}$password${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET}  Expires   : ${C_YELLOW}$expire_date${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET}  Sessions  : ${C_YELLOW}$limit${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET}  Total BW  : ${C_YELLOW}$bw_display${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET}  Daily BW  : ${C_YELLOW}$daily_bw_display${C_RESET}"
    echo -e "  ${C_CYAN}└────────────────────────────────────────────┘${C_RESET}"
    echo
    read -p "$(echo -e "${C_BLUE}👉 Generate client config for this user? (y/n) [n]: ${C_RESET}")" gen_conf
    if [[ "$gen_conf" == "y" || "$gen_conf" == "Y" ]]; then
        generate_client_config "$username" "$password"
    fi

    invalidate_banner_cache
    refresh_dynamic_banner_routing_if_enabled
}

delete_user() {
    clear; show_banner
    echo
    menu_section "DELETE SSH USERS" "$C_TITLE"
    echo
    _select_multi_user_interface "Select User(s) to Delete" "true"
    if [[ ${#SELECTED_USERS[@]} -eq 0 || "${SELECTED_USERS[0]}" == "NO_USERS" ]]; then return; fi
    
    echo
    echo -e "  ${C_CYAN}┌── Selected Users ──────────────────────────┐${C_RESET}"
    for u in "${SELECTED_USERS[@]}"; do
        local line; line=$(grep "^$u:" "$DB_FILE" 2>/dev/null)
        if [[ -n "$line" ]]; then
            local _u2 _p2 expiry2 limit2 bw2
            IFS=: read -r _u2 _p2 expiry2 limit2 bw2 _ <<< "$line"
            echo -e "  ${C_CYAN}│${C_RESET}  ${C_YELLOW}$u${C_RESET} — Exp: ${C_RED}$expiry2${C_RESET} | Conn: ${C_CYAN}$limit2${C_RESET} | BW: ${C_ORANGE}${bw2:-0}GB${C_RESET}"
        else
            echo -e "  ${C_CYAN}│${C_RESET}  ${C_YELLOW}$u${C_RESET} ${C_DIM}(not in DB)${C_RESET}"
        fi
    done
    echo -e "  ${C_CYAN}└────────────────────────────────────────────┘${C_RESET}"
    echo
    echo -e "  ${C_GREEN}[1]${C_RESET} Export log before deleting"
    echo -e "  ${C_GREEN}[2]${C_RESET} Delete directly without log"
    echo -e "  ${C_RED}[0]${C_RESET} Cancel"
    echo
    read -p "$(echo -e "${C_BLUE}👉 Select action [2]: ${C_RESET}")" do_export
    do_export=${do_export:-2}
    if [[ "$do_export" == "0" ]]; then echo -e "\n${C_YELLOW}❌ Deletion cancelled.${C_RESET}"; return; fi
    if [[ "$do_export" == "1" ]]; then
        local export_file="/root/ff_deleted_$(date +%F).log"
        for u in "${SELECTED_USERS[@]}"; do
            grep "^$u:" "$DB_FILE" 2>/dev/null >> "$export_file"
        done
        echo -e "  ${C_GREEN}✅ Log saved: ${C_YELLOW}$export_file${C_RESET}"
    fi

    echo -e "\n${C_BLUE}🗑️ Deleting selected user(s)...${C_RESET}"
    for u in "${SELECTED_USERS[@]}"; do
        _log_action "DELETE" "$u" "by_admin"
        send_telegram_msg "🗑️ <b>User Deleted</b>%0AUser: <b>$u</b>"
    done
    delete_firewallfalcon_user_accounts "${SELECTED_USERS[@]}"
}

edit_user() {
    clear; show_banner
    echo
    menu_section "EDIT USER ACCOUNT" "$C_TITLE"
    echo
    _select_user_interface "Select User to Edit"
    local username=$SELECTED_USER
    if [[ "$username" == "NO_USERS" ]] || [[ -z "$username" ]]; then return; fi

    while true; do
        clear; show_banner
        echo
        menu_section "EDIT USER: $username" "$C_TITLE"
        
        local current_line; current_line=$(grep "^$username:" "$DB_FILE")
        local cur_pass cur_expiry cur_limit cur_bw cur_daily_bw
        IFS=: read -r _ cur_pass cur_expiry cur_limit cur_bw cur_daily_bw _ <<< "$current_line"
        [[ -z "$cur_bw" ]] && cur_bw="0"
        [[ ! "$cur_daily_bw" =~ ^[0-9]+\.?[0-9]*$ ]] && cur_daily_bw="0"
        
        local cur_bw_display="Unlimited"; [[ "$cur_bw" != "0" ]] && cur_bw_display="${cur_bw} GB"
        local cur_daily_bw_display="Unlimited"; [[ "$cur_daily_bw" != "0" ]] && cur_daily_bw_display="${cur_daily_bw} GB/day"
        
        local bw_used_display="0.00 GB"
        if [[ -f "$BANDWIDTH_DIR/${username}.usage" ]]; then
            local used_bytes=0; read -r used_bytes < "$BANDWIDTH_DIR/${username}.usage" 2>/dev/null || used_bytes=0
            [[ -n "$used_bytes" && "$used_bytes" != "0" ]] && bw_used_display=$(awk "BEGIN {printf \"%.2f GB\", $used_bytes / 1073741824}")
        fi
        
        local daily_bw_used_display="0.00 GB"
        if [[ -f "$BANDWIDTH_DIR/${username}.daily_usage" ]]; then
            local d_used_bytes=0; read -r d_used_bytes < "$BANDWIDTH_DIR/${username}.daily_usage" 2>/dev/null || d_used_bytes=0
            [[ -n "$d_used_bytes" && "$d_used_bytes" != "0" ]] && daily_bw_used_display=$(awk "BEGIN {printf \"%.2f GB\", $d_used_bytes / 1073741824}")
        fi

        echo
        echo -e "  ${C_CYAN}┌── Account Settings ────────────────────────┐${C_RESET}"
        echo -e "  ${C_CYAN}│${C_RESET}  Password  : ${C_YELLOW}$cur_pass${C_RESET}"
        echo -e "  ${C_CYAN}│${C_RESET}  Expires   : ${C_YELLOW}$cur_expiry${C_RESET}"
        echo -e "  ${C_CYAN}│${C_RESET}  Sessions  : ${C_YELLOW}$cur_limit${C_RESET}"
        echo -e "  ${C_CYAN}│${C_RESET}  Total BW  : ${C_YELLOW}$cur_bw_display${C_RESET} (${C_CYAN}Used: $bw_used_display${C_RESET})"
        echo -e "  ${C_CYAN}│${C_RESET}  Daily BW  : ${C_YELLOW}$cur_daily_bw_display${C_RESET} (${C_CYAN}Used: $daily_bw_used_display${C_RESET})"
        echo -e "  ${C_CYAN}└────────────────────────────────────────────┘${C_RESET}"
        echo
        printf "  ${C_CHOICE}%-4s${C_RESET} %-28s ${C_CHOICE}%-4s${C_RESET} %s\n" "[1]" "Change Password" "[2]" "Change Expiry Date"
        printf "  ${C_CHOICE}%-4s${C_RESET} %-28s ${C_CHOICE}%-4s${C_RESET} %s\n" "[3]" "Change Connection Limit" "[4]" "Change Total Bandwidth"
        printf "  ${C_CHOICE}%-4s${C_RESET} %-28s ${C_CHOICE}%-4s${C_RESET} %s\n" "[5]" "Change Daily Bandwidth" "[6]" "Reset Bandwidth Counters"
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[7]" "Copy Settings to User"
        echo
        printf "  ${C_WARN}%-4s${C_RESET} %s\n" "[0]" "Finish Editing"
        echo
        if ! read -r -p "$(echo -e "${C_BLUE}👉 Select detail to edit: ${C_RESET}")" edit_choice; then
            return
        fi
        case $edit_choice in
            1)
               local new_pass=""
               read -p "👉 Enter new password (Enter = auto-generate): " new_pass
               if [[ -z "$new_pass" ]]; then
                   new_pass=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 8)
                   echo -e "   ${C_GREEN}🔑 Auto Password: ${C_YELLOW}$new_pass${C_RESET}"
               else
                   check_password_strength "$new_pass"
               fi
               echo "$username:$new_pass" | chpasswd
               sed -i "s/^$username:.*/$username:$new_pass:$cur_expiry:$cur_limit:$cur_bw:$cur_daily_bw/" "$DB_FILE"
               echo -e "\n${C_GREEN}✅ Password changed to: ${C_YELLOW}$new_pass${C_RESET}"
               ;;
            2) read -p "👉 Days to add: " days
               if [[ "$days" =~ ^[0-9]+$ ]]; then
                   echo -e "  ${C_GREEN}[1]${C_RESET} Extend from Today  ${C_GREEN}[2]${C_RESET} Extend from Current Expiry"
                   read -p "👉 Mode [1]: " ext_mode
                   local new_expire_date
                   if [[ "${ext_mode}" == "2" && -n "$cur_expiry" && "$cur_expiry" != "Never" ]]; then
                       new_expire_date=$(date -d "$cur_expiry +$days days" +%Y-%m-%d 2>/dev/null || date -d "+$days days" +%Y-%m-%d)
                   else
                       new_expire_date=$(date -d "+$days days" +%Y-%m-%d)
                   fi
                   chage -E "$new_expire_date" "$username"
                   sed -i "s/^$username:.*/$username:$cur_pass:$new_expire_date:$cur_limit:$cur_bw:$cur_daily_bw/" "$DB_FILE"
                   echo -e "\n${C_GREEN}✅ Expiration: ${C_DIM}$cur_expiry${C_RESET} → ${C_GREEN}$new_expire_date${C_RESET}"
               else echo -e "\n${C_RED}❌ Invalid number of days.${C_RESET}"; fi ;;
            3) read -p "👉 New simultaneous connection limit: " new_limit
               if [[ "$new_limit" =~ ^[0-9]+$ ]]; then
                   sed -i "s/^$username:.*/$username:$cur_pass:$cur_expiry:$new_limit:$cur_bw:$cur_daily_bw/" "$DB_FILE"
                   echo -e "\n${C_GREEN}✅ Connection limit set to: ${C_YELLOW}$new_limit${C_RESET}"
               else echo -e "\n${C_RED}❌ Invalid limit.${C_RESET}"; fi ;;
            4) read -p "👉 New TOTAL bandwidth limit in GB (0 = unlimited): " new_bw
               if [[ "$new_bw" =~ ^[0-9]+\.?[0-9]*$ ]]; then
                   sed -i "s/^$username:.*/$username:$cur_pass:$cur_expiry:$cur_limit:$new_bw:$cur_daily_bw/" "$DB_FILE"
                   local bw_msg="Unlimited"; [[ "$new_bw" != "0" ]] && bw_msg="${new_bw} GB"
                   echo -e "\n${C_GREEN}✅ Total bandwidth limit set to: ${C_YELLOW}$bw_msg${C_RESET}"
                   if [[ "$new_bw" == "0" ]] || [[ -f "$BANDWIDTH_DIR/${username}.usage" ]]; then
                       local used_bytes; used_bytes=$(cat "$BANDWIDTH_DIR/${username}.usage" 2>/dev/null || echo 0)
                       local new_quota_bytes; new_quota_bytes=$(awk "BEGIN {printf \"%.0f\", $new_bw * 1073741824}")
                       if [[ "$new_bw" == "0" ]] || [[ "$used_bytes" -lt "$new_quota_bytes" ]]; then
                           usermod -U "$username" &>/dev/null
                       fi
                   fi
               else echo -e "\n${C_RED}❌ Invalid bandwidth value.${C_RESET}"; fi ;;
            5) read -p "👉 New DAILY bandwidth limit in GB (0 = unlimited): " new_daily_bw
               if [[ "$new_daily_bw" =~ ^[0-9]+\.?[0-9]*$ ]]; then
                   sed -i "s/^$username:.*/$username:$cur_pass:$cur_expiry:$cur_limit:$cur_bw:$new_daily_bw/" "$DB_FILE"
                   local daily_bw_msg="Unlimited"; [[ "$new_daily_bw" != "0" ]] && daily_bw_msg="${new_daily_bw} GB/day"
                   echo -e "\n${C_GREEN}✅ Daily bandwidth limit set to: ${C_YELLOW}$daily_bw_msg${C_RESET}"
                   if [[ "$new_daily_bw" == "0" ]] || [[ -f "$BANDWIDTH_DIR/${username}.daily_usage" ]]; then
                       local d_used_bytes; d_used_bytes=$(cat "$BANDWIDTH_DIR/${username}.daily_usage" 2>/dev/null || echo 0)
                       local new_d_quota_bytes; new_d_quota_bytes=$(awk "BEGIN {printf \"%.0f\", $new_daily_bw * 1073741824}")
                       if [[ "$new_daily_bw" == "0" ]] || [[ "$d_used_bytes" -lt "$new_d_quota_bytes" ]]; then
                           usermod -U "$username" &>/dev/null
                           rm -f "$BANDWIDTH_DIR/${username}.daily_locked"
                       fi
                   fi
               else echo -e "\n${C_RED}❌ Invalid bandwidth value.${C_RESET}"; fi ;;
            6)
               echo "0" > "$BANDWIDTH_DIR/${username}.usage"
               echo "0" > "$BANDWIDTH_DIR/${username}.daily_usage"
               rm -f "$BANDWIDTH_DIR/${username}.daily_locked"
               usermod -U "$username" &>/dev/null
               echo -e "\n${C_GREEN}✅ Bandwidth counters reset to 0.${C_RESET}"
               ;;
            7)
               read -p "👉 Enter target username to copy settings to: " copy_target
               if grep -q "^$copy_target:" "$DB_FILE" 2>/dev/null; then
                   local ct_pass; ct_pass=$(grep "^$copy_target:" "$DB_FILE" | cut -d: -f2)
                   sed -i "s/^$copy_target:.*/$copy_target:$ct_pass:$cur_expiry:$cur_limit:$cur_bw:$cur_daily_bw/" "$DB_FILE"
                   chage -E "$cur_expiry" "$copy_target" 2>/dev/null
                   echo -e "\n${C_GREEN}✅ Settings copied from ${C_YELLOW}$username${C_RESET}${C_GREEN} to ${C_YELLOW}$copy_target${C_RESET}"
               else
                   echo -e "\n${C_RED}❌ User '$copy_target' not found.${C_RESET}"
               fi
               ;;
            0) return ;;
            *) echo -e "\n${C_RED}❌ Invalid option.${C_RESET}" ;;
        esac
        echo -e "\nPress ${C_YELLOW}[Enter]${C_RESET} to continue..." && read -r || return
    done
}

lock_user() {
    clear; show_banner
    echo
    menu_section "LOCK USER ACCOUNTS" "$C_TITLE"
    echo
    _select_multi_user_interface "Select User(s) to Lock"
    if [[ ${#SELECTED_USERS[@]} -eq 0 || "${SELECTED_USERS[0]}" == "NO_USERS" ]]; then return; fi
    
    refresh_ssh_session_cache
    echo
    echo -e "  ${C_CYAN}┌── Active Sessions ─────────────────────────┐${C_RESET}"
    for u in "${SELECTED_USERS[@]}"; do
        local online_count="${SSH_SESSION_COUNTS[$u]:-0}"
        echo -e "  ${C_CYAN}│${C_RESET}  ${C_YELLOW}$u${C_RESET}: $online_count session(s) active"
    done
    echo -e "  ${C_CYAN}└────────────────────────────────────────────┘${C_RESET}"
    echo
    echo -e "  ${C_GREEN}[1]${C_RESET} Permanent lock"
    echo -e "  ${C_GREEN}[2]${C_RESET} Timed lock (auto-unlock in minutes)"
    echo -e "  ${C_RED}[0]${C_RESET} Cancel"
    echo
    read -p "$(echo -e "${C_BLUE}👉 Select lock type [1]: ${C_RESET}")" lock_type
    lock_type=${lock_type:-1}
    if [[ "$lock_type" == "0" ]]; then echo -e "\n${C_YELLOW}❌ Lock cancelled.${C_RESET}"; return; fi

    local lock_mins=0
    if [[ "$lock_type" == "2" ]]; then
        read -p "👉 Auto-unlock duration in minutes [60]: " lock_mins
        lock_mins=${lock_mins:-60}
    fi

    echo -e "\n${C_BLUE}🔒 Locking selected user(s)...${C_RESET}"
    for u in "${SELECTED_USERS[@]}"; do
        if ! id "$u" &>/dev/null; then
             echo -e " ❌ User '${C_YELLOW}$u${C_RESET}' does not exist."
             continue
        fi
        
        usermod -L "$u"
        if [ $? -eq 0 ]; then
            killall -u "$u" -9 &>/dev/null
            echo -e " ✅ ${C_YELLOW}$u${C_RESET} locked and sessions terminated."
            _log_action "LOCK" "$u" "timed=${lock_mins}min"
            if [[ "$lock_mins" =~ ^[0-9]+$ && "$lock_mins" -gt 0 ]]; then
                echo "usermod -U $u" | at now + ${lock_mins} minutes &>/dev/null
                echo -e "   ${C_DIM}⏰ Auto-unlock scheduled in ${lock_mins} minutes${C_RESET}"
            fi
        else
            echo -e " ❌ Failed to lock ${C_YELLOW}$u${C_RESET}."
        fi
    done
}

unlock_user() {
    clear; show_banner
    echo
    menu_section "UNLOCK USER ACCOUNTS" "$C_TITLE"
    echo
    _select_multi_user_interface "Select User(s) to Unlock"
    if [[ ${#SELECTED_USERS[@]} -eq 0 || "${SELECTED_USERS[0]}" == "NO_USERS" ]]; then return; fi
    
    echo
    echo -e "  ${C_CYAN}┌── Lock Reason Analysis ────────────────────┐${C_RESET}"
    for u in "${SELECTED_USERS[@]}"; do
        local reason="Manual"
        local line; line=$(grep "^$u:" "$DB_FILE" 2>/dev/null)
        if [[ -n "$line" ]]; then
            local _u _p exp lim bw dbw _extra
            IFS=: read -r _u _p exp lim bw dbw _extra <<< "$line"
            if [[ -n "$exp" && "$exp" != "Never" ]]; then
                local exp_ts; exp_ts=$(date -d "$exp" +%s 2>/dev/null || echo 0)
                local now_ts; now_ts=$(date +%s)
                if (( exp_ts > 0 && exp_ts < now_ts )); then reason="Expired on $exp"; fi
            fi
            if [[ -f "$BANDWIDTH_DIR/${u}.usage" && -n "$bw" && "$bw" != "0" ]]; then
                local used=0; read -r used < "$BANDWIDTH_DIR/${u}.usage" 2>/dev/null || used=0
                local limit_bytes; limit_bytes=$(awk "BEGIN {printf \"%.0f\", $bw * 1073741824}" 2>/dev/null || echo 0)
                if [[ "$limit_bytes" != "0" && "$used" -ge "$limit_bytes" ]]; then reason="Total BW Exceeded"; fi
            fi
            if [[ -f "$BANDWIDTH_DIR/${u}.daily_usage" && -n "$dbw" && "$dbw" != "0" ]]; then
                local dused=0; read -r dused < "$BANDWIDTH_DIR/${u}.daily_usage" 2>/dev/null || dused=0
                local dlimit_bytes; dlimit_bytes=$(awk "BEGIN {printf \"%.0f\", $dbw * 1073741824}" 2>/dev/null || echo 0)
                if [[ "$dlimit_bytes" != "0" && "$dused" -ge "$dlimit_bytes" ]]; then reason="Daily BW Exceeded"; fi
            fi
        fi
        echo -e "  ${C_CYAN}│${C_RESET}  ${C_YELLOW}$u${C_RESET}: $reason"
    done
    echo -e "  ${C_CYAN}└────────────────────────────────────────────┘${C_RESET}"
    echo
    echo -e "  ${C_GREEN}[1]${C_RESET} Unlock user(s) & reset bandwidth counters"
    echo -e "  ${C_GREEN}[2]${C_RESET} Unlock user(s) only"
    echo -e "  ${C_RED}[0]${C_RESET} Cancel"
    echo
    read -p "$(echo -e "${C_BLUE}👉 Select action [1]: ${C_RESET}")" unlock_action
    unlock_action=${unlock_action:-1}
    if [[ "$unlock_action" == "0" ]]; then echo -e "\n${C_YELLOW}❌ Unlock cancelled.${C_RESET}"; return; fi

    local reset_bw=false
    [[ "$unlock_action" == "1" ]] && reset_bw=true

    echo -e "\n${C_BLUE}🔓 Unlocking selected user(s)...${C_RESET}"
    for u in "${SELECTED_USERS[@]}"; do
        if ! id "$u" &>/dev/null; then
             echo -e " ❌ User '${C_YELLOW}$u${C_RESET}' does not exist."
             continue
        fi
        
        usermod -U "$u"
        if [ $? -eq 0 ]; then
            echo -e " ✅ ${C_YELLOW}$u${C_RESET} unlocked."
            _log_action "UNLOCK" "$u" "bw_reset=$reset_bw"
            if $reset_bw; then
                echo "0" > "$BANDWIDTH_DIR/${u}.usage" 2>/dev/null
                echo "0" > "$BANDWIDTH_DIR/${u}.daily_usage" 2>/dev/null
                rm -f "$BANDWIDTH_DIR/${u}.daily_locked" 2>/dev/null
                echo -e "   ${C_DIM}📦 Bandwidth counters reset to 0${C_RESET}"
            fi
        else
            echo -e " ❌ Failed to unlock ${C_YELLOW}$u${C_RESET}."
        fi
    done
}

list_users() {
    clear; show_banner
    echo
    menu_section "MANAGED USERS LIST" "$C_TITLE"
    echo
    if [[ ! -s "$DB_FILE" ]]; then
        echo -e "  ${C_YELLOW}ℹ️ No users are currently being managed.${C_RESET}\n"
        return
    fi
    echo -e "  ${C_CYAN}---------------------------------------------------------------------------------------------------${C_RESET}"
    printf "  ${C_BOLD}${C_WHITE}%-18s | %-12s | %-10s | %-25s | %-20s${C_RESET}\n" "USERNAME" "EXPIRATION" "SESSIONS" "BANDWIDTH" "STATUS"
    echo -e "  ${C_CYAN}---------------------------------------------------------------------------------------------------${C_RESET}"

    local current_ts
    printf -v current_ts '%(%s)T' -1
    local -A system_user_lookup=()
    local -A locked_user_lookup=()

    while IFS=: read -r system_user _rest; do
        [[ -n "$system_user" ]] && system_user_lookup["$system_user"]=1
    done < /etc/passwd

    if [[ -r /etc/shadow ]]; then
        while IFS=: read -r shadow_user shadow_hash _rest; do
            [[ -n "$shadow_user" && "${shadow_hash:0:1}" == "!" ]] && locked_user_lookup["$shadow_user"]=1
        done < /etc/shadow
    else
        while read -r passwd_user _ passwd_status _rest; do
            [[ -z "$passwd_user" ]] && continue
            [[ "$passwd_status" == "L" ]] && locked_user_lookup["$passwd_user"]=1
        done < <(passwd -Sa 2>/dev/null)
    fi
    refresh_ssh_session_cache

    local total_u=0 active_u=0 locked_u=0 expired_u=0
    while IFS=: read -r user pass expiry limit bandwidth_gb daily_bandwidth_gb _extra; do
        total_u=$((total_u+1))
        local online_count="${SSH_SESSION_COUNTS[$user]:-0}"
        local connection_string="$online_count / $limit"
        local plain_status="Active"
        local status="${C_GREEN}Active${C_RESET}"
        local quota_exceeded=false

        [[ -z "$bandwidth_gb" ]] && bandwidth_gb="0"
        [[ ! "$daily_bandwidth_gb" =~ ^[0-9]+\.?[0-9]*$ ]] && daily_bandwidth_gb="0"
        
        local bw_string="Unlimited"
        local total_str=""
        local daily_str=""
        
        if [[ "$bandwidth_gb" != "0" ]]; then
            local used_bytes=0
            if [[ -f "$BANDWIDTH_DIR/${user}.usage" ]]; then
                read -r used_bytes < "$BANDWIDTH_DIR/${user}.usage" 2>/dev/null || used_bytes=0
                [[ "$used_bytes" =~ ^[0-9]+$ ]] || used_bytes=0
            fi
            local used_gb
            used_gb=$(awk "BEGIN {printf \"%.1f\", $used_bytes / 1073741824}")
            total_str="${used_gb}/${bandwidth_gb}G"
            local quota_bytes
            quota_bytes=$(awk "BEGIN {printf \"%.0f\", $bandwidth_gb * 1073741824}")
            if [[ "$quota_bytes" =~ ^[0-9]+$ ]] && (( used_bytes >= quota_bytes )); then
                quota_exceeded=true
            fi
        fi
        
        if [[ "$daily_bandwidth_gb" != "0" ]]; then
            local d_used_bytes=0
            if [[ -f "$BANDWIDTH_DIR/${user}.daily_usage" ]]; then
                read -r d_used_bytes < "$BANDWIDTH_DIR/${user}.daily_usage" 2>/dev/null || d_used_bytes=0
                [[ "$d_used_bytes" =~ ^[0-9]+$ ]] || d_used_bytes=0
            fi
            local d_used_gb
            d_used_gb=$(awk "BEGIN {printf \"%.1f\", $d_used_bytes / 1073741824}")
            daily_str="${d_used_gb}/${daily_bandwidth_gb}G/d"
            local d_quota_bytes
            d_quota_bytes=$(awk "BEGIN {printf \"%.0f\", $daily_bandwidth_gb * 1073741824}")
            if [[ "$d_quota_bytes" =~ ^[0-9]+$ ]] && (( d_used_bytes >= d_quota_bytes )); then
                quota_exceeded=true
            fi
        fi
        
        if [[ -n "$total_str" && -n "$daily_str" ]]; then
            bw_string="$total_str | $daily_str"
        elif [[ -n "$total_str" ]]; then
            bw_string="$total_str"
        elif [[ -n "$daily_str" ]]; then
            bw_string="$daily_str"
        fi

        if [[ -z "${system_user_lookup[$user]+x}" ]]; then
            plain_status="Not Found"
            status="${C_RED}Not Found${C_RESET}"
        elif [[ -n "$expiry" && "$expiry" != "Never" ]]; then
            local expiry_ts
            expiry_ts=$(date -d "$expiry" +%s 2>/dev/null || echo 0)
            if [[ "$expiry_ts" =~ ^[0-9]+$ ]] && (( expiry_ts > 0 && expiry_ts < current_ts )); then
                plain_status="Expired"
                status="${C_RED}Expired${C_RESET}"
                expired_u=$((expired_u+1))
            fi
        fi

        if [[ "$plain_status" == "Active" && "$quota_exceeded" == true ]]; then
            if [[ -n "${locked_user_lookup[$user]+x}" ]]; then
                plain_status="BW Locked"
                status="${C_RED}BW Locked${C_RESET}"
                locked_u=$((locked_u+1))
            else
                plain_status="Quota Exceeded"
                status="${C_RED}Quota Exceeded${C_RESET}"
            fi
        elif [[ "$plain_status" == "Active" && -n "${locked_user_lookup[$user]+x}" ]]; then
            plain_status="Locked"
            status="${C_YELLOW}Locked${C_RESET}"
            locked_u=$((locked_u+1))
        elif [[ "$plain_status" == "Active" ]]; then
            active_u=$((active_u+1))
        fi

        local line_color="$C_WHITE"
        case "$plain_status" in
            "Active") line_color="$C_GREEN" ;;
            "Locked") line_color="$C_YELLOW" ;;
            "Expired") line_color="$C_RED" ;;
            "BW Locked") line_color="$C_RED" ;;
            "Quota Exceeded") line_color="$C_RED" ;;
            "Not Found") line_color="$C_DIM" ;;
        esac

        printf "  ${line_color}%-18s ${C_RESET}| ${C_YELLOW}%-12s ${C_RESET}| ${C_CYAN}%-10s ${C_RESET}| ${C_ORANGE}%-25s ${C_RESET}| %-20s\n" "$user" "$expiry" "$connection_string" "$bw_string" "$status"
    done < <(sort "$DB_FILE")
    echo -e "  ${C_CYAN}---------------------------------------------------------------------------------------------------${C_RESET}"
    echo -e "  ${C_DIM}Total: ${C_WHITE}$total_u${C_RESET} ${C_DIM}| Active: ${C_GREEN}$active_u${C_RESET} ${C_DIM}| Locked: ${C_YELLOW}$locked_u${C_RESET} ${C_DIM}| Expired: ${C_RED}$expired_u${C_RESET}\n"
}

renew_user() {
    clear; show_banner
    echo
    menu_section "RENEW USER ACCOUNTS" "$C_TITLE"
    echo
    _select_multi_user_interface "Select User(s) to Renew"
    if [[ ${#SELECTED_USERS[@]} -eq 0 || "${SELECTED_USERS[0]}" == "NO_USERS" ]]; then return; fi
    
    read -p "👉 Days to extend [30]: " days
    days=${days:-30}
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then echo -e "\n${C_RED}❌ Invalid number of days.${C_RESET}"; return; fi
    
    echo
    echo -e "  ${C_GREEN}[1]${C_RESET} Extend from Today"
    echo -e "  ${C_GREEN}[2]${C_RESET} Extend from Current Expiry"
    echo -e "  ${C_RED}[0]${C_RESET} Cancel"
    echo
    read -p "$(echo -e "${C_BLUE}👉 Select renewal mode [1]: ${C_RESET}")" renew_mode
    renew_mode=${renew_mode:-1}
    if [[ "$renew_mode" == "0" ]]; then echo -e "\n${C_YELLOW}❌ Renewal cancelled.${C_RESET}"; return; fi
    
    echo -e "\n${C_BLUE}🔄 Renewing selected user(s)...${C_RESET}"
    for u in "${SELECTED_USERS[@]}"; do
        local line pass _expiry limit bw daily_bw
        line=$(grep "^$u:" "$DB_FILE")
        IFS=: read -r _ pass _expiry limit bw daily_bw _ <<< "$line"
        [[ -z "$bw" ]] && bw="0"
        [[ -z "$daily_bw" ]] && daily_bw="0"
        local new_expire_date
        if [[ "$renew_mode" == "2" && -n "$_expiry" && "$_expiry" != "Never" ]]; then
            new_expire_date=$(date -d "$_expiry +$days days" +%Y-%m-%d 2>/dev/null || date -d "+$days days" +%Y-%m-%d)
        else
            new_expire_date=$(date -d "+$days days" +%Y-%m-%d)
        fi
        chage -E "$new_expire_date" "$u"
        sed -i "s/^$u:.*/$u:$pass:$new_expire_date:$limit:$bw:$daily_bw/" "$DB_FILE"
        usermod -U "$u" &>/dev/null
        echo -e " ✅ ${C_YELLOW}$u${C_RESET}: ${C_DIM}${_expiry}${C_RESET} → ${C_GREEN}${new_expire_date}${C_RESET} (unlocked)"
        _log_action "RENEW_USER" "Renewed $u for $days days (mode $renew_mode). Unlocked."
    done
}

cleanup_expired() {
    clear; show_banner
    echo
    menu_section "CLEANUP EXPIRED USERS" "$C_TITLE"
    echo
    local expired_users=()
    local current_ts; current_ts=$(date +%s)

    if [[ -s "$DB_FILE" ]]; then
        while IFS=: read -r user pass expiry limit bandwidth_gb _extra; do
            local expiry_ts; expiry_ts=$(date -d "$expiry" +%s 2>/dev/null || echo 0)
            if [[ $expiry_ts -lt $current_ts && $expiry_ts -ne 0 ]]; then
                expired_users+=("$user")
            fi
        done < "$DB_FILE"
    fi

    if [ ${#expired_users[@]} -eq 0 ]; then
        echo -e "  ${C_CYAN}Status:${C_RESET} ${C_GREEN}No expired users found.${C_RESET}"
        return
    fi

    echo -e "  ${C_CYAN}Expired Users (${#expired_users[@]}):${C_RESET} ${C_RED}${expired_users[*]}${C_RESET}"
    echo
    printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[1]" "Delete Expired Users"
    printf "  ${C_DANGER}%-4s${C_RESET} %s\n" "[0]" "Return"
    echo
    read -r -p "$(echo -e ${C_PROMPT}"> Select an option: "${C_RESET})" confirm
    if [[ "$confirm" == "1" ]]; then
        echo -e "\n${C_BLUE}Deleting expired users...${C_RESET}"
        delete_firewallfalcon_user_accounts "${expired_users[@]}"
        echo -e "\n${C_GREEN}✅ Expired users cleaned up successfully.${C_RESET}"
    fi
}

backup_user_data() {
    clear; show_banner
    echo
    menu_section "BACKUP USER DATA" "$C_TITLE"
    echo
    echo -e "  ${C_CYAN}Existing Backups:${C_RESET}"
    local count=0
    while read -r file size; do
        if [[ -n "$file" ]]; then
            echo -e "  • ${C_WHITE}$(basename "$file")${C_RESET} ${C_DIM}($size)${C_RESET}"
            count=$((count+1))
        fi
    done < <(ls -lh /root/ff_backup_*.tar.gz /root/firewallfalcon_users.tar.gz 2>/dev/null | awk '{print $NF, $5}')
    [[ $count -eq 0 ]] && echo -e "  ${C_DIM}(No backups found)${C_RESET}"
    echo
    printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[1]" "Create Backup Now"
    printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[2]" "Purge Old Backups (Keep Last 5)"
    echo
    printf "  ${C_DANGER}%-4s${C_RESET} %s\n" "[0]" "Return"
    echo
    read -r -p "$(echo -e ${C_PROMPT}"> Select an option [1]: "${C_RESET})" bk_act
    bk_act=${bk_act:-1}

    case "$bk_act" in
        1)
            local auto_name="/root/ff_backup_$(date +%F-%H%M).tar.gz"
            mkdir -p "$DB_DIR" 2>/dev/null
            touch "$DB_FILE" 2>/dev/null
            echo -e "\n${C_BLUE}Creating user data backup...${C_RESET}"
            tar -czf "$auto_name" -C "$(dirname "$DB_DIR")" "$(basename "$DB_DIR")"
            if [ $? -eq 0 ]; then
                local bk_size; bk_size=$(du -sh "$auto_name" 2>/dev/null | cut -f1)
                echo -e "\n${C_GREEN}✅ Backup created: ${C_YELLOW}$auto_name ${C_CYAN}($bk_size)${C_RESET}"
            else
                echo -e "\n${C_RED}❌ ERROR: Backup failed.${C_RESET}"
            fi
            ;;
        2)
            ls -t /root/ff_backup_*.tar.gz 2>/dev/null | tail -n +6 | xargs -r rm -f
            echo -e "\n${C_GREEN}✅ Old backups purged (kept last 5).${C_RESET}"
            ;;
        0|*) ;;
    esac
}

restore_user_data() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 📥 Restore User Data ---${C_RESET}"
    
    # Collect list of files
    local backups=()
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            backups+=("$line")
        fi
    done < <(ls -t /root/ff_backup_*.tar.gz /root/firewallfalcon_users.tar.gz 2>/dev/null)

    if (( ${#backups[@]} == 0 )); then
        echo -e "  ${C_RED}❌ No backups found in /root/.${C_RESET}"
        echo
        read -p "👉 Press Enter to return..."
        return
    fi

    echo -e "${C_CYAN}Select a backup to restore:${C_RESET}"
    local i=1
    for bk in "${backups[@]}"; do
        local size; size=$(du -sh "$bk" 2>/dev/null | awk '{print $1}')
        printf "  ${C_CHOICE}[%d]${C_RESET} %s (${C_YELLOW}%s${C_RESET})\n" "$i" "$bk" "$size"
        ((i++))
    done
    echo
    printf "  ${C_DANGER}[0]${C_RESET} Return/Cancel\n"
    echo

    local choice
    read -p "👉 Select option [0-$((${#backups[@]}))]: " choice
    choice=${choice:-0}

    if [[ "$choice" == "0" ]]; then
        echo -e "\n${C_YELLOW}❌ Restore cancelled.${C_RESET}"
        return
    fi

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#backups[@]} )); then
        echo -e "\n${C_RED}❌ ERROR: Invalid choice.${C_RESET}"
        return
    fi

    local backup_path="${backups[$((choice - 1))]}"
    # ── BETA: Archive preview ────────────────────────────────────── ✦new
    echo -e "\n${C_CYAN}Archive preview ${NEW_TAG}:${C_RESET}"   # ✦new
    tar -tzf "$backup_path" 2>/dev/null | head -15   # ✦new
    local bk_cnt; bk_cnt=$(tar -xzOf "$backup_path" firewallfalcon/users.db 2>/dev/null | wc -l)   # ✦new
    echo -e "\n  ${C_CYAN}Users in backup: ${C_YELLOW}$bk_cnt${C_RESET} | Currently: ${C_YELLOW}$(wc -l < "$DB_FILE" 2>/dev/null)${C_RESET}"   # ✦new
    echo   # ✦new
    echo -e "\n${C_RED}${C_BOLD}⚠️ WARNING:${C_RESET} This will overwrite all current users and settings."
    echo -e "It will restore user accounts, passwords, limits, and expiration dates from the backup file."
    read -p "👉 Are you absolutely sure you want to proceed? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then echo -e "\n${C_YELLOW}❌ Restore cancelled.${C_RESET}"; return; fi
    # ── BETA: Safety backup ──────────────────────────────────────── ✦new
    echo -e "\n${C_BLUE}💾 Creating safety backup of current data ${NEW_TAG}...${C_RESET}"   # ✦new
    local safety_bk="/root/ff_pre_restore_$(date +%F-%H%M).tar.gz"   # ✦new
    tar -czf "$safety_bk" -C "$(dirname "$DB_DIR")" "$(basename "$DB_DIR")" 2>/dev/null   # ✦new
    echo -e "  ${C_GREEN}✅ Safety backup: ${C_YELLOW}$safety_bk${C_RESET}"   # ✦new
    local temp_dir
    temp_dir=$(mktemp -d)
    echo -e "\n${C_BLUE}⚙️ Extracting backup file to a temporary location...${C_RESET}"
    tar -xzf "$backup_path" -C "$temp_dir"
    if [ $? -ne 0 ]; then
        echo -e "\n${C_RED}❌ ERROR: Failed to extract backup file. Aborting.${C_RESET}"
        rm -rf "$temp_dir"
        return
    fi
    local restored_db_file="$temp_dir/firewallfalcon/users.db"
    if [ ! -f "$restored_db_file" ]; then
        echo -e "\n${C_RED}❌ ERROR: users.db not found in the backup. Cannot restore user accounts.${C_RESET}"
        rm -rf "$temp_dir"
        return
    fi
    echo -e "${C_BLUE}⚙️ Overwriting current user database...${C_RESET}"
    mkdir -p "$DB_DIR"
    cp "$restored_db_file" "$DB_FILE"
    if [ -d "$temp_dir/firewallfalcon/ssl" ]; then
        cp -r "$temp_dir/firewallfalcon/ssl" "$DB_DIR/"
    fi
    if [ -d "$temp_dir/firewallfalcon/dnstt" ]; then
        cp -r "$temp_dir/firewallfalcon/dnstt" "$DB_DIR/"
    fi
    if [ -f "$temp_dir/firewallfalcon/dns_info.conf" ]; then
        cp "$temp_dir/firewallfalcon/dns_info.conf" "$DB_DIR/"
    fi
    if [ -f "$temp_dir/firewallfalcon/dnstt_info.conf" ]; then
        cp "$temp_dir/firewallfalcon/dnstt_info.conf" "$DB_DIR/"
    fi
    if [ -f "$temp_dir/firewallfalcon/falconproxy_config.conf" ]; then
        cp "$temp_dir/firewallfalcon/falconproxy_config.conf" "$DB_DIR/"
    fi
    
    echo -e "${C_BLUE}⚙️ Re-synchronizing system accounts with the restored database...${C_RESET}"
    ensure_firewallfalcon_system_group
    
    while IFS=: read -r user pass expiry limit; do
        echo "Processing user: ${C_YELLOW}$user${C_RESET}"
        if ! id "$user" &>/dev/null; then
            echo " - User does not exist in system. Creating..."
            useradd -m -s /usr/sbin/nologin "$user"
        fi
        usermod -aG "$FF_USERS_GROUP" "$user" 2>/dev/null
        echo " - Setting password..."
        echo "$user:$pass" | chpasswd
        echo " - Setting expiration to $expiry..."
        chage -E "$expiry" "$user"
        echo " - Connection limit is $limit (enforced by PAM)"
    done < "$DB_FILE"
    rm -rf "$temp_dir"
    echo -e "\n${C_GREEN}✅ SUCCESS: User data restore completed.${C_RESET}"
    
    invalidate_banner_cache
    refresh_dynamic_banner_routing_if_enabled
}

_enable_banner_in_sshd_config() {
    echo -e "\n${C_BLUE}⚙️ Configuring sshd_config...${C_RESET}"
    disable_dynamic_ssh_banner_system
    sed -i.bak -E 's/^( *Banner *).*/#\1/' /etc/ssh/sshd_config
    if ! grep -q -E "^Banner $SSH_BANNER_FILE" /etc/ssh/sshd_config; then
        echo -e "\n# DAHOOM SSH Banner\nBanner $SSH_BANNER_FILE" >> /etc/ssh/sshd_config
    fi
    echo -e "${C_GREEN}✅ sshd_config updated.${C_RESET}"
}

_restart_ssh() {
    echo -e "\n${C_BLUE}🔄 Restarting SSH service to apply changes...${C_RESET}"
    local ssh_service_name=""
    if [ -f /lib/systemd/system/sshd.service ]; then
        ssh_service_name="sshd.service"
    elif [ -f /lib/systemd/system/ssh.service ]; then
        ssh_service_name="ssh.service"
    else
        echo -e "${C_RED}❌ Could not find sshd.service or ssh.service. Cannot restart SSH.${C_RESET}"
        return 1
    fi

    systemctl restart "${ssh_service_name}"
    if [ $? -eq 0 ]; then
        echo -e "${C_GREEN}✅ SSH service ('${ssh_service_name}') restarted successfully.${C_RESET}"
    else
        echo -e "${C_RED}❌ Failed to restart SSH service ('${ssh_service_name}'). Please check 'journalctl -u ${ssh_service_name}' for errors.${C_RESET}"
    fi
}

set_ssh_banner_paste() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 📋 Paste Static SSH Banner ---${C_RESET}"
    echo -e "Paste your custom banner below. Press ${C_YELLOW}[Ctrl+D]${C_RESET} when you are finished."
    echo -e "${C_DIM}This will be shown to all SSH users through 'Banner $SSH_BANNER_FILE'.${C_RESET}"
    echo -e "${C_DIM}The current banner (if any) will be overwritten.${C_RESET}"
    echo -e "--------------------------------------------------"
    cat > "$SSH_BANNER_FILE"
    chmod 644 "$SSH_BANNER_FILE"
    echo -e "\n--------------------------------------------------"
    echo -e "\n${C_GREEN}✅ Static banner content saved.${C_RESET}"
    _enable_banner_in_sshd_config
    _restart_ssh
    echo -e "\nPress ${C_YELLOW}[Enter]${C_RESET} to return..." && read -r
}

view_ssh_banner() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 👁️ Current SSH Banner ---${C_RESET}"
    if [ -f "$SSH_BANNER_FILE" ]; then
        echo -e "\n${C_CYAN}--- BEGIN BANNER ---${C_RESET}"
        cat "$SSH_BANNER_FILE"
        echo -e "${C_CYAN}---- END BANNER ----${C_RESET}"
    else
        echo -e "\n${C_YELLOW}ℹ️ No banner file found at $SSH_BANNER_FILE.${C_RESET}"
    fi
    echo -e "\nPress ${C_YELLOW}[Enter]${C_RESET} to return..." && read -r
}

remove_ssh_banner() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🗑️ Disable SSH Banners ---${C_RESET}"
    read -p "👉 Are you sure you want to disable all SSH banners? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then
        echo -e "\n${C_YELLOW}❌ Action cancelled.${C_RESET}"
        echo -e "\nPress ${C_YELLOW}[Enter]${C_RESET} to return..." && read -r
        return
    fi
    if [ -f "$SSH_BANNER_FILE" ]; then
        rm -f "$SSH_BANNER_FILE"
        echo -e "\n${C_GREEN}✅ Removed banner file: $SSH_BANNER_FILE${C_RESET}"
    else
        echo -e "\n${C_YELLOW}ℹ️ No banner file to remove.${C_RESET}"
    fi
    disable_dynamic_ssh_banner_system
    echo -e "\n${C_BLUE}⚙️ Disabling banner in sshd_config...${C_RESET}"
    disable_static_ssh_banner_in_sshd_config
    echo -e "${C_GREEN}✅ Banner disabled in configuration.${C_RESET}"
    _restart_ssh
    echo -e "\nPress ${C_YELLOW}[Enter]${C_RESET} to return..." && read -r
}

preview_dynamic_ssh_banner() {
    if ! is_dynamic_ssh_banner_enabled; then
        echo -e "\n${C_RED}❌ Dynamic banners are not enabled right now.${C_RESET}"
        press_enter
        return
    fi

    echo -e "${C_DIM}Refreshing dynamic banner worker...${C_RESET}"
    setup_limiter_service >/dev/null 2>&1
    _select_user_interface "--- 📝 Preview Dynamic Banner ---"
    local u=$SELECTED_USER
    if [[ -z "$u" || "$u" == "NO_USERS" ]]; then
        return
    fi

    echo -e "\n${C_CYAN}--- Dynamic Banner Preview for user '$u' ---${C_RESET}\n"
    if [[ -f "/etc/firewallfalcon/banners/${u}.txt" ]]; then
        cat "/etc/firewallfalcon/banners/${u}.txt"
    else
        echo -e "${C_RED}Banner file not generated yet. Waiting up to 10s for the worker...${C_RESET}"
        sleep 5
        if ! cat "/etc/firewallfalcon/banners/${u}.txt" 2>/dev/null; then
            echo -e "\n${C_RED}Still not generated. Here are the last limiter logs:${C_RESET}"
            echo -e "----------------------------------------------------------------------"
            journalctl -u firewallfalcon-limiter -n 15 --no-pager
            echo -e "----------------------------------------------------------------------"
        fi
    fi
    press_enter
}

# NOTE: The full ssh_banner_menu() with dynamic/static support is defined later in the file.

install_udp_custom() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🚀 Installing udp-custom ---${C_RESET}"
    if [ -f "$UDP_CUSTOM_SERVICE_FILE" ] || [ -f "$UDPGW_SERVICE_FILE" ]; then
        echo -e "\n${C_YELLOW}ℹ️ udp-custom is already installed.${C_RESET}"
        return
    fi

    check_and_free_ports 36712 7800 || return
    check_and_open_firewall_port 36712 udp || return

    echo -e "\n${C_GREEN}⚙️ Creating directory for udp-custom...${C_RESET}"
    rm -rf "$UDP_CUSTOM_DIR"
    mkdir -p "$UDP_CUSTOM_DIR"

    echo -e "\n${C_GREEN}⚙️ Detecting system architecture...${C_RESET}"
    local arch
    arch=$(uname -m)
    local update_branch
    update_branch=$(get_update_branch)
    local binary_url=""
    if [[ "$arch" == "x86_64" ]]; then
        binary_url="https://raw.githubusercontent.com/mooa322/fm/${update_branch}/udp/udp-custom-linux-amd64"
        echo -e "${C_BLUE}ℹ️ Detected x86_64 (amd64) architecture.${C_RESET}"
    elif [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then
        binary_url="https://raw.githubusercontent.com/mooa322/fm/${update_branch}/udp/udp-custom-linux-arm"
        echo -e "${C_BLUE}ℹ️ Detected ARM64 architecture.${C_RESET}"
    else
        echo -e "\n${C_RED}❌ Unsupported architecture: $arch. Cannot install udp-custom.${C_RESET}"
        rm -rf "$UDP_CUSTOM_DIR"
        return
    fi

    echo -e "\n${C_GREEN}📥 Downloading udp-custom binary...${C_RESET}"
    wget -q --show-progress -O "$UDP_CUSTOM_DIR/udp-custom" "$binary_url"
    if [ $? -ne 0 ]; then
        echo -e "\n${C_RED}❌ Failed to download the udp-custom binary.${C_RESET}"
        rm -rf "$UDP_CUSTOM_DIR"
        return
    fi
    chmod +x "$UDP_CUSTOM_DIR/udp-custom"

    echo -e "\n${C_GREEN}📦 Setting up udpgw helper...${C_RESET}"
    if [[ "$arch" == "x86_64" ]]; then
        wget -q --show-progress -O "$UDPGW_BINARY" "https://raw.githubusercontent.com/http-custom/udp-custom/main/module/udpgw"
        if [ $? -ne 0 ]; then
            echo -e "\n${C_RED}❌ Failed to download the udpgw helper binary.${C_RESET}"
            rm -rf "$UDP_CUSTOM_DIR"
            return
        fi
        chmod +x "$UDPGW_BINARY"
    else
        echo -e "${C_YELLOW}ℹ️ Architecture is $arch. Compiling udpgw from source (this may take a minute)...${C_RESET}"
        ff_pkg_install cmake g++ make git >/dev/null 2>&1
        local temp_build="/tmp/badvpn_build"
        rm -rf "$temp_build"
        git clone -q https://github.com/ambrop72/badvpn.git "$temp_build"
        (cd "$temp_build" && cmake . >/dev/null 2>&1 && make >/dev/null 2>&1)
        local compiled_bin=$(find "$temp_build" -name "badvpn-udpgw" -type f | head -n 1)
        if [[ -n "$compiled_bin" && -f "$compiled_bin" ]]; then
            cp "$compiled_bin" "$UDPGW_BINARY"
            chmod +x "$UDPGW_BINARY"
        else
            echo -e "\n${C_RED}❌ Failed to compile udpgw helper for $arch.${C_RESET}"
            rm -rf "$UDP_CUSTOM_DIR" "$temp_build"
            return
        fi
        rm -rf "$temp_build"
    fi

    echo -e "\n${C_GREEN}📝 Creating default config.json...${C_RESET}"
    cat > "$UDP_CUSTOM_DIR/config.json" <<EOF
{
  "listen": ":36712",
  "stream_buffer": 33554432,
  "receive_buffer": 83886080,
  "auth": {
    "mode": "passwords"
  }
}
EOF
    chmod 644 "$UDP_CUSTOM_DIR/config.json"

    echo -e "\n${C_GREEN}📝 Creating udpgw systemd service file...${C_RESET}"
    cat > "$UDPGW_SERVICE_FILE" <<EOF
[Unit]
Description=DAHOOM UDPGW Backend
After=network.target

[Service]
User=root
Type=simple
ExecStart=$UDPGW_BINARY --listen-addr 127.0.0.1:7800 --max-clients 1000 --max-connections-for-client 100
Restart=always
RestartSec=2s

[Install]
WantedBy=multi-user.target
EOF

    echo -e "\n${C_GREEN}📝 Creating systemd service file...${C_RESET}"
    cat > "$UDP_CUSTOM_SERVICE_FILE" <<EOF
[Unit]
Description=UDP Custom by DAHOOM
After=network.target

[Service]
User=root
Type=simple
ExecStart=$UDP_CUSTOM_DIR/udp-custom server
WorkingDirectory=$UDP_CUSTOM_DIR/
Restart=always
RestartSec=2s

[Install]
WantedBy=multi-user.target
EOF

    echo -e "\n${C_GREEN}▶️ Enabling and starting udp-custom service...${C_RESET}"
    systemctl daemon-reload
    systemctl enable udpgw.service
    systemctl start udpgw.service
    systemctl enable udp-custom.service
    systemctl start udp-custom.service
    sleep 2
    if systemctl is-active --quiet udpgw && systemctl is-active --quiet udp-custom; then
        echo -e "\n${C_GREEN}✅ SUCCESS: udp-custom is installed and active.${C_RESET}"
    else
        echo -e "\n${C_RED}❌ ERROR: udp-custom service failed to start.${C_RESET}"
        echo -e "${C_YELLOW}ℹ️ Displaying last 15 lines of the udp-custom and udpgw logs for diagnostics:${C_RESET}"
        journalctl -u udp-custom.service -n 15 --no-pager
        journalctl -u udpgw.service -n 15 --no-pager
    fi
}

uninstall_udp_custom() {
    echo -e "\n${C_BOLD}${C_PURPLE}--- 🗑️ Uninstalling udp-custom ---${C_RESET}"
    if [ ! -f "$UDP_CUSTOM_SERVICE_FILE" ] && [ ! -f "$UDPGW_SERVICE_FILE" ]; then
        echo -e "${C_YELLOW}ℹ️ udp-custom is not installed, skipping.${C_RESET}"
        return
    fi
    echo -e "${C_GREEN}🛑 Stopping and disabling udpgw service...${C_RESET}"
    systemctl stop udpgw.service >/dev/null 2>&1
    systemctl disable udpgw.service >/dev/null 2>&1
    echo -e "${C_GREEN}🛑 Stopping and disabling udp-custom service...${C_RESET}"
    systemctl stop udp-custom.service >/dev/null 2>&1
    systemctl disable udp-custom.service >/dev/null 2>&1
    echo -e "${C_GREEN}🗑️ Removing systemd service file...${C_RESET}"
    rm -f "$UDP_CUSTOM_SERVICE_FILE"
    rm -f "$UDPGW_SERVICE_FILE"
    systemctl daemon-reload
    echo -e "${C_GREEN}🗑️ Removing udp-custom directory and files...${C_RESET}"
    rm -rf "$UDP_CUSTOM_DIR"
    rm -f "$UDPGW_BINARY"
    echo -e "${C_GREEN}✅ udp-custom has been uninstalled successfully.${C_RESET}"
}


ensure_badvpn_service_is_quiet() {
    if [[ ! -f "$BADVPN_SERVICE_FILE" ]] || grep -q "^StandardOutput=null$" "$BADVPN_SERVICE_FILE" 2>/dev/null; then
        return
    fi

    local tmp_service
    tmp_service=$(mktemp)
    awk '
        /^\[Service\]$/ {
            print
            print "StandardOutput=null"
            print "StandardError=null"
            next
        }
        { print }
    ' "$BADVPN_SERVICE_FILE" > "$tmp_service" && mv "$tmp_service" "$BADVPN_SERVICE_FILE"
    rm -f "$tmp_service" 2>/dev/null
    systemctl daemon-reload
    systemctl restart badvpn.service >/dev/null 2>&1 || true
}

install_badvpn() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🚀 Installing badvpn (udpgw) ---${C_RESET}"
    if [ -f "$BADVPN_SERVICE_FILE" ]; then
        echo -e "\n${C_YELLOW}ℹ️ badvpn is already installed.${C_RESET}"
        return
    fi
    check_and_open_firewall_port 7300 udp || return
    echo -e "\n${C_GREEN}🔄 Updating package lists...${C_RESET}"
    ff_apt_update || return
    echo -e "\n${C_GREEN}📦 Installing all required packages...${C_RESET}"
    ff_pkg_install cmake g++ make screen git build-essential libssl-dev libnspr4-dev libnss3-dev pkg-config || {
        echo -e "${C_RED}❌ Failed to install badvpn build dependencies.${C_RESET}"
        return
    }
    echo -e "\n${C_GREEN}📥 Cloning badvpn from github...${C_RESET}"
    git clone https://github.com/ambrop72/badvpn.git "$BADVPN_BUILD_DIR"
    cd "$BADVPN_BUILD_DIR" || { echo -e "${C_RED}❌ Failed to change directory to build folder.${C_RESET}"; return; }
    echo -e "\n${C_GREEN}⚙️ Running CMake...${C_RESET}"
    cmake . || { echo -e "${C_RED}❌ CMake configuration failed.${C_RESET}"; rm -rf "$BADVPN_BUILD_DIR"; return; }
    echo -e "\n${C_GREEN}🛠️ Compiling source...${C_RESET}"
    make || { echo -e "${C_RED}❌ Compilation (make) failed.${C_RESET}"; rm -rf "$BADVPN_BUILD_DIR"; return; }
    local badvpn_binary
    badvpn_binary=$(find "$BADVPN_BUILD_DIR" -name "badvpn-udpgw" -type f | head -n 1)
    if [[ -z "$badvpn_binary" || ! -f "$badvpn_binary" ]]; then
        echo -e "${C_RED}❌ ERROR: Could not find the compiled 'badvpn-udpgw' binary after compilation.${C_RESET}"
        rm -rf "$BADVPN_BUILD_DIR"
        return
    fi
    echo -e "${C_GREEN}ℹ️ Found binary at: $badvpn_binary${C_RESET}"
    chmod +x "$badvpn_binary"
    echo -e "\n${C_GREEN}📝 Creating systemd service file...${C_RESET}"
    cat > "$BADVPN_SERVICE_FILE" <<-EOF
[Unit]
Description=BadVPN UDP Gateway
After=network.target
[Service]
ExecStart=$badvpn_binary --listen-addr 0.0.0.0:7300 --max-clients 1000 --max-connections-for-client 8
User=root
Restart=always
RestartSec=3
StandardOutput=null
StandardError=null
[Install]
WantedBy=multi-user.target
EOF
    echo -e "\n${C_GREEN}▶️ Enabling and starting badvpn service...${C_RESET}"
    systemctl daemon-reload
    systemctl enable badvpn.service
    systemctl start badvpn.service
    sleep 2
    if systemctl is-active --quiet badvpn; then
        echo -e "\n${C_GREEN}✅ SUCCESS: badvpn (udpgw) is installed and active on port 7300.${C_RESET}"
    else
        echo -e "\n${C_RED}❌ ERROR: badvpn service failed to start.${C_RESET}"
        echo -e "${C_YELLOW}ℹ️ Displaying last 15 lines of the service log for diagnostics:${C_RESET}"
        journalctl -u badvpn.service -n 15 --no-pager
    fi
}

uninstall_badvpn() {
    echo -e "\n${C_BOLD}${C_PURPLE}--- 🗑️ Uninstalling badvpn (udpgw) ---${C_RESET}"
    if [ ! -f "$BADVPN_SERVICE_FILE" ]; then
        echo -e "${C_YELLOW}ℹ️ badvpn is not installed, skipping.${C_RESET}"
        return
    fi
    echo -e "${C_GREEN}🛑 Stopping and disabling badvpn service...${C_RESET}"
    systemctl stop badvpn.service >/dev/null 2>&1
    systemctl disable badvpn.service >/dev/null 2>&1
    echo -e "${C_GREEN}🗑️ Removing systemd service file...${C_RESET}"
    rm -f "$BADVPN_SERVICE_FILE"
    systemctl daemon-reload
    echo -e "${C_GREEN}🗑️ Removing badvpn build directory...${C_RESET}"
    rm -rf "$BADVPN_BUILD_DIR"
    echo -e "${C_GREEN}✅ badvpn has been uninstalled successfully.${C_RESET}"
}

load_edge_cert_info() {
    EDGE_CERT_MODE=""
    EDGE_DOMAIN=""
    EDGE_EMAIL=""
    if [ -f "$EDGE_CERT_INFO_FILE" ]; then
        source "$EDGE_CERT_INFO_FILE"
    fi
}

save_edge_cert_info() {
    local cert_mode="$1"
    local cert_domain="$2"
    local cert_email="$3"
    mkdir -p "$DB_DIR"
    cat > "$EDGE_CERT_INFO_FILE" <<EOF
EDGE_CERT_MODE="$cert_mode"
EDGE_DOMAIN="$cert_domain"
EDGE_EMAIL="$cert_email"
EOF
}

detect_preferred_host() {
    local host_domain=""
    load_edge_cert_info
    if [[ -n "$EDGE_DOMAIN" ]]; then
        host_domain="$EDGE_DOMAIN"
    fi
    if [[ -z "$host_domain" && -f "$CLOUDFLARE_INFO_FILE" ]]; then
        host_domain=$(grep 'CF_DOMAIN' "$CLOUDFLARE_INFO_FILE" 2>/dev/null | cut -d'"' -f2)
    fi
    if [[ -z "$host_domain" && -f "$DNS_INFO_FILE" ]]; then
        host_domain=$(grep 'FULL_DOMAIN' "$DNS_INFO_FILE" | cut -d'"' -f2)
    fi
    if [[ -z "$host_domain" && -f "/etc/firewallfalcon/custom_domain.info" ]]; then
        host_domain=$(grep 'CUSTOM_DOMAIN' "/etc/firewallfalcon/custom_domain.info" 2>/dev/null | cut -d'"' -f2)
    fi
    if [[ -z "$host_domain" && -f "$NGINX_CONFIG_FILE" ]]; then
        local nginx_domain
        nginx_domain=$(grep -oP 'server_name \K[^\s;]+' "$NGINX_CONFIG_FILE" 2>/dev/null | head -n 1)
        if [[ "$nginx_domain" != "_" && -n "$nginx_domain" ]]; then
            host_domain="$nginx_domain"
        fi
    fi
    if [[ -z "$host_domain" ]]; then
        host_domain=$(curl -s -4 icanhazip.com)
    fi
    echo "$host_domain"
}

backup_edge_configs() {
    if [ -f "$NGINX_CONFIG_FILE" ] && [ ! -f "${NGINX_CONFIG_FILE}.bak.firewallfalcon" ]; then
        cp "$NGINX_CONFIG_FILE" "${NGINX_CONFIG_FILE}.bak.firewallfalcon" 2>/dev/null
    fi
    if [ -f "$HAPROXY_CONFIG" ] && [ ! -f "${HAPROXY_CONFIG}.bak.firewallfalcon" ]; then
        cp "$HAPROXY_CONFIG" "${HAPROXY_CONFIG}.bak.firewallfalcon" 2>/dev/null
    fi
}

ensure_edge_stack_packages() {
    local missing_packages=()
    if ! command -v haproxy &> /dev/null || [ ! -f "/etc/haproxy/haproxy.cfg" ]; then
        missing_packages+=("haproxy")
    fi
    if ! command -v nginx &> /dev/null || [ ! -f "/etc/nginx/nginx.conf" ]; then
        missing_packages+=("nginx")
    fi
    command -v openssl &> /dev/null || missing_packages+=("openssl")

    if (( ${#missing_packages[@]} > 0 )); then
        echo -e "\n${C_BLUE}📦 Installing required packages: ${missing_packages[*]}${C_RESET}"
        if ! ff_pkg_install "${missing_packages[@]}"; then
            echo -e "${C_YELLOW}⚠️ Package installation failed. Attempting to fix broken configurations...${C_RESET}"
            if command -v apt-get &>/dev/null; then
                apt-get purge -y nginx nginx-common haproxy >/dev/null 2>&1
            fi
            if ! ff_pkg_install "${missing_packages[@]}"; then
                echo -e "${C_RED}❌ Failed to install the required packages.${C_RESET}"
                return 1
            fi
        fi
    fi
    return 0
}

build_shared_tls_bundle() {
    if [ ! -s "$SSL_CERT_CHAIN_FILE" ] || [ ! -s "$SSL_CERT_KEY_FILE" ]; then
        echo -e "${C_RED}❌ Certificate chain or key is missing.${C_RESET}"
        return 1
    fi
    cat "$SSL_CERT_CHAIN_FILE" "$SSL_CERT_KEY_FILE" > "$SSL_CERT_FILE" || return 1
    chmod 644 "$SSL_CERT_CHAIN_FILE"
    chmod 600 "$SSL_CERT_KEY_FILE" "$SSL_CERT_FILE"
    return 0
}

generate_self_signed_edge_cert() {
    local common_name="$1"
    mkdir -p "$SSL_CERT_DIR"
    echo -e "\n${C_GREEN}🔐 Generating a shared self-signed certificate...${C_RESET}"
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
        -keyout "$SSL_CERT_KEY_FILE" \
        -out "$SSL_CERT_CHAIN_FILE" \
        -subj "/CN=$common_name" \
        >/dev/null 2>&1 || {
            echo -e "${C_RED}❌ Failed to generate the self-signed certificate.${C_RESET}"
            return 1
        }
    build_shared_tls_bundle || return 1
    save_edge_cert_info "self-signed" "$common_name" ""
    echo -e "${C_GREEN}✅ Shared certificate created for ${C_YELLOW}$common_name${C_RESET}"
    return 0
}

_install_certbot() {
    if command -v certbot &> /dev/null; then
        echo -e "${C_GREEN}✅ Certbot is already installed.${C_RESET}"
        return 0
    fi
    echo -e "${C_BLUE}📦 Installing Certbot...${C_RESET}"
    ff_pkg_install certbot || {
        echo -e "${C_RED}❌ Failed to install Certbot.${C_RESET}"
        return 1
    }
    echo -e "${C_GREEN}✅ Certbot installed successfully.${C_RESET}"
    return 0
}

obtain_certbot_edge_cert() {
    local domain_name="$1"
    local email="$2"
    local restart_haproxy=0
    local restart_nginx=0

    mkdir -p "$SSL_CERT_DIR"
    _install_certbot || return 1

    if systemctl is-active --quiet haproxy; then restart_haproxy=1; fi
    if systemctl is-active --quiet nginx; then restart_nginx=1; fi

    echo -e "\n${C_BLUE}🛑 Stopping HAProxy and Nginx for Certbot validation...${C_RESET}"
    systemctl stop haproxy >/dev/null 2>&1
    systemctl stop nginx >/dev/null 2>&1
    sleep 2

    check_and_free_ports "$EDGE_PUBLIC_HTTP_PORT" "$EDGE_PUBLIC_TLS_PORT" || {
        [[ "$restart_nginx" -eq 1 ]] && systemctl start nginx >/dev/null 2>&1
        [[ "$restart_haproxy" -eq 1 ]] && systemctl start haproxy >/dev/null 2>&1
        return 1
    }

    echo -e "\n${C_BLUE}🚀 Requesting a Certbot certificate for ${C_YELLOW}$domain_name${C_RESET}"
    certbot certonly --standalone -d "$domain_name" --non-interactive --agree-tos -m "$email"
    if [ $? -ne 0 ]; then
        echo -e "\n${C_RED}❌ Certbot failed to obtain a certificate.${C_RESET}"
        echo -e "${C_YELLOW}ℹ️ Make sure the domain points to this server and port 80 is reachable.${C_RESET}"
        [[ "$restart_nginx" -eq 1 ]] && systemctl start nginx >/dev/null 2>&1
        [[ "$restart_haproxy" -eq 1 ]] && systemctl start haproxy >/dev/null 2>&1
        return 1
    fi

    local certbot_chain="/etc/letsencrypt/live/$domain_name/fullchain.pem"
    local certbot_key="/etc/letsencrypt/live/$domain_name/privkey.pem"
    if [ ! -f "$certbot_chain" ] || [ ! -f "$certbot_key" ]; then
        echo -e "\n${C_RED}❌ Certbot completed, but the certificate files were not found.${C_RESET}"
        [[ "$restart_nginx" -eq 1 ]] && systemctl start nginx >/dev/null 2>&1
        [[ "$restart_haproxy" -eq 1 ]] && systemctl start haproxy >/dev/null 2>&1
        return 1
    fi

    cp "$certbot_chain" "$SSL_CERT_CHAIN_FILE"
    cp "$certbot_key" "$SSL_CERT_KEY_FILE"
    build_shared_tls_bundle || {
        [[ "$restart_nginx" -eq 1 ]] && systemctl start nginx >/dev/null 2>&1
        [[ "$restart_haproxy" -eq 1 ]] && systemctl start haproxy >/dev/null 2>&1
        return 1
    }
    save_edge_cert_info "certbot" "$domain_name" "$email"
    echo -e "${C_GREEN}✅ Certbot certificate copied into ${C_YELLOW}$SSL_CERT_DIR${C_RESET}"
    return 0
}

select_edge_certificate() {
    local preferred_host
    local cert_choice
    local has_existing_cert=false

    preferred_host=$(detect_preferred_host)
    if [[ -z "$preferred_host" ]]; then
        preferred_host="firewallfalcon.local"
    fi

    if [ -s "$SSL_CERT_FILE" ] && [ -s "$SSL_CERT_CHAIN_FILE" ] && [ -s "$SSL_CERT_KEY_FILE" ]; then
        has_existing_cert=true
    fi

    load_edge_cert_info

    echo -e "\n${C_BOLD}${C_PURPLE}--- 🔐 Shared TLS Certificate ---${C_RESET}"
    echo -e "${C_DIM}The same certificate will be used by HAProxy and the internal Nginx proxy.${C_RESET}"

    if $has_existing_cert; then
        local existing_label="${EDGE_CERT_MODE:-existing}"
        if [[ -n "$EDGE_DOMAIN" ]]; then
            existing_label="$existing_label - $EDGE_DOMAIN"
        fi
        printf "  ${C_CHOICE}[ 1]${C_RESET} %-52s\n" "Reuse existing certificate (${existing_label})"
        printf "  ${C_CHOICE}[ 2]${C_RESET} %-52s\n" "Replace with a new self-signed certificate"
        printf "  ${C_CHOICE}[ 3]${C_RESET} %-52s\n" "Replace with a Certbot certificate"
        echo
        read -p "👉 Enter choice [1]: " cert_choice
        cert_choice=${cert_choice:-1}
    else
        printf "  ${C_CHOICE}[ 1]${C_RESET} %-52s\n" "Generate a self-signed certificate"
        printf "  ${C_CHOICE}[ 2]${C_RESET} %-52s\n" "Use a Certbot certificate"
        echo
        read -p "👉 Enter choice [1]: " cert_choice
        cert_choice=${cert_choice:-1}
    fi

    case "$cert_choice" in
        1)
            if $has_existing_cert; then
                echo -e "${C_GREEN}✅ Reusing the existing shared certificate.${C_RESET}"
                return 0
            fi
            local common_name
            read -p "👉 Enter the certificate Common Name / SNI label [$preferred_host]: " common_name
            common_name=${common_name:-$preferred_host}
            generate_self_signed_edge_cert "$common_name"
            ;;
        2)
            if $has_existing_cert; then
                local common_name
                read -p "👉 Enter the certificate Common Name / SNI label [$preferred_host]: " common_name
                common_name=${common_name:-$preferred_host}
                generate_self_signed_edge_cert "$common_name"
            else
                local default_domain=""
                local domain_name
                local email
                if ! _is_valid_ipv4 "$preferred_host"; then
                    default_domain="$preferred_host"
                fi
                if [[ -n "$default_domain" ]]; then
                    read -p "👉 Enter your domain name [$default_domain]: " domain_name
                    domain_name=${domain_name:-$default_domain}
                else
                    read -p "👉 Enter your domain name (e.g. vpn.example.com): " domain_name
                fi
                if [[ -z "$domain_name" ]]; then
                    echo -e "${C_RED}❌ Domain name cannot be empty.${C_RESET}"
                    return 1
                fi
                if _is_valid_ipv4 "$domain_name"; then
                    echo -e "${C_RED}❌ Certbot requires a real domain name, not a raw IP address.${C_RESET}"
                    return 1
                fi
                read -p "👉 Enter your email for Let's Encrypt: " email
                if [[ -z "$email" ]]; then
                    echo -e "${C_RED}❌ Email cannot be empty.${C_RESET}"
                    return 1
                fi
                obtain_certbot_edge_cert "$domain_name" "$email"
            fi
            ;;
        3)
            if ! $has_existing_cert; then
                echo -e "${C_RED}❌ Invalid option.${C_RESET}"
                return 1
            fi
            local default_domain=""
            local domain_name
            local email
            if [[ -n "$EDGE_DOMAIN" ]] && ! _is_valid_ipv4 "$EDGE_DOMAIN"; then
                default_domain="$EDGE_DOMAIN"
            fi
            if [[ -z "$default_domain" ]] && ! _is_valid_ipv4 "$preferred_host"; then
                default_domain="$preferred_host"
            fi
            if [[ -n "$default_domain" ]]; then
                read -p "👉 Enter your domain name [$default_domain]: " domain_name
                domain_name=${domain_name:-$default_domain}
            else
                read -p "👉 Enter your domain name (e.g. vpn.example.com): " domain_name
            fi
            if [[ -z "$domain_name" ]]; then
                echo -e "${C_RED}❌ Domain name cannot be empty.${C_RESET}"
                return 1
            fi
            if _is_valid_ipv4 "$domain_name"; then
                echo -e "${C_RED}❌ Certbot requires a real domain name, not a raw IP address.${C_RESET}"
                return 1
            fi
            read -p "👉 Enter your email for Let's Encrypt [${EDGE_EMAIL}]: " email
            email=${email:-$EDGE_EMAIL}
            if [[ -z "$email" ]]; then
                echo -e "${C_RED}❌ Email cannot be empty.${C_RESET}"
                return 1
            fi
            obtain_certbot_edge_cert "$domain_name" "$email"
            ;;
        *)
            echo -e "${C_RED}❌ Invalid option.${C_RESET}"
            return 1
            ;;
    esac
}

write_internal_nginx_config() {
    local server_name="$1"
    [[ -z "$server_name" ]] && server_name="_"
    mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
    cat > "$NGINX_CONFIG_FILE" <<EOF
server {
    listen 127.0.0.1:${NGINX_INTERNAL_HTTP_PORT} default_server;
    listen 127.0.0.1:${NGINX_INTERNAL_TLS_PORT} ssl http2 default_server;
    server_tokens off;
    server_name ${server_name};

    ssl_certificate ${SSL_CERT_CHAIN_FILE};
    ssl_certificate_key ${SSL_CERT_KEY_FILE};
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!eNULL:!MD5:!DES:!RC4:!ADH:!SSLv3:!EXP:!PSK:!DSS;
    resolver 1.1.1.1 8.8.8.8 ipv6=off valid=300s;

    location ~ ^/(?<fwdport>\d+)/(?<fwdpath>.*)$ {
        client_max_body_size 0;
        client_body_timeout 1d;
        grpc_read_timeout 1d;
        grpc_socket_keepalive on;
        proxy_read_timeout 1d;
        proxy_http_version 1.1;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_socket_keepalive on;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        if (\$content_type ~* "GRPC") { grpc_pass grpc://127.0.0.1:\$fwdport\$is_args\$args; break; }
        proxy_pass http://127.0.0.1:\$fwdport\$is_args\$args;
        break;
    }

    location / {
        proxy_read_timeout 3600s;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_http_version 1.1;
        proxy_socket_keepalive on;
        tcp_nodelay on;
        tcp_nopush off;
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF
    ln -sf "$NGINX_CONFIG_FILE" /etc/nginx/sites-enabled/default
}

write_haproxy_edge_config() {
    mkdir -p /etc/haproxy
    cat > "$HAPROXY_CONFIG" <<EOF
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log     global
    mode    tcp
    option  tcplog
    option  dontlognull
    timeout connect 5s
    timeout client  24h
    timeout server  24h

# ====================================================================
# TIER 1: PORT ${EDGE_PUBLIC_HTTP_PORT} (Cleartext Payloads & Raw SSH)
# ====================================================================
frontend port_80_edge
    bind *:${EDGE_PUBLIC_HTTP_PORT}
    mode tcp
    tcp-request inspect-delay 2s

    acl is_ssh payload(0,7) -m bin 5353482d322e30

    tcp-request content accept if is_ssh
    tcp-request content accept if HTTP

    use_backend direct_ssh if is_ssh
    default_backend nginx_cleartext

# ====================================================================
# TIER 1: PORT ${EDGE_PUBLIC_TLS_PORT} (TLS v2ray, SSL Payloads, Raw SSH)
# ====================================================================
frontend port_443_edge
    bind *:${EDGE_PUBLIC_TLS_PORT}
    mode tcp
    tcp-request inspect-delay 2s

    acl is_ssh payload(0,7) -m bin 5353482d322e30
    acl is_tls req.ssl_hello_type 1
    acl has_web_alpn req.ssl_alpn -m sub h2 http/1.1

    tcp-request content accept if is_ssh
    tcp-request content accept if HTTP
    tcp-request content accept if is_tls

    use_backend direct_ssh if is_ssh
    use_backend nginx_cleartext if HTTP
    use_backend nginx_tls if is_tls has_web_alpn
    default_backend loopback_ssl_terminator

# ====================================================================
# TIER 2: INTERNAL DECRYPTOR (Only for Any-SNI SSH-TLS)
# ====================================================================
frontend internal_decryptor
    bind 127.0.0.1:${HAPROXY_INTERNAL_DECRYPT_PORT} ssl crt ${SSL_CERT_FILE}
    mode tcp
    tcp-request inspect-delay 2s

    acl is_ssh payload(0,7) -m bin 5353482d322e30
    tcp-request content accept if is_ssh
    tcp-request content accept if HTTP

    use_backend direct_ssh if is_ssh
    default_backend nginx_cleartext

# ====================================================================
# DESTINATION BACKENDS (Clean handoffs, no proxy headers)
# ====================================================================
backend direct_ssh
    mode tcp
    server ssh_server 127.0.0.1:22

backend nginx_cleartext
    mode tcp
    server nginx_8880 127.0.0.1:${NGINX_INTERNAL_HTTP_PORT}

backend nginx_tls
    mode tcp
    server nginx_8443 127.0.0.1:${NGINX_INTERNAL_TLS_PORT}

backend loopback_ssl_terminator
    mode tcp
    server haproxy_ssl 127.0.0.1:${HAPROXY_INTERNAL_DECRYPT_PORT}
EOF
}

save_edge_ports_info() {
    cat > "$NGINX_PORTS_FILE" <<EOF
EDGE_HTTP_PORT="${EDGE_PUBLIC_HTTP_PORT}"
EDGE_TLS_PORT="${EDGE_PUBLIC_TLS_PORT}"
HTTP_PORTS="${NGINX_INTERNAL_HTTP_PORT}"
TLS_PORTS="${NGINX_INTERNAL_TLS_PORT}"
EOF
}

configure_edge_stack() {
    local server_name="$1"
    [[ -z "$server_name" ]] && server_name="_"

    backup_edge_configs

    echo -e "\n${C_BLUE}📝 Writing internal Nginx config (127.0.0.1:${NGINX_INTERNAL_HTTP_PORT}/${NGINX_INTERNAL_TLS_PORT})...${C_RESET}"
    write_internal_nginx_config "$server_name"

    echo -e "${C_BLUE}📝 Writing HAProxy edge config (${EDGE_PUBLIC_HTTP_PORT}/${EDGE_PUBLIC_TLS_PORT})...${C_RESET}"
    write_haproxy_edge_config

    echo -e "\n${C_BLUE}🧪 Validating Nginx configuration...${C_RESET}"
    if ! nginx -t >/dev/null 2>&1; then
        echo -e "${C_RED}❌ Nginx configuration validation failed.${C_RESET}"
        nginx -t
        return 1
    fi

    echo -e "${C_BLUE}🧪 Validating HAProxy configuration...${C_RESET}"
    if ! haproxy -c -f "$HAPROXY_CONFIG" >/dev/null 2>&1; then
        echo -e "${C_RED}❌ HAProxy configuration validation failed.${C_RESET}"
        haproxy -c -f "$HAPROXY_CONFIG"
        return 1
    fi

    systemctl daemon-reload
    systemctl enable nginx >/dev/null 2>&1
    systemctl enable haproxy >/dev/null 2>&1

    echo -e "\n${C_BLUE}▶️ Restarting internal Nginx...${C_RESET}"
    systemctl restart nginx || {
        echo -e "${C_RED}❌ Nginx failed to restart.${C_RESET}"
        systemctl status nginx --no-pager
        return 1
    }

    echo -e "${C_BLUE}▶️ Restarting HAProxy edge...${C_RESET}"
    systemctl restart haproxy || {
        echo -e "${C_RED}❌ HAProxy failed to restart.${C_RESET}"
        systemctl status haproxy --no-pager
        return 1
    }

    sleep 2
    if ! systemctl is-active --quiet nginx; then
        echo -e "${C_RED}❌ Nginx is not active after restart.${C_RESET}"
        systemctl status nginx --no-pager
        return 1
    fi
    if ! systemctl is-active --quiet haproxy; then
        echo -e "${C_RED}❌ HAProxy is not active after restart.${C_RESET}"
        systemctl status haproxy --no-pager
        return 1
    fi

    save_edge_ports_info
    return 0
}

install_ssl_tunnel() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🚀 Installing HAProxy Edge Stack (80/443 -> 8880/8443) ---${C_RESET}"
    echo -e "\n${C_CYAN}This installer will configure:${C_RESET}"
    echo -e "   • HAProxy on ${C_WHITE}${EDGE_PUBLIC_HTTP_PORT}/${EDGE_PUBLIC_TLS_PORT}${C_RESET}"
    echo -e "   • Internal Nginx on ${C_WHITE}${NGINX_INTERNAL_HTTP_PORT}/${NGINX_INTERNAL_TLS_PORT}${C_RESET}"
    echo -e "   • Loopback SSL decryptor on ${C_WHITE}${HAPROXY_INTERNAL_DECRYPT_PORT}${C_RESET}"

    if [ -f "$HAPROXY_CONFIG" ] || [ -f "$NGINX_CONFIG_FILE" ]; then
        echo -e "\n${C_YELLOW}⚠️ Existing HAProxy/Nginx configs will be replaced with the DAHOOM edge layout.${C_RESET}"
        read -p "👉 Continue with the replacement? (y/n): " confirm_replace
        if [[ "$confirm_replace" != "y" && "$confirm_replace" != "Y" ]]; then
            echo -e "${C_RED}❌ Installation cancelled.${C_RESET}"
            return
        fi
    fi

    mkdir -p "$DB_DIR" "$SSL_CERT_DIR"

    ensure_edge_stack_packages || return

    systemctl stop haproxy >/dev/null 2>&1
    systemctl stop nginx >/dev/null 2>&1
    sleep 1

    check_and_free_ports \
        "$EDGE_PUBLIC_HTTP_PORT" \
        "$EDGE_PUBLIC_TLS_PORT" \
        "$NGINX_INTERNAL_HTTP_PORT" \
        "$NGINX_INTERNAL_TLS_PORT" \
        "$HAPROXY_INTERNAL_DECRYPT_PORT" || return

    check_and_open_firewall_port "$EDGE_PUBLIC_HTTP_PORT" tcp || return
    check_and_open_firewall_port "$EDGE_PUBLIC_TLS_PORT" tcp || return

    select_edge_certificate || return

    load_edge_cert_info
    local server_name="${EDGE_DOMAIN:-$(detect_preferred_host)}"
    [[ -z "$server_name" ]] && server_name="_"

    configure_edge_stack "$server_name" || return

    echo -e "\n${C_GREEN}✅ SUCCESS: HAProxy edge stack is active.${C_RESET}"
    echo -e "   • Public edge ports: ${C_YELLOW}${EDGE_PUBLIC_HTTP_PORT}/${EDGE_PUBLIC_TLS_PORT}${C_RESET}"
    echo -e "   • Internal Nginx ports: ${C_YELLOW}${NGINX_INTERNAL_HTTP_PORT}/${NGINX_INTERNAL_TLS_PORT}${C_RESET}"
    echo -e "   • Shared certificate: ${C_YELLOW}${EDGE_CERT_MODE:-unknown}${C_RESET}"
}

uninstall_ssl_tunnel() {
    echo -e "\n${C_BOLD}${C_PURPLE}--- 🗑️ Uninstalling HAProxy Edge Stack ---${C_RESET}"
    if ! command -v haproxy &> /dev/null; then
        echo -e "${C_YELLOW}ℹ️ HAProxy is not installed, skipping service removal.${C_RESET}"
    else
        echo -e "${C_GREEN}🛑 Stopping and disabling HAProxy...${C_RESET}"
        systemctl stop haproxy >/dev/null 2>&1
        systemctl disable haproxy >/dev/null 2>&1
    fi

    if [ -f "$HAPROXY_CONFIG" ]; then
        cat > "$HAPROXY_CONFIG" <<EOF
global
    log /dev/log local0
    log /dev/log local1 notice

defaults
    log     global
EOF
    fi

    local delete_cert="n"
    if [[ "$UNINSTALL_MODE" == "silent" ]]; then
        delete_cert="y"
    elif [ -f "$SSL_CERT_FILE" ] || [ -f "$SSL_CERT_CHAIN_FILE" ] || [ -f "$SSL_CERT_KEY_FILE" ]; then
        if systemctl is-active --quiet nginx; then
            echo -e "${C_YELLOW}⚠️ The shared certificate is also used by the internal Nginx proxy.${C_RESET}"
        fi
        read -p "👉 Delete the shared TLS certificate too? (y/n): " delete_cert
    fi

    if [[ "$delete_cert" == "y" || "$delete_cert" == "Y" ]]; then
        if systemctl is-active --quiet nginx; then
            echo -e "${C_GREEN}🛑 Stopping Nginx because the shared certificate is being removed...${C_RESET}"
            systemctl stop nginx >/dev/null 2>&1
        fi
        rm -f "$SSL_CERT_FILE" "$SSL_CERT_CHAIN_FILE" "$SSL_CERT_KEY_FILE" "$EDGE_CERT_INFO_FILE"
        rm -f "$NGINX_PORTS_FILE"
        echo -e "${C_GREEN}🗑️ Shared certificate files removed.${C_RESET}"
    fi

    echo -e "${C_GREEN}✅ HAProxy edge stack has been removed.${C_RESET}"
    if systemctl is-active --quiet nginx; then
        echo -e "${C_DIM}The internal Nginx proxy is still installed on ${NGINX_INTERNAL_HTTP_PORT}/${NGINX_INTERNAL_TLS_PORT}.${C_RESET}"
    fi
}

show_dnstt_details() {
    if [ -f "$DNSTT_CONFIG_FILE" ]; then
        source "$DNSTT_CONFIG_FILE"
        echo -e "\n${C_GREEN}=====================================================${C_RESET}"
        echo -e "${C_GREEN}            📡 DNSTT Connection Details             ${C_RESET}"
        echo -e "${C_GREEN}=====================================================${C_RESET}"
        echo -e "\n${C_WHITE}Your connection details:${C_RESET}"
        echo -e "  - ${C_CYAN}Tunnel Domain:${C_RESET} ${C_YELLOW}$TUNNEL_DOMAIN${C_RESET}"
        echo -e "  - ${C_CYAN}Public Key:${C_RESET}    ${C_YELLOW}$PUBLIC_KEY${C_RESET}"
        if [[ -n "$FORWARD_DESC" ]]; then
            echo -e "  - ${C_CYAN}Forwarding To:${C_RESET} ${C_YELLOW}$FORWARD_DESC${C_RESET}"
        else
            echo -e "  - ${C_CYAN}Forwarding To:${C_RESET} ${C_YELLOW}Unknown (config_missing)${C_RESET}"
        fi
        if [[ -n "$MTU_VALUE" ]]; then
            echo -e "  - ${C_CYAN}MTU Value:${C_RESET}     ${C_YELLOW}$MTU_VALUE${C_RESET}"
        fi
        if [[ "$DNSTT_RECORDS_MANAGED" == "false" && -n "$NS_DOMAIN" ]]; then
             echo -e "  - ${C_CYAN}NS Record:${C_RESET}     ${C_YELLOW}$NS_DOMAIN${C_RESET}"
        fi
        
        if [[ "$FORWARD_DESC" == *"V2Ray"* ]]; then
             echo -e "  - ${C_CYAN}Action Required:${C_RESET} ${C_YELLOW}Ensure a V2Ray service (vless/vmess/trojan) listens on port 8787 (no TLS)${C_RESET}"
        elif [[ "$FORWARD_DESC" == *"SSH"* ]]; then
             echo -e "  - ${C_CYAN}Action Required:${C_RESET} ${C_YELLOW}Ensure your SSH client is configured to use the DNS tunnel.${C_RESET}"
        fi
        
        echo -e "\n${C_DIM}Use these details in your client configuration.${C_RESET}"
    else
        echo -e "\n${C_YELLOW}ℹ️ DNSTT configuration file not found. Details are unavailable.${C_RESET}"
    fi
}

install_dnstt() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 📡 DNSTT (DNS Tunnel) Management ---${C_RESET}"
    if [ -f "$DNSTT_SERVICE_FILE" ]; then
        echo -e "\n${C_YELLOW}ℹ️ DNSTT is already installed.${C_RESET}"
        show_dnstt_details
        return
    fi
    
    # --- FIX: Force release of Port 53 / Disable systemd-resolved ---
    echo -e "${C_GREEN}⚙️ Forcing release of Port 53 (stopping systemd-resolved)...${C_RESET}"
    systemctl stop systemd-resolved >/dev/null 2>&1
    systemctl disable systemd-resolved >/dev/null 2>&1
    # Mask it so it never starts again on reboot
    systemctl mask systemd-resolved >/dev/null 2>&1
    chattr -i /etc/resolv.conf &>/dev/null
    rm -f /etc/resolv.conf
    printf 'nameserver 8.8.8.8\nnameserver 8.8.4.4\n' > /etc/resolv.conf
    chattr +i /etc/resolv.conf
    # ----------------------------------------------------------------
    
    echo -e "\n${C_BLUE}🔎 Checking if port 53 (UDP) is available...${C_RESET}"
    if ss -lunp | grep -q ':53\s'; then
        if [[ $(ps -p $(ss -lunp | grep ':53\s' | grep -oP 'pid=\K[0-9]+') -o comm=) == "systemd-resolve" ]]; then
            echo -e "${C_YELLOW}⚠️ Warning: Port 53 is in use by 'systemd-resolved'.${C_RESET}"
            echo -e "${C_YELLOW}This is the system's DNS stub resolver. It must be disabled to run DNSTT.${C_RESET}"
            read -p "👉 Allow the script to automatically disable it and reconfigure DNS? (y/n): " resolve_confirm
            if [[ "$resolve_confirm" == "y" || "$resolve_confirm" == "Y" ]]; then
                echo -e "${C_GREEN}⚙️ Stopping and disabling systemd-resolved to free port 53...${C_RESET}"
                systemctl stop systemd-resolved
                systemctl disable systemd-resolved
                chattr -i /etc/resolv.conf &>/dev/null
                rm -f /etc/resolv.conf
                echo "nameserver 8.8.8.8" > /etc/resolv.conf
                chattr +i /etc/resolv.conf
                echo -e "${C_GREEN}✅ Port 53 has been freed and DNS set to 8.8.8.8.${C_RESET}"
            else
                echo -e "${C_RED}❌ Cannot proceed without freeing port 53. Aborting.${C_RESET}"
                return
            fi
        else
            check_and_free_ports "53" || return
        fi
    else
        echo -e "${C_GREEN}✅ Port 53 (UDP) is free to use.${C_RESET}"
    fi

    check_and_open_firewall_port 53 udp || return



    local forward_port=""
    local forward_desc=""
    echo -e "\n${C_BLUE}Please choose where DNSTT should forward traffic:${C_RESET}"
    echo -e "  ${C_GREEN}[ 1]${C_RESET} ➡️ Forward to local SSH service (port 22)"
    echo -e "  ${C_GREEN}[ 2]${C_RESET} ➡️ Forward to local V2Ray backend (port 8787)"
    read -p "👉 Enter your choice [2]: " fwd_choice
    fwd_choice=${fwd_choice:-2}
    if [[ "$fwd_choice" == "1" ]]; then
        forward_port="22"
        forward_desc="SSH (port 22)"
        echo -e "${C_GREEN}ℹ️ DNSTT will forward to SSH on 127.0.0.1:22.${C_RESET}"
        

        
    elif [[ "$fwd_choice" == "2" ]]; then
        forward_port="8787"
        forward_desc="V2Ray (port 8787)"
        echo -e "${C_GREEN}ℹ️ DNSTT will forward to V2Ray on 127.0.0.1:8787.${C_RESET}"
    else
        echo -e "${C_RED}❌ Invalid choice. Aborting.${C_RESET}"
        return
    fi
    local FORWARD_TARGET="127.0.0.1:$forward_port"
    
    local NS_DOMAIN=""
    local TUNNEL_DOMAIN=""
    local DNSTT_RECORDS_MANAGED="true"
    local NS_SUBDOMAIN=""
    local TUNNEL_SUBDOMAIN=""
    local HAS_IPV6="false"

    read -p "👉 Auto-generate DNS records or use custom ones? (auto/custom) [auto]: " dns_choice
    dns_choice=${dns_choice:-auto}

    if [[ "$dns_choice" == "custom" ]]; then
        DNSTT_RECORDS_MANAGED="false"
        read -p "👉 Enter your full nameserver domain (e.g., ns1.yourdomain.com): " NS_DOMAIN
        if [[ -z "$NS_DOMAIN" ]]; then echo -e "\n${C_RED}❌ Nameserver domain cannot be empty. Aborting.${C_RESET}"; return; fi
        read -p "👉 Enter your full tunnel domain (e.g., tun.yourdomain.com): " TUNNEL_DOMAIN
        if [[ -z "$TUNNEL_DOMAIN" ]]; then echo -e "\n${C_RED}❌ Tunnel domain cannot be empty. Aborting.${C_RESET}"; return; fi
    else
        echo -e "\n${C_BLUE}⚙️ Configuring DNS records for DNSTT...${C_RESET}"
        local SERVER_IPV4
        SERVER_IPV4=$(curl -s -4 icanhazip.com)
        if ! _is_valid_ipv4 "$SERVER_IPV4"; then
            echo -e "\n${C_RED}❌ Error: Could not retrieve a valid public IPv4 address from icanhazip.com.${C_RESET}"
            echo -e "${C_YELLOW}ℹ️ Please check your server's network connection and DNS resolver settings.${C_RESET}"
            echo -e "   Output received: '$SERVER_IPV4'"
            return 1
        fi
        
        local SERVER_IPV6
        SERVER_IPV6=$(curl -s -6 icanhazip.com --max-time 5)
        
        local RANDOM_STR
        RANDOM_STR=$(tr -dc a-z0-9 < /dev/urandom | head -c 6)
        NS_SUBDOMAIN="ns-$RANDOM_STR"
        TUNNEL_SUBDOMAIN="tun-$RANDOM_STR"
        NS_DOMAIN="$NS_SUBDOMAIN.$DESEC_DOMAIN"
        TUNNEL_DOMAIN="$TUNNEL_SUBDOMAIN.$DESEC_DOMAIN"

        local API_DATA
        API_DATA=$(printf '[{"subname": "%s", "type": "A", "ttl": 3600, "records": ["%s"]}, {"subname": "%s", "type": "NS", "ttl": 3600, "records": ["%s."]}]' \
            "$NS_SUBDOMAIN" "$SERVER_IPV4" "$TUNNEL_SUBDOMAIN" "$NS_DOMAIN")

        if [[ -n "$SERVER_IPV6" ]]; then
            local aaaa_record
            aaaa_record=$(printf ',{"subname": "%s", "type": "AAAA", "ttl": 3600, "records": ["%s"]}' "$NS_SUBDOMAIN" "$SERVER_IPV6")
            API_DATA="${API_DATA%?}${aaaa_record}]"
            HAS_IPV6="true"
        fi

        local CREATE_RESPONSE
        CREATE_RESPONSE=$(curl -s -w "%{http_code}" -X POST "https://desec.io/api/v1/domains/$DESEC_DOMAIN/rrsets/" \
            -H "Authorization: Token $DESEC_TOKEN" -H "Content-Type: application/json" \
            --data "$API_DATA")
        
        local HTTP_CODE=${CREATE_RESPONSE: -3}
        local RESPONSE_BODY=${CREATE_RESPONSE:0:${#CREATE_RESPONSE}-3}

        if [[ "$HTTP_CODE" -ne 201 ]]; then
            echo -e "${C_RED}❌ Failed to create auto DNSTT records via deSEC (HTTP $HTTP_CODE).${C_RESET}"
            if [[ -n "$RESPONSE_BODY" ]]; then
                echo -e "${C_YELLOW}Response: $(echo "$RESPONSE_BODY" | jq -r '.detail // .' 2>/dev/null || echo "$RESPONSE_BODY")${C_RESET}"
            fi
            echo -e "\n${C_CYAN}ℹ️ The default deSEC domain '$DESEC_DOMAIN' is unavailable or requires custom credentials.${C_RESET}"
            read -p "👉 Would you like to enter your own custom NS & Tunnel domains instead? (y/n) [y]: " fallback_custom
            fallback_custom=${fallback_custom:-y}
            if [[ "$fallback_custom" == "y" || "$fallback_custom" == "Y" ]]; then
                DNSTT_RECORDS_MANAGED="false"
                read -p "👉 Enter your full nameserver domain (e.g., ns1.yourdomain.com): " NS_DOMAIN
                if [[ -z "$NS_DOMAIN" ]]; then echo -e "\n${C_RED}❌ Nameserver domain cannot be empty. Aborting.${C_RESET}"; return; fi
                read -p "👉 Enter your full tunnel domain (e.g., tun.yourdomain.com): " TUNNEL_DOMAIN
                if [[ -z "$TUNNEL_DOMAIN" ]]; then echo -e "\n${C_RED}❌ Tunnel domain cannot be empty. Aborting.${C_RESET}"; return; fi
            else
                return 1
            fi
        fi
    fi
    
    read -p "👉 Enter MTU value (e.g., 512, 1200) or press [Enter] for default: " mtu_value
    local mtu_string=""
    if [[ "$mtu_value" =~ ^[0-9]+$ ]]; then
        mtu_string=" -mtu $mtu_value"
        echo -e "${C_GREEN}ℹ️ Using MTU: $mtu_value${C_RESET}"
    else
        mtu_value=""
        echo -e "${C_YELLOW}ℹ️ Using default MTU.${C_RESET}"
    fi

    echo -e "\n${C_BLUE}📥 Downloading pre-compiled DNSTT server binary from GitHub (mooa322/fm)...${C_RESET}"
    local arch
    arch=$(uname -m)
    local update_branch; update_branch=$(get_update_branch)
    local binary_url=""
    if [[ "$arch" == "x86_64" ]]; then
        binary_url="https://raw.githubusercontent.com/mooa322/fm/${update_branch}/udp/dnstt-server-linux-amd64"
        echo -e "${C_BLUE}ℹ️ Detected x86_64 (amd64) architecture.${C_RESET}"
    elif [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then
        binary_url="https://raw.githubusercontent.com/mooa322/fm/${update_branch}/udp/dnstt-server-linux-arm64"
        echo -e "${C_BLUE}ℹ️ Detected ARM64 architecture.${C_RESET}"
    else
        echo -e "\n${C_RED}❌ Unsupported architecture: $arch. Cannot install DNSTT.${C_RESET}"
        return
    fi
    
    curl -sL "$binary_url" -o "$DNSTT_BINARY"
    if [ $? -ne 0 ]; then
        echo -e "\n${C_RED}❌ Failed to download the DNSTT binary.${C_RESET}"
        return
    fi
    chmod +x "$DNSTT_BINARY"

    echo -e "${C_BLUE}🔐 Generating cryptographic keys...${C_RESET}"
    mkdir -p "$DNSTT_KEYS_DIR"
    "$DNSTT_BINARY" -gen-key -privkey-file "$DNSTT_KEYS_DIR/server.key" -pubkey-file "$DNSTT_KEYS_DIR/server.pub"
    if [[ ! -f "$DNSTT_KEYS_DIR/server.key" ]]; then echo -e "${C_RED}❌ Failed to generate DNSTT keys.${C_RESET}"; return; fi
    
    local PUBLIC_KEY
    PUBLIC_KEY=$(cat "$DNSTT_KEYS_DIR/server.pub")
    
    echo -e "\n${C_BLUE}📝 Creating systemd service...${C_RESET}"
    cat > "$DNSTT_SERVICE_FILE" <<-EOF
[Unit]
Description=DNSTT (DNS Tunnel) Server for $forward_desc
After=network-online.target
Wants=network-online.target
Conflicts=systemd-resolved.service
[Service]
Type=simple
User=root
ExecStartPre=/bin/bash -c 'systemctl stop systemd-resolved 2>/dev/null; systemctl mask systemd-resolved 2>/dev/null; chattr -i /etc/resolv.conf 2>/dev/null; printf "nameserver 8.8.8.8\\nnameserver 8.8.4.4\\n" > /etc/resolv.conf; chattr +i /etc/resolv.conf; sleep 1'
ExecStart=$DNSTT_BINARY -udp :53$mtu_string -privkey-file $DNSTT_KEYS_DIR/server.key $TUNNEL_DOMAIN $FORWARD_TARGET
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
    echo -e "\n${C_BLUE}💾 Saving configuration and starting service...${C_RESET}"
    cat > "$DNSTT_CONFIG_FILE" <<-EOF
NS_SUBDOMAIN="$NS_SUBDOMAIN"
TUNNEL_SUBDOMAIN="$TUNNEL_SUBDOMAIN"
NS_DOMAIN="$NS_DOMAIN"
TUNNEL_DOMAIN="$TUNNEL_DOMAIN"
PUBLIC_KEY="$PUBLIC_KEY"
FORWARD_DESC="$forward_desc"
DNSTT_RECORDS_MANAGED="$DNSTT_RECORDS_MANAGED"
HAS_IPV6="$HAS_IPV6"
MTU_VALUE="$mtu_value"
EOF
    systemctl daemon-reload
    systemctl enable dnstt.service
    systemctl start dnstt.service
    sleep 2
    if systemctl is-active --quiet dnstt.service; then
        echo -e "\n${C_GREEN}✅ SUCCESS: DNSTT has been installed and started!${C_RESET}"
        show_dnstt_details
    else
        echo -e "\n${C_RED}❌ ERROR: DNSTT service failed to start.${C_RESET}"
        journalctl -u dnstt.service -n 15 --no-pager
    fi
}

uninstall_dnstt() {
    echo -e "\n${C_BOLD}${C_PURPLE}--- 🗑️ Uninstalling DNSTT ---${C_RESET}"
    if [ ! -f "$DNSTT_SERVICE_FILE" ]; then
        echo -e "${C_YELLOW}ℹ️ DNSTT does not appear to be installed, skipping.${C_RESET}"
        return
    fi
    local confirm="y"
    if [[ "$UNINSTALL_MODE" != "silent" ]]; then
        read -p "👉 Are you sure you want to uninstall DNSTT? This will delete DNS records if they were auto-generated. (y/n): " confirm
    fi
    if [[ "$confirm" != "y" ]]; then
        echo -e "\n${C_YELLOW}❌ Uninstallation cancelled.${C_RESET}"
        return
    fi
    echo -e "${C_BLUE}🛑 Stopping and disabling DNSTT service...${C_RESET}"
    systemctl stop dnstt.service > /dev/null 2>&1
    systemctl disable dnstt.service > /dev/null 2>&1
    if [ -f "$DNSTT_CONFIG_FILE" ]; then
        source "$DNSTT_CONFIG_FILE"
        if [[ "$DNSTT_RECORDS_MANAGED" == "true" ]]; then
            echo -e "${C_BLUE}🗑️ Removing auto-generated DNS records...${C_RESET}"
            curl -s -X DELETE "https://desec.io/api/v1/domains/$DESEC_DOMAIN/rrsets/$TUNNEL_SUBDOMAIN/NS/" \
                 -H "Authorization: Token $DESEC_TOKEN" > /dev/null
            curl -s -X DELETE "https://desec.io/api/v1/domains/$DESEC_DOMAIN/rrsets/$NS_SUBDOMAIN/A/" \
                 -H "Authorization: Token $DESEC_TOKEN" > /dev/null
            if [[ "$HAS_IPV6" == "true" ]]; then
                curl -s -X DELETE "https://desec.io/api/v1/domains/$DESEC_DOMAIN/rrsets/$NS_SUBDOMAIN/AAAA/" \
                     -H "Authorization: Token $DESEC_TOKEN" > /dev/null
            fi
            echo -e "${C_GREEN}✅ DNS records have been removed.${C_RESET}"
        else
            echo -e "${C_YELLOW}⚠️ DNS records were manually configured. Please delete them from your DNS provider.${C_RESET}"
        fi
    fi
    echo -e "${C_BLUE}🗑️ Removing service files and binaries...${C_RESET}"
    rm -f "$DNSTT_SERVICE_FILE"
    rm -f "$DNSTT_BINARY"
    rm -rf "$DNSTT_KEYS_DIR"
    rm -f "$DNSTT_CONFIG_FILE"
    systemctl daemon-reload
    
    echo -e "${C_YELLOW}ℹ️ Restoring system DNS resolver...${C_RESET}"
    chattr -i /etc/resolv.conf &>/dev/null
    systemctl unmask systemd-resolved &>/dev/null
    systemctl enable systemd-resolved &>/dev/null
    systemctl start systemd-resolved &>/dev/null

    echo -e "\n${C_GREEN}✅ DNSTT has been successfully uninstalled.${C_RESET}"
}

install_falcon_proxy() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🦅 Installing Falcon Proxy (Websockets/Socks) ---${C_RESET}"
    
    if [ -f "$FALCONPROXY_SERVICE_FILE" ]; then
        echo -e "\n${C_YELLOW}ℹ️ Falcon Proxy is already installed.${C_RESET}"
        if [ -f "$FALCONPROXY_CONFIG_FILE" ]; then
            source "$FALCONPROXY_CONFIG_FILE"
            echo -e "   It is configured to run on port(s): ${C_YELLOW}$PORTS${C_RESET}"
            echo -e "   Installed Version: ${C_YELLOW}${INSTALLED_VERSION:-Unknown}${C_RESET}"
        fi
        read -p "👉 Do you want to reinstall/update? (y/n): " confirm_reinstall
        if [[ "$confirm_reinstall" != "y" ]]; then return; fi
    fi

    local ports
    read -p "👉 Enter port(s) for Falcon Proxy (e.g., 8080 or 8080 8888) [8080]: " ports
    ports=${ports:-8080}

    local port_array=($ports)
    for port in "${port_array[@]}"; do
        if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
            echo -e "\n${C_RED}❌ Invalid port number: $port. Aborting.${C_RESET}"
            return
        fi
        check_and_free_ports "$port" || return
        check_and_open_firewall_port "$port" tcp || return
    done

    local update_branch; update_branch=$(get_update_branch)
    local download_url="https://raw.githubusercontent.com/mooa322/fm/${update_branch}/udp/falconproxy"

    echo -e "\n${C_GREEN}📥 Downloading Falcon Proxy binary from GitHub (mooa322/fm)...${C_RESET}"
    if ! wget -q --show-progress -O "$FALCONPROXY_BINARY" "$download_url"; then
        echo -e "\n${C_RED}❌ Failed to download Falcon Proxy binary from $download_url.${C_RESET}"
        return 1
    fi
    chmod +x "$FALCONPROXY_BINARY"
    local SELECTED_VERSION="official-binary"

    echo -e "\n${C_GREEN}📝 Creating systemd service file...${C_RESET}"
    cat > "$FALCONPROXY_SERVICE_FILE" <<EOF
[Unit]
Description=Falcon Proxy ($SELECTED_VERSION)
After=network.target

[Service]
User=root
Type=simple
ExecStart=$FALCONPROXY_BINARY -p $ports
Restart=always
RestartSec=2s

[Install]
WantedBy=default.target
EOF

    echo -e "\n${C_GREEN}💾 Saving configuration...${C_RESET}"
    cat > "$FALCONPROXY_CONFIG_FILE" <<EOF
PORTS="$ports"
INSTALLED_VERSION="$SELECTED_VERSION"
EOF

    echo -e "\n${C_GREEN}▶️ Enabling and starting Falcon Proxy service...${C_RESET}"
    systemctl daemon-reload
    systemctl enable falconproxy.service
    systemctl restart falconproxy.service
    sleep 2
    
    if systemctl is-active --quiet falconproxy; then
        echo -e "\n${C_GREEN}✅ SUCCESS: Falcon Proxy $SELECTED_VERSION is installed and active.${C_RESET}"
        echo -e "   Listening on port(s): ${C_YELLOW}$ports${C_RESET}"
    else
        echo -e "\n${C_RED}❌ ERROR: Falcon Proxy service failed to start.${C_RESET}"
        echo -e "${C_YELLOW}ℹ️ Displaying last 15 lines of the service log for diagnostics:${C_RESET}"
        journalctl -u falconproxy.service -n 15 --no-pager
    fi
}

uninstall_falcon_proxy() {
    echo -e "\n${C_BOLD}${C_PURPLE}--- 🗑️ Uninstalling Falcon Proxy ---${C_RESET}"
    if [ ! -f "$FALCONPROXY_SERVICE_FILE" ]; then
        echo -e "${C_YELLOW}ℹ️ Falcon Proxy is not installed, skipping.${C_RESET}"
        return
    fi
    echo -e "${C_GREEN}🛑 Stopping and disabling Falcon Proxy service...${C_RESET}"
    systemctl stop falconproxy.service >/dev/null 2>&1
    systemctl disable falconproxy.service >/dev/null 2>&1
    echo -e "${C_GREEN}🗑️ Removing service file...${C_RESET}"
    rm -f "$FALCONPROXY_SERVICE_FILE"
    systemctl daemon-reload
    echo -e "${C_GREEN}🗑️ Removing binary and config files...${C_RESET}"
    rm -f "$FALCONPROXY_BINARY"
    rm -f "$FALCONPROXY_CONFIG_FILE"
    echo -e "${C_GREEN}✅ Falcon Proxy has been uninstalled successfully.${C_RESET}"
}

# --- ZiVPN Installation Logic ---
install_zivpn() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🚀 Installing ZiVPN (UDP/VPN) ---${C_RESET}"
    
    if [ -f "$ZIVPN_SERVICE_FILE" ]; then
        echo -e "\n${C_YELLOW}ℹ️ ZiVPN is already installed.${C_RESET}"
        return
    fi

    if [ ! -f "$BADVPN_SERVICE_FILE" ]; then
        echo -e "\n${C_YELLOW}⚠️ ZiVPN requires the badvpn (udpgw) backend to provide internet access.${C_RESET}"
        echo -e "${C_GREEN}📦 Automatically installing badvpn backend...${C_RESET}"
        sleep 2
        install_badvpn
        clear; show_banner
        echo -e "${C_BOLD}${C_PURPLE}--- 🚀 Resuming ZiVPN Installation ---${C_RESET}"
    fi

    check_and_free_ports 5667 || return
    check_and_open_firewall_port 5667 udp || return
    check_and_open_firewall_port_range "6000:19999" udp || return

    echo -e "\n${C_GREEN}⚙️ Checking system architecture...${C_RESET}"
    local arch=$(uname -m)
    local update_branch; update_branch=$(get_update_branch)
    local zivpn_url=""
    
    if [[ "$arch" == "x86_64" ]]; then
        zivpn_url="https://raw.githubusercontent.com/mooa322/fm/${update_branch}/udp/udp-zivpn-linux-amd64"
        echo -e "${C_BLUE}ℹ️ Detected AMD64/x86_64 architecture.${C_RESET}"
    elif [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then
        zivpn_url="https://raw.githubusercontent.com/mooa322/fm/${update_branch}/udp/udp-zivpn-linux-arm64"
        echo -e "${C_BLUE}ℹ️ Detected ARM64 architecture.${C_RESET}"
    elif [[ "$arch" == "armv7l" || "$arch" == "arm" ]]; then
         zivpn_url="https://raw.githubusercontent.com/mooa322/fm/${update_branch}/udp/udp-zivpn-linux-arm"
         echo -e "${C_BLUE}ℹ️ Detected ARM architecture.${C_RESET}"
    else
        echo -e "${C_RED}❌ Unsupported architecture: $arch${C_RESET}"
        return
    fi

    echo -e "\n${C_GREEN}📦 Downloading ZiVPN binary...${C_RESET}"
    if ! wget -q --show-progress -O "$ZIVPN_BIN" "$zivpn_url"; then
        echo -e "${C_RED}❌ Download failed. Check internet connection.${C_RESET}"
        return
    fi
    chmod +x "$ZIVPN_BIN"

    echo -e "\n${C_GREEN}⚙️ Configuring ZIVPN...${C_RESET}"
    mkdir -p "$ZIVPN_DIR"
    
    # Generate Certificates
    echo -e "${C_BLUE}🔐 Generating self-signed certificates...${C_RESET}"
    if ! command -v openssl &>/dev/null; then
        ff_pkg_install openssl >/dev/null 2>&1 || {
            echo -e "${C_RED}❌ Failed to install openssl for ZiVPN certificate generation.${C_RESET}"
            return
        }
    fi
    
    openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
        -subj "/C=US/ST=California/L=Los Angeles/O=Example Corp/OU=IT Department/CN=zivpn" \
        -keyout "$ZIVPN_KEY_FILE" -out "$ZIVPN_CERT_FILE" 2>/dev/null

    if [ ! -f "$ZIVPN_CERT_FILE" ]; then
        echo -e "${C_RED}❌ Failed to generate certificates.${C_RESET}"
        return
    fi

    # System Tuning
    echo -e "${C_BLUE}🔧 Tuning system network parameters...${C_RESET}"
    sysctl -w net.core.rmem_max=16777216 >/dev/null
    sysctl -w net.core.wmem_max=16777216 >/dev/null

    # Create Service
    echo -e "${C_BLUE}📝 Creating systemd service file...${C_RESET}"
    cat <<EOF > "$ZIVPN_SERVICE_FILE"
[Unit]
Description=zivpn VPN Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$ZIVPN_DIR
ExecStart=$ZIVPN_BIN server -c $ZIVPN_CONFIG_FILE
Restart=always
RestartSec=3
Environment=ZIVPN_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

    # Configure Passwords
    echo -e "\n${C_YELLOW}🔑 ZiVPN Password Setup${C_RESET}"
    read -p "👉 Enter passwords separated by commas (e.g., user1,user2) [Default: 'zi']: " input_config
    
    if [ -n "$input_config" ]; then
        IFS=',' read -r -a config_array <<< "$input_config"
        # Ensure array format for JSON
        json_passwords=$(printf '"%s",' "${config_array[@]}")
        json_passwords="[${json_passwords%,}]"
    else
        json_passwords='["zi"]'
    fi

    # Create Config File
    cat <<EOF > "$ZIVPN_CONFIG_FILE"
{
  "listen": ":5667",
   "cert": "$ZIVPN_CERT_FILE",
   "key": "$ZIVPN_KEY_FILE",
   "obfs":"zivpn",
   "auth": {
    "mode": "passwords", 
    "config": $json_passwords
  }
}
EOF

    echo -e "\n${C_GREEN}🚀 Starting ZiVPN Service...${C_RESET}"
    systemctl daemon-reload
    systemctl enable zivpn.service
    systemctl start zivpn.service

    # Port Forwarding / Firewall
    echo -e "${C_BLUE}🔥 Configuring Firewall Rules (Redirecting 6000-19999 -> 5667)...${C_RESET}"
    
    # Determine primary interface
    local iface=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
    
    if [ -n "$iface" ]; then
        iptables -t nat -C PREROUTING -i "$iface" -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null || \
            iptables -t nat -A PREROUTING -i "$iface" -p udp --dport 6000:19999 -j DNAT --to-destination :5667
        # Note: IPTables rules are not persistent by default without iptables-persistent package
    else
        echo -e "${C_YELLOW}⚠️ Could not detect default interface for IPTables redirection.${C_RESET}"
    fi

    # Cleanup
    rm -f zi.sh zi2.sh 2>/dev/null

    if systemctl is-active --quiet zivpn.service; then
        echo -e "\n${C_GREEN}✅ ZiVPN Installed Successfully!${C_RESET}"
        echo -e "   - UDP Port: 5667 (Direct)"
        echo -e "   - UDP Ports: 6000-19999 (Forwarded)"
    else
        echo -e "\n${C_RED}❌ ZiVPN Service failed to start. Check logs: journalctl -u zivpn.service${C_RESET}"
    fi
}

uninstall_zivpn() {
    if [[ "$UNINSTALL_MODE" != "silent" ]]; then
        clear; show_banner
        echo -e "${C_BOLD}${C_PURPLE}--- 🗑️ Uninstall ZiVPN ---${C_RESET}"
    fi
    
    if [ ! -f "$ZIVPN_SERVICE_FILE" ] && [ ! -f "$ZIVPN_BIN" ]; then
        if [[ "$UNINSTALL_MODE" != "silent" ]]; then
            echo -e "\n${C_YELLOW}ℹ️ ZiVPN does not appear to be installed.${C_RESET}"
        fi
        return
    fi

    local confirm="y"
    if [[ "$UNINSTALL_MODE" != "silent" ]]; then
        read -p "👉 Are you sure you want to uninstall ZiVPN? (y/n): " confirm
    fi
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${C_YELLOW}Cancelled.${C_RESET}"
        return
    fi

    echo -e "\n${C_BLUE}🛑 Stopping services...${C_RESET}"
    systemctl stop zivpn.service 2>/dev/null
    systemctl disable zivpn.service 2>/dev/null

    local iface
    iface=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
    if [ -n "$iface" ]; then
        iptables -t nat -D PREROUTING -i "$iface" -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null || true
    fi
    
    echo -e "${C_BLUE}🗑️ Removing files...${C_RESET}"
    rm -f "$ZIVPN_SERVICE_FILE"
    rm -rf "$ZIVPN_DIR"
    rm -f "$ZIVPN_BIN"
    
    systemctl daemon-reload
    
    # Clean cache (from original uninstall script logic)
    echo -e "${C_BLUE}🧹 Cleaning memory cache...${C_RESET}"
    sync; echo 3 > /proc/sys/vm/drop_caches

    echo -e "\n${C_GREEN}✅ ZiVPN Uninstalled Successfully.${C_RESET}"
}

purge_nginx() {
    local mode="$1"
    if [[ "$mode" != "silent" ]]; then
        clear; show_banner
        echo -e "${C_BOLD}${C_PURPLE}--- 🔥 Purge Internal Nginx Proxy ---${C_RESET}"
        if ! command -v nginx &> /dev/null; then
            rm -f "$NGINX_PORTS_FILE"
            echo -e "\n${C_YELLOW}ℹ️ Nginx is not installed. Nothing to do.${C_RESET}"
            return
        fi
        echo -e "\n${C_YELLOW}⚠️ This removes the internal Nginx proxy on ${NGINX_INTERNAL_HTTP_PORT}/${NGINX_INTERNAL_TLS_PORT}.${C_RESET}"
        if systemctl is-active --quiet haproxy; then
            echo -e "${C_YELLOW}⚠️ HAProxy will stay installed, but web payload routing from ${EDGE_PUBLIC_HTTP_PORT}/${EDGE_PUBLIC_TLS_PORT} will stop until you reinstall the stack.${C_RESET}"
        fi
        read -p "👉 Continue and purge Nginx? (y/n): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo -e "\n${C_YELLOW}❌ Uninstallation cancelled.${C_RESET}"
            return
        fi
    fi
    echo -e "\n${C_BLUE}🛑 Stopping Nginx service...${C_RESET}"
    systemctl stop nginx >/dev/null 2>&1
    systemctl disable nginx >/dev/null 2>&1
    echo -e "\n${C_BLUE}🗑️ Purging Nginx packages...${C_RESET}"
    ff_pkg_purge nginx nginx-common >/dev/null 2>&1
    ff_pkg_autoremove
    echo -e "\n${C_BLUE}🗑️ Removing leftover files...${C_RESET}"
    rm -f /etc/ssl/certs/nginx-selfsigned.pem
    rm -f /etc/ssl/private/nginx-selfsigned.key
    rm -rf /etc/nginx
    rm -f "${NGINX_CONFIG_FILE}.bak"
    rm -f "${NGINX_CONFIG_FILE}.bak.certbot"
    rm -f "${NGINX_CONFIG_FILE}.bak.selfsigned"
    rm -f "${NGINX_CONFIG_FILE}.bak.firewallfalcon"
    rm -f "$NGINX_PORTS_FILE"
    if [[ "$mode" != "silent" ]]; then
        echo -e "\n${C_GREEN}✅ Internal Nginx proxy purged. Shared DAHOOM certificates were kept.${C_RESET}"
    fi
}

install_nginx_proxy() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🚀 Reconfiguring Internal Nginx Proxy (8880/8443) ---${C_RESET}"
    echo -e "\n${C_CYAN}This keeps HAProxy on ${EDGE_PUBLIC_HTTP_PORT}/${EDGE_PUBLIC_TLS_PORT} and rewrites the internal Nginx proxy on ${NGINX_INTERNAL_HTTP_PORT}/${NGINX_INTERNAL_TLS_PORT}.${C_RESET}"

    if [ ! -s "$SSL_CERT_FILE" ] || [ ! -s "$SSL_CERT_CHAIN_FILE" ] || [ ! -s "$SSL_CERT_KEY_FILE" ]; then
        echo -e "\n${C_YELLOW}⚠️ No shared DAHOOM certificate was found.${C_RESET}"
        echo -e "${C_DIM}Running the full HAProxy edge installer so the certificate and both services stay aligned.${C_RESET}"
        install_ssl_tunnel
        return
    fi

    mkdir -p "$DB_DIR" "$SSL_CERT_DIR"
    ensure_edge_stack_packages || return

    systemctl stop haproxy >/dev/null 2>&1
    systemctl stop nginx >/dev/null 2>&1
    sleep 1

    check_and_free_ports \
        "$EDGE_PUBLIC_HTTP_PORT" \
        "$EDGE_PUBLIC_TLS_PORT" \
        "$NGINX_INTERNAL_HTTP_PORT" \
        "$NGINX_INTERNAL_TLS_PORT" \
        "$HAPROXY_INTERNAL_DECRYPT_PORT" || return

    check_and_open_firewall_port "$EDGE_PUBLIC_HTTP_PORT" tcp || return
    check_and_open_firewall_port "$EDGE_PUBLIC_TLS_PORT" tcp || return

    load_edge_cert_info
    local server_name="${EDGE_DOMAIN:-$(detect_preferred_host)}"
    [[ -z "$server_name" ]] && server_name="_"

    configure_edge_stack "$server_name" || return

    echo -e "\n${C_GREEN}✅ Internal Nginx proxy reconfigured successfully.${C_RESET}"
    echo -e "   • Public HAProxy edge: ${C_YELLOW}${EDGE_PUBLIC_HTTP_PORT}/${EDGE_PUBLIC_TLS_PORT}${C_RESET}"
    echo -e "   • Internal Nginx: ${C_YELLOW}${NGINX_INTERNAL_HTTP_PORT}/${NGINX_INTERNAL_TLS_PORT}${C_RESET}"
}

request_certbot_ssl() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🔒 Shared Certbot Certificate (HAProxy + Nginx) ---${C_RESET}"
    echo -e "\n${C_DIM}This will replace the shared certificate used by HAProxy on ${EDGE_PUBLIC_TLS_PORT} and internal Nginx on ${NGINX_INTERNAL_TLS_PORT}.${C_RESET}"

    mkdir -p "$DB_DIR" "$SSL_CERT_DIR"
    ensure_edge_stack_packages || return
    load_edge_cert_info

    local preferred_host
    local default_domain=""
    local domain_name
    local email

    preferred_host=$(detect_preferred_host)
    if [[ -n "$EDGE_DOMAIN" ]] && ! _is_valid_ipv4 "$EDGE_DOMAIN"; then
        default_domain="$EDGE_DOMAIN"
    elif [[ -n "$preferred_host" ]] && ! _is_valid_ipv4 "$preferred_host"; then
        default_domain="$preferred_host"
    fi

    if [[ -n "$default_domain" ]]; then
        read -p "👉 Enter your domain name [$default_domain]: " domain_name
        domain_name=${domain_name:-$default_domain}
    else
        read -p "👉 Enter your domain name (e.g. vpn.example.com): " domain_name
    fi
    if [[ -z "$domain_name" ]]; then
        echo -e "\n${C_RED}❌ Domain name cannot be empty.${C_RESET}"
        return
    fi
    if _is_valid_ipv4 "$domain_name"; then
        echo -e "\n${C_RED}❌ Certbot requires a real domain name, not a raw IP address.${C_RESET}"
        return
    fi

    read -p "👉 Enter your email for Let's Encrypt [${EDGE_EMAIL}]: " email
    email=${email:-$EDGE_EMAIL}
    if [[ -z "$email" ]]; then
        echo -e "\n${C_RED}❌ Email address cannot be empty.${C_RESET}"
        return
    fi

    check_and_open_firewall_port "$EDGE_PUBLIC_HTTP_PORT" tcp || return
    check_and_open_firewall_port "$EDGE_PUBLIC_TLS_PORT" tcp || return

    obtain_certbot_edge_cert "$domain_name" "$email" || return
    configure_edge_stack "$domain_name" || return

    echo -e "\n${C_GREEN}✅ Shared Certbot certificate applied successfully.${C_RESET}"
    echo -e "   • Domain: ${C_YELLOW}${domain_name}${C_RESET}"
    echo -e "   • Public edge: ${C_YELLOW}${EDGE_PUBLIC_HTTP_PORT}/${EDGE_PUBLIC_TLS_PORT}${C_RESET}"
}

nginx_proxy_menu() {
    while true; do
    show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🌐 Internal Nginx Proxy Management ---${C_RESET}"

    local nginx_status="${C_STATUS_I}Inactive${C_RESET}"
    local haproxy_status="${C_STATUS_I}Inactive${C_RESET}"
    if systemctl is-active --quiet nginx; then
        nginx_status="${C_STATUS_A}Active${C_RESET}"
    fi
    if systemctl is-active --quiet haproxy; then
        haproxy_status="${C_STATUS_A}Active${C_RESET}"
    fi

    load_edge_cert_info
    local cert_info="${EDGE_CERT_MODE:-Not configured}"
    if [[ -n "$EDGE_DOMAIN" ]]; then
        cert_info="${cert_info} - ${EDGE_DOMAIN}"
    fi

    echo -e "\n${C_WHITE}Nginx:${C_RESET} ${nginx_status}"
    echo -e "${C_WHITE}HAProxy:${C_RESET} ${haproxy_status}"
    echo -e "${C_DIM}Public Edge: ${EDGE_PUBLIC_HTTP_PORT}/${EDGE_PUBLIC_TLS_PORT} | Internal Nginx: ${NGINX_INTERNAL_HTTP_PORT}/${NGINX_INTERNAL_TLS_PORT}${C_RESET}"
    echo -e "${C_DIM}Shared Certificate: ${cert_info}${C_RESET}"

    echo -e "\n${C_BOLD}Select an action:${C_RESET}\n"
    
    if systemctl is-active --quiet nginx; then
         printf "  ${C_CHOICE}[ 1]${C_RESET} %s\n" "$(pad_right '🛑 Stop Nginx Service' 40)"
         printf "  ${C_CHOICE}[ 2]${C_RESET} %s\n" "$(pad_right '🔄 Restart HAProxy + Nginx Stack' 40)"
         printf "  ${C_CHOICE}[ 3]${C_RESET} %s\n" "$(pad_right '⚙️ Re-install/Re-configure Edge Stack' 40)"
         printf "  ${C_CHOICE}[ 4]${C_RESET} %s\n" "$(pad_right '🔒 Switch/Renew Shared SSL (Certbot)' 40)"
         printf "  ${C_CHOICE}[ 5]${C_RESET} %s\n" "$(pad_right '🔥 Uninstall/Purge Nginx' 40)"
    else
         printf "  ${C_CHOICE}[ 1]${C_RESET} %s\n" "$(pad_right '▶️ Start Nginx Service' 40)"
         printf "  ${C_CHOICE}[ 3]${C_RESET} %s\n" "$(pad_right '⚙️ Install/Configure Edge Stack' 40)"
         printf "  ${C_CHOICE}[ 4]${C_RESET} %s\n" "$(pad_right '🔒 Switch/Renew Shared SSL (Certbot)' 40)"
         printf "  ${C_CHOICE}[ 5]${C_RESET} %s\n" "$(pad_right '🔥 Uninstall/Purge Nginx' 40)"
    fi

    echo -e "\n  ${C_WARN}[ 0]${C_RESET} ↩️ Return"
    echo
    if ! read -r -p "$(echo -e ${C_PROMPT}"👉 Select an option: "${C_RESET})" choice; then
        echo
        return
    fi
    
    case $choice in
        1) 
            if systemctl is-active --quiet nginx; then
                echo -e "\n${C_BLUE}🛑 Stopping Nginx...${C_RESET}"
                systemctl stop nginx
                echo -e "${C_GREEN}✅ Nginx stopped.${C_RESET}"
                if systemctl is-active --quiet haproxy; then
                    echo -e "${C_YELLOW}⚠️ HAProxy is still running, but web traffic that depends on internal Nginx will not work until Nginx starts again.${C_RESET}"
                fi
            else
                echo -e "\n${C_BLUE}▶️ Starting Nginx...${C_RESET}"
                systemctl start nginx
                if systemctl is-active --quiet nginx; then
                    echo -e "${C_GREEN}✅ Nginx started.${C_RESET}"
                else
                    echo -e "${C_RED}❌ Failed to start Nginx.${C_RESET}"
                fi
            fi
            press_enter
            ;;
        2)
            echo -e "\n${C_BLUE}🔄 Restarting Nginx and HAProxy...${C_RESET}"
            local restart_ok=true
            systemctl restart nginx || restart_ok=false
            if command -v haproxy &> /dev/null; then
                systemctl restart haproxy || restart_ok=false
            else
                restart_ok=false
            fi
            if $restart_ok && systemctl is-active --quiet nginx && systemctl is-active --quiet haproxy; then
                echo -e "${C_GREEN}✅ HAProxy + Nginx stack restarted.${C_RESET}"
            else
                echo -e "${C_RED}❌ One or more services failed to restart.${C_RESET}"
            fi
            press_enter
            ;;
        3) 
             install_nginx_proxy; press_enter
             ;;
        4)
             request_certbot_ssl; press_enter
             ;;
        5)
             purge_nginx; press_enter
             ;;
        0) return ;;
        *) invalid_option ;;
    esac
    done
}

get_xui_installed_variant() {
    if [[ ! -f "/etc/systemd/system/x-ui.service" && ! -f "/lib/systemd/system/x-ui.service" && ! -f "/usr/local/x-ui/x-ui" && ! -d "/usr/local/x-ui" ]]; then
        echo "none"
    else
        echo "x-ui"
    fi
}

get_panel_status() {
    local target_panel="$1" # "x-ui"
    if [[ ! -f "/etc/systemd/system/x-ui.service" && ! -f "/lib/systemd/system/x-ui.service" && ! -f "/usr/local/x-ui/x-ui" && ! -d "/usr/local/x-ui" ]]; then
        echo "${C_STATUS_I}(Not Installed)${C_RESET}"
        return
    fi

    if pgrep -x x-ui &>/dev/null; then
        echo "${C_STATUS_A}(Active)${C_RESET}"
    else
        echo "${C_YELLOW}(Stopped)${C_RESET}"
    fi
}

install_panel_menu() {
    install_xui_panel
}

install_xui_panel() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 📦 Install X-UI Panel (alireza0) ---${C_RESET}"
    echo
    echo -e "  ${C_CYAN}Choose installation mode:${C_RESET}\n"
    printf "  ${C_CHOICE}[ 1]${C_RESET} %s %s\n" "$(pad_right '⚡ Automated Quick Install (Free deSEC SSL Domain + Port 54321)' 60)" "${C_STATUS_A}⭐ Recommended${C_RESET}"
    printf "  ${C_CHOICE}[ 2]${C_RESET} %s %s\n" "$(pad_right '🛠️  Standard Interactive Installation (Official Wizard)' 60)" ""
    echo
    printf "  ${C_DANGER}[ 0]${C_RESET} Cancel\n"
    echo
    read -r -p "$(echo -e ${C_PROMPT}"> Select mode [1]: "${C_RESET})" inst_mode
    inst_mode=${inst_mode:-1}

    case "$inst_mode" in
        1)
            echo -e "\n${C_BLUE}🌐 Step 1/4: Provisioning Free deSEC SSL Domain (*.aljailane.dedyn.io)...${C_RESET}"
            local panel_domain=""
            if [[ -f "$DNS_INFO_FILE" ]]; then
                source "$DNS_INFO_FILE" 2>/dev/null
                panel_domain="$FULL_DOMAIN"
            fi
            if [[ -z "$panel_domain" ]]; then
                generate_dns_record </dev/null 2>&1 || true
                if [[ -f "$DNS_INFO_FILE" ]]; then
                    source "$DNS_INFO_FILE" 2>/dev/null
                    panel_domain="$FULL_DOMAIN"
                fi
            fi
            if [[ -n "$panel_domain" ]]; then
                echo -e "  ${C_GREEN}✔ Dedicated Domain:${C_RESET} ${C_YELLOW}${panel_domain}${C_RESET}"
            fi

            echo -e "\n${C_BLUE}📦 Step 2/4: Installing X-UI Core Files...${C_RESET}"
            mkdir -p "/etc/firewallfalcon" 2>/dev/null
            echo "x-ui" > "/etc/firewallfalcon/.panel_type" 2>/dev/null || true
            printf "y\n54321\n" | bash <(curl -Ls https://raw.githubusercontent.com/mooa322/X-UI/main/install.sh) || true

            echo -e "\n${C_BLUE}🔒 Step 3/4: Configuring SSL Certificate & Panel Security...${C_RESET}"
            local cert_file="" key_file=""
            if [[ -n "$panel_domain" ]]; then
                if ! command -v certbot &>/dev/null; then
                    ff_pkg_install certbot >/dev/null 2>&1 || true
                fi
                if command -v certbot &>/dev/null; then
                    systemctl stop nginx &>/dev/null || true
                    systemctl stop haproxy &>/dev/null || true
                    command -v fuser &>/dev/null && fuser -k 80/tcp &>/dev/null || true
                    certbot certonly --standalone -d "$panel_domain" --agree-tos --register-unsafely-without-email --non-interactive >/dev/null 2>&1 || true
                    systemctl start nginx &>/dev/null || true
                    systemctl start haproxy &>/dev/null || true
                    if [[ -f "/etc/letsencrypt/live/$panel_domain/fullchain.pem" && -f "/etc/letsencrypt/live/$panel_domain/privkey.pem" ]]; then
                        cert_file="/etc/letsencrypt/live/$panel_domain/fullchain.pem"
                        key_file="/etc/letsencrypt/live/$panel_domain/privkey.pem"
                    fi
                fi
            fi

            if command -v python3 &>/dev/null && [[ -f "/etc/x-ui/x-ui.db" ]]; then
                python3 -c "
import sqlite3, os
db = '/etc/x-ui/x-ui.db'
if os.path.exists(db):
    try:
        conn = sqlite3.connect(db)
        c = conn.cursor()
        c.execute(\"DELETE FROM settings WHERE key IN ('webPort', 'port', 'webCertFile', 'webKeyFile')\")
        c.execute(\"INSERT INTO settings (key, value) VALUES (?, ?)\", ('webPort', '54321'))
        if '$cert_file' and '$key_file' and os.path.isfile('$cert_file') and os.path.isfile('$key_file'):
            c.execute(\"INSERT INTO settings (key, value) VALUES (?, ?)\", ('webCertFile', '$cert_file'))
            c.execute(\"INSERT INTO settings (key, value) VALUES (?, ?)\", ('webKeyFile', '$key_file'))
        else:
            c.execute(\"INSERT INTO settings (key, value) VALUES (?, ?)\", ('webCertFile', ''))
            c.execute(\"INSERT INTO settings (key, value) VALUES (?, ?)\", ('webKeyFile', ''))
        conn.commit()
        conn.close()
    except Exception:
        pass
" 2>/dev/null || true
            fi

            echo -e "\n${C_BLUE}🔥 Step 4/4: Opening Firewall & Starting Service...${C_RESET}"
            command -v ufw &>/dev/null && ufw allow 54321/tcp &>/dev/null && ufw allow 80/tcp &>/dev/null || true
            command -v iptables &>/dev/null && iptables -I INPUT -p tcp --dport 54321 -j ACCEPT 2>/dev/null || true
            if command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
                firewall-cmd --add-port=54321/tcp --permanent &>/dev/null || true
                firewall-cmd --reload &>/dev/null || true
            fi

            pkill -9 -f "x-ui" 2>/dev/null || true
            sleep 0.5
            systemctl daemon-reload 2>/dev/null || true
            systemctl enable x-ui 2>/dev/null || true
            systemctl restart x-ui 2>/dev/null || true
            sleep 1.5

            echo -e "\n${C_GREEN}✅ X-UI Installation Finished!${C_RESET}\n"
            show_xui_access_info "X-UI Panel"
            ;;
        2)
            echo -e "\n  Downloading and running official X-UI interactive installer..."
            mkdir -p "/etc/firewallfalcon" 2>/dev/null
            echo "x-ui" > "/etc/firewallfalcon/.panel_type" 2>/dev/null || true
            bash <(curl -Ls https://raw.githubusercontent.com/mooa322/X-UI/main/install.sh)
            repair_xui_access "X-UI Panel"
            ;;
        0)
            echo -e "\n${C_YELLOW}❌ Installation cancelled.${C_RESET}"
            return
            ;;
        *)
            invalid_option
            ;;
    esac
}

uninstall_xui_panel() {
    if [[ "$UNINSTALL_MODE" != "silent" ]]; then
        clear; show_banner
        echo -e "${C_BOLD}${C_PURPLE}--- 🗑️ Uninstall X-UI Panel ---${C_RESET}"
    fi
    if ! command -v x-ui &>/dev/null && [ ! -d /usr/local/x-ui ] && [ ! -f /etc/systemd/system/x-ui.service ] && [ ! -f /lib/systemd/system/x-ui.service ]; then
        if [[ "$UNINSTALL_MODE" != "silent" ]]; then
            echo -e "\n${C_YELLOW}ℹ️ No X-UI panel appears to be installed.${C_RESET}"
        fi
        return
    fi
    local confirm="y"
    if [[ "$UNINSTALL_MODE" != "silent" ]]; then
        read -p "👉 Are you sure you want to thoroughly uninstall X-UI? (y/n): " confirm
    fi
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        if [[ "$UNINSTALL_MODE" != "silent" ]]; then
            echo -e "\n${C_BLUE}⚙️ Running uninstaller and removing services...${C_RESET}"
        fi
        x-ui uninstall >/dev/null 2>&1 || true
        systemctl stop x-ui >/dev/null 2>&1 || true
        systemctl disable x-ui >/dev/null 2>&1 || true
        pkill -9 -f "x-ui" >/dev/null 2>&1 || true
        rm -f /etc/systemd/system/x-ui.service /lib/systemd/system/x-ui.service
        rm -f /usr/local/bin/x-ui /usr/bin/x-ui
        rm -rf /usr/local/x-ui/
        rm -rf /etc/x-ui/
        rm -f "/etc/firewallfalcon/.panel_type"
        systemctl daemon-reload 2>/dev/null || true
        if [[ "$UNINSTALL_MODE" != "silent" ]]; then
            echo -e "\n${C_GREEN}✅ X-UI has been thoroughly uninstalled.${C_RESET}"
        fi
    else
        echo -e "\n${C_YELLOW}❌ Uninstallation cancelled.${C_RESET}"
    fi
}

show_xui_access_info() {
    local panel_name="${1:-X-UI Panel}"
    local db_path="/etc/x-ui/x-ui.db"
    local env_path="/etc/x-ui/install-result.env"
    local server_ip="${GLOBAL_SERVER_IPV4:-}"
    if [[ -z "$server_ip" ]]; then
        if [[ -f "$DNS_INFO_FILE" ]]; then
            server_ip=$(grep -E '^SERVER_IPV4=' "$DNS_INFO_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d '"')
        fi
        if [[ -z "$server_ip" ]]; then
            server_ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')
        fi
        [[ -z "$server_ip" ]] && server_ip="127.0.0.1"
        GLOBAL_SERVER_IPV4="$server_ip"
    fi
    
    local domain_name=""
    if [[ -f "$DNS_INFO_FILE" ]]; then
        source "$DNS_INFO_FILE" 2>/dev/null
        domain_name="$FULL_DOMAIN"
    fi

    echo -e "  ${C_PURPLE}──────────────── ${panel_name^^} ACCESS INFO ────────────────${C_RESET}"
    
    local port="" base_path="" user="" pass="" has_cert="false"

    # 1. Parse install-result.env if present
    if [[ -f "$env_path" ]]; then
        user=$(grep -E '^Username:' "$env_path" 2>/dev/null | awk '{print $2}')
        [[ -z "$user" ]] && user=$(grep -E '^USERNAME=' "$env_path" 2>/dev/null | cut -d'=' -f2 | tr -d '"')
        
        pass=$(grep -E '^Password:' "$env_path" 2>/dev/null | awk '{print $2}')
        [[ -z "$pass" ]] && pass=$(grep -E '^PASSWORD=' "$env_path" 2>/dev/null | cut -d'=' -f2 | tr -d '"')
        
        port=$(grep -E '^Port:' "$env_path" 2>/dev/null | awk '{print $2}')
        [[ -z "$port" ]] && port=$(grep -E '^PORT=' "$env_path" 2>/dev/null | cut -d'=' -f2 | tr -d '"')
        
        base_path=$(grep -E '^WebBasePath:' "$env_path" 2>/dev/null | awk '{print $2}')
        [[ -z "$base_path" ]] && base_path=$(grep -E '^WEBBASEPATH=' "$env_path" 2>/dev/null | cut -d'=' -f2 | tr -d '"')
    fi

    # 2. Query SQLite database (always read real live settings from /etc/x-ui/x-ui.db)
    if [[ -f "$db_path" ]] && command -v python3 &>/dev/null; then
        local _xui_parsed
        _xui_parsed=$(python3 <<'EOF'
import sqlite3, os

db_file = "/etc/x-ui/x-ui.db"
res = {"port": "54321", "base_path": "", "user": "admin", "pass": "admin", "has_cert": False}

if os.path.exists(db_file):
    try:
        conn = sqlite3.connect(db_file)
        c = conn.cursor()
        c.execute("SELECT key, value FROM settings")
        cert_file = ""
        key_file = ""
        for k, v in c.fetchall():
            val = str(v).strip()
            if k in ("webPort", "port") and val and val != "0":
                res["port"] = val
            elif k in ("webBasePath", "basePath") and val:
                res["base_path"] = val
            elif k in ("webCertFile", "webCert") and val:
                cert_file = val
            elif k in ("webKeyFile", "webCertKey") and val:
                key_file = val

        if cert_file and key_file and os.path.isfile(cert_file) and os.path.isfile(key_file) and os.path.getsize(cert_file) > 0:
            res["has_cert"] = True
        else:
            live_dir = "/etc/letsencrypt/live"
            if os.path.isdir(live_dir):
                for d in sorted(os.listdir(live_dir)):
                    fc = os.path.join(live_dir, d, "fullchain.pem")
                    pk = os.path.join(live_dir, d, "privkey.pem")
                    if os.path.isfile(fc) and os.path.isfile(pk) and os.path.getsize(fc) > 0:
                        res["has_cert"] = True
                        break

        try:
            c.execute("SELECT username, password FROM users LIMIT 1")
            row = c.fetchone()
            if row:
                res["user"] = str(row[0])
                res["pass"] = str(row[1])
        except:
            pass

        conn.close()
    except Exception:
        pass

print(f"port='{res['port']}'; base_path='{res['base_path']}'; user='{res['user']}'; pass='{res['pass']}'; has_cert='{str(res['has_cert']).lower()}'")
EOF
)
        if [[ -n "$_xui_parsed" ]]; then
            eval "$_xui_parsed"
        fi
    fi

    # 3. Fallbacks and Port Sanitization
    if [[ -z "$port" || "$port" == "0" || ! "$port" =~ ^[0-9]+$ ]]; then
        port="54321"
    fi

    [[ -z "$user" ]] && user="admin"
    if [[ -z "$pass" || "$pass" == \$2* ]]; then
        pass="admin (or password set during installation)"
    fi

    # 4. Format URL
    base_path=$(echo "$base_path" | sed 's|^/||;s|/$||')
    local proto="http"
    [[ "$has_cert" == "true" ]] && proto="https"

    local domain_url="" ip_url="" domain_http_url="" ip_http_url=""
    if [[ -n "$base_path" ]]; then
        [[ -n "$domain_name" ]] && domain_url="${proto}://${domain_name}:${port}/${base_path}/"
        [[ -n "$domain_name" ]] && domain_http_url="http://${domain_name}:${port}/${base_path}/"
        ip_url="${proto}://${server_ip}:${port}/${base_path}/"
        ip_http_url="http://${server_ip}:${port}/${base_path}/"
    else
        [[ -n "$domain_name" ]] && domain_url="${proto}://${domain_name}:${port}/"
        [[ -n "$domain_name" ]] && domain_http_url="http://${domain_name}:${port}/"
        ip_url="${proto}://${server_ip}:${port}/"
        ip_http_url="http://${server_ip}:${port}/"
    fi

    local live_status="${C_GREEN}🟢 Active (Running)${C_RESET}"
    if ! pgrep -x x-ui &>/dev/null; then
        live_status="${C_RED}🔴 Stopped (Try Fix & Repair Access)${C_RESET}"
    fi

    echo -e "  ${C_CYAN}Service Status :${C_RESET} ${live_status}"
    echo -e "  ${C_CYAN}Server IP      :${C_RESET} ${C_YELLOW}${server_ip}${C_RESET}"
    if [[ -n "$domain_name" ]]; then
        echo -e "  ${C_CYAN}Free SSL Domain:${C_RESET} ${C_GREEN}${domain_name}${C_RESET}"
    fi
    echo -e "  ${C_CYAN}Dedicated Port :${C_RESET} ${C_YELLOW}${port}${C_RESET}"
    echo -e "  ${C_CYAN}Username       :${C_RESET} ${C_GREEN}${user}${C_RESET}"
    echo -e "  ${C_CYAN}Password       :${C_RESET} ${C_GREEN}${pass}${C_RESET}"
    if [[ -n "$base_path" ]]; then
        echo -e "  ${C_CYAN}Web Base Path  :${C_RESET} ${C_YELLOW}/${base_path}/${C_RESET}"
    fi
    echo -e "  ${C_CYAN}Protocol       :${C_RESET} ${C_YELLOW}${proto^^}${C_RESET}"
    if [[ -n "$domain_url" ]]; then
        echo -e "  ${C_CYAN}Direct Domain  :${C_RESET} ${C_GREEN}${domain_url}${C_RESET}"
    fi
    echo -e "  ${C_CYAN}Direct IP URL  :${C_RESET} ${C_GREEN}${ip_url}${C_RESET}"
    if [[ "$proto" == "https" ]]; then
        if [[ -n "$domain_http_url" ]]; then
            echo -e "  ${C_CYAN}HTTP Domain URL:${C_RESET} ${C_YELLOW}${domain_http_url}${C_RESET}"
        fi
        echo -e "  ${C_CYAN}HTTP IP URL    :${C_RESET} ${C_YELLOW}${ip_http_url}${C_RESET}"
    fi
    echo -e "  ${C_CYAN}Docs / Repo    :${C_RESET} https://github.com/mooa322/X-UI"
    echo -e "  ${C_PURPLE}────────────────────────────────────────────────────────${C_RESET}"
    echo
}

repair_xui_access() {
    local panel_name="${1:-X-UI Panel}"
    local db_path="/etc/x-ui/x-ui.db"
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🔧 Auto-Repair ${panel_name} Access & Ports ---${C_RESET}\n"

    echo -e "  ${C_CYAN}Step 1/5:${C_RESET} Inspecting x-ui installation..."
    if [[ ! -f "$db_path" && ! -d "/usr/local/x-ui" ]]; then
        echo -e "  ${C_RED}❌ x-ui installation files not found at /usr/local/x-ui.${C_RESET}"
        return
    fi

    echo -e "  ${C_CYAN}Step 2/5:${C_RESET} Reading, sanitizing and repairing panel settings..."
    local default_port="54321"
    local port="$default_port"
    if [[ -f "$db_path" ]] && command -v python3 &>/dev/null; then
        port=$(python3 -c "
import sqlite3, os
p = '$default_port'
try:
    if os.path.exists('/etc/x-ui/x-ui.db'):
        conn = sqlite3.connect('/etc/x-ui/x-ui.db')
        c = conn.cursor()
        c.execute(\"SELECT value FROM settings WHERE key IN ('webPort', 'port') LIMIT 1\")
        row = c.fetchone()
        if row and str(row[0]).strip() and str(row[0]).strip() != '0':
            p = str(row[0]).strip()
        c.execute(\"DELETE FROM settings WHERE key IN ('webPort', 'port')\")
        c.execute(\"INSERT INTO settings (key, value) VALUES (?, ?)\", ('webPort', p))
        
        # Verify if SSL cert paths in DB exist. If broken, search for valid cert in /etc/letsencrypt/live/
        c.execute(\"SELECT key, value FROM settings WHERE key IN ('webCertFile', 'webKeyFile')\")
        cert_rows = dict(c.fetchall())
        c_file = cert_rows.get('webCertFile', '')
        k_file = cert_rows.get('webKeyFile', '')

        if not (c_file and k_file and os.path.isfile(c_file) and os.path.isfile(k_file)):
            found_cert, found_key = '', ''
            live_dir = '/etc/letsencrypt/live'
            if os.path.isdir(live_dir):
                for d in sorted(os.listdir(live_dir)):
                    cand_cert = os.path.join(live_dir, d, 'fullchain.pem')
                    cand_key = os.path.join(live_dir, d, 'privkey.pem')
                    if os.path.isfile(cand_cert) and os.path.isfile(cand_key):
                        found_cert, found_key = cand_cert, cand_key
                        break
            c.execute(\"DELETE FROM settings WHERE key IN ('webCertFile', 'webKeyFile')\")
            c.execute(\"INSERT INTO settings (key, value) VALUES (?, ?)\", ('webCertFile', found_cert))
            c.execute(\"INSERT INTO settings (key, value) VALUES (?, ?)\", ('webKeyFile', found_key))
        
        conn.commit()
        conn.close()
except:
    pass
print(p)
" 2>/dev/null || echo "$default_port")
    fi
    echo -e "  ${C_GREEN}✔ Dedicated Port verified:${C_RESET} ${C_YELLOW}${port}${C_RESET}"

    echo -e "  ${C_CYAN}Step 3/5:${C_RESET} Unblocking firewall ports (UFW, Iptables, Firewalld)..."
    command -v ufw &>/dev/null && ufw allow "${port}/tcp" &>/dev/null || true
    command -v iptables &>/dev/null && iptables -I INPUT -p tcp --dport "${port}" -j ACCEPT 2>/dev/null || true
    if command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
        firewall-cmd --add-port="${port}/tcp" --permanent &>/dev/null || true
        firewall-cmd --reload &>/dev/null || true
    fi
    echo -e "  ${C_GREEN}✔ Port ${port} opened across all firewall layers.${C_RESET}"

    echo -e "  ${C_CYAN}Step 4/5:${C_RESET} Killing hanging processes & restarting x-ui daemon..."
    pkill -9 -f "x-ui" 2>/dev/null || true
    sleep 0.5
    systemctl daemon-reload 2>/dev/null || true
    systemctl enable x-ui 2>/dev/null || true
    systemctl restart x-ui 2>/dev/null || true
    sleep 1.5

    echo -e "  ${C_CYAN}Step 5/5:${C_RESET} Checking listening status..."
    local is_listening=false
    if command -v ss &>/dev/null; then
        ss -tulpn 2>/dev/null | grep -q ":${port} " && is_listening=true
    elif command -v netstat &>/dev/null; then
        netstat -tulpn 2>/dev/null | grep -q ":${port} " && is_listening=true
    fi

    if $is_listening || systemctl is-active --quiet x-ui 2>/dev/null; then
        echo -e "  ${C_GREEN}✅ Success! ${panel_name} service is running and listening on port ${port}.${C_RESET}"
    else
        echo -e "  ${C_YELLOW}⚠️ Service started. If connection fails, try option [3] to reset port/credentials.${C_RESET}"
    fi

    show_xui_access_info "$panel_name"
}

reset_xui_credentials() {
    local panel_name="${1:-X-UI Panel}"
    local db_path="/etc/x-ui/x-ui.db"
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🔑 Reset ${panel_name} Port & Credentials ---${C_RESET}\n"

    read -r -p "$(echo -e ${C_PROMPT}"> Enter new Port [54321]: "${C_RESET})" new_port
    new_port=${new_port:-54321}
    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || (( new_port < 1 || new_port > 65535 )); then
        echo -e "\n${C_RED}❌ Invalid port number. Must be between 1 and 65535.${C_RESET}"
        return
    fi

    read -r -p "$(echo -e ${C_PROMPT}"> Enter new Username [admin]: "${C_RESET})" new_user
    new_user=${new_user:-admin}

    read -r -p "$(echo -e ${C_PROMPT}"> Enter new Password [admin]: "${C_RESET})" new_pass
    new_pass=${new_pass:-admin}

    read -r -p "$(echo -e ${C_PROMPT}"> Reset Base Path to root (/) ? (y/n) [y]: "${C_RESET})" reset_path
    reset_path=${reset_path:-y}

    echo -e "\n${C_BLUE}⚙️ Updating database settings...${C_RESET}"
    if command -v python3 &>/dev/null; then
        python3 -c "
import sqlite3, os
db = '$db_path'
if os.path.exists(db):
    try:
        conn = sqlite3.connect(db)
        c = conn.cursor()
        c.execute(\"DELETE FROM settings WHERE key IN ('webPort', 'port')\")
        c.execute(\"INSERT INTO settings (key, value) VALUES (?, ?)\", ('webPort', '$new_port'))
        if '${reset_path,,}' == 'y':
            c.execute(\"DELETE FROM settings WHERE key IN ('webBasePath', 'basePath', 'webCertFile', 'webKeyFile')\")
            c.execute(\"INSERT INTO settings (key, value) VALUES (?, ?)\", ('webBasePath', ''))
            c.execute(\"INSERT INTO settings (key, value) VALUES (?, ?)\", ('webCertFile', ''))
            c.execute(\"INSERT INTO settings (key, value) VALUES (?, ?)\", ('webKeyFile', ''))
        c.execute(\"UPDATE users SET username=?, password=? WHERE id=1 OR rowid=1\", ('$new_user', '$new_pass'))
        if c.rowcount == 0:
            c.execute(\"INSERT OR REPLACE INTO users (id, username, password) VALUES (1, ?, ?)\", ('$new_user', '$new_pass'))
        conn.commit()
        conn.close()
        print('DB_OK')
    except Exception as e:
        print('ERR:' + str(e))
" 2>/dev/null
    fi

    # Unblock new port in firewall
    command -v ufw &>/dev/null && ufw allow "${new_port}/tcp" &>/dev/null || true
    command -v iptables &>/dev/null && iptables -I INPUT -p tcp --dport "${new_port}" -j ACCEPT 2>/dev/null || true
    if command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
        firewall-cmd --add-port="${new_port}/tcp" --permanent &>/dev/null || true
        firewall-cmd --reload &>/dev/null || true
    fi

    # Restart x-ui
    systemctl restart x-ui 2>/dev/null || true
    sleep 1

    echo -e "${C_GREEN}✅ Credentials, Port & Firewall updated successfully!${C_RESET}\n"
    show_xui_access_info "$panel_name"
}

sync_xui_domain_ssl() {
    local panel_name="${1:-X-UI Panel}"
    local new_domain="$2"
    local db_path="/etc/x-ui/x-ui.db"

    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🔄 Rebuild & Sync SSL Certificate (${new_domain}) ---${C_RESET}\n"

    if [[ -z "$new_domain" ]]; then
        echo -e "${C_RED}❌ No active system domain provided.${C_RESET}"
        return 1
    fi

    echo -e "  ${C_BLUE}🌐 Step 1/3: Requesting Let's Encrypt SSL certificate for ${C_YELLOW}${new_domain}${C_BLUE}...${C_RESET}"
    if ! command -v certbot &>/dev/null; then
        ff_pkg_install certbot >/dev/null 2>&1 || true
    fi

    local cert_file="" key_file=""
    if command -v certbot &>/dev/null; then
        systemctl stop nginx &>/dev/null || true
        systemctl stop haproxy &>/dev/null || true
        command -v fuser &>/dev/null && fuser -k 80/tcp &>/dev/null || true
        certbot certonly --standalone -d "$new_domain" --agree-tos --register-unsafely-without-email --non-interactive >/dev/null 2>&1 || true
        systemctl start nginx &>/dev/null || true
        systemctl start haproxy &>/dev/null || true
        if [[ -f "/etc/letsencrypt/live/$new_domain/fullchain.pem" && -f "/etc/letsencrypt/live/$new_domain/privkey.pem" ]]; then
            cert_file="/etc/letsencrypt/live/$new_domain/fullchain.pem"
            key_file="/etc/letsencrypt/live/$new_domain/privkey.pem"
        fi
    fi

    if [[ -z "$cert_file" || -z "$key_file" ]]; then
        echo -e "  ${C_RED}❌ Failed to obtain SSL certificate for ${new_domain}.${C_RESET}"
        echo -e "  ${C_YELLOW}ℹ️ Ensure port 80 is reachable and DNS has propagated.${C_RESET}"
        return 1
    fi

    echo -e "  ${C_GREEN}✔ SSL Certificate obtained successfully!${C_RESET}"

    echo -e "\n  ${C_BLUE}🔒 Step 2/3: Mirroring certificates & updating ${panel_name} database...${C_RESET}"
    mkdir -p "/root/cert/${new_domain}" 2>/dev/null
    cp -f "$cert_file" "/root/cert/${new_domain}/fullchain.pem" 2>/dev/null || true
    cp -f "$key_file" "/root/cert/${new_domain}/privkey.pem" 2>/dev/null || true
    cp -f "$cert_file" "/root/cert.crt" 2>/dev/null || true
    cp -f "$key_file" "/root/private.key" 2>/dev/null || true

    if command -v python3 &>/dev/null && [[ -f "$db_path" ]]; then
        python3 -c "
import sqlite3, os
db = '$db_path'
if os.path.exists(db):
    try:
        conn = sqlite3.connect(db)
        c = conn.cursor()
        c.execute(\"DELETE FROM settings WHERE key IN ('webCertFile', 'webKeyFile', 'webCert', 'webCertKey')\")
        c.execute(\"INSERT INTO settings (key, value) VALUES (?, ?)\", ('webCertFile', '$cert_file'))
        c.execute(\"INSERT INTO settings (key, value) VALUES (?, ?)\", ('webKeyFile', '$key_file'))
        conn.commit()
        conn.close()
    except Exception as e:
        print('DB_ERR:', e)
" 2>/dev/null || true
    fi

    echo -e "\n  ${C_BLUE}⚙️ Step 3/3: Restarting ${panel_name} service...${C_RESET}"
    systemctl daemon-reload 2>/dev/null || true
    systemctl restart x-ui 2>/dev/null || true
    sleep 1

    echo -e "\n  ${C_GREEN}✅ Domain & SSL Certificate synced and applied successfully!${C_RESET}\n"
    show_xui_access_info "$panel_name"
}

show_xui_client_configs() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}────────────────── 📡 X-UI CLIENT CONFIGURATIONS ──────────────────${C_RESET}\n"

    local db_path="/etc/x-ui/x-ui.db"
    if [[ ! -f "$db_path" ]]; then
        echo -e "  ${C_RED}❌ X-UI database not found at ${db_path}.${C_RESET}"
        return
    fi

    local server_ip="${GLOBAL_SERVER_IPV4:-}"
    if [[ -z "$server_ip" ]]; then
        if [[ -f "$DNS_INFO_FILE" ]]; then
            server_ip=$(grep -E '^SERVER_IPV4=' "$DNS_INFO_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d '"')
        fi
        if [[ -z "$server_ip" ]]; then
            server_ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')
        fi
        [[ -z "$server_ip" ]] && server_ip="127.0.0.1"
    fi
    local domain_name=""
    if [[ -f "$DNS_INFO_FILE" ]]; then
        source "$DNS_INFO_FILE" 2>/dev/null
        domain_name="$FULL_DOMAIN"
    fi

    python3 -c "
import sqlite3, json, base64, urllib.parse

db = '$db_path'
server_ip = '$server_ip'
domain = '$domain_name'
host = domain if domain else server_ip

try:
    conn = sqlite3.connect(db)
    cur = conn.cursor()
    cur.execute('SELECT id, remark, port, protocol, settings, stream_settings, enable FROM inbounds')
    rows = cur.fetchall()
    conn.close()

    if not rows:
        print('  \033[0;33m⚠️ No inbounds (configurations) found in X-UI database.\033[0m')
        print('  \033[0;36m👉 Create inbounds inside the X-UI Web Panel to generate config links here.\033[0m\n')
    else:
        print(f'  \033[0;32m✔ Found {len(rows)} inbound service(s) configured:\033[0m\n')
        for r in rows:
            inbound_id, remark, port, proto, settings_str, stream_str, enable = r
            status_tag = '\033[0;32m[Enabled]\033[0m' if enable else '\033[0;31m[Disabled]\033[0m'
            remark = remark if remark else f'Inbound-{inbound_id}'
            print(f'  \033[1;37m┌── #{inbound_id} {remark} ({proto.upper()}:{port}) {status_tag} ──┐\033[0m')
            
            try:
                settings = json.loads(settings_str) if settings_str else {}
            except:
                settings = {}
            try:
                stream = json.loads(stream_str) if stream_str else {}
            except:
                stream = {}

            net = stream.get('network', 'tcp')
            sec = stream.get('security', 'none')
            clients = settings.get('clients', [])

            print(f'  \033[0;36m│\033[0m Protocol : \033[0;33m{proto.upper()}\033[0m | Network: \033[0;33m{net}\033[0m | Security: \033[0;33m{sec}\033[0m')
            print(f'  \033[0;36m│\033[0m Address  : \033[0;32m{host}\033[0m | Port: \033[0;33m{port}\033[0m')

            if clients:
                for idx, c in enumerate(clients, 1):
                    uuid = c.get('id', c.get('password', ''))
                    email = c.get('email', f'client{idx}')
                    tag = f'{remark}-{email}'
                    encoded_tag = urllib.parse.quote(tag)

                    link = ''
                    if proto == 'vless':
                        flow = c.get('flow', '')
                        flow_param = f'&flow={flow}' if flow else ''
                        link = f'vless://{uuid}@{host}:{port}?type={net}&security={sec}{flow_param}#{encoded_tag}'
                    elif proto == 'vmess':
                        vmess_dict = {
                            'v': '2',
                            'ps': tag,
                            'add': host,
                            'port': port,
                            'id': uuid,
                            'aid': c.get('alterId', 0),
                            'net': net,
                            'type': 'none',
                            'host': '',
                            'path': '',
                            'tls': 'tls' if sec == 'tls' else ''
                        }
                        raw_b64 = base64.b64encode(json.dumps(vmess_dict).encode()).decode()
                        link = f'vmess://{raw_b64}'
                    elif proto == 'trojan':
                        link = f'trojan://{uuid}@{host}:{port}?security={sec}&type={net}#{encoded_tag}'
                    elif proto == 'shadowsocks':
                        method = settings.get('method', 'aes-256-gcm')
                        userpass = f'{method}:{uuid}'
                        b64_up = base64.b64encode(userpass.encode()).decode()
                        link = f'ss://{b64_up}@{host}:{port}#{encoded_tag}'

                    if link:
                        print(f'  \033[0;36m│\033[0m Client #{idx} ({email}):')
                        print(f'  \033[0;32m  {link}\033[0m')
            else:
                print('  \033[0;36m│\033[0m No individual client UUIDs defined.')

            print('  \033[1;37m└──────────────────────────────────────────────────────────┘\033[0m\n')

except Exception as e:
    print('  \033[0;31m❌ Error reading X-UI configurations:\033[0m', e)
" 2>/dev/null
}

show_xui_speed_wiki() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}──────────────── 🚀 X-UI SPEED & TUNING WIKI ────────────────${C_RESET}\n"

    echo -e "  ${C_CYAN}1. BBR Congestion Control (Google BBR v1/v3):${C_RESET}"
    echo -e "     • Maximizes throughput on lossy, high-latency wireless and mobile networks."
    local cur_cc; cur_cc=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}')
    echo -e "     • Current TCP Alg : ${C_GREEN}${cur_cc:-cubic}${C_RESET}"
    if [[ "$cur_cc" != "bbr" ]]; then
        echo -e "     • ${C_YELLOW}Recommendation: Enable BBR from System Optimization menu [Option 15].${C_RESET}"
    fi

    echo -e "\n  ${C_CYAN}2. Protocol & Transport Performance Guide:${C_RESET}"
    echo -e "     • ${C_BOLD}VLESS + XTLS / REALITY (TCP)${C_RESET}: Fastest performance, lowest CPU overhead, zero TLS-in-TLS."
    echo -e "     • ${C_BOLD}VLESS + gRPC + TLS${C_RESET}: Multiplexed single-connection transport, great against aggressive SNI filters."
    echo -e "     • ${C_BOLD}VLESS + WebSocket + CDN (Cloudflare)${C_RESET}: Best for hiding origin server IP, slightly higher latency."
    echo -e "     • ${C_BOLD}Trojan + TCP + TLS${C_RESET}: Highly stable, standard HTTPS camouflage."

    echo -e "\n  ${C_CYAN}3. Recommended Client-Side Applications:${C_RESET}"
    echo -e "     • ${C_BOLD}Android:${C_RESET} v2rayNG, NekoBox, Sing-box"
    echo -e "     • ${C_BOLD}iOS / macOS:${C_RESET} Shadowrocket, Sing-box, V2Box, Streisand"
    echo -e "     • ${C_BOLD}Windows:${C_RESET} v2rayN, Nekoray, Clash Verge"

    echo -e "\n  ${C_CYAN}4. Network & Buffer Tweaks Applied by DAHOOM:${C_RESET}"
    echo -e "     • TCP Fast Open (TFO = 3)"
    echo -e "     • Enlarged socket read/write buffers (rmem_max/wmem_max = 67MB)"
    echo -e "     • TCP Keepalive intervals tuned for low power consumption & fast dead-link drop."
    echo -e "  ${C_PURPLE}────────────────────────────────────────────────────────────${C_RESET}\n"
}

xui_panel_management_menu() {
    local panel_name="${1:-X-UI Panel}"
    local install_fn="install_xui_panel"

    while true; do
        show_banner
        echo
        menu_section "$panel_name" "$C_TITLE"

        local is_installed=false
        local curr_status=""

        if [[ -f "/etc/systemd/system/x-ui.service" || -f "/lib/systemd/system/x-ui.service" || -f "/usr/local/x-ui/x-ui" || -d "/usr/local/x-ui" ]]; then
            is_installed=true
            if systemctl is-active --quiet x-ui 2>/dev/null || pgrep -x x-ui &>/dev/null; then
                curr_status="${C_GREEN}🟢 Active (Running)${C_RESET}"
            else
                curr_status="${C_YELLOW}🟡 Installed (Stopped)${C_RESET}"
            fi
        else
            curr_status="${C_GRAY}⚪ Not Installed${C_RESET}"
        fi

        echo -e "      ${C_GRAY}Status:${C_RESET} $curr_status"
        echo

        if $is_installed; then
            # Display Full Access Information Box
            show_xui_access_info "$panel_name"

            # Check if active system domain has changed from X-UI configured certificate domain
            local sys_domain=""
            if [[ -f "$DNS_INFO_FILE" ]]; then
                source "$DNS_INFO_FILE" 2>/dev/null
                sys_domain="$FULL_DOMAIN"
            fi
            local xui_cert_dom=""
            if [[ -f "/etc/x-ui/x-ui.db" ]] && command -v python3 &>/dev/null; then
                xui_cert_dom=$(python3 -c "
import sqlite3, os
try:
    conn = sqlite3.connect('/etc/x-ui/x-ui.db')
    c = conn.cursor()
    c.execute(\"SELECT value FROM settings WHERE key IN ('webCertFile', 'webCert') LIMIT 1\")
    row = c.fetchone()
    if row and row[0]:
        val = str(row[0])
        # Extract domain name if stored inside /etc/letsencrypt/live/<domain>/...
        if '/live/' in val:
            parts = val.split('/live/')[1].split('/')
            print(parts[0].strip())
        elif '/cert/' in val:
            parts = val.split('/cert/')[1].split('/')
            print(parts[0].strip())
    conn.close()
except:
    pass
" 2>/dev/null)
            fi

            local domain_mismatch=false
            if [[ -n "$sys_domain" && -n "$xui_cert_dom" && "$sys_domain" != "$xui_cert_dom" ]]; then
                domain_mismatch=true
                echo -e "  ${C_ORANGE}⚠️  NOTICE: Active Domain has changed!${C_RESET}"
                echo -e "  ${C_GRAY}Current System Domain:${C_RESET} ${C_GREEN}${sys_domain}${C_RESET}"
                echo -e "  ${C_GRAY}X-UI Configured Domain:${C_RESET} ${C_RED}${xui_cert_dom}${C_RESET}"
                echo -e "  ${C_YELLOW}👉 Use option [8] below to rebuild SSL & apply the new domain.${C_RESET}\n"
            fi

            printf "      ${C_CHOICE}%-4s${C_RESET} %s\n" "[1]" "Restart Service"
            printf "      ${C_CHOICE}%-4s${C_RESET} %s\n" "[2]" "Fix & Repair Access (Ports & Firewall)"
            printf "      ${C_CHOICE}%-4s${C_RESET} %s\n" "[3]" "Reset Port & Credentials (Username/Password)"
            printf "      ${C_CHOICE}%-4s${C_RESET} %s\n" "[4]" "Launch x-ui CLI Manager"
            printf "      ${C_CHOICE}%-4s${C_RESET} %s\n" "[5]" "View Client Inbound Configurations (Links & Keys)"
            printf "      ${C_CHOICE}%-4s${C_RESET} %s\n" "[6]" "Speed & Performance Tuning Wiki"
            if $domain_mismatch; then
                printf "      ${C_NEW}%-4s${C_RESET} %s\n" "[8]" "Sync & Rebuild SSL Certificate with New Domain (${sys_domain})"
            fi
            printf "      ${C_DANGER}%-4s${C_RESET} %s\n" "[7]" "Uninstall $panel_name"
            echo
            printf "      ${C_DANGER}%-4s${C_RESET} %s\n" "[0]" "Return"
            echo
            if ! read -r -p "$(echo -e ${C_PROMPT}"> Select an action: "${C_RESET})" choice; then
                echo; return
            fi
            case $choice in
                1)
                    echo -e "\n${C_BLUE}🔄 Restarting x-ui service...${C_RESET}"
                    systemctl daemon-reload 2>/dev/null || true
                    systemctl reset-failed x-ui 2>/dev/null || true
                    systemctl restart x-ui 2>/dev/null || true
                    sleep 1
                    if systemctl is-active --quiet x-ui 2>/dev/null; then
                        echo -e "${C_GREEN}✅ x-ui service restarted successfully.${C_RESET}"
                    else
                        echo -e "${C_RED}❌ Failed to start x-ui service. Checking logs:${C_RESET}"
                        journalctl -u x-ui -n 8 --no-pager 2>/dev/null || true
                    fi
                    press_enter
                    ;;
                2)
                    repair_xui_access "$panel_name"
                    press_enter
                    ;;
                3)
                    reset_xui_credentials "$panel_name"
                    press_enter
                    ;;
                4)
                    if command -v x-ui &>/dev/null; then
                        x-ui
                    else
                        echo -e "\n${C_RED}❌ x-ui binary not found in PATH.${C_RESET}"
                    fi
                    press_enter
                    ;;
                5)
                    show_xui_client_configs
                    press_enter
                    ;;
                6)
                    show_xui_speed_wiki
                    press_enter
                    ;;
                8)
                    if $domain_mismatch; then
                        sync_xui_domain_ssl "$panel_name" "$sys_domain"
                        press_enter
                    else
                        invalid_option
                    fi
                    ;;
                7)
                    read -r -p "$(echo -e "${C_WARN}> Are you sure you want to uninstall ${panel_name}? (y/n) [n]: ${C_RESET}")" conf_un
                    if [[ "${conf_un,,}" == "y" ]]; then
                        uninstall_xui_panel
                    else
                        echo -e "\n${C_YELLOW}❌ Uninstall cancelled.${C_RESET}"
                    fi
                    press_enter
                    return
                    ;;
                0) return ;;
                *) invalid_option ;;
            esac
        else
            printf "      ${C_CHOICE}%-4s${C_RESET} %s\n" "[1]" "Install $panel_name"
            echo
            printf "      ${C_DANGER}%-4s${C_RESET} %s\n" "[0]" "Return"
            echo
            if ! read -r -p "$(echo -e ${C_PROMPT}"> Select an action: "${C_RESET})" choice; then
                echo; return
            fi
            case $choice in
                1)
                    "$install_fn"
                    press_enter
                    ;;
                0) return ;;
                *) invalid_option ;;
            esac
        fi
    done
}

refresh_ssh_session_cache() {
    local now db_mtime
    printf -v now '%(%s)T' -1
    db_mtime=$(stat -c %Y "$DB_FILE" 2>/dev/null || echo 0)

    if (( SSH_SESSION_CACHE_TS > 0 && now - SSH_SESSION_CACHE_TS < SSH_SESSION_CACHE_TTL && db_mtime == SSH_SESSION_CACHE_DB_MTIME )); then
        return
    fi

    SSH_SESSION_COUNTS=()
    SSH_SESSION_PIDS=()
    SSH_SESSION_TOTAL=0
    SSH_SESSION_CACHE_DB_MTIME=$db_mtime

    if [[ ! -s "$DB_FILE" ]]; then
        SSH_SESSION_CACHE_TS=$now
        return
    fi

    local -A managed_user_lookup=()
    local -A uid_user_lookup=()
    local -A session_pids=()
    local -A loginuid_pids=()
    local managed_user system_user system_uid ssh_pid ssh_owner candidate_user login_uid

    while IFS=: read -r managed_user _rest; do
        [[ -n "$managed_user" && "$managed_user" != \#* ]] && managed_user_lookup["$managed_user"]=1
    done < "$DB_FILE"

    while IFS=: read -r system_user _ system_uid _rest; do
        [[ -n "$system_user" && "$system_uid" =~ ^[0-9]+$ ]] && uid_user_lookup["$system_uid"]="$system_user"
    done < /etc/passwd

    while read -r ssh_pid ssh_owner; do
        [[ "$ssh_pid" =~ ^[0-9]+$ ]] || continue
        if [[ -n "$ssh_owner" && "$ssh_owner" != "root" && "$ssh_owner" != "sshd" && -n "${managed_user_lookup[$ssh_owner]+x}" ]]; then
            session_pids["$ssh_owner"]+="$ssh_pid "
        fi
    done < <(ps -C sshd,sshd-session -o pid=,user= 2>/dev/null)

    local user pid
    for user in "${!managed_user_lookup[@]}"; do
        unset unique_pids
        local -A unique_pids=()

        for pid in ${session_pids[$user]}; do
            [[ "$pid" =~ ^[0-9]+$ ]] && unique_pids["$pid"]=1
        done

        SSH_SESSION_COUNTS["$user"]=${#unique_pids[@]}
        if (( ${#unique_pids[@]} > 0 )); then
            for pid in "${!unique_pids[@]}"; do
                SSH_SESSION_PIDS["$user"]+="$pid "
            done
            SSH_SESSION_TOTAL=$((SSH_SESSION_TOTAL + ${#unique_pids[@]}))
        fi
    done

    SSH_SESSION_CACHE_TS=$now
}

count_managed_online_sessions() {
    refresh_ssh_session_cache
    echo "$SSH_SESSION_TOTAL"
}

invalidate_banner_cache() {
    BANNER_CACHE_TS=0
    SSH_SESSION_CACHE_TS=0
}

refresh_banner_cache() {
    local now
    printf -v now '%(%s)T' -1
    if (( BANNER_CACHE_TS > 0 && now - BANNER_CACHE_TS < BANNER_CACHE_TTL )); then
        return
    fi

    if [[ -z "$BANNER_CACHE_OS_NAME" ]]; then
        BANNER_CACHE_OS_NAME=$(grep -oP 'PRETTY_NAME="\K[^"]+' /etc/os-release 2>/dev/null || echo "Linux")
    fi
    BANNER_CACHE_UP_TIME=$(uptime -p 2>/dev/null | sed 's/up //' || echo "unknown")
    BANNER_CACHE_RAM_USAGE=$(free -m | awk '/^Mem:/{if($2>0){printf "%.2f", $3*100/$2}else{print "0.00"}}')
    BANNER_CACHE_CPU_LOAD=$(awk '{print $1}' /proc/loadavg 2>/dev/null)
    BANNER_CACHE_ACTIVE_USERS=0
    BANNER_CACHE_LOCKED_USERS=0
    BANNER_CACHE_EXPIRED_USERS=0
    BANNER_CACHE_TOTAL_USERS=0

    if [[ -s "$DB_FILE" ]]; then
        local now_ts; now_ts=$(date +%s)
        local -A shadow_locked=()
        if [[ -r /etc/shadow ]]; then
            while IFS=: read -r _su _sh_h _r; do
                [[ -n "$_su" && "${_sh_h:0:1}" == "!" ]] && shadow_locked["$_su"]=1
            done < /etc/shadow
        fi

        while IFS=: read -r _u _p exp _r; do
            [[ -z "$_u" || "$_u" == \#* ]] && continue
            (( BANNER_CACHE_TOTAL_USERS++ ))
            local e_ts=0
            [[ -n "$exp" && "$exp" != "Never" ]] && e_ts=$(date -d "$exp" +%s 2>/dev/null || echo 0)

            if [[ -n "${shadow_locked[$_u]+x}" ]]; then
                (( BANNER_CACHE_LOCKED_USERS++ ))
            elif (( e_ts > 0 && e_ts < now_ts )); then
                (( BANNER_CACHE_EXPIRED_USERS++ ))
            else
                (( BANNER_CACHE_ACTIVE_USERS++ ))
            fi
        done < "$DB_FILE"
    fi
    BANNER_CACHE_ONLINE_USERS=$(count_managed_online_sessions)

    BANNER_CACHE_REMOTE_VER=""
    BANNER_CACHE_HAS_UPDATE=false
    # cur_sha is now guaranteed to be a clean 7-char SHA by get_installed_sha()
    local cur_sha; cur_sha=$(get_installed_sha 2>/dev/null || echo "")

    _check_remote_ver_bg

    if [[ -f "$UPDATE_CACHE_FILE" ]]; then
        local _t_ts raw_sha rem_sha
        read -r _t_ts raw_sha < "$UPDATE_CACHE_FILE" 2>/dev/null
        # cache file stores raw API SHA (7 chars) — strip any accidental prefix just in case
        rem_sha="${raw_sha##*beta_}"
        rem_sha="${rem_sha##*4.6.0_}"
        rem_sha="${rem_sha##*4.5.0_}"
        rem_sha="${rem_sha##*beta-}"
        rem_sha="${rem_sha:0:7}"

        if [[ -z "$raw_sha" || "$raw_sha" == *"2026"* || ${#rem_sha} -ne 7 ]]; then
            # invalid / stale cache — purge and re-trigger background fetch
            rm -f "$UPDATE_CACHE_FILE" 2>/dev/null
            _check_remote_ver_bg
        else
            BANNER_CACHE_REMOTE_VER="4.6.0_${rem_sha}"
            # Both cur_sha and rem_sha are clean 7-char SHAs — reliable comparison
            if [[ -n "$cur_sha" && ${#cur_sha} -eq 7 && "$cur_sha" != "$rem_sha" ]]; then
                BANNER_CACHE_HAS_UPDATE=true
            fi
        fi
    fi

    BANNER_CACHE_TS=$now
}

show_banner() {
    if [[ -t 1 ]]; then
        printf '\033[H\033[2J\033[3J'
        clear 2>/dev/null || true
    fi
    refresh_banner_cache

    local _VER _pad_title _pad_badge _len_title _len_badge
    _VER=$(get_current_version_tag 2>/dev/null || echo "dev")
    _len_title=$(( 13 + ${#_VER} ))
    _pad_title=$(( 58 - _len_title ))
    [[ $_pad_title -lt 1 ]] && _pad_title=1

    # ── Elegant Unified Frame ─────────────────────────────────────────────
    echo
    echo -e "  ${C_BOLD}${C_BLUE}╭──────────────────────────────────────────────────────────╮${C_RESET}"
    echo -e "  ${C_BOLD}${C_BLUE}│${C_RESET}  ${C_BOLD}${C_ORANGE}🦅 DAHOOM${C_RESET}  ${C_DIM}${C_GRAY}${_VER}${C_RESET}$(printf '%*s' "$_pad_title" '')${C_BOLD}${C_BLUE}│${C_RESET}"
    echo -e "  ${C_BOLD}${C_BLUE}├──────────────────────────────────────────────────────────┤${C_RESET}"
    printf "  ${C_BOLD}${C_BLUE}│${C_RESET}  ${C_GRAY}%-8s${C_RESET} ${C_WHITE}%-17s${C_RESET} ${C_GRAY}│${C_RESET}  ${C_GRAY}%-6s${C_RESET} ${C_WHITE}%-18s${C_RESET} ${C_BOLD}${C_BLUE}│${C_RESET}\n" \
        "OS" "${BANNER_CACHE_OS_NAME:0:17}" "Uptime" "${BANNER_CACHE_UP_TIME:0:18}"
    printf "  ${C_BOLD}${C_BLUE}│${C_RESET}  ${C_GRAY}%-8s${C_RESET} ${C_WHITE}%-17s${C_RESET} ${C_GRAY}│${C_RESET}  ${C_GRAY}%-6s${C_RESET} ${C_GREEN}%-18s${C_RESET} ${C_BOLD}${C_BLUE}│${C_RESET}\n" \
        "Memory" "${BANNER_CACHE_RAM_USAGE}% Used" "Load" "$BANNER_CACHE_CPU_LOAD"
    printf "  ${C_BOLD}${C_BLUE}│${C_RESET}  ${C_GRAY}%-8s${C_RESET} ${C_WHITE}%-17s${C_RESET} ${C_GRAY}│${C_RESET}  ${C_GRAY}%-6s${C_RESET} ${C_CYAN}%-18s${C_RESET} ${C_BOLD}${C_BLUE}│${C_RESET}\n" \
        "Sessions" "${BANNER_CACHE_ONLINE_USERS} Online" "Mode" "Multi-Protocol"
    echo -e "  ${C_BOLD}${C_BLUE}├──────────────────────────────────────────────────────────┤${C_RESET}"

    # ── User Status Cards (Compact & Perfectly Framed) ────────────────────
    _len_badge=$(( 51 + ${#BANNER_CACHE_ACTIVE_USERS} + ${#BANNER_CACHE_LOCKED_USERS} + ${#BANNER_CACHE_EXPIRED_USERS} + ${#BANNER_CACHE_TOTAL_USERS} ))
    _pad_badge=$(( 58 - _len_badge ))
    [[ $_pad_badge -lt 1 ]] && _pad_badge=1

    echo -e "  ${C_BOLD}${C_BLUE}│${C_RESET}  ${C_GREEN}🟢 ${BANNER_CACHE_ACTIVE_USERS} Active${C_RESET} ${C_GRAY}│${C_RESET} ${C_YELLOW}🟡 ${BANNER_CACHE_LOCKED_USERS} Locked${C_RESET} ${C_GRAY}│${C_RESET} ${C_RED}🔴 ${BANNER_CACHE_EXPIRED_USERS} Expired${C_RESET} ${C_GRAY}│${C_RESET} ${C_WHITE}👥 ${BANNER_CACHE_TOTAL_USERS} Total${C_RESET}$(printf '%*s' "$_pad_badge" '')${C_BOLD}${C_BLUE}│${C_RESET}"
    echo -e "  ${C_BOLD}${C_BLUE}╰──────────────────────────────────────────────────────────╯${C_RESET}"
}

# --- Per-service Dynamic Action Menu (Install if not installed, Restart & Uninstall if installed) ---
service_action_menu() {
    local title="$1" status="$2" install_fn="$3" uninstall_fn="$4" svc_unit="${5:-}"
    local install_label="${6:-Install $title}" uninstall_label="${7:-Uninstall $title}"

    while true; do
        show_banner
        echo
        menu_section "$title" "$C_TITLE"

        local is_inst=false
        local is_act=false
        local curr_status=""

        # Check status dynamically (0ms)
        if [[ -n "$svc_unit" ]]; then
            if pgrep -x "$svc_unit" &>/dev/null || pgrep -f "$svc_unit" &>/dev/null; then
                is_inst=true
                is_act=true
                curr_status="${C_GREEN}🟢 Active (Running)${C_RESET}"
            elif [[ -f "/etc/systemd/system/${svc_unit}.service" || -f "/lib/systemd/system/${svc_unit}.service" ]] || command -v "$svc_unit" &>/dev/null || [[ "$svc_unit" == "x-ui" && -d "/usr/local/x-ui" ]]; then
                is_inst=true
                is_act=false
                curr_status="${C_YELLOW}🟡 Installed (Stopped)${C_RESET}"
            else
                is_inst=false
                is_act=false
                curr_status="${C_GRAY}⚪ Not Installed${C_RESET}"
            fi
        else
            if [[ "$status" =~ [Aa]ctive|[Ii]nstalled ]]; then
                is_inst=true
                curr_status="$status"
            else
                is_inst=false
                curr_status="${C_GRAY}⚪ Not Installed${C_RESET}"
            fi
        fi

        echo -e "      ${C_GRAY}Status:${C_RESET} $curr_status"
        echo

        if $is_inst; then
            printf "      ${C_CHOICE}%-4s${C_RESET} %s\n" "[1]" "Restart Service"
            printf "      ${C_DANGER}%-4s${C_RESET} %s\n" "[2]" "$uninstall_label"
            echo
            printf "      ${C_DANGER}%-4s${C_RESET} %s\n" "[0]" "Return"
            echo
            if ! read -r -p "$(echo -e ${C_PROMPT}"> Select an action: "${C_RESET})" choice; then
                echo; return
            fi
            case $choice in
                1)
                    if [[ -n "$svc_unit" ]]; then
                        echo -e "\n${C_BLUE}🔄 Restarting ${title} (${svc_unit})...${C_RESET}"
                        systemctl restart "$svc_unit" 2>/dev/null || true
                        sleep 1
                        if systemctl is-active --quiet "$svc_unit" 2>/dev/null; then
                            echo -e "${C_GREEN}✅ ${title} restarted successfully.${C_RESET}"
                        else
                            echo -e "${C_RED}❌ Failed to start ${title}. Check logs: journalctl -u ${svc_unit} -n 10${C_RESET}"
                        fi
                    else
                        echo -e "\n${C_BLUE}🔄 Restarting ${title}...${C_RESET}"
                        "$install_fn"
                    fi
                    press_enter
                    ;;
                2)
                    read -r -p "$(echo -e "${C_WARN}> Are you sure you want to uninstall ${title}? (y/n) [n]: ${C_RESET}")" conf_un
                    if [[ "${conf_un,,}" == "y" ]]; then
                        "$uninstall_fn"
                        echo -e "\n${C_GREEN}✅ ${title} uninstalled successfully.${C_RESET}"
                    else
                        echo -e "\n${C_YELLOW}❌ Uninstall cancelled.${C_RESET}"
                    fi
                    press_enter
                    return
                    ;;
                0) return ;;
                *) invalid_option ;;
            esac
        else
            printf "      ${C_CHOICE}%-4s${C_RESET} %s\n" "[1]" "$install_label"
            echo
            printf "      ${C_DANGER}%-4s${C_RESET} %s\n" "[0]" "Return"
            echo
            if ! read -r -p "$(echo -e ${C_PROMPT}"> Select an action: "${C_RESET})" choice; then
                echo; return
            fi
            case $choice in
                1)
                    "$install_fn"
                    press_enter
                    ;;
                0) return ;;
                *) invalid_option ;;
            esac
        fi
    done
}

# ── AUTO-HEALING SERVICE GUARD ─────────────────────────────────────────
AUTO_HEALING_CONF="/etc/firewallfalcon/auto_healing.conf"

run_auto_healing_check() {
    local services=("badvpn" "udp-custom" "haproxy" "nginx" "dnstt" "falconproxy" "zivpn" "x-ui" "xray")
    local lock_file="/tmp/.ff_auto_healing.lock"
    [[ -f "$lock_file" ]] && return
    touch "$lock_file" 2>/dev/null

    for svc in "${services[@]}"; do
        if systemctl is-enabled "$svc" &>/dev/null; then
            if ! systemctl is-active --quiet "$svc" 2>/dev/null; then
                systemctl restart "$svc" &>/dev/null
                _log_action "AUTO_HEAL_RESTART" "$svc" "status=restarted"
                send_telegram_msg "⚡ <b>Auto-Healing Guard Alert</b>%0AService <b>$svc</b> was down and auto-restarted successfully!"
            fi
        fi
    done

    rm -f "$lock_file" 2>/dev/null
}

auto_healing_menu() {
    while true; do
        clear; show_banner
        echo
        menu_section "AUTO-HEALING SERVICE GUARD" "$C_TITLE"
        echo
        local status="Disabled"
        if (crontab -l 2>/dev/null | grep -q "_run_auto_healing"); then
            status="${C_GREEN}Active (Automated Background Self-Healing)${C_RESET}"
        else
            status="${C_RED}Disabled${C_RESET}"
        fi

        echo -e "  ${C_CYAN}Guard Status:${C_RESET} $status"
        echo
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[1]" "Enable Automated Auto-Healing Guard"
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[2]" "Disable Auto-Healing Guard"
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[3]" "Run Instant Health Check & Heal"
        echo
        printf "  ${C_DANGER}%-4s${C_RESET} %s\n" "[0]" "Return"
        echo
        if ! read -r -p "$(echo -e ${C_PROMPT}"> Select an option: "${C_RESET})" ah_act; then
            return
        fi
        case "$ah_act" in
            1)
                (crontab -l 2>/dev/null | grep -v "_run_auto_healing") | crontab -
                (crontab -l 2>/dev/null; echo "*/2 * * * * bash /usr/local/bin/menu _run_auto_healing &>/dev/null") | crontab -
                echo -e "\n${C_GREEN}✅ Automated Auto-Healing Guard enabled (runs every 2 mins).${C_RESET}"
                press_enter
                ;;
            2)
                (crontab -l 2>/dev/null | grep -v "_run_auto_healing") | crontab -
                echo -e "\n${C_GREEN}✅ Auto-Healing Guard disabled.${C_RESET}"
                press_enter
                ;;
            3)
                echo -e "\n${C_BLUE}Running instant health check...${C_RESET}"
                run_auto_healing_check
                echo -e "${C_GREEN}✅ Health check completed.${C_RESET}"
                press_enter
                ;;
            0) return ;;
            *) invalid_option ;;
        esac
    done
}

# ── VLESS / REALITY PROTOCOL MODULE ───────────────────────────────────
_ensure_v2ray_manager() {
    mkdir -p /etc/firewallfalcon/panel /usr/local/bin /etc/firewallfalcon
    _fm_panel_file v2ray_manager.py /etc/firewallfalcon/panel/v2ray_manager.py 2>/dev/null
    cp -f /etc/firewallfalcon/panel/v2ray_manager.py /usr/local/bin/v2ray_manager.py 2>/dev/null
    cp -f /etc/firewallfalcon/panel/v2ray_manager.py /etc/firewallfalcon/v2ray_manager.py 2>/dev/null
    chmod +x /etc/firewallfalcon/panel/v2ray_manager.py /usr/local/bin/v2ray_manager.py 2>/dev/null || true
}

install_vless_reality() {
    echo -e "\n${C_BLUE}Installing Xray core and configuring V2Ray services...${C_RESET}"
    mkdir -p /etc/xray /usr/local/etc/xray /var/log/xray /etc/firewallfalcon/panel /usr/local/bin 2>/dev/null
    chmod -R 777 /var/log/xray 2>/dev/null || true
    touch /var/log/xray/access.log /var/log/xray/error.log 2>/dev/null && chmod 666 /var/log/xray/*.log 2>/dev/null || true
    
    if ! command -v xray &>/dev/null; then
        bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root &>/dev/null
    fi
    _ensure_v2ray_manager
    
    # Generate authentic Xray Reality Keypair directly from installed xray binary
    if command -v xray &>/dev/null; then
        local key_out real_priv real_pub
        key_out=$(xray x25519 2>/dev/null)
        real_priv=$(echo "$key_out" | grep -iE "private *key:" | head -n1 | awk '{print $NF}' | tr -d '\r\n ')
        real_pub=$(echo "$key_out" | grep -iE "public *key:|password:" | head -n1 | awk '{print $NF}' | tr -d '\r\n ')
        if [[ -n "$real_priv" && -n "$real_pub" && ${#real_priv} -ge 43 ]]; then
            python3 -c "
import sys, json, os
sys.path.extend(['/etc/firewallfalcon/panel', '/etc/firewallfalcon', '/usr/local/bin'])
try:
    import v2ray_manager
    inb = v2ray_manager.read_v2ray_inbounds()
    inb.setdefault('vless_reality', {})['privateKey'] = '$real_priv'
    inb['vless_reality']['publicKey'] = '$real_pub'
    v2ray_manager.write_v2ray_inbounds(inb)
except Exception:
    pass
" 2>/dev/null
        fi
    fi

    # Build and deploy configuration
    python3 -c "import sys; sys.path.extend(['/etc/firewallfalcon/panel', '/etc/firewallfalcon', '/usr/local/bin']); import v2ray_manager; v2ray_manager.apply_xray_config_safe()" 2>/dev/null
    
    # Ensure systemd service file has correct root user and ExecStart
    cat > /etc/systemd/system/xray.service <<'EOF'
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartSec=3s
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload &>/dev/null || true
    systemctl reset-failed xray &>/dev/null || true
    systemctl enable xray &>/dev/null || true
    systemctl restart xray 2>/dev/null || true
    sleep 1.5

    if systemctl is-active --quiet xray 2>/dev/null; then
        echo -e "${C_GREEN}✅ Xray core installed and running actively!${C_RESET}"
    else
        systemctl reset-failed xray 2>/dev/null || true
        systemctl start xray 2>/dev/null || true
        sleep 1.5
        if systemctl is-active --quiet xray 2>/dev/null; then
            echo -e "${C_GREEN}✅ Xray core started successfully!${C_RESET}"
        else
            echo -e "${C_RED}❌ Xray core failed to start. Diagnostics:${C_RESET}"
            xray -test -config /usr/local/etc/xray/config.json 2>/dev/null || xray -test -config /etc/xray/config.json 2>/dev/null || true
            journalctl -u xray -n 8 --no-pager 2>/dev/null || true
        fi
    fi
}

reinstall_vless_reality() {
    echo -e "\n${C_BLUE}Safely reinstalling & repairing Xray core binaries and configs...${C_RESET}"
    systemctl stop xray &>/dev/null || true
    systemctl reset-failed xray &>/dev/null || true
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root &>/dev/null
    mkdir -p /etc/xray /usr/local/etc/xray /var/log/xray 2>/dev/null
    chmod -R 777 /var/log/xray 2>/dev/null || true
    touch /var/log/xray/access.log /var/log/xray/error.log 2>/dev/null && chmod 666 /var/log/xray/*.log 2>/dev/null || true
    _ensure_v2ray_manager
    
    if command -v xray &>/dev/null; then
        local key_out real_priv real_pub
        key_out=$(xray x25519 2>/dev/null)
        real_priv=$(echo "$key_out" | grep -iE "private *key:" | head -n1 | awk '{print $NF}' | tr -d '\r\n ')
        real_pub=$(echo "$key_out" | grep -iE "public *key:|password:" | head -n1 | awk '{print $NF}' | tr -d '\r\n ')
        if [[ -n "$real_priv" && -n "$real_pub" && ${#real_priv} -ge 43 ]]; then
            python3 -c "
import sys, json, os
sys.path.extend(['/etc/firewallfalcon/panel', '/etc/firewallfalcon', '/usr/local/bin'])
try:
    import v2ray_manager
    inb = v2ray_manager.read_v2ray_inbounds()
    inb.setdefault('vless_reality', {})['privateKey'] = '$real_priv'
    inb['vless_reality']['publicKey'] = '$real_pub'
    v2ray_manager.write_v2ray_inbounds(inb)
except Exception:
    pass
" 2>/dev/null
        fi
    fi

    python3 -c "import sys; sys.path.extend(['/etc/firewallfalcon/panel', '/etc/firewallfalcon', '/usr/local/bin']); import v2ray_manager; v2ray_manager.apply_xray_config_safe()" 2>/dev/null
    
    cat > /etc/systemd/system/xray.service <<'EOF'
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartSec=3s
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload &>/dev/null || true
    systemctl reset-failed xray &>/dev/null || true
    systemctl enable xray &>/dev/null || true
    systemctl restart xray 2>/dev/null || true
    sleep 1.5

    if systemctl is-active --quiet xray 2>/dev/null; then
        echo -e "${C_GREEN}✅ Xray core reinstalled and running successfully!${C_RESET}"
    else
        systemctl reset-failed xray 2>/dev/null || true
        systemctl start xray 2>/dev/null || true
        sleep 1.5
        if systemctl is-active --quiet xray 2>/dev/null; then
            echo -e "${C_GREEN}✅ Xray core started successfully!${C_RESET}"
        else
            echo -e "${C_RED}❌ Xray service failed to start after reinstall.${C_RESET}"
            xray -test -config /usr/local/etc/xray/config.json 2>/dev/null || xray -test -config /etc/xray/config.json 2>/dev/null || true
            journalctl -u xray -n 8 --no-pager 2>/dev/null || true
        fi
    fi
}

uninstall_vless_reality() {
    local u_conf="y"
    if [[ "$UNINSTALL_MODE" != "silent" ]]; then
        echo -e "\n${C_WARN}Are you sure you want to completely uninstall Xray core? (y/n) [n]: ${C_RESET}"
        read -r -p "> " u_conf
    fi
    if [[ "${u_conf,,}" == "y" ]]; then
        if [[ "$UNINSTALL_MODE" != "silent" ]]; then
            echo -e "\n${C_BLUE}Stopping and removing Xray core...${C_RESET}"
        fi
        systemctl stop xray &>/dev/null || true
        systemctl disable xray &>/dev/null || true
        if command -v xray &>/dev/null; then
            bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove &>/dev/null || rm -f /usr/local/bin/xray
        fi
        if [[ "$UNINSTALL_MODE" != "silent" ]]; then
            echo -e "${C_GREEN}✅ Xray core uninstalled successfully.${C_RESET}"
        fi
    else
        echo -e "\n${C_YELLOW}❌ Uninstall cancelled.${C_RESET}"
    fi
}

view_xray_status_logs() {
    clear; show_banner
    echo
    menu_section "XRAY CORE STATUS & LOGS" "$C_TITLE"
    echo
    if systemctl is-active --quiet xray 2>/dev/null; then
        echo -e "  ${C_CYAN}Service Status:${C_RESET} ${C_GREEN}Active (Running)${C_RESET}"
    elif command -v xray &>/dev/null; then
        echo -e "  ${C_CYAN}Service Status:${C_RESET} ${C_YELLOW}Stopped / Inactive${C_RESET}"
    else
        echo -e "  ${C_CYAN}Service Status:${C_RESET} ${C_RED}Not Installed${C_RESET}"
    fi
    echo -e "\n${C_BLUE}--- Configuration Test ---${C_RESET}"
    if command -v xray &>/dev/null && [[ -f /etc/xray/config.json ]]; then
        xray -test -config /etc/xray/config.json 2>&1 | head -n 5
    else
        echo "Xray binary or config missing."
    fi
    echo -e "\n${C_BLUE}--- Recent Xray Journal Logs ---${C_RESET}"
    journalctl -u xray -n 12 --no-pager 2>/dev/null || echo "No journal logs available."
    echo
    press_enter
}

_select_v2ray_user_interface() {
    local title="${1:-Select V2Ray User}"
    clear; show_banner
    echo
    menu_section "$title" "$C_TITLE"
    echo
    SELECTED_V2RAY_USER=""
    _ensure_v2ray_manager
    local -a v2_users=()
    mapfile -t v2_users < <(python3 -c "
import sys
sys.path.extend(['/etc/firewallfalcon/panel', '/etc/firewallfalcon', '/usr/local/bin'])
try:
    import v2ray_manager
    for u in v2ray_manager.read_v2ray_users():
        if u.get('username'):
            print(u['username'])
except Exception as e:
    pass
")
    
    if [ ${#v2_users[@]} -eq 0 ]; then
        echo -e "${C_YELLOW}ℹ️ No V2Ray users found in database.${C_RESET}"
        echo -e "${C_CYAN}💡 Tip: Use option [36] to import existing SSH users into V2Ray.${C_RESET}\n"
        press_enter
        SELECTED_V2RAY_USER="NO_USERS"
        return
    fi
    echo -e "Please select a V2Ray user:\n"
    for i in "${!v2_users[@]}"; do
        printf "  ${C_CHOICE}[%2d]${C_RESET} %s\n" "$((i+1))" "${v2_users[$i]}"
    done
    echo -e "\n  ${C_DANGER} [ 0]${C_RESET} Cancel"
    echo
    local choice
    while true; do
        if ! read -r -p "$(echo -e ${C_PROMPT}"> Enter number or username (0 to cancel): "${C_RESET})" choice; then
            SELECTED_V2RAY_USER=""
            return
        fi
        choice=$(echo "$choice" | xargs 2>/dev/null || echo "$choice")
        if [[ -z "$choice" || "$choice" == "0" || "${choice,,}" == "cancel" || "${choice,,}" == "q" ]]; then
            SELECTED_V2RAY_USER=""
            return
        fi
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#v2_users[@]}" ]; then
            SELECTED_V2RAY_USER="${v2_users[$((choice-1))]}"
            return
        else
            local found=""
            for u in "${v2_users[@]}"; do
                if [[ "$u" == "$choice" ]]; then found="$u"; break; fi
            done
            if [[ -n "$found" ]]; then
                SELECTED_V2RAY_USER="$found"
                return
            else
                echo -e "${C_RED}❌ Invalid selection. Please check and try again.${C_RESET}"
            fi
        fi
    done
}

v2ray_create_user_cli() {
    clear; show_banner
    echo
    menu_section "CREATE V2RAY USER" "$C_TITLE"
    echo
    read -p "$(echo -e "${C_PROMPT}> Username (0 to cancel): ${C_RESET}")" v_un
    v_un=$(echo "$v_un" | xargs 2>/dev/null || echo "$v_un")
    [[ -z "$v_un" || "$v_un" == "0" || "${v_un,,}" == "cancel" || "${v_un,,}" == "q" ]] && return
    
    read -p "$(echo -e "${C_PROMPT}> Duration in days [30]: ${C_RESET}")" v_days
    v_days=${v_days:-30}
    
    read -p "$(echo -e "${C_PROMPT}> Bandwidth Quota in GB (0 for unlimited) [0]: ${C_RESET}")" v_bw
    v_bw=${v_bw:-0}

    read -p "$(echo -e "${C_PROMPT}> Max Connections (Devices) [2]: ${C_RESET}")" v_conn
    v_conn=${v_conn:-2}

    echo -e "\n${C_BLUE}Creating user in V2Ray engine...${C_RESET}"
    _ensure_v2ray_manager
    python3 -c "
import sys
sys.path.extend(['/etc/firewallfalcon/panel', '/etc/firewallfalcon', '/usr/local/bin'])
try:
    import v2ray_manager
    u = v2ray_manager.create_v2ray_user('$v_un', days=$v_days, bandwidth_gb=$v_bw, max_conn=$v_conn)
    print(f'${C_GREEN}✅ Created UUID: ${C_YELLOW}{u[\"uuid\"]}${C_RESET}')
    print(f'${C_GREEN}📡 Sub Token: ${C_YELLOW}{u[\"sub_token\"]}${C_RESET}')
except Exception as e:
    print(f'${C_RED}❌ Error creating V2Ray user: {e}${C_RESET}')
"
    echo
    press_enter
}

v2ray_list_users_cli() {
    clear; show_banner
    echo
    menu_section "V2RAY USERS LIST" "$C_TITLE"
    echo
    _ensure_v2ray_manager
    python3 -c "
import sys
sys.path.extend(['/etc/firewallfalcon/panel', '/etc/firewallfalcon', '/usr/local/bin'])
try:
    import v2ray_manager
    users = v2ray_manager.read_v2ray_users()
    print(f'Total V2Ray Users: {len(users)}\n')
    if not users:
        print('No V2Ray users registered yet. Tip: Run option [36] to import SSH users.')
    for u in users:
        st = '🟢 Active' if u.get('is_active') else '🔴 Inactive'
        bw = f\"{u.get('bandwidth_gb', 0)} GB\" if u.get('bandwidth_gb', 0) > 0 else 'Unlimited'
        print(f\"- {u['username']:<15} | {st:<10} | Exp: {u.get('expire_date',''):<12} | BW: {bw:<10} | Protos: {','.join(u.get('protocols',[]))}\")
except Exception as e:
    print(f'${C_RED}❌ Error reading V2Ray users: {e}${C_RESET}')
"
    echo
    press_enter
}

v2ray_show_user_links_cli() {
    _select_v2ray_user_interface "V2RAY SUBSCRIPTION & CONFIGS"
    local u=$SELECTED_V2RAY_USER
    if [[ "$u" == "NO_USERS" || -z "$u" ]]; then return; fi

    clear; show_banner
    echo
    menu_section "V2RAY CONFIGS & SUB: $u" "$C_TITLE"
    echo
    _ensure_v2ray_manager
    python3 -c "
import sys
sys.path.extend(['/etc/firewallfalcon/panel', '/etc/firewallfalcon', '/usr/local/bin'])
try:
    import v2ray_manager
    user = v2ray_manager.find_v2ray_user('$u')
    if user:
        links = v2ray_manager.generate_user_protocol_links(user)
        print(f'📡 Universal Subscription Token: {user.get(\"sub_token\", \"\")}')
        print(f'🔗 Path: /sub/v2ray/{user.get(\"sub_token\", \"\")}\n')
        print('Direct Protocol Links:\n')
        for l in links:
            print(f'[{l[\"type\"]} - {l[\"security\"]}]')
            print(f'{l[\"link\"]}\n')
    else:
        print('User not found.')
except Exception as e:
    print(f'${C_RED}❌ Error generating links: {e}${C_RESET}')
"
    echo
    press_enter
}

v2ray_renew_user_cli() {
    _select_v2ray_user_interface "RENEW V2RAY USER"
    local u=$SELECTED_V2RAY_USER
    if [[ "$u" == "NO_USERS" || -z "$u" ]]; then return; fi

    read -p "$(echo -e "${C_PROMPT}> Additional Days to add [30]: ${C_RESET}")" v_days
    v_days=${v_days:-30}
    
    _ensure_v2ray_manager
    python3 -c "
import sys
sys.path.extend(['/etc/firewallfalcon/panel', '/etc/firewallfalcon', '/usr/local/bin'])
try:
    import v2ray_manager
    res = v2ray_manager.renew_v2ray_user('$u', days=$v_days)
    if res:
        print(f'${C_GREEN}✅ User $u renewed! New expiration: {res[\"expire_date\"]}${C_RESET}')
    else:
        print('${C_RED}❌ User not found${C_RESET}')
except Exception as e:
    print(f'${C_RED}❌ Error renewing user: {e}${C_RESET}')
"
    echo
    press_enter
}

v2ray_delete_user_cli() {
    _select_v2ray_user_interface "DELETE V2RAY USER"
    local u=$SELECTED_V2RAY_USER
    if [[ "$u" == "NO_USERS" || -z "$u" ]]; then return; fi

    read -p "$(echo -e "${C_WARN}> Confirm deleting V2Ray user '$u'? (y/n) [n]: ${C_RESET}")" v_conf
    if [[ "${v_conf,,}" == "y" ]]; then
        _ensure_v2ray_manager
        python3 -c "
import sys
sys.path.extend(['/etc/firewallfalcon/panel', '/etc/firewallfalcon', '/usr/local/bin'])
try:
    import v2ray_manager
    ok = v2ray_manager.delete_v2ray_user('$u')
    if ok:
        print('${C_GREEN}✅ User $u deleted successfully.${C_RESET}')
    else:
        print('${C_RED}❌ User not found.${C_RESET}')
except Exception as e:
    print(f'${C_RED}❌ Error deleting user: {e}${C_RESET}')
"
    else
        echo -e "\n${C_YELLOW}❌ Deletion cancelled.${C_RESET}"
    fi
    echo
    press_enter
}

v2ray_import_ssh_cli() {
    clear; show_banner
    echo
    menu_section "IMPORT SSH USERS TO V2RAY" "$C_TITLE"
    echo
    echo -e "${C_CYAN}This will scan all existing SSH users and import them into V2Ray.${C_RESET}"
    read -p "$(echo -e "${C_WARN}> Proceed with import? (y/n) [y]: ${C_RESET}")" v_conf
    v_conf=${v_conf:-y}
    if [[ "${v_conf,,}" == "y" ]]; then
        echo -e "\n${C_BLUE}Importing SSH users into V2Ray...${C_RESET}"
        _ensure_v2ray_manager
        python3 -c "
import sys
sys.path.extend(['/etc/firewallfalcon/panel', '/etc/firewallfalcon', '/usr/local/bin'])
try:
    import v2ray_manager
    res = v2ray_manager.import_ssh_users_to_v2ray()
    print(f'${C_GREEN}✅ Imported: {res[\"imported\"]} new users | Skipped/Existing: {res[\"skipped\"]}${C_RESET}')
    print(f'📊 Total V2Ray Users: {res[\"total_v2ray\"]}')
except Exception as e:
    print(f'${C_RED}❌ Error importing users: {e}${C_RESET}')
"
    else
        echo -e "\n${C_YELLOW}❌ Import cancelled.${C_RESET}"
    fi
    echo
    press_enter
}

vless_reality_menu() {
    while true; do
        clear; show_banner
        echo
        local is_installed=false
        local is_active=false
        
        if command -v xray &>/dev/null || [[ -f /usr/local/bin/xray ]]; then
            is_installed=true
        fi
        
        if systemctl is-active --quiet xray 2>/dev/null; then
            is_active=true
        fi

        local inst_badge="${C_RED}🔴 Not Installed${C_RESET}"
        $is_installed && inst_badge="${C_GREEN}🟢 Installed${C_RESET}"

        local svc_badge="${C_GRAY}⚪ Inactive${C_RESET}"
        if $is_active; then
            svc_badge="${C_GREEN}🟢 Active (Running)${C_RESET}"
        elif $is_installed; then
            svc_badge="${C_YELLOW}🟡 Stopped${C_RESET}"
        fi

        menu_section "V2RAY & XRAY CORE MANAGEMENT" "$C_TITLE"
        echo
        echo -e "  📦 Installation: ${inst_badge}   │   ⚡ Service: ${svc_badge}"
        echo -e "${C_BLUE}  ─────────────────────────────────────────────────────────${C_RESET}"
        echo

        if ! $is_installed; then
            printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[1]" "Install Xray Core"
            printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[2]" "Create V2Ray User"
            printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[3]" "List V2Ray Users"
            printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[4]" "Import All SSH Users to V2Ray"
            echo
            printf "  ${C_DANGER}%-4s${C_RESET} %s\n" "[0]" "Return to Main Menu"
            echo
            if ! read -r -p "$(echo -e ${C_PROMPT}"> Select an option: "${C_RESET})" vx_opt; then return; fi

            case "$vx_opt" in
                1) install_vless_reality; press_enter ;;
                2) v2ray_create_user_cli ;;
                3) v2ray_list_users_cli ;;
                4) v2ray_import_ssh_cli ;;
                0) return ;;
                *) invalid_option ;;
            esac
        else
            printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[1]" "Reinstall / Repair Core"
            printf "  ${C_DANGER}%-4s${C_RESET} %s\n" "[2]" "Uninstall Xray Core"
            if $is_active; then
                printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[3]" "Restart Xray Service"
                printf "  ${C_WARN}%-4s${C_RESET} %s\n" "[4]" "Stop Xray Service"
            else
                printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[3]" "Start Xray Service"
            fi
            printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[5]" "View Core Status & Logs"
            printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[6]" "Create V2Ray User"
            printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[7]" "List V2Ray Users"
            printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[8]" "Show User Subscription & Links"
            printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[9]" "Renew / Extend V2Ray User"
            printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[10]" "Delete V2Ray User"
            printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[11]" "Import All SSH Users to V2Ray"
            printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[12]" "Regenerate Reality Keypair"
            echo
            printf "  ${C_DANGER}%-4s${C_RESET} %s\n" "[0]" "Return to Main Menu"
            echo
            if ! read -r -p "$(echo -e ${C_PROMPT}"> Select an option: "${C_RESET})" vx_opt; then return; fi

            case "$vx_opt" in
                1) reinstall_vless_reality; press_enter ;;
                2) uninstall_vless_reality; press_enter ;;
                3)
                    if $is_active; then
                        echo -e "\n${C_BLUE}Restarting Xray service...${C_RESET}"
                        systemctl daemon-reload &>/dev/null || true
                        systemctl reset-failed xray &>/dev/null || true
                        systemctl restart xray 2>/dev/null
                        sleep 1.2
                        if systemctl is-active --quiet xray 2>/dev/null; then
                            echo -e "${C_GREEN}✅ Xray restarted and active!${C_RESET}"
                        else
                            echo -e "${C_RED}❌ Failed to restart Xray.${C_RESET}"
                        fi
                    else
                        echo -e "\n${C_BLUE}Starting Xray service...${C_RESET}"
                        systemctl daemon-reload &>/dev/null || true
                        systemctl reset-failed xray &>/dev/null || true
                        systemctl start xray 2>/dev/null
                        sleep 1.2
                        if systemctl is-active --quiet xray 2>/dev/null; then
                            echo -e "${C_GREEN}✅ Xray started and active!${C_RESET}"
                        else
                            echo -e "${C_RED}❌ Failed to start Xray.${C_RESET}"
                        fi
                    fi
                    press_enter
                    ;;
                4)
                    if $is_active; then
                        echo -e "\n${C_BLUE}Stopping Xray service...${C_RESET}"
                        systemctl stop xray 2>/dev/null
                        sleep 1
                        echo -e "${C_YELLOW}⏸️ Xray service stopped.${C_RESET}"
                        press_enter
                    else
                        invalid_option
                    fi
                    ;;
                5) view_xray_status_logs ;;
                6) v2ray_create_user_cli ;;
                7) v2ray_list_users_cli ;;
                8) v2ray_show_user_links_cli ;;
                9) v2ray_renew_user_cli ;;
                10) v2ray_delete_user_cli ;;
                11) v2ray_import_ssh_cli ;;
                12)
                    _ensure_v2ray_manager
                    python3 -c "import sys; sys.path.extend(['/etc/firewallfalcon/panel', '/etc/firewallfalcon', '/usr/local/bin']); import v2ray_manager; k = v2ray_manager.generate_x25519_keypair(); inb = v2ray_manager.read_v2ray_inbounds(); inb['vless_reality']['publicKey']=k['publicKey']; inb['vless_reality']['privateKey']=k['privateKey']; v2ray_manager.write_v2ray_inbounds(inb); print('New Reality Public Key:', k['publicKey'])" 2>/dev/null
                    echo -e "${C_GREEN}✅ New Reality Keypair generated and applied.${C_RESET}"
                    press_enter
                    ;;
                0) return ;;
                *) invalid_option ;;
            esac
        fi
    done
}

# ── IP FIREWALL MODULE (WHITELIST / BLACKLIST) ───────────────────────────
IP_BLACKLIST_CONF="/etc/firewallfalcon/ip_blacklist.conf"
IP_WHITELIST_CONF="/etc/firewallfalcon/ip_whitelist.conf"
FF_IPTABLES_CHAIN="FF_FIREWALL"

_ensure_ff_chain() {
    iptables -N "$FF_IPTABLES_CHAIN" 2>/dev/null
    iptables -C INPUT -j "$FF_IPTABLES_CHAIN" 2>/dev/null || \
        iptables -I INPUT 1 -j "$FF_IPTABLES_CHAIN" 2>/dev/null
}

_apply_ip_rules() {
    _ensure_ff_chain
    iptables -F "$FF_IPTABLES_CHAIN" 2>/dev/null
    # Whitelist first (ACCEPT before any DROP)
    if [[ -s "$IP_WHITELIST_CONF" ]]; then
        while IFS= read -r ip; do
            [[ -z "$ip" || "$ip" == \#* ]] && continue
            iptables -A "$FF_IPTABLES_CHAIN" -s "$ip" -j ACCEPT 2>/dev/null
        done < "$IP_WHITELIST_CONF"
    fi
    # Blacklist (DROP)
    if [[ -s "$IP_BLACKLIST_CONF" ]]; then
        while IFS= read -r ip; do
            [[ -z "$ip" || "$ip" == \#* ]] && continue
            iptables -A "$FF_IPTABLES_CHAIN" -s "$ip" -j DROP 2>/dev/null
        done < "$IP_BLACKLIST_CONF"
    fi
}

ip_firewall_menu() {
    while true; do
        clear; show_banner
        echo
        menu_section "IP FIREWALL — WHITELIST & BLACKLIST" "$C_TITLE"
        echo
        mkdir -p "/etc/firewallfalcon" 2>/dev/null
        local bl_count=0 wl_count=0
        [[ -s "$IP_BLACKLIST_CONF" ]] && bl_count=$(grep -cEv '^\s*(#|$)' "$IP_BLACKLIST_CONF" 2>/dev/null || echo 0)
        [[ -s "$IP_WHITELIST_CONF" ]] && wl_count=$(grep -cEv '^\s*(#|$)' "$IP_WHITELIST_CONF" 2>/dev/null || echo 0)
        echo -e "  ${C_CYAN}Blacklisted IPs :${C_RESET} ${C_RED}${bl_count}${C_RESET}  ${C_DIM}(blocked)${C_RESET}"
        echo -e "  ${C_CYAN}Whitelisted IPs :${C_RESET} ${C_GREEN}${wl_count}${C_RESET}  ${C_DIM}(always allowed)${C_RESET}"
        echo
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[1]" "Add IP to Blacklist  (BLOCK)"
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[2]" "Remove IP from Blacklist"
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[3]" "Add IP to Whitelist  (ALWAYS ALLOW)"
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[4]" "Remove IP from Whitelist"
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[5]" "View All Rules"
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[6]" "Re-Apply All Rules"
        printf "  ${C_DANGER}%-4s${C_RESET} %s\n" "[7]" "Flush All Rules (clear everything)"
        echo
        printf "  ${C_DANGER}%-4s${C_RESET} %s\n" "[0]" "Return"
        echo
        if ! read -r -p "$(echo -e ${C_PROMPT}"> Select an option: "${C_RESET})" ipf_act; then return; fi
        case "$ipf_act" in
            1)
                read -r -p "$(echo -e "  ${C_BLUE}👉 Enter IP or CIDR to BLOCK (e.g. 1.2.3.4 / 1.2.3.0/24): ${C_RESET}")" block_ip
                [[ -z "$block_ip" ]] && continue
                if grep -qxF "$block_ip" "$IP_BLACKLIST_CONF" 2>/dev/null; then
                    echo -e "\n  ${C_YELLOW}⚠️  '$block_ip' is already blacklisted.${C_RESET}"
                else
                    echo "$block_ip" >> "$IP_BLACKLIST_CONF"
                    _apply_ip_rules
                    echo -e "\n  ${C_GREEN}✅ '$block_ip' blocked successfully.${C_RESET}"
                fi
                press_enter ;;
            2)
                if [[ ! -s "$IP_BLACKLIST_CONF" ]]; then
                    echo -e "\n  ${C_YELLOW}Blacklist is empty.${C_RESET}"; press_enter; continue; fi
                echo -e "\n  ${C_CYAN}Current Blacklist:${C_RESET}"
                while IFS= read -r ip; do
                    [[ -z "$ip" || "$ip" == \#* ]] && continue
                    echo -e "    ${C_RED}✖${C_RESET} $ip"
                done < "$IP_BLACKLIST_CONF"
                echo
                read -r -p "$(echo -e "  ${C_BLUE}👉 Enter IP to remove: ${C_RESET}")" rm_ip
                [[ -z "$rm_ip" ]] && continue
                sed -i "\#^${rm_ip}\$#d" "$IP_BLACKLIST_CONF" 2>/dev/null
                _apply_ip_rules
                echo -e "\n  ${C_GREEN}✅ '$rm_ip' removed from blacklist.${C_RESET}"
                press_enter ;;
            3)
                read -r -p "$(echo -e "  ${C_BLUE}👉 Enter IP or CIDR to WHITELIST: ${C_RESET}")" allow_ip
                [[ -z "$allow_ip" ]] && continue
                if grep -qxF "$allow_ip" "$IP_WHITELIST_CONF" 2>/dev/null; then
                    echo -e "\n  ${C_YELLOW}⚠️  '$allow_ip' is already whitelisted.${C_RESET}"
                else
                    echo "$allow_ip" >> "$IP_WHITELIST_CONF"
                    _apply_ip_rules
                    echo -e "\n  ${C_GREEN}✅ '$allow_ip' added to whitelist.${C_RESET}"
                fi
                press_enter ;;
            4)
                if [[ ! -s "$IP_WHITELIST_CONF" ]]; then
                    echo -e "\n  ${C_YELLOW}Whitelist is empty.${C_RESET}"; press_enter; continue; fi
                echo -e "\n  ${C_CYAN}Current Whitelist:${C_RESET}"
                while IFS= read -r ip; do
                    [[ -z "$ip" || "$ip" == \#* ]] && continue
                    echo -e "    ${C_GREEN}✔${C_RESET} $ip"
                done < "$IP_WHITELIST_CONF"
                echo
                read -r -p "$(echo -e "  ${C_BLUE}👉 Enter IP to remove: ${C_RESET}")" rm_wl
                [[ -z "$rm_wl" ]] && continue
                sed -i "\#^${rm_wl}\$#d" "$IP_WHITELIST_CONF" 2>/dev/null
                _apply_ip_rules
                echo -e "\n  ${C_GREEN}✅ '$rm_wl' removed from whitelist.${C_RESET}"
                press_enter ;;
            5)
                echo
                echo -e "  ${C_RED}━━ Blacklist (BLOCKED) ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
                if [[ -s "$IP_BLACKLIST_CONF" ]]; then
                    while IFS= read -r ip; do [[ -z "$ip" || "$ip" == \#* ]] && continue
                        echo -e "    ${C_RED}✖${C_RESET} $ip"; done < "$IP_BLACKLIST_CONF"
                else echo -e "    ${C_DIM}(empty)${C_RESET}"; fi
                echo
                echo -e "  ${C_GREEN}━━ Whitelist (ALWAYS ALLOWED) ━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
                if [[ -s "$IP_WHITELIST_CONF" ]]; then
                    while IFS= read -r ip; do [[ -z "$ip" || "$ip" == \#* ]] && continue
                        echo -e "    ${C_GREEN}✔${C_RESET} $ip"; done < "$IP_WHITELIST_CONF"
                else echo -e "    ${C_DIM}(empty)${C_RESET}"; fi
                echo
                echo -e "  ${C_CYAN}━━ Active iptables chain ($FF_IPTABLES_CHAIN) ━━━━━━━━━━━━${C_RESET}"
                iptables -L "$FF_IPTABLES_CHAIN" -n --line-numbers 2>/dev/null | while read -r line; do
                    echo "    $line"; done
                press_enter ;;
            6)
                _apply_ip_rules
                echo -e "\n  ${C_GREEN}✅ All IP rules re-applied.${C_RESET}"; press_enter ;;
            7)
                read -r -p "$(echo -e "  ${C_YELLOW}⚠️  Clear ALL rules? (y/n): ${C_RESET}")" flush_confirm
                if [[ "${flush_confirm,,}" == "y" ]]; then
                    iptables -F "$FF_IPTABLES_CHAIN" 2>/dev/null
                    > "$IP_BLACKLIST_CONF"; > "$IP_WHITELIST_CONF"
                    echo -e "\n  ${C_GREEN}✅ All IP rules flushed.${C_RESET}"
                fi
                press_enter ;;
            0) return ;;
            *) invalid_option ;;
        esac
    done
}

# ── PER-USER SPEED LIMITER MODULE ────────────────────────────────────────
USER_SPEED_CONF="/etc/firewallfalcon/user_speeds.conf"

_get_active_iface() {
    ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1
}

_setup_htb_root_if_needed() {
    local iface="$1"
    if ! tc qdisc show dev "$iface" 2>/dev/null | grep -q "htb"; then
        tc qdisc add dev "$iface" root handle 1: htb default 11 r2q 1 2>/dev/null
        tc class add dev "$iface" parent 1: classid 1:1 htb rate 1000mbit burst 100k 2>/dev/null
        tc class add dev "$iface" parent 1:1 classid 1:11 htb rate 1000mbit burst 100k 2>/dev/null
    fi
}

_apply_user_speed() {
    local username="$1" speed_mbps="$2" remove="${3:-0}"
    local uid; uid=$(id -u "$username" 2>/dev/null)
    [[ -z "$uid" ]] && return 1
    local iface; iface=$(_get_active_iface)
    [[ -z "$iface" ]] && return 1
    local mark=$uid
    # Remove existing rules for this user
    iptables -t mangle -D OUTPUT -m owner --uid-owner "$uid" -j MARK --set-mark "$mark" 2>/dev/null
    tc filter del dev "$iface" parent 1: handle "$mark" fw 2>/dev/null
    tc class del dev "$iface" classid "1:$mark" 2>/dev/null
    [[ "$remove" == "1" ]] && return 0
    # Apply new limit
    _setup_htb_root_if_needed "$iface"
    local rate_kbit=$(( speed_mbps * 1024 ))
    local burst_kbit=$(( speed_mbps * 1024 / 8 ))
    [[ "$burst_kbit" -lt 1600 ]] && burst_kbit=1600
    tc class add dev "$iface" parent 1:1 classid "1:$mark" htb rate "${rate_kbit}kbit" burst "${burst_kbit}k" 2>/dev/null
    tc filter add dev "$iface" parent 1: protocol ip handle "$mark" fw flowid "1:$mark" 2>/dev/null
    iptables -t mangle -A OUTPUT -m owner --uid-owner "$uid" -j MARK --set-mark "$mark" 2>/dev/null
}

_apply_all_user_speeds() {
    [[ ! -s "$USER_SPEED_CONF" ]] && return
    while IFS=: read -r u spd; do
        [[ -z "$u" || -z "$spd" || "$u" == \#* ]] && continue
        _apply_user_speed "$u" "$spd"
    done < "$USER_SPEED_CONF"
}

user_speed_menu() {
    while true; do
        clear; show_banner
        echo
        menu_section "PER-USER SPEED LIMITER" "$C_TITLE"
        echo
        mkdir -p "/etc/firewallfalcon" 2>/dev/null
        local iface; iface=$(_get_active_iface)
        echo -e "  ${C_CYAN}Active Interface:${C_RESET} ${C_YELLOW}${iface:-unknown}${C_RESET}"
        echo
        local has_limits=false
        if [[ -s "$USER_SPEED_CONF" ]]; then
            echo -e "  ${C_BOLD}${C_CYAN}$(printf '%-22s' 'Username')Speed Limit${C_RESET}"
            echo -e "  ${C_DIM}$(printf '%.0s─' {1..34})${C_RESET}"
            while IFS=: read -r u spd; do
                [[ -z "$u" || "$u" == \#* ]] && continue
                has_limits=true
                printf "  ${C_WHITE}%-22s${C_RESET} ${C_YELLOW}%s Mbps${C_RESET}\n" "$u" "$spd"
            done < "$USER_SPEED_CONF"
            echo
        fi
        $has_limits || echo -e "  ${C_DIM}No per-user speed limits configured.${C_RESET}\n"
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[1]" "Set Speed Limit for a User"
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[2]" "Remove Speed Limit from a User"
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[3]" "Re-Apply All User Speeds (after reboot)"
        printf "  ${C_DANGER}%-4s${C_RESET} %s\n" "[4]" "Remove ALL Per-User Speed Limits"
        echo
        printf "  ${C_DANGER}%-4s${C_RESET} %s\n" "[0]" "Return"
        echo
        if ! read -r -p "$(echo -e ${C_PROMPT}"> Select an option: "${C_RESET})" us_act; then return; fi
        case "$us_act" in
            1)
                read -r -p "$(echo -e "  ${C_BLUE}👉 Enter username: ${C_RESET}")" tgt_user
                [[ -z "$tgt_user" ]] && continue
                if ! id "$tgt_user" &>/dev/null; then
                    echo -e "\n  ${C_RED}❌ User '$tgt_user' not found.${C_RESET}"; press_enter; continue; fi
                read -r -p "$(echo -e "  ${C_BLUE}👉 Enter speed limit in Mbps (e.g. 5, 10, 25): ${C_RESET}")" tgt_speed
                if [[ ! "$tgt_speed" =~ ^[0-9]+$ || "$tgt_speed" -lt 1 ]]; then
                    echo -e "\n  ${C_RED}❌ Invalid speed. Must be a positive integer.${C_RESET}"; press_enter; continue; fi
                sed -i "/^${tgt_user}:/d" "$USER_SPEED_CONF" 2>/dev/null
                echo "${tgt_user}:${tgt_speed}" >> "$USER_SPEED_CONF"
                _apply_user_speed "$tgt_user" "$tgt_speed"
                echo -e "\n  ${C_GREEN}✅ Speed limit set to ${tgt_speed} Mbps for '${tgt_user}'.${C_RESET}"
                press_enter ;;
            2)
                read -r -p "$(echo -e "  ${C_BLUE}👉 Enter username to remove limit: ${C_RESET}")" rm_user
                [[ -z "$rm_user" ]] && continue
                sed -i "/^${rm_user}:/d" "$USER_SPEED_CONF" 2>/dev/null
                _apply_user_speed "$rm_user" 0 1
                echo -e "\n  ${C_GREEN}✅ Speed limit removed for '${rm_user}' (Unlimited).${C_RESET}"
                press_enter ;;
            3)
                _apply_all_user_speeds
                echo -e "\n  ${C_GREEN}✅ All per-user speed limits re-applied.${C_RESET}"; press_enter ;;
            4)
                read -r -p "$(echo -e "  ${C_YELLOW}⚠️  Remove ALL per-user speed limits? (y/n): ${C_RESET}")" flush_us
                if [[ "${flush_us,,}" == "y" ]]; then
                    if [[ -s "$USER_SPEED_CONF" ]]; then
                        while IFS=: read -r u _; do
                            [[ -z "$u" || "$u" == \#* ]] && continue
                            _apply_user_speed "$u" 0 1
                        done < "$USER_SPEED_CONF"
                    fi
                    > "$USER_SPEED_CONF"
                    echo -e "\n  ${C_GREEN}✅ All per-user speed limits removed.${C_RESET}"
                fi
                press_enter ;;
            0) return ;;
            *) invalid_option ;;
        esac
    done
}

# ── CONNECTION LOGS MODULE ────────────────────────────────────────────────
connection_logs_menu() {
    while true; do
        clear; show_banner
        echo
        menu_section "CONNECTION LOGS & EXPORT" "$C_TITLE"
        echo
        # Quick stats
        local online_now; online_now=$(who 2>/dev/null | wc -l)
        local last_count; last_count=$(last -n 1 -a 2>/dev/null | grep -cv "^$\|wtmp" || echo 0)
        echo -e "  ${C_CYAN}Currently Online :${C_RESET} ${C_GREEN}${online_now}${C_RESET}"
        echo -e "  ${C_CYAN}Last Login       :${C_RESET} ${C_YELLOW}$(last -n 1 -a 2>/dev/null | head -1 | awk '{print $1, $4, $5, $6}')${C_RESET}"
        echo
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[1]" "View Last 30 Connections (all users)"
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[2]" "View Failed Login Attempts"
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[3]" "Export Logs for a Specific User"
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[4]" "Export Full Log (all users)"
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[5]" "View Currently Logged-In Users"
        echo
        printf "  ${C_DANGER}%-4s${C_RESET} %s\n" "[0]" "Return"
        echo
        if ! read -r -p "$(echo -e ${C_PROMPT}"> Select an option: "${C_RESET})" cl_act; then return; fi
        case "$cl_act" in
            1)
                clear; show_banner; echo
                menu_section "LAST 30 CONNECTIONS" "$C_CYAN"
                echo
                last -n 30 -a 2>/dev/null | while read -r line; do
                    if echo "$line" | grep -q "still logged in"; then
                        echo -e "  ${C_GREEN}${line}${C_RESET}"
                    elif echo "$line" | grep -q "gone"; then
                        echo -e "  ${C_DIM}${line}${C_RESET}"
                    else
                        echo "  $line"
                    fi
                done
                press_enter ;;
            2)
                clear; show_banner; echo
                menu_section "FAILED LOGIN ATTEMPTS" "$C_DANGER"
                echo
                local fail_out; fail_out=$(lastb -n 30 2>/dev/null | head -30)
                if [[ -n "$fail_out" && ! "$fail_out" == *"command not found"* ]]; then
                    echo "$fail_out" | while read -r line; do
                        echo -e "  ${C_RED}${line}${C_RESET}"; done
                else
                    echo -e "  ${C_CYAN}Fetching from journalctl...${C_RESET}"
                    journalctl -u ssh -u sshd --since "72 hours ago" 2>/dev/null \
                        | grep -iE "Failed|Invalid|error" | tail -30 \
                        | while read -r line; do echo -e "  ${C_RED}${line}${C_RESET}"; done
                fi
                press_enter ;;
            3)
                read -r -p "$(echo -e "  ${C_BLUE}👉 Enter username: ${C_RESET}")" log_user
                [[ -z "$log_user" ]] && continue
                local export_file="/root/ff_log_${log_user}_$(date +%F).log"
                {
                    echo "──────────────────────────────────────────────────"
                    echo "  DAHOOM — Connection Log"
                    echo "  User    : $log_user"
                    echo "  Date    : $(date)"
                    echo "──────────────────────────────────────────────────"
                    echo
                    echo "── SSH Login History ──────────────────────────────"
                    last "$log_user" -a 2>/dev/null || echo "(no data)"
                    echo
                    echo "── Failed Attempts ────────────────────────────────"
                    lastb "$log_user" 2>/dev/null | head -20 || echo "(no data)"
                    echo
                    echo "── journalctl (last 72h) ──────────────────────────"
                    journalctl -u ssh -u sshd --since "72 hours ago" 2>/dev/null \
                        | grep "$log_user" | head -40 || echo "(no data)"
                } > "$export_file"
                echo -e "\n  ${C_GREEN}✅ Exported to: ${C_YELLOW}${export_file}${C_RESET}"
                press_enter ;;
            4)
                local export_file="/root/ff_log_all_$(date +%F_%H%M).log"
                {
                    echo "──────────────────────────────────────────────────"
                    echo "  DAHOOM — Full Connection Log"
                    echo "  Date: $(date)"
                    echo "──────────────────────────────────────────────────"
                    echo
                    echo "── Currently Online ───────────────────────────────"
                    who -a 2>/dev/null
                    echo
                    echo "── Last 100 Logins ────────────────────────────────"
                    last -n 100 -a 2>/dev/null
                    echo
                    echo "── Last 50 Failed Attempts ────────────────────────"
                    lastb -n 50 2>/dev/null || echo "(lastb not available)"
                    echo
                    echo "── Managed Users Connection Summary ───────────────"
                    if [[ -s "$DB_FILE" ]]; then
                        while IFS=: read -r u _rest; do
                            [[ -z "$u" || "$u" == \#* ]] && continue
                            local last_login; last_login=$(last "$u" -n 1 -a 2>/dev/null | head -1)
                            printf "  %-20s %s\n" "$u" "${last_login:-(never)}"
                        done < "$DB_FILE"
                    fi
                } > "$export_file"
                echo -e "\n  ${C_GREEN}✅ Exported to: ${C_YELLOW}${export_file}${C_RESET}"
                press_enter ;;
            5)
                clear; show_banner; echo
                menu_section "CURRENTLY LOGGED-IN USERS" "$C_CYAN"
                echo
                printf "  ${C_BOLD}${C_CYAN}%-16s %-8s %-16s %-16s %s${C_RESET}\n" \
                    "User" "TTY" "From" "Login@" "Idle"
                echo -e "  ${C_DIM}$(printf '%.0s─' {1..70})${C_RESET}"
                who -u 2>/dev/null | while read -r w_user w_tty w_date w_time w_idle w_pid w_from; do
                    local w_ip="${w_from//[()]/}"
                    printf "  ${C_WHITE}%-16s${C_RESET} %-8s ${C_CYAN}%-16s${C_RESET} ${C_YELLOW}%-16s${C_RESET} %s\n" \
                        "$w_user" "$w_tty" "${w_ip:-(local)}" "${w_date} ${w_time}" "${w_idle:-.}"
                done
                echo
                press_enter ;;
            0) return ;;
            *) invalid_option ;;
        esac
    done
}

# ── LIVE SESSION MONITOR MODULE ───────────────────────────────────────────
live_session_monitor() {
    local auto_refresh=5   # seconds between auto-refreshes

    # Force cache invalidation so we always see fresh data
    SSH_SESSION_CACHE_TS=0

    while true; do
        clear; show_banner
        echo
        menu_section "LIVE SESSION MONITOR" "$C_TITLE"
        echo

        # ── Force fresh session data ──────────────────────────────────────
        SSH_SESSION_CACHE_TS=0
        refresh_ssh_session_cache

        local now_ts; printf -v now_ts '%(%s)T' -1
        local total_online="$SSH_SESSION_TOTAL"
        local total_managed; total_managed=$(wc -l < "$DB_FILE" 2>/dev/null || echo 0)

        echo -e "  ${C_CYAN}Online Users  :${C_RESET} ${C_GREEN}${total_online}${C_RESET}  ${C_DIM}|  Total Accounts: ${C_WHITE}${total_managed}${C_RESET}"
        echo -e "  ${C_CYAN}Refresh Every :${C_RESET} ${C_YELLOW}${auto_refresh}s${C_RESET}   ${C_DIM}|  $(date '+%H:%M:%S')${C_RESET}"
        echo

        # ── Header row ────────────────────────────────────────────────────
        printf "  ${C_BOLD}${C_CYAN}%-18s %-20s %-10s %-8s %-10s${C_RESET}\n" \
            "Username" "Remote IP" "Login Time" "Duration" "Sessions"
        echo -e "  ${C_DIM}$(printf '%.0s─' {1..66})${C_RESET}"

        # ── Collect who output into map: user → "ip logintime" ───────────
        local -A who_ip=()
        local -A who_time=()

        # Parse `who` output: user pts/X date time (ip)
        while read -r w_user w_tty w_date w_time w_ip_raw; do
            # Strip parentheses from IP
            local w_ip="${w_ip_raw//[()]/}"
            [[ -z "$w_ip" ]] && w_ip="${w_tty}"   # fallback to tty if no IP
            local w_login="${w_date} ${w_time}"
            # Map user → first IP seen (may have multiple entries)
            [[ -z "${who_ip[$w_user]}" ]] && who_ip["$w_user"]="$w_ip"
            [[ -z "${who_time[$w_user]}" ]] && who_time["$w_user"]="$w_login"
        done < <(who 2>/dev/null)

        # ── Display each managed user that has sessions ───────────────────
        local found_any=false
        local -a online_users=()

        while IFS=: read -r u _rest; do
            [[ -z "$u" || "$u" == \#* ]] && continue
            local sess_count="${SSH_SESSION_COUNTS[$u]:-0}"
            (( sess_count > 0 )) || continue
            online_users+=("$u")
        done < "$DB_FILE"

        if [[ ${#online_users[@]} -eq 0 ]]; then
            echo -e "\n  ${C_DIM}No users currently connected.${C_RESET}"
        else
            found_any=true
            for u in "${online_users[@]}"; do
                local sess_count="${SSH_SESSION_COUNTS[$u]:-0}"
                local ip="${who_ip[$u]:-Unknown}"
                local login_t="${who_time[$u]:-—}"

                # Calculate duration from /proc/PID/stat start time
                local duration="—"
                local pids="${SSH_SESSION_PIDS[$u]:-}"
                local first_pid; first_pid=$(echo "$pids" | awk '{print $1}')
                if [[ -n "$first_pid" && -f "/proc/$first_pid/stat" ]]; then
                    local proc_start clk_tck up_s start_s elapsed_s
                    proc_start=$(awk '{print $22}' "/proc/$first_pid/stat" 2>/dev/null)
                    clk_tck=$(getconf CLK_TCK 2>/dev/null || echo 100)
                    up_s=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo 0)
                    if [[ -n "$proc_start" && -n "$up_s" ]]; then
                        start_s=$(( now_ts - up_s + proc_start / clk_tck ))
                        elapsed_s=$(( now_ts - start_s ))
                        if (( elapsed_s >= 3600 )); then
                            duration="$(( elapsed_s/3600 ))h$(( (elapsed_s%3600)/60 ))m"
                        elif (( elapsed_s >= 60 )); then
                            duration="$(( elapsed_s/60 ))m$(( elapsed_s%60 ))s"
                        else
                            duration="${elapsed_s}s"
                        fi
                    fi
                fi

                # Colour code: green = 1 session, yellow = 2, red = 3+
                local sess_color="$C_GREEN"
                (( sess_count == 2 )) && sess_color="$C_YELLOW"
                (( sess_count >= 3 )) && sess_color="$C_RED"

                printf "  ${C_WHITE}%-18s${C_RESET} ${C_CYAN}%-20s${C_RESET} %-10s ${C_YELLOW}%-8s${C_RESET} ${sess_color}%-10s${C_RESET}\n" \
                    "$u" "$ip" "$(echo "$login_t" | awk '{print $2}')" "$duration" "$sess_count"
            done
        fi

        echo -e "\n  ${C_DIM}$(printf '%.0s─' {1..66})${C_RESET}"
        echo
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[k]" "Kick a User (disconnect)"
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[r]" "Refresh Now"
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[5]" "Set Refresh Interval (current: ${auto_refresh}s)"
        echo
        printf "  ${C_DANGER}%-4s${C_RESET} %s\n" "[0]" "Return"
        echo

        # ── Non-blocking read with timeout = auto_refresh ─────────────────
        local lsm_choice=""
        if read -r -t "$auto_refresh" -p "$(echo -e "${C_PROMPT}> Select an option (auto-refresh in ${auto_refresh}s): ${C_RESET}")" lsm_choice 2>/dev/null; then
            : # got input
        else
            lsm_choice=""  # timeout → auto refresh
        fi

        case "${lsm_choice,,}" in
            k)
                # ── Kick user ──────────────────────────────────────────────
                if [[ ${#online_users[@]} -eq 0 ]]; then
                    echo -e "\n  ${C_YELLOW}No online users to kick.${C_RESET}"
                    sleep 1.5
                    continue
                fi
                echo
                echo -e "  ${C_CYAN}Online users:${C_RESET} ${online_users[*]}"
                read -r -p "$(echo -e "  ${C_BLUE}👉 Enter username to kick: ${C_RESET}")" kick_user
                if [[ -z "$kick_user" ]]; then
                    continue
                fi
                local kick_pids="${SSH_SESSION_PIDS[$kick_user]:-}"
                if [[ -z "$kick_pids" ]]; then
                    echo -e "\n  ${C_RED}❌ User '$kick_user' not found or has no active sessions.${C_RESET}"
                    sleep 1.5
                    continue
                fi
                read -r -p "$(echo -e "  ${C_YELLOW}⚠️  Disconnect all sessions for '${kick_user}'? (y/n): ${C_RESET}")" kick_confirm
                if [[ "${kick_confirm,,}" == "y" ]]; then
                    local kicked=0
                    for kpid in $kick_pids; do
                        if kill -HUP "$kpid" 2>/dev/null; then
                            (( kicked++ ))
                        fi
                    done
                    echo -e "\n  ${C_GREEN}✅ Kicked ${kicked} session(s) for '${kick_user}'.${C_RESET}"
                    SSH_SESSION_CACHE_TS=0
                    sleep 1.5
                fi
                ;;
            r|"")
                # refresh — loop continues
                ;;
            5)
                read -r -p "$(echo -e "  ${C_BLUE}👉 Enter new refresh interval in seconds [5]: ${C_RESET}")" new_interval
                new_interval="${new_interval:-5}"
                if [[ "$new_interval" =~ ^[0-9]+$ && "$new_interval" -ge 1 ]]; then
                    auto_refresh="$new_interval"
                fi
                ;;
            0)
                return
                ;;
            *)
                # Unknown — just refresh
                ;;
        esac
    done
}

# ── SPEED LIMITER MODULE ──────────────────────────────────────────────
SPEED_LIMIT_CONF="/etc/firewallfalcon/speed_limiter.conf"

# ── ADVANCED LOGS HUB MODULE ──────────────────────────────────────────────
_show_log_file() {
    local fpath="$1" title="$2"
    clear; show_banner; echo
    menu_section "$title" "$C_TITLE"
    echo
    if [[ ! -s "$fpath" ]]; then
        echo -e "  ${C_DIM}(No log entries recorded yet in ${fpath})${C_RESET}"
    else
        read -r -p "$(echo -e "${C_BLUE}👉 Enter search filter (or press Enter to view all): ${C_RESET}")" s_term
        echo
        if [[ -n "$s_term" ]]; then
            grep -i "$s_term" "$fpath" 2>/dev/null | tail -n 50
        else
            tail -n 50 "$fpath" 2>/dev/null
        fi
    fi
    echo
    press_enter
}

advanced_logs_menu() {
    mkdir -p "$LOGS_DIR" 2>/dev/null
    for lf in admin_audit.log client_connections.log service_health.log security_alerts.log reseller_audit.log; do
        [[ -f "$LOGS_DIR/$lf" ]] || touch "$LOGS_DIR/$lf" 2>/dev/null
    done
    while true; do
        clear; show_banner
        echo
        menu_section "ADVANCED LOGS & HEALTH HUB" "$C_TITLE"
        echo
        local admin_cnt client_cnt service_cnt sec_cnt res_cnt
        admin_cnt=$(wc -l < "$LOGS_DIR/admin_audit.log" 2>/dev/null || echo 0)
        client_cnt=$(wc -l < "$LOGS_DIR/client_connections.log" 2>/dev/null || echo 0)
        service_cnt=$(wc -l < "$LOGS_DIR/service_health.log" 2>/dev/null || echo 0)
        sec_cnt=$(wc -l < "$LOGS_DIR/security_alerts.log" 2>/dev/null || echo 0)
        res_cnt=$(wc -l < "$LOGS_DIR/reseller_audit.log" 2>/dev/null || echo 0)

        echo -e "  ${C_DIM}Dir: ${C_YELLOW}${LOGS_DIR}${C_RESET} | ${C_DIM}Admin:${C_GREEN}${admin_cnt}${C_RESET} ${C_DIM}Clients:${C_GREEN}${client_cnt}${C_RESET} ${C_DIM}Services:${C_YELLOW}${service_cnt}${C_RESET} ${C_DIM}Security:${C_RED}${sec_cnt}${C_RESET} ${C_DIM}Resellers:${C_CYAN}${res_cnt}${C_RESET}"
        echo
        printf "  ${C_CHOICE}%-4s${C_RESET} %-23s ${C_CHOICE}%-4s${C_RESET} %s\n" "[1]" "Admin Audit Logs" "[2]" "Client Connections"
        printf "  ${C_CHOICE}%-4s${C_RESET} %-23s ${C_CHOICE}%-4s${C_RESET} %s\n" "[3]" "Service Health Logs" "[4]" "Security Alerts Logs"
        printf "  ${C_CHOICE}%-4s${C_RESET} %-23s ${C_CHOICE}%-4s${C_RESET} %s\n" "[5]" "Reseller Audit Logs" "[6]" "Live Log Stream"
        printf "  ${C_CHOICE}%-4s${C_RESET} %-23s\n" "[7]" "Rotate / Clear Logs"
        echo
        printf "  ${C_DANGER}%-4s${C_RESET} %s\n" "[0]" "Return"
        echo
        if ! read -r -p "$(echo -e ${C_PROMPT}"> Select an option: "${C_RESET})" log_opt; then
            return
        fi
        case "$log_opt" in
            1) _show_log_file "$LOGS_DIR/admin_audit.log" "ADMIN AUDIT LOGS" ;;
            2) _show_log_file "$LOGS_DIR/client_connections.log" "CLIENT CONNECTION LOGS" ;;
            3) _show_log_file "$LOGS_DIR/service_health.log" "SERVICE HEALTH LOGS" ;;
            4) _show_log_file "$LOGS_DIR/security_alerts.log" "SECURITY ALERTS LOGS" ;;
            5) _show_log_file "$LOGS_DIR/reseller_audit.log" "RESELLER AUDIT LOGS" ;;
            6)
                clear; show_banner; echo
                menu_section "LIVE LOG TAIL (Press Ctrl+C to stop)" "$C_TITLE"
                echo
                tail -n 30 -f "$LOGS_DIR"/*.log 2>/dev/null || press_enter
                ;;
            7)
                clear; show_banner; echo
                read -r -p "$(echo -e "${C_DANGER}⚠️ Clear all log files in ${LOGS_DIR}? (y/n): ${C_RESET}")" confirm_clean
                if [[ "${confirm_clean,,}" == "y" ]]; then
                    rm -f "$LOGS_DIR"/*.log 2>/dev/null
                    echo -e "\n  ${C_GREEN}✅ All log files cleared successfully.${C_RESET}"
                    press_enter
                fi
                ;;
            0) return ;;
            *) invalid_option ;;
        esac
    done
}

speed_limiter_menu() {
    while true; do
        clear; show_banner
        echo
        menu_section "SPEED LIMITER & TRAFFIC SHAPING" "$C_TITLE"
        echo
        local iface; iface=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
        local cur_limit="Unlimited"
        if [ -f "$SPEED_LIMIT_CONF" ]; then
            source "$SPEED_LIMIT_CONF" 2>/dev/null
            cur_limit="${GLOBAL_SPEED_LIMIT:-Unlimited} Mbps"
        fi

        echo -e "  ${C_CYAN}Active Interface:${C_RESET} ${C_YELLOW}${iface}${C_RESET}"
        echo -e "  ${C_CYAN}Global Limit    :${C_RESET} ${C_GREEN}${cur_limit}${C_RESET}"
        echo
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[1]" "Set Global Speed Limit (Mbps)"
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[2]" "Remove Speed Limit (Unlimited)"
        echo
        printf "  ${C_DANGER}%-4s${C_RESET} %s\n" "[0]" "Return"
        echo
        if ! read -r -p "$(echo -e ${C_PROMPT}"> Select an option: "${C_RESET})" sl_act; then
            return
        fi
        case "$sl_act" in
            1)
                read -r -p "$(echo -e "${C_BLUE}👉 Enter Max Speed in Mbps (e.g. 10, 20, 50): ${C_RESET}")" mbps
                if [[ "$mbps" =~ ^[0-9]+$ && "$mbps" -gt 0 ]]; then
                    mkdir -p "/etc/firewallfalcon" 2>/dev/null
                    echo "GLOBAL_SPEED_LIMIT=\"$mbps\"" > "$SPEED_LIMIT_CONF"
                    if command -v tc &>/dev/null; then
                        # Remove existing rules cleanly
                        tc qdisc del dev "$iface" root 2>/dev/null
                        # r2q=1 prevents "quantum too big" warnings for low/high rates
                        local rate_kbit=$(( mbps * 1024 ))
                        local burst_kbit=$(( mbps * 1024 / 8 ))
                        [[ "$burst_kbit" -lt 1600 ]] && burst_kbit=1600   # minimum burst 1600 bytes
                        tc qdisc add dev "$iface" root handle 1: htb default 11 r2q 1 2>/dev/null
                        tc class add dev "$iface" parent 1: classid 1:1 htb rate "${rate_kbit}kbit" burst "${burst_kbit}k" 2>/dev/null
                        tc class add dev "$iface" parent 1:1 classid 1:11 htb rate "${rate_kbit}kbit" burst "${burst_kbit}k" 2>/dev/null
                    fi
                    echo -e "\n${C_GREEN}✅ Global speed limit set to ${mbps} Mbps on interface $iface.${C_RESET}"
                fi
                press_enter
                ;;
            2)
                rm -f "$SPEED_LIMIT_CONF"
                if command -v tc &>/dev/null; then
                    tc qdisc del dev "$iface" root 2>/dev/null
                fi
                echo -e "\n${C_GREEN}✅ Speed limit removed (Unlimited).${C_RESET}"
                press_enter
                ;;
            0) return ;;
            *) invalid_option ;;
        esac
    done
}

protocol_menu() {
    local badvpn_status udp_custom_status zivpn_status ssl_tunnel_status dnstt_status falconproxy_status nginx_status panel_3xui_status panel_xui_status vless_status
    while true; do
        show_banner

        # Fast in-memory process & status check (0ms)
        if pgrep -x badvpn-udpgw &>/dev/null; then
            badvpn_status="${C_STATUS_A}(Active)${C_RESET}"
        else
            badvpn_status="${C_STATUS_I}(Inactive)${C_RESET}"
        fi

        if pgrep -x udp-custom &>/dev/null; then
            udp_custom_status="${C_STATUS_A}(Active)${C_RESET}"
        else
            udp_custom_status="${C_STATUS_I}(Inactive)${C_RESET}"
        fi

        if pgrep -x zivpn &>/dev/null; then
            zivpn_status="${C_STATUS_A}(Active)${C_RESET}"
        else
            zivpn_status="${C_STATUS_I}(Inactive)${C_RESET}"
        fi

        if pgrep -x haproxy &>/dev/null; then
            ssl_tunnel_status="${C_STATUS_A}(Active)${C_RESET}"
        else
            ssl_tunnel_status="${C_STATUS_I}(Inactive)${C_RESET}"
        fi

        if pgrep -f dnstt-server &>/dev/null; then
            dnstt_status="${C_STATUS_A}(Active)${C_RESET}"
        else
            dnstt_status="${C_STATUS_I}(Inactive)${C_RESET}"
        fi

        if pgrep -f falconproxy &>/dev/null; then
            if [ -f "$FALCONPROXY_CONFIG_FILE" ]; then source "$FALCONPROXY_CONFIG_FILE" 2>/dev/null; fi
            falconproxy_status="${C_STATUS_A}(Active - ${INSTALLED_VERSION:-latest})${C_RESET}"
        else
            falconproxy_status="${C_STATUS_I}(Inactive)${C_RESET}"
        fi

        if pgrep -x nginx &>/dev/null; then
            nginx_status="${C_STATUS_A}(Active)${C_RESET}"
        else
            nginx_status="${C_STATUS_I}(Inactive)${C_RESET}"
        fi

        local active_xui_variant; active_xui_variant=$(get_xui_installed_variant)
        panel_xui_status=$(get_panel_status "x-ui")

        if pgrep -x xray &>/dev/null || pgrep -f "/usr/local/bin/xray" &>/dev/null; then
            vless_status="${C_STATUS_A}(Active)${C_RESET}"
        elif [[ -x "/usr/local/bin/xray" || -f "/etc/systemd/system/xray.service" ]]; then
            vless_status="${C_STATUS_A}(Installed)${C_RESET}"
        else
            vless_status="${C_STATUS_I}(Not Installed)${C_RESET}"
        fi

        echo
        menu_section "PROTOCOL & PANEL MANAGEMENT" "$C_TITLE"
        echo -e "    ${C_ACCENT}--- TUNNELLING PROTOCOLS ---${C_RESET}"
        printf "    ${C_CHOICE}%-4s${C_RESET} %-24s %s\n" "[1]" "BadVPN UDP" "$badvpn_status"
        printf "    ${C_CHOICE}%-4s${C_RESET} %-24s %s\n" "[2]" "UDP Custom" "$udp_custom_status"
        printf "    ${C_CHOICE}%-4s${C_RESET} %-24s %s\n" "[3]" "HAProxy Edge" "$ssl_tunnel_status"
        printf "    ${C_CHOICE}%-4s${C_RESET} %-24s %s\n" "[4]" "DNSTT SlowDNS" "$dnstt_status"
        printf "    ${C_CHOICE}%-4s${C_RESET} %-24s %s\n" "[5]" "Falcon Proxy" "$falconproxy_status"
        printf "    ${C_CHOICE}%-4s${C_RESET} %-24s %s\n" "[6]" "Nginx Proxy" "$nginx_status"
        printf "    ${C_CHOICE}%-4s${C_RESET} %-24s %s\n" "[7]" "ZiVPN UDP" "$zivpn_status"
        printf "    ${C_CHOICE}%-4s${C_RESET} %-24s %s\n" "[10]" "VLESS REALITY" "$vless_status"
        echo -e "    ${C_ACCENT}--- MANAGEMENT PANELS ---${C_RESET}"
        printf "    ${C_CHOICE}%-4s${C_RESET} %-24s %s\n" "[8]" "X-UI Panel" "$panel_xui_status"
        echo
        printf "    ${C_WARN}%-4s${C_RESET} %s\n" "[0]" "Return"
        echo
        if ! read -r -p "$(echo -e ${C_PROMPT}"> Select a service: "${C_RESET})" choice; then
            echo
            return
        fi
        case $choice in
            1) service_action_menu "BadVPN UDP" "$badvpn_status" install_badvpn uninstall_badvpn "badvpn" "Install BadVPN" "Uninstall BadVPN" ;;
            2) service_action_menu "UDP Custom" "$udp_custom_status" install_udp_custom uninstall_udp_custom "udp-custom" "Install UDP Custom" "Uninstall UDP Custom" ;;
            3) service_action_menu "HAProxy Edge" "$ssl_tunnel_status" install_ssl_tunnel uninstall_ssl_tunnel "haproxy" "Install HAProxy Edge" "Uninstall HAProxy Edge" ;;
            4) service_action_menu "DNSTT SlowDNS" "$dnstt_status" install_dnstt uninstall_dnstt "dnstt" "Install DNSTT" "Uninstall DNSTT" ;;
            5) service_action_menu "Falcon Proxy" "$falconproxy_status" install_falcon_proxy uninstall_falcon_proxy "falconproxy" "Install Falcon Proxy" "Uninstall Falcon Proxy" ;;
            6) service_action_menu "Nginx Proxy" "$nginx_status" nginx_proxy_menu purge_nginx "nginx" "Install Nginx Proxy" "Uninstall / Purge Nginx" ;;
            7) service_action_menu "ZiVPN UDP" "$zivpn_status" install_zivpn uninstall_zivpn "zivpn" "Install ZiVPN" "Uninstall ZiVPN" ;;
            10) vless_reality_menu ;;
            8|9) xui_panel_management_menu "X-UI Panel" ;;
            0) return ;;
            *) invalid_option ;;
        esac
    done
}


# ====================================================================
# --- Web Control Panel Functions ---
# ====================================================================

generate_autologin_link_sh() {
    local ip="$1"
    local port="${2:-44380}"
    local secret="$3"
    local username="${4:-admin}"
    
    python3 -c "
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
tokens[token] = {
    'username': '$username',
    'role': 'admin',
    'created_at': now,
    'expires_at': now + 3600
}

try:
    with open(autologin_file, 'w', encoding='utf-8') as f:
        json.dump(tokens, f)
except Exception:
    pass

secret_val = '$secret'.strip().lstrip('/')
secret_path = f'/{secret_val}' if secret_val else ''
print(f'http://$ip:$port{secret_path}?auth={token}')
" 2>/dev/null || echo ""
}

install_web_panel() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🌐 Installing Web Control Panel ---${C_RESET}"
    
    if [ -f "$PANEL_SERVICE_FILE" ]; then
        echo -e "\n${C_YELLOW}ℹ️ Web Panel is already installed.${C_RESET}"
        show_panel_credentials
        return
    fi
    
    # Check Python 3
    if ! command -v python3 &>/dev/null; then
        echo -e "${C_RED}❌ Python 3 is required but not installed.${C_RESET}"
        echo -e "${C_YELLOW}Installing python3...${C_RESET}"
        ff_pkg_install python3 || { echo -e "${C_RED}❌ Failed to install python3.${C_RESET}"; return; }
    fi
    
    echo -e "${C_BLUE}🔎 Checking if port $PANEL_PORT is available...${C_RESET}"
    check_and_free_ports "$PANEL_PORT" || return
    check_and_open_firewall_port "$PANEL_PORT" tcp || return
    
    # Generate random credentials and secret URL path
    local panel_user
    panel_user=$(tr -dc 'a-z' < /dev/urandom | head -c 4)$(tr -dc '0-9' < /dev/urandom | head -c 4)
    local panel_pass
    panel_pass=$(tr -dc 'A-Za-z0-9@#$' < /dev/urandom | head -c 16)
    local panel_pass_hash
    panel_pass_hash=$(echo -n "$panel_pass" | sha256sum | awk '{print $1}')
    local panel_secret
    panel_secret="panel_$(tr -dc 'a-z0-9' < /dev/urandom | head -c 8)"
    
    echo -e "${C_BLUE}📥 Downloading panel files...${C_RESET}"
    mkdir -p "$PANEL_HTML_DIR"
    
    # Download backend & helpers
    _fm_panel_file panel.py "$PANEL_SCRIPT"
    if [ $? -ne 0 ] || [ ! -s "$PANEL_SCRIPT" ]; then
        echo -e "${C_RED}❌ Failed to download panel backend.${C_RESET}"
        return
    fi
    cp -f "$PANEL_SCRIPT" "$PANEL_HTML_DIR/panel.py" 2>/dev/null || true
    ln -sf "$PANEL_SCRIPT" /usr/local/bin/panel.py 2>/dev/null || true
    chmod +x "$PANEL_SCRIPT" "$PANEL_HTML_DIR/panel.py" 2>/dev/null || true
    sed -i 's/\r$//' "$PANEL_SCRIPT" 2>/dev/null || true
    
    # Download frontend templates
    _fm_panel_file index.html "$PANEL_HTML_FILE"
    _fm_panel_file reseller.html "$PANEL_HTML_DIR/reseller.html" 2>/dev/null || true
    if [ $? -ne 0 ] || [ ! -s "$PANEL_HTML_FILE" ]; then
        echo -e "${C_RED}❌ Failed to download panel frontend.${C_RESET}"
        return
    fi
    
    # Save credentials
    cat > "$PANEL_CONF" <<-PEOF
PANEL_USER="$panel_user"
PANEL_PASS_HASH="$panel_pass_hash"
PANEL_PASS_PLAIN="$panel_pass"
PANEL_SECRET="$panel_secret"
PANEL_NAME="DAHOOM"
PANEL_LOGO="👑"
PANEL_PORT="$PANEL_PORT"
PEOF
    chmod 600 "$PANEL_CONF"
    
    # Create systemd service
    cat > "$PANEL_SERVICE_FILE" <<-SEOF
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
SEOF
    
    systemctl daemon-reload
    systemctl enable firewallfalcon-panel &>/dev/null
    systemctl start firewallfalcon-panel &>/dev/null
    sleep 2
    
    if systemctl is-active --quiet firewallfalcon-panel; then
        local server_ip autologin_link
        server_ip="${GLOBAL_SERVER_IPV4:-$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')}"
        [[ -z "$server_ip" ]] && server_ip="YOUR_SERVER_IP"
        autologin_link=$(generate_autologin_link_sh "$server_ip" "${PANEL_PORT}" "${panel_secret}" "${panel_user}")
        
        clear; show_banner
        echo -e "${C_GREEN}=====================================================${C_RESET}"
        echo -e "${C_GREEN}     ✅ Web Control Panel Installed Successfully!     ${C_RESET}"
        echo -e "${C_GREEN}=====================================================${C_RESET}"
        echo -e "\n${C_CYAN}  🌐 Panel URL:${C_RESET}        ${C_YELLOW}http://${server_ip}:${PANEL_PORT}/${panel_secret}${C_RESET}"
        echo -e "${C_CYAN}  👤 Username:${C_RESET}         ${C_YELLOW}${panel_user}${C_RESET}"
        echo -e "${C_CYAN}  🔑 Password:${C_RESET}         ${C_YELLOW}${panel_pass}${C_RESET}"
        echo -e "${C_CYAN}  🔐 Secret Path:${C_RESET}       ${C_YELLOW}/${panel_secret}${C_RESET}"
        if [[ -n "$autologin_link" ]]; then
            echo -e "\n${C_CYAN}  ⚡ 1-Click Auto-Login:${C_RESET} ${C_GREEN}${autologin_link}${C_RESET}"
            echo -e "     ${C_GRAY}(Dynamic token valid for 1 hour — 1-Click instant login without password)${C_RESET}"
        fi
        echo -e "\n${C_DIM}  Save these credentials! You can view them later from option [32] > [3].${C_RESET}"
    else
        echo -e "\n${C_RED}❌ Panel service failed to start. Checking logs:${C_RESET}"
        journalctl -u firewallfalcon-panel -n 15 --no-pager
    fi
}

uninstall_web_panel() {
    if [ ! -f "$PANEL_SERVICE_FILE" ]; then
        if [[ "$UNINSTALL_MODE" != "silent" ]]; then
            echo -e "${C_YELLOW}ℹ️ Web Panel is not installed.${C_RESET}"
        fi
        return
    fi
    
    if [[ "$UNINSTALL_MODE" != "silent" ]]; then
        echo -e "\n${C_BOLD}${C_PURPLE}--- 🗑️ Uninstalling Web Control Panel ---${C_RESET}"
        read -p "👉 Are you sure you want to uninstall the Web Panel? (y/n): " confirm
        if [[ "$confirm" != "y" ]]; then
            echo -e "\n${C_YELLOW}❌ Uninstallation cancelled.${C_RESET}"
            return
        fi
    fi
    
    echo -e "${C_BLUE}🛑 Stopping and removing Web Panel service...${C_RESET}"
    systemctl stop firewallfalcon-panel &>/dev/null
    systemctl disable firewallfalcon-panel &>/dev/null
    rm -f "$PANEL_SERVICE_FILE"
    rm -f "$PANEL_SCRIPT"
    rm -rf "$PANEL_HTML_DIR"
    rm -f "$PANEL_CONF"
    systemctl daemon-reload
    
    echo -e "${C_GREEN}✅ Web Panel has been uninstalled.${C_RESET}"
}

show_panel_credentials() {
    if [ ! -f "$PANEL_CONF" ]; then
        echo -e "\n${C_YELLOW}ℹ️ Web Panel is not installed.${C_RESET}"
        return
    fi
    
    source "$PANEL_CONF"
    local server_ip secret_suffix autologin_link
    server_ip="${GLOBAL_SERVER_IPV4:-$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')}"
    [[ -z "$server_ip" ]] && server_ip="YOUR_SERVER_IP"
    secret_suffix=""
    if [[ -n "$PANEL_SECRET" ]]; then
        secret_suffix="/${PANEL_SECRET}"
    fi
    
    autologin_link=$(generate_autologin_link_sh "$server_ip" "${PANEL_PORT:-44380}" "${PANEL_SECRET}" "${PANEL_USER}")
    
    echo -e "\n${C_GREEN}=====================================================${C_RESET}"
    echo -e "${C_GREEN}         🌐 Web Panel Credentials                    ${C_RESET}"
    echo -e "${C_GREEN}=====================================================${C_RESET}"
    echo -e "\n${C_CYAN}  🌐 Panel URL:${C_RESET}        ${C_YELLOW}http://${server_ip}:${PANEL_PORT:-44380}${secret_suffix}${C_RESET}"
    echo -e "${C_CYAN}  👤 Username:${C_RESET}         ${C_YELLOW}${PANEL_USER}${C_RESET}"
    echo -e "${C_CYAN}  🔑 Password:${C_RESET}         ${C_YELLOW}${PANEL_PASS_PLAIN}${C_RESET}"
    if [[ -n "$PANEL_SECRET" ]]; then
        echo -e "${C_CYAN}  🔐 Secret Path:${C_RESET}       ${C_YELLOW}/${PANEL_SECRET}${C_RESET}"
    fi
    if [[ -n "$autologin_link" ]]; then
        echo -e "\n${C_CYAN}  ⚡ 1-Click Auto-Login:${C_RESET} ${C_GREEN}${autologin_link}${C_RESET}"
        echo -e "     ${C_GRAY}(Dynamic token valid for 1 hour — 1-Click instant login without password)${C_RESET}"
    fi
    
    if pgrep -f "firewallfalcon-panel.py" &>/dev/null || pgrep -f "panel.py" &>/dev/null || systemctl is-active --quiet firewallfalcon-panel 2>/dev/null; then
        echo -e "\n${C_CYAN}  📡 Status:${C_RESET}           ${C_GREEN}🟢 Running${C_RESET}"
    else
        echo -e "\n${C_CYAN}  📡 Status:${C_RESET}           ${C_RED}🔴 Stopped${C_RESET}"
    fi
}

change_panel_credentials() {
    if [ ! -f "$PANEL_CONF" ]; then
        echo -e "\n${C_YELLOW}ℹ️ Web Panel is not installed.${C_RESET}"
        return
    fi
    
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🔑 Change Web Panel Credentials & Secret Path ---${C_RESET}"
    show_panel_credentials
    
    echo ""
    read -p "👉 Enter new username (or press Enter to keep current): " new_user
    read -p "🔑 Enter new password (or press Enter to auto-generate): " new_pass
    read -p "🔐 Enter new secret URL path (e.g., secret123, or press Enter to keep): " new_secret
    
    source "$PANEL_CONF"
    
    if [[ -z "$new_user" ]]; then
        new_user="$PANEL_USER"
    fi
    if [[ -z "$new_pass" ]]; then
        new_pass=$(tr -dc 'A-Za-z0-9@#$' < /dev/urandom | head -c 16)
        echo -e "${C_GREEN}🔑 Auto-generated password: ${C_YELLOW}$new_pass${C_RESET}"
    fi
    if [[ -z "$new_secret" ]]; then
        new_secret="${PANEL_SECRET:-panel_$(tr -dc 'a-z0-9' < /dev/urandom | head -c 8)}"
    fi
    new_secret=$(echo "$new_secret" | sed 's/^\///')
    
    local new_hash
    new_hash=$(echo -n "$new_pass" | sha256sum | awk '{print $1}')
    
    cat > "$PANEL_CONF" <<-PEOF
PANEL_USER="$new_user"
PANEL_PASS_HASH="$new_hash"
PANEL_PASS_PLAIN="$new_pass"
PANEL_SECRET="$new_secret"
PEOF
    chmod 600 "$PANEL_CONF"
    
    systemctl restart firewallfalcon-panel &>/dev/null
    echo -e "\n${C_GREEN}✅ Panel credentials & secret path updated!${C_RESET}"
    echo -e "  ${C_CYAN}👤 Username:${C_RESET}    ${C_YELLOW}$new_user${C_RESET}"
    echo -e "  ${C_CYAN}🔑 Password:${C_RESET}    ${C_YELLOW}$new_pass${C_RESET}"
    echo -e "  ${C_CYAN}🔐 Secret Path:${C_RESET}  ${C_YELLOW}/$new_secret${C_RESET}"
}

update_web_panel() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🔄 Updating Web Control Panel Files ---${C_RESET}"
    
    if [ ! -f "$PANEL_SERVICE_FILE" ]; then
        echo -e "\n${C_YELLOW}ℹ️ Web Panel is not installed yet.${C_RESET}"
        return
    fi
    
    echo -e "${C_BLUE}📥 Downloading latest panel backend & frontend...${C_RESET}"
    mkdir -p "$PANEL_HTML_DIR"
    
    _fm_panel_file panel.py "$PANEL_SCRIPT"
    if [ $? -ne 0 ] || [ ! -s "$PANEL_SCRIPT" ]; then
        echo -e "${C_RED}❌ Failed to download panel backend.${C_RESET}"
        return
    fi
    cp -f "$PANEL_SCRIPT" "$PANEL_HTML_DIR/panel.py" 2>/dev/null || true
    ln -sf "$PANEL_SCRIPT" /usr/local/bin/panel.py 2>/dev/null || true
    chmod +x "$PANEL_SCRIPT" "$PANEL_HTML_DIR/panel.py" 2>/dev/null || true
    sed -i 's/\r$//' "$PANEL_SCRIPT" 2>/dev/null || true
    
    _fm_panel_file index.html "$PANEL_HTML_FILE"
    _fm_panel_file reseller.html "$PANEL_HTML_DIR/reseller.html" 2>/dev/null || true
    if [ $? -ne 0 ] || [ ! -s "$PANEL_HTML_FILE" ]; then
        echo -e "${C_RED}❌ Failed to download panel frontend.${C_RESET}"
        return
    fi
    
    echo -e "${C_BLUE}🔄 Restarting Web Panel service...${C_RESET}"
    systemctl daemon-reload
    systemctl restart firewallfalcon-panel &>/dev/null
    sleep 1
    
    if systemctl is-active --quiet firewallfalcon-panel; then
        echo -e "\n${C_GREEN}✅ Web Panel updated & restarted successfully!${C_RESET}"
        if [ -f "$PANEL_CONF" ]; then
            source "$PANEL_CONF"
            local server_ip autologin_link
            server_ip="${GLOBAL_SERVER_IPV4:-$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')}"
            [[ -z "$server_ip" ]] && server_ip="YOUR_SERVER_IP"
            autologin_link=$(generate_autologin_link_sh "$server_ip" "${PANEL_PORT:-44380}" "${PANEL_SECRET}" "${PANEL_USER}")
            if [[ -n "$autologin_link" ]]; then
                echo -e "\n${C_CYAN}  ⚡ 1-Click Auto-Login:${C_RESET} ${C_GREEN}${autologin_link}${C_RESET}"
                echo -e "     ${C_GRAY}(Dynamic token valid for 1 hour — 1-Click instant login without password)${C_RESET}"
            fi
        fi
        echo -e "\n${C_CYAN}💡 IMPORTANT:${C_RESET} Perform a Hard Refresh in your browser (${C_YELLOW}Ctrl + F5${C_RESET} or ${C_YELLOW}Cmd + Shift + R${C_RESET}) to clear browser cache."
    else
        echo -e "\n${C_RED}❌ Failed to restart Web Panel service. Checking logs:${C_RESET}"
        journalctl -u firewallfalcon-panel -n 15 --no-pager
    fi
}

web_panel_menu() {
    while true; do
        clear; show_banner
        echo
        menu_section "WEB CONTROL PANEL" "$C_TITLE"
        echo
        
        if [ -f "$PANEL_SERVICE_FILE" ]; then
            if systemctl is-active --quiet firewallfalcon-panel 2>/dev/null; then
                echo -e "  ${C_CYAN}Status:${C_RESET} ${C_GREEN}Installed & Running${C_RESET}"
            else
                echo -e "  ${C_CYAN}Status:${C_RESET} ${C_RED}Installed (Stopped)${C_RESET}"
            fi
        else
            echo -e "  ${C_CYAN}Status:${C_RESET} ${C_YELLOW}Not Installed${C_RESET}"
        fi
        echo
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[1]" "Install Web Panel"
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[2]" "Uninstall Web Panel"
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[3]" "Show Panel Credentials"
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[4]" "Change Panel Credentials"
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[5]" "Restart Panel Service"
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[6]" "Update Web Panel Files"
        echo
        printf "  ${C_DANGER}%-4s${C_RESET} %s\n" "[0]" "Return"
        echo
        if ! read -r -p "$(echo -e ${C_PROMPT}"> Select an option: "${C_RESET})" panel_choice; then
            return
        fi
        case $panel_choice in
            1) install_web_panel; press_enter ;;
            2) uninstall_web_panel; press_enter ;;
            3) show_panel_credentials; press_enter ;;
            4) change_panel_credentials; press_enter ;;
            5)
                if [ -f "$PANEL_SERVICE_FILE" ]; then
                    systemctl restart firewallfalcon-panel &>/dev/null
                    sleep 1
                    if systemctl is-active --quiet firewallfalcon-panel; then
                        echo -e "\n${C_GREEN}✅ Web Panel service restarted successfully.${C_RESET}"
                    else
                        echo -e "\n${C_RED}❌ Failed to restart. Checking logs:${C_RESET}"
                        journalctl -u firewallfalcon-panel -n 10 --no-pager
                    fi
                else
                    echo -e "\n${C_YELLOW}ℹ️ Web Panel is not installed.${C_RESET}"
                fi
                press_enter
                ;;
            6) update_web_panel; press_enter ;;
            0) return ;;
            *) invalid_option ;;
        esac
    done
}

uninstall_script() {
    if [[ "$UNINSTALL_MODE" != "silent" ]]; then
        clear; show_banner
        echo
        menu_section "UNINSTALL FIREWALL FALCON" "$C_TITLE"
        echo
        echo -e "  ${C_RED}⚠️ WARNING: This will remove DAHOOM, its services, protocols,${C_RESET}"
        echo -e "  ${C_RED}   and optionally all configured user accounts permanently.${C_RESET}"
        echo
        printf "  ${C_DANGER}%-4s${C_RESET} %s\n" "[1]" "Proceed with full uninstallation"
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[0]" "Cancel and return"
        echo
        read -r -p "$(echo -e ${C_PROMPT}"> Select an option [0]: "${C_RESET})" uninst_choice
        uninst_choice=${uninst_choice:-0}
        if [[ "$uninst_choice" != "1" ]]; then
            echo -e "\n${C_GREEN}✅ Uninstallation cancelled.${C_RESET}"
            sleep 1
            return
        fi

        local -a removable_users=()
        local remove_users_on_uninstall=false
        mapfile -t removable_users < <(get_firewallfalcon_known_users)
        if [[ ${#removable_users[@]} -gt 0 ]]; then
            echo -e "\n${C_YELLOW}👥 System SSH users detected (${#removable_users[@]}): ${C_CYAN}${removable_users[*]}${C_RESET}"
            echo -e "  ${C_RED}[1]${C_RESET} Delete these SSH users permanently"
            echo -e "  ${C_GREEN}[2]${C_RESET} Keep SSH user accounts on system"
            echo
            read -r -p "$(echo -e ${C_PROMPT}"> Select user option [2]: "${C_RESET})" user_choice
            user_choice=${user_choice:-2}
            if [[ "$user_choice" == "1" ]]; then
                remove_users_on_uninstall=true
            fi
        fi
    fi

    export UNINSTALL_MODE="silent"
    clear; show_banner
    echo
    echo -e "  ${C_CYAN}┌── Uninstallation in Progress ──────────────────────────┐${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET}  ${C_RED}${C_BOLD}Starting DAHOOM Complete System Purge...${C_RESET}"
    echo -e "  ${C_CYAN}└────────────────────────────────────────────────────────┘${C_RESET}"
    echo

    # Step 1: User cleanup (if selected)
    if [[ "$remove_users_on_uninstall" == "true" ]]; then
        show_progress_bar "[1/6] Deleting SSH user accounts..." 15 0.02
        delete_firewallfalcon_user_accounts "${removable_users[@]}" >/dev/null 2>&1 || true
    else
        show_progress_bar "[1/6] Preserving SSH user accounts..." 10 0.01
    fi

    # Step 2: Stopping background daemons and services
    show_progress_bar "[2/6] Stopping background daemons & active limiters..." 20 0.02
    systemctl stop firewallfalcon-limiter &>/dev/null || true
    systemctl disable firewallfalcon-limiter &>/dev/null || true
    rm -f "$LIMITER_SERVICE" "$LIMITER_SCRIPT" 2>/dev/null || true

    systemctl stop firewallfalcon-bandwidth &>/dev/null || true
    systemctl disable firewallfalcon-bandwidth &>/dev/null || true
    rm -f "$BANDWIDTH_SERVICE" "$BANDWIDTH_SCRIPT" "$TRIAL_CLEANUP_SCRIPT" 2>/dev/null || true
    rm -rf "$LEGACY_BANDWIDTH_DIR" 2>/dev/null || true

    systemctl stop firewallfalcon-health &>/dev/null || true
    systemctl disable firewallfalcon-health &>/dev/null || true
    rm -f "/etc/systemd/system/firewallfalcon-health.service" "/usr/local/bin/firewallfalcon-health.py" 2>/dev/null || true

    # Step 3: Tunnelling protocols & Proxies
    show_progress_bar "[3/6] Purging VPN protocols, proxies & web panels..." 25 0.02
    purge_nginx "silent" </dev/null &>/dev/null || true
    uninstall_dnstt </dev/null &>/dev/null || true
    uninstall_badvpn </dev/null &>/dev/null || true
    uninstall_udp_custom </dev/null &>/dev/null || true
    uninstall_ssl_tunnel </dev/null &>/dev/null || true
    uninstall_falcon_proxy </dev/null &>/dev/null || true
    uninstall_zivpn </dev/null &>/dev/null || true
    uninstall_vless_reality </dev/null &>/dev/null || true
    uninstall_web_panel </dev/null &>/dev/null || true
    uninstall_xui_panel </dev/null &>/dev/null || true
    delete_dns_record </dev/null &>/dev/null || true

    # Step 4: Restoring SSH security, default PAM MOTD & network rules
    show_progress_bar "[4/6] Restoring SSH configurations & system MOTD..." 15 0.02
    restore_default_server_motd </dev/null &>/dev/null || true
    rm -f "$LOGIN_INFO_SCRIPT" "$SSHD_FF_CONFIG" 2>/dev/null || true
    systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || true
    chattr -i /etc/resolv.conf 2>/dev/null || true

    # Step 5: Cleaning directories, certificates & caches
    show_progress_bar "[5/6] Removing databases, certificates & temp caches..." 20 0.02
    rm -rf "$BADVPN_BUILD_DIR" "$UDP_CUSTOM_DIR" "$DB_DIR" 2>/dev/null || true

    # Step 6: Reloading systemd & removing menu binary
    show_progress_bar "[6/6] Finalizing daemon-reload & removing menu executable..." 15 0.02
    systemctl daemon-reload 2>/dev/null || true
    local menu_loc; menu_loc=$(command -v menu 2>/dev/null || echo "/usr/local/bin/menu")
    rm -f "$menu_loc" "/usr/bin/fm" "/usr/local/bin/fm" 2>/dev/null || true

    echo
    echo -e "  ${C_CYAN}┌── Uninstallation Complete ─────────────────────────────┐${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET}  ${C_GREEN}✅ DAHOOM uninstalled successfully.${C_RESET}"
    echo -e "  ${C_CYAN}└────────────────────────────────────────────────────────┘${C_RESET}"
    echo
    exit 0
}

# --- NEW FEATURES ---

create_trial_account() {
    clear; show_banner
    echo
    menu_section "CREATE TRIAL ACCOUNT" "$C_TITLE"
    echo
    if ! command -v at &>/dev/null; then
        ff_pkg_install at >/dev/null 2>&1 || {
            echo -e "${C_RED}❌ Failed to install 'at' daemon.${C_RESET}"
            return
        }
        systemctl enable atd &>/dev/null; systemctl start atd &>/dev/null
    fi
    systemctl is-active --quiet atd || systemctl start atd &>/dev/null

    local trial_count; trial_count=$(grep -c ":trial$" "$DB_FILE" 2>/dev/null || echo 0)
    echo -e "  ${C_DIM}Active trial accounts: ${C_CYAN}$trial_count${C_RESET}"
    echo
    printf "  ${C_CHOICE}%-4s${C_RESET} %-20s ${C_CHOICE}%-4s${C_RESET} %s\n" "[1]" "1 Hour" "[2]" "2 Hours"
    printf "  ${C_CHOICE}%-4s${C_RESET} %-20s ${C_CHOICE}%-4s${C_RESET} %s\n" "[3]" "3 Hours" "[4]" "6 Hours"
    printf "  ${C_CHOICE}%-4s${C_RESET} %-20s ${C_CHOICE}%-4s${C_RESET} %s\n" "[5]" "12 Hours" "[6]" "1 Day (24h)"
    printf "  ${C_CHOICE}%-4s${C_RESET} %-20s ${C_CHOICE}%-4s${C_RESET} %s\n" "[7]" "3 Days (72h)" "[8]" "Custom Hours"
    echo
    printf "  ${C_WARN}%-4s${C_RESET} %s\n" "[0]" "Cancel"
    echo
    if ! read -r -p "$(echo -e "${C_BLUE}👉 Select duration [1]: ${C_RESET}")" dur_choice; then
        return
    fi
    dur_choice=${dur_choice:-1}

    local duration_hours=1 duration_label="1 Hour"
    case $dur_choice in
        1) duration_hours=1;   duration_label="1 Hour" ;;
        2) duration_hours=2;   duration_label="2 Hours" ;;
        3) duration_hours=3;   duration_label="3 Hours" ;;
        4) duration_hours=6;   duration_label="6 Hours" ;;
        5) duration_hours=12;  duration_label="12 Hours" ;;
        6) duration_hours=24;  duration_label="1 Day" ;;
        7) duration_hours=72;  duration_label="3 Days" ;;
        8) read -p "👉 Enter custom duration in hours: " custom_hours
           if ! [[ "$custom_hours" =~ ^[0-9]+$ ]] || [[ "$custom_hours" -lt 1 ]]; then
               echo -e "\n${C_RED}❌ Invalid duration.${C_RESET}"; return
           fi
           duration_hours=$custom_hours
           duration_label="$custom_hours Hours"
           ;;
        0) echo -e "\n${C_YELLOW}❌ Creation cancelled.${C_RESET}"; return ;;
        *) echo -e "\n${C_RED}❌ Invalid option.${C_RESET}"; return ;;
    esac

    local rand_suffix=$(tr -dc 'a-z0-9' < /dev/urandom | head -c 5)
    local default_username="trial_${rand_suffix}"
    read -p "👉 Username [${default_username}]: " username
    username=${username:-$default_username}

    if id "$username" &>/dev/null || grep -q "^$username:" "$DB_FILE"; then
        echo -e "\n${C_RED}❌ Error: User '$username' already exists.${C_RESET}"; return
    fi

    local default_pass=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 8)
    read -p "👉 Password [${default_pass}]: " custom_pass
    local password=${custom_pass:-$default_pass}

    read -p "👉 Simultaneous Connections [1]: " limit
    limit=${limit:-1}

    read -p "👉 Total Bandwidth GB (0 = unlimited) [0]: " bandwidth_gb
    bandwidth_gb=${bandwidth_gb:-0}

    local expire_date
    if [[ "$duration_hours" -ge 24 ]]; then
        local days=$((duration_hours / 24))
        expire_date=$(date -d "+$days days" +%Y-%m-%d)
    else
        expire_date=$(date -d "+1 day" +%Y-%m-%d)
    fi
    local expiry_timestamp
    expiry_timestamp=$(date -d "+${duration_hours} hours" '+%Y-%m-%d %H:%M:%S')

    ensure_firewallfalcon_system_group
    useradd -m -s /usr/sbin/nologin "$username"
    usermod -aG "$FF_USERS_GROUP" "$username" 2>/dev/null
    echo "$username:$password" | chpasswd
    chage -E "$expire_date" "$username"
    echo "$username:$password:$expire_date:$limit:$bandwidth_gb:trial" >> "$DB_FILE"

    echo "$TRIAL_CLEANUP_SCRIPT $username" | at now + ${duration_hours} hours 2>/dev/null
    _log_action "TRIAL" "$username" "${duration_label}"

    local bw_display="Unlimited"
    if [[ "$bandwidth_gb" != "0" ]]; then bw_display="${bandwidth_gb} GB"; fi

    clear; show_banner
    echo
    echo -e "${C_GREEN}✅ Trial account created successfully!${C_RESET}\n"
    echo -e "  ${C_CYAN}┌── Trial Details ───────────────────────────┐${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET}  Username  : ${C_YELLOW}$username${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET}  Password  : ${C_YELLOW}$password${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET}  Duration  : ${C_CYAN}$duration_label${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET}  Expires   : ${C_RED}$expiry_timestamp${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET}  Sessions  : ${C_YELLOW}$limit${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET}  Total BW  : ${C_YELLOW}$bw_display${C_RESET}"
    echo -e "  ${C_CYAN}└────────────────────────────────────────────┘${C_RESET}"
    echo
    echo -e "  ${C_DIM}Share-ready: Host: ${C_CYAN}$(curl -s -4 icanhazip.com --max-time 5 2>/dev/null)${C_RESET}${C_DIM} | User: ${C_YELLOW}$username${C_RESET}${C_DIM} | Pass: ${C_YELLOW}$password${C_RESET}"
    echo
    read -p "👉 Generate client config now? (y/n) [n]: " gen_conf
    if [[ "$gen_conf" == "y" || "$gen_conf" == "Y" ]]; then
        generate_client_config "$username" "$password"
    fi

    invalidate_banner_cache
    refresh_dynamic_banner_routing_if_enabled
}

view_user_bandwidth() {
    clear; show_banner
    echo
    menu_section "USER BANDWIDTH DETAILS" "$C_TITLE"
    echo
    _select_user_interface "Select User to Inspect"
    local u=$SELECTED_USER
    if [[ "$u" == "NO_USERS" || -z "$u" ]]; then return; fi

    clear; show_banner
    echo
    menu_section "BANDWIDTH: $u" "$C_TITLE"
    echo
    local line; line=$(grep "^$u:" "$DB_FILE")
    local _u _p _e _l bandwidth_gb daily_bandwidth_gb
    IFS=: read -r _u _p _e _l bandwidth_gb daily_bandwidth_gb _ <<< "$line"
    [[ -z "$bandwidth_gb" ]] && bandwidth_gb="0"
    [[ ! "$daily_bandwidth_gb" =~ ^[0-9]+\.?[0-9]*$ ]] && daily_bandwidth_gb="0"

    local used_bytes=0
    if [[ -f "$BANDWIDTH_DIR/${u}.usage" ]]; then
        read -r used_bytes < "$BANDWIDTH_DIR/${u}.usage" 2>/dev/null || used_bytes=0
        [[ -z "$used_bytes" ]] && used_bytes=0
    fi

    local used_mb; used_mb=$(awk "BEGIN {printf \"%.2f\", $used_bytes / 1048576}")
    local used_gb; used_gb=$(awk "BEGIN {printf \"%.3f\", $used_bytes / 1073741824}")

    echo -e "  ${C_CYAN}Total Data Used:${C_RESET}     ${C_WHITE}${used_gb} GB${C_RESET} (${used_mb} MB)"

    if [[ "$bandwidth_gb" == "0" ]]; then
        echo -e "  ${C_CYAN}Total Limit:${C_RESET}         ${C_GREEN}Unlimited${C_RESET}"
    else
        local quota_bytes; quota_bytes=$(awk "BEGIN {printf \"%.0f\", $bandwidth_gb * 1073741824}")
        local percentage; percentage=$(awk "BEGIN {printf \"%.1f\", ($used_bytes / $quota_bytes) * 100}")
        local remaining_bytes; remaining_bytes=$((quota_bytes - used_bytes))
        (( remaining_bytes < 0 )) && remaining_bytes=0
        local remaining_gb; remaining_gb=$(awk "BEGIN {printf \"%.3f\", $remaining_bytes / 1073741824}")

        echo -e "  ${C_CYAN}Total Limit:${C_RESET}         ${C_YELLOW}${bandwidth_gb} GB${C_RESET}"
        echo -e "  ${C_CYAN}Remaining:${C_RESET}           ${C_WHITE}${remaining_gb} GB${C_RESET}"

        local bar_width=30
        local filled; filled=$(awk "BEGIN {printf \"%.0f\", ($percentage / 100) * $bar_width}")
        (( filled > bar_width )) && filled=$bar_width
        local empty=$((bar_width - filled))
        local bar_color="$C_GREEN"
        (( $(awk "BEGIN {print ($percentage > 80)}") )) && bar_color="$C_RED" || {
            (( $(awk "BEGIN {print ($percentage > 50)}") )) && bar_color="$C_YELLOW"
        }
        printf "  ${C_CYAN}Total Progress:${C_RESET}      ${bar_color}["
        for ((i=0; i<filled; i++)); do printf "█"; done
        for ((i=0; i<empty; i++)); do printf "░"; done
        printf "]${C_RESET} ${percentage}%%\n"

        if [[ "$used_bytes" -ge "$quota_bytes" ]]; then
            echo -e "  ${C_RED}⚠️ USER HAS EXCEEDED TOTAL BANDWIDTH QUOTA${C_RESET}"
        fi
    fi

    if [[ "$daily_bandwidth_gb" != "0" ]]; then
        echo
        local d_used=0
        [[ -f "$BANDWIDTH_DIR/${u}.daily_usage" ]] && read -r d_used < "$BANDWIDTH_DIR/${u}.daily_usage" 2>/dev/null || d_used=0
        local d_used_gb; d_used_gb=$(awk "BEGIN {printf \"%.3f\", $d_used / 1073741824}")
        local d_quota_bytes; d_quota_bytes=$(awk "BEGIN {printf \"%.0f\", $daily_bandwidth_gb * 1073741824}")
        local d_pct; d_pct=$(awk "BEGIN {printf \"%.1f\", ($d_used / $d_quota_bytes) * 100}")
        local d_remain=$((d_quota_bytes - d_used)); (( d_remain < 0 )) && d_remain=0
        local d_remain_gb; d_remain_gb=$(awk "BEGIN {printf \"%.3f\", $d_remain / 1073741824}")

        echo -e "  ${C_CYAN}Daily Data Used:${C_RESET}     ${C_WHITE}${d_used_gb} GB${C_RESET}"
        echo -e "  ${C_CYAN}Daily Limit:${C_RESET}         ${C_YELLOW}${daily_bandwidth_gb} GB/day${C_RESET}"
        echo -e "  ${C_CYAN}Daily Remaining:${C_RESET}     ${C_WHITE}${d_remain_gb} GB${C_RESET}"

        local d_filled; d_filled=$(awk "BEGIN {printf \"%.0f\", ($d_pct / 100) * 30}")
        (( d_filled > 30 )) && d_filled=30
        local d_empty=$((30 - d_filled))
        local d_color="$C_GREEN"
        (( $(awk "BEGIN {print ($d_pct > 80)}") )) && d_color="$C_RED" || {
            (( $(awk "BEGIN {print ($d_pct > 50)}") )) && d_color="$C_YELLOW"
        }
        printf "  ${C_CYAN}Daily Progress:${C_RESET}      ${d_color}["
        for ((i=0; i<d_filled; i++)); do printf "█"; done
        for ((i=0; i<d_empty; i++)); do printf "░"; done
        printf "]${C_RESET} ${d_pct}%%\n"
    fi
    echo
}

bulk_create_users() {
    clear; show_banner
    echo
    menu_section "BULK CREATE USERS" "$C_TITLE"
    echo
    read -p "👉 Username prefix [user]: " prefix
    prefix=${prefix:-user}

    read -p "👉 Number of users to create [5]: " count
    count=${count:-5}
    if ! [[ "$count" =~ ^[0-9]+$ ]] || [[ "$count" -lt 1 ]] || [[ "$count" -gt 100 ]]; then
        echo -e "\n${C_RED}❌ Invalid count (1-100).${C_RESET}"; return
    fi

    read -p "👉 Starting index number [1]: " start_num
    start_num=${start_num:-1}
    if ! [[ "$start_num" =~ ^[0-9]+$ ]]; then start_num=1; fi

    read -p "👉 Duration in days [30]: " days
    days=${days:-30}

    read -p "👉 Simultaneous Connections per user [1]: " limit
    limit=${limit:-1}

    read -p "👉 Total Bandwidth GB (0 = unlimited) [0]: " bandwidth_gb
    bandwidth_gb=${bandwidth_gb:-0}

    read -p "👉 Daily Bandwidth GB (0 = unlimited) [0]: " daily_bandwidth_gb
    daily_bandwidth_gb=${daily_bandwidth_gb:-0}

    local expire_date; expire_date=$(date -d "+$days days" +%Y-%m-%d)
    local bw_display="Unlimited"; [[ "$bandwidth_gb" != "0" ]] && bw_display="${bandwidth_gb} GB"

    echo
    echo -e "  ${C_CYAN}┌── Bulk Creation Summary ───────────────────┐${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET}  Range     : ${C_YELLOW}${prefix}${start_num}${C_RESET} to ${C_YELLOW}${prefix}$((start_num+count-1))${C_RESET} (${C_CYAN}${count} users${C_RESET})"
    echo -e "  ${C_CYAN}│${C_RESET}  Expires   : ${C_YELLOW}$expire_date${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET}  Sessions  : ${C_YELLOW}$limit${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET}  Total BW  : ${C_YELLOW}$bw_display${C_RESET}"
    echo -e "  ${C_CYAN}└────────────────────────────────────────────┘${C_RESET}"
    echo
    echo -e "  ${C_GREEN}[1]${C_RESET} Confirm bulk creation"
    echo -e "  ${C_RED}[0]${C_RESET} Cancel"
    echo
    read -p "$(echo -e "${C_BLUE}👉 Select option [1]: ${C_RESET}")" bulk_confirm
    bulk_confirm=${bulk_confirm:-1}
    if [[ "$bulk_confirm" != "1" ]]; then echo -e "\n${C_YELLOW}❌ Creation cancelled.${C_RESET}"; return; fi

    ensure_firewallfalcon_system_group
    local output_file="/root/bulk_users_$(date +%F-%H%M).txt"
    echo -e "\n${C_BLUE}⚙️ Creating $count users...${C_RESET}\n"
    echo -e "  ${C_CYAN}----------------------------------------------------------------${C_RESET}"
    printf "  ${C_BOLD}${C_WHITE}%-20s | %-15s | %-12s${C_RESET}\n" "USERNAME" "PASSWORD" "EXPIRES"
    echo -e "  ${C_CYAN}----------------------------------------------------------------${C_RESET}"

    local created=0
    for ((i=start_num; i<start_num+count; i++)); do
        local username="${prefix}${i}"
        if id "$username" &>/dev/null || grep -q "^$username:" "$DB_FILE"; then
            echo -e "${C_RED}  ⚠️ Skipping '$username' — already exists${C_RESET}"
            continue
        fi
        local password=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 8)
        useradd -m -s /usr/sbin/nologin "$username"
        usermod -aG "$FF_USERS_GROUP" "$username" 2>/dev/null
        echo "$username:$password" | chpasswd
        chage -E "$expire_date" "$username"
        echo "$username:$password:$expire_date:$limit:$bandwidth_gb:$daily_bandwidth_gb:bulk" >> "$DB_FILE"
        echo "$username:$password:$expire_date" >> "$output_file"
        printf "  ${C_GREEN}%-20s${C_RESET} | ${C_YELLOW}%-15s${C_RESET} | ${C_CYAN}%-12s${C_RESET}\n" "$username" "$password" "$expire_date"
        created=$((created + 1))
    done

    echo -e "  ${C_CYAN}----------------------------------------------------------------${C_RESET}"
    echo -e "  ${C_GREEN}✅ Created $created users successfully!${C_RESET}"
    echo -e "  ${C_GREEN}✅ Credentials saved to: ${C_YELLOW}$output_file${C_RESET}\n"

    invalidate_banner_cache
    refresh_dynamic_banner_routing_if_enabled
}

generate_client_config() {
    local user=$1
    local pass=$2

    local host_ip=$(curl -s -4 icanhazip.com --max-time 5 2>/dev/null || echo "YOUR_SERVER_IP")
    local host_domain
    host_domain=$(detect_preferred_host)
    [[ -z "$host_domain" ]] && host_domain="$host_ip"

    echo
    menu_section "CLIENT CONFIGURATION: $user [VLESS Supported]" "$C_TITLE"
    echo
    echo -e "  ${C_CYAN}┌── Credentials ─────────────────────────────┐${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET}  Username  : ${C_YELLOW}$user${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET}  Password  : ${C_YELLOW}$pass${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET}  Host/IP   : ${C_WHITE}$host_domain${C_RESET}"
    local user_expiry; user_expiry=$(grep "^${user}:" "$DB_FILE" 2>/dev/null | cut -d: -f3)
    [[ -n "$user_expiry" ]] && echo -e "  ${C_CYAN}│${C_RESET}  Expires   : ${C_RED}$user_expiry${C_RESET}"
    echo -e "  ${C_CYAN}└────────────────────────────────────────────┘${C_RESET}"
    echo
    echo -e "  ${C_BOLD}SSH Direct:${C_RESET}         Host: $host_domain | Port: 22"

    if systemctl is-active --quiet haproxy; then
        echo -e "  ${C_BOLD}HAProxy Edge Stack:${C_RESET} Host: $host_domain | Port 80 (HTTP) | Port 443 (TLS/SSL)"
    elif systemctl is-active --quiet nginx; then
        echo -e "  ${C_BOLD}Internal Nginx:${C_RESET}     Ports: ${NGINX_INTERNAL_HTTP_PORT} / ${NGINX_INTERNAL_TLS_PORT}"
    fi

    if systemctl is-active --quiet udp-custom; then
        echo -e "  ${C_BOLD}UDP Custom:${C_RESET}         IP: $host_ip | Ports: 1-65535"
    fi

    if systemctl is-active --quiet dnstt; then
        if [ -f "$DNSTT_CONFIG_FILE" ]; then
            source "$DNSTT_CONFIG_FILE"
            echo -e "  ${C_BOLD}DNSTT SlowDNS:${C_RESET}      NS: $TUNNEL_DOMAIN | PubKey: $PUBLIC_KEY"
        fi
    fi

    if systemctl is-active --quiet zivpn; then
        echo -e "  ${C_BOLD}ZiVPN UDP:${C_RESET}          Port: 5667"
    fi

    if systemctl is-active --quiet xray; then
        local uuid; uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "a1b2c3d4-e5f6-7890-abcd-1234567890ab")
        local vless_link="vless://${uuid}@${host_ip}:443?security=reality&encryption=none&pbk=google-sni&headerType=none&type=tcp&sni=dl.google.com#${user}-DAHOOM"
        echo -e "  ${C_BOLD}VLESS REALITY Link:${C_RESET} ${C_YELLOW}${vless_link}${C_RESET}"
        if command -v qrencode &>/dev/null; then
            echo -e "\n  ${C_CYAN}VLESS REALITY QR Code:${C_RESET}"
            qrencode -t ansiutf8 "$vless_link"
        fi
    fi
    echo
}

client_config_menu() {
    clear; show_banner
    echo
    menu_section "CLIENT CONFIGURATIONS" "$C_TITLE"
    echo
    _select_user_interface "Select User to Generate Config"
    local u=$SELECTED_USER
    if [[ "$u" == "NO_USERS" || -z "$u" ]]; then return; fi

    local pass=$(grep "^$u:" "$DB_FILE" | cut -d: -f2)
    generate_client_config "$u" "$pass"

    echo -e "  ${C_GREEN}[1]${C_RESET} Save config to file (/root/${u}_config.txt)"
    echo -e "  ${C_WARN}[0]${C_RESET} Return"
    echo
    read -p "$(echo -e "${C_BLUE}👉 Select action [0]: ${C_RESET}")" save_conf
    if [[ "$save_conf" == "1" ]]; then
        local conf_file="/root/${u}_config.txt"
        generate_client_config "$u" "$pass" > "$conf_file" 2>/dev/null
        echo -e "\n  ${C_GREEN}✅ Config file saved: ${C_YELLOW}$conf_file${C_RESET}"
    fi
}

format_rate_from_kbps() {
    local kbps=${1:-0}
    if (( kbps >= 1024 )); then
        printf "%d.%02d MB/s" $((kbps / 1024)) $((((kbps % 1024) * 100) / 1024))
    else
        printf "%d KB/s" "$kbps"
    fi
}

# Lightweight Bash Monitor (No vnStat required)
simple_live_monitor() {
    local iface=$1
    local rx_file="/sys/class/net/$iface/statistics/rx_bytes"
    local tx_file="/sys/class/net/$iface/statistics/tx_bytes"
    local interval=2
    local stop_monitor=0
    local rx1 tx1 rx2 tx2 rx_diff tx_diff rx_kbs tx_kbs rx_fmt tx_fmt

    if [[ -z "$iface" || ! -r "$rx_file" || ! -r "$tx_file" ]]; then
        echo -e "\n${C_RED}❌ Could not read interface statistics for '${iface:-unknown}'.${C_RESET}"
        return
    fi

    echo -e "\n${C_BLUE}⚡ Starting Lightweight Traffic Monitor for $iface...${C_RESET}"
    echo -e "${C_DIM}Press [Ctrl+C] to stop.${C_RESET}\n"

    read -r rx1 < "$rx_file"
    read -r tx1 < "$tx_file"

    printf "%-15s | %-15s\n" "⬇️ Download" "⬆️ Upload"
    echo "-----------------------------------"

    trap 'stop_monitor=1' INT TERM
    while (( ! stop_monitor )); do
        sleep "$interval"
        read -r rx2 < "$rx_file" || break
        read -r tx2 < "$tx_file" || break

        rx_diff=$((rx2 - rx1))
        tx_diff=$((tx2 - tx1))
        (( rx_diff < 0 )) && rx_diff=0
        (( tx_diff < 0 )) && tx_diff=0

        rx_kbs=$((rx_diff / 1024 / interval))
        tx_kbs=$((tx_diff / 1024 / interval))
        rx_fmt=$(format_rate_from_kbps "$rx_kbs")
        tx_fmt=$(format_rate_from_kbps "$tx_kbs")

        printf "\r%-15s | %-15s" "$rx_fmt" "$tx_fmt"

        rx1=$rx2
        tx1=$tx2
    done
    trap - INT TERM
    echo
}

traffic_monitor_menu() {
    clear; show_banner
    echo
    menu_section "NETWORK TRAFFIC MONITOR" "$C_TITLE"
    echo
    
    # Find active interface
    local iface=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
    local all_ifaces=($(ls /sys/class/net/ 2>/dev/null | grep -v lo))
    if [[ ${#all_ifaces[@]} -gt 1 ]]; then
        echo -e "  ${C_CYAN}Available interfaces:${C_RESET}"
        for idx in "${!all_ifaces[@]}"; do
            echo -e "  ${C_GREEN}[$((idx+1))]${C_RESET} ${all_ifaces[$idx]}"
        done
        read -p "$(echo -e "${C_BLUE}👉 Select interface [default: $iface]: ${C_RESET}")" iface_choice
        if [[ "$iface_choice" =~ ^[0-9]+$ && "$iface_choice" -ge 1 && "$iface_choice" -le ${#all_ifaces[@]} ]]; then
            iface="${all_ifaces[$((iface_choice-1))]}"
        fi
    fi

    if [[ -r "/sys/class/net/$iface/statistics/rx_bytes" ]]; then
        local boot_rx boot_tx
        read -r boot_rx < "/sys/class/net/$iface/statistics/rx_bytes" 2>/dev/null || boot_rx=0
        read -r boot_tx < "/sys/class/net/$iface/statistics/tx_bytes" 2>/dev/null || boot_tx=0
        local brx_gb; brx_gb=$(awk "BEGIN{printf \"%.2f\", $boot_rx/1073741824}")
        local btx_gb; btx_gb=$(awk "BEGIN{printf \"%.2f\", $boot_tx/1073741824}")
        echo -e "  ${C_CYAN}Interface:${C_RESET} ${C_YELLOW}${iface}${C_RESET} ${C_DIM}| Total since boot: RX ${C_GREEN}${brx_gb} GB${C_RESET} ${C_DIM}| TX ${C_GREEN}${btx_gb} GB${C_RESET}"
    fi
    
    echo
    printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[1]" "Live Monitor"
    printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[2]" "Total Traffic"
    printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[3]" "Daily/Monthly Logs"
    echo
    printf "  ${C_DANGER}%-4s${C_RESET} %s\n" "[0]" "Return"
    echo
    read -p "$(echo -e ${C_PROMPT}"> Select an option: "${C_RESET})" t_choice
    case $t_choice in
        1) 
           simple_live_monitor "$iface"
           ;;
        2)
            local rx_total=$(cat /sys/class/net/$iface/statistics/rx_bytes)
            local tx_total=$(cat /sys/class/net/$iface/statistics/tx_bytes)
            local rx_mb=$((rx_total / 1024 / 1024))
            local tx_mb=$((tx_total / 1024 / 1024))
            echo -e "\n${C_BLUE}📊 Total Traffic (Since Boot):${C_RESET}"
            echo -e "   ⬇️ Download: ${C_WHITE}${rx_mb} MB${C_RESET}"
            echo -e "   ⬆️ Upload:   ${C_WHITE}${tx_mb} MB${C_RESET}"
            press_enter
            ;;
        3) 
           # vnStat Logic
           if ! command -v vnstat &> /dev/null; then
               echo -e "\n${C_YELLOW}⚠️ vnStat is not installed.${C_RESET}"
               echo -e "   This tool provides persistent history (Daily/Monthly reports)."
               echo -e "   It is lightweight but requires installation."
               read -p "👉 Install vnStat now? (y/n): " confirm
                if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                     echo -e "\n${C_BLUE}📦 Installing vnStat...${C_RESET}"
                     ff_pkg_install vnstat >/dev/null 2>&1 || {
                         echo -e "${C_RED}❌ Failed to install vnStat.${C_RESET}"
                         sleep 1
                         return
                     }
                     systemctl enable vnstat >/dev/null 2>&1
                     systemctl restart vnstat >/dev/null 2>&1
                    local default_iface=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
                    vnstat --add -i "$default_iface" >/dev/null 2>&1
                    echo -e "${C_GREEN}✅ Installed.${C_RESET}"
                    sleep 1
               else
                    return
               fi
           fi
           echo
           vnstat -i "$iface"
           echo -e "\n${C_DIM}Run 'vnstat -d' or 'vnstat -m' manually for specific views.${C_RESET}"
           press_enter
           ;;
        *) return ;;
    esac
}

torrent_block_menu() {
    clear; show_banner
    echo
    menu_section "TORRENT BLOCKING" "$C_TITLE"
    echo
    if iptables -L FORWARD 2>/dev/null | grep -qi "bittorrent\|torrent"; then
        echo -e "  ${C_CYAN}Status:${C_RESET} ${C_GREEN}Active (Blocked)${C_RESET}"
    else
        echo -e "  ${C_CYAN}Status:${C_RESET} ${C_RED}Inactive (Allowed)${C_RESET}"
    fi
    echo
    printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[1]" "Enable Blocking"
    printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[2]" "Disable Blocking"
    echo
    printf "  ${C_DANGER}%-4s${C_RESET} %s\n" "[0]" "Return"
    echo
    read -p "$(echo -e ${C_PROMPT}"> Select an option: "${C_RESET})" b_choice
    
    case $b_choice in
        1)
            echo -e "\n${C_BLUE}Applying Anti-Torrent rules...${C_RESET}"
            _flush_torrent_rules
            
            iptables -A FORWARD -m string --string "BitTorrent" --algo bm -j DROP
            iptables -A FORWARD -m string --string "BitTorrent protocol" --algo bm -j DROP
            iptables -A FORWARD -m string --string "peer_id=" --algo bm -j DROP
            iptables -A FORWARD -m string --string ".torrent" --algo bm -j DROP
            iptables -A FORWARD -m string --string "announce.php?passkey=" --algo bm -j DROP
            iptables -A FORWARD -m string --string "torrent" --algo bm -j DROP
            iptables -A FORWARD -m string --string "info_hash" --algo bm -j DROP
            iptables -A FORWARD -m string --string "get_peers" --algo bm -j DROP
            iptables -A FORWARD -m string --string "find_node" --algo bm -j DROP
            
            iptables -A OUTPUT -m string --string "BitTorrent" --algo bm -j DROP
            iptables -A OUTPUT -m string --string "BitTorrent protocol" --algo bm -j DROP
            iptables -A OUTPUT -m string --string "peer_id=" --algo bm -j DROP
            iptables -A OUTPUT -m string --string ".torrent" --algo bm -j DROP
            iptables -A OUTPUT -m string --string "announce.php?passkey=" --algo bm -j DROP
            iptables -A OUTPUT -m string --string "torrent" --algo bm -j DROP
            iptables -A OUTPUT -m string --string "info_hash" --algo bm -j DROP
            iptables -A OUTPUT -m string --string "get_peers" --algo bm -j DROP
            iptables -A OUTPUT -m string --string "find_node" --algo bm -j DROP
            
            if ff_pkg_is_installed iptables-persistent &>/dev/null; then
                netfilter-persistent save &>/dev/null
            fi
            
            echo -e "${C_GREEN}✅ Torrent Blocking Enabled.${C_RESET}"
            press_enter
            ;;
        2)
            echo -e "\n${C_BLUE}Removing Anti-Torrent rules...${C_RESET}"
            _flush_torrent_rules
            if ff_pkg_is_installed iptables-persistent &>/dev/null; then
                netfilter-persistent save &>/dev/null
            fi
            echo -e "${C_GREEN}✅ Torrent Blocking Disabled.${C_RESET}"
            press_enter
            ;;
        *) return ;;
    esac
}

_flush_torrent_rules() {
    iptables -D FORWARD -m string --string "BitTorrent" --algo bm -j DROP 2>/dev/null
    iptables -D FORWARD -m string --string "BitTorrent protocol" --algo bm -j DROP 2>/dev/null
    iptables -D FORWARD -m string --string "peer_id=" --algo bm -j DROP 2>/dev/null
    iptables -D FORWARD -m string --string ".torrent" --algo bm -j DROP 2>/dev/null
    iptables -D FORWARD -m string --string "announce.php?passkey=" --algo bm -j DROP 2>/dev/null
    iptables -D FORWARD -m string --string "torrent" --algo bm -j DROP 2>/dev/null
    iptables -D FORWARD -m string --string "info_hash" --algo bm -j DROP 2>/dev/null
    iptables -D FORWARD -m string --string "get_peers" --algo bm -j DROP 2>/dev/null
    iptables -D FORWARD -m string --string "find_node" --algo bm -j DROP 2>/dev/null

    iptables -D OUTPUT -m string --string "BitTorrent" --algo bm -j DROP 2>/dev/null
    iptables -D OUTPUT -m string --string "BitTorrent protocol" --algo bm -j DROP 2>/dev/null
    iptables -D OUTPUT -m string --string "peer_id=" --algo bm -j DROP 2>/dev/null
    iptables -D OUTPUT -m string --string ".torrent" --algo bm -j DROP 2>/dev/null
    iptables -D OUTPUT -m string --string "announce.php?passkey=" --algo bm -j DROP 2>/dev/null
    iptables -D OUTPUT -m string --string "torrent" --algo bm -j DROP 2>/dev/null
    iptables -D OUTPUT -m string --string "info_hash" --algo bm -j DROP 2>/dev/null
    iptables -D OUTPUT -m string --string "get_peers" --algo bm -j DROP 2>/dev/null
    iptables -D OUTPUT -m string --string "find_node" --algo bm -j DROP 2>/dev/null
}

# ── TELEGRAM BOT HELPERS & MENU ───────────────────────────────────────
TELEGRAM_CONF="/etc/firewallfalcon/telegram.conf"

send_telegram_msg() {
    local msg="$1"
    if [[ -f "$TELEGRAM_CONF" ]]; then
        local BOT_TOKEN CHAT_ID NOTIFY_ENABLED
        source "$TELEGRAM_CONF" 2>/dev/null
        if [[ "$NOTIFY_ENABLED" == "true" && -n "$BOT_TOKEN" && -n "$CHAT_ID" ]]; then
            curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
                -d "chat_id=${CHAT_ID}" \
                -d "text=${msg}" \
                -d "parse_mode=HTML" &>/dev/null &
        fi
    fi
}

send_telegram_doc() {
    local doc_file="$1" caption="$2"
    if [[ -f "$TELEGRAM_CONF" && -f "$doc_file" ]]; then
        local BOT_TOKEN CHAT_ID NOTIFY_ENABLED
        source "$TELEGRAM_CONF" 2>/dev/null
        if [[ "$NOTIFY_ENABLED" == "true" && -n "$BOT_TOKEN" && -n "$CHAT_ID" ]]; then
            curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" \
                -F "chat_id=${CHAT_ID}" \
                -F "document=@${doc_file}" \
                -F "caption=${caption}" &>/dev/null &
        fi
    fi
}

telegram_bot_menu() {
    while true; do
        clear; show_banner
        echo
        menu_section "TELEGRAM BOT & BACKUP" "$C_TITLE"
        echo
        local token="" chat="" enabled="false"
        if [ -f "$TELEGRAM_CONF" ]; then
            source "$TELEGRAM_CONF" 2>/dev/null
            token="${BOT_TOKEN:-Not Configured}"
            chat="${CHAT_ID:-Not Configured}"
            enabled="${NOTIFY_ENABLED:-false}"
        fi

        local status_str="${C_RED}Disabled${C_RESET}"
        [[ "$enabled" == "true" ]] && status_str="${C_GREEN}Active${C_RESET}"

        echo -e "  ${C_CYAN}Bot Status:${C_RESET} $status_str"
        echo -e "  ${C_CYAN}Chat ID   :${C_RESET} ${C_YELLOW}${chat}${C_RESET}"
        echo
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[1]" "Configure Bot Token & Chat ID"
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[2]" "Send Test Message"
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[3]" "Backup & Send to Telegram Now"
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[4]" "Toggle Notifications (On/Off)"
        echo
        printf "  ${C_DANGER}%-4s${C_RESET} %s\n" "[0]" "Return"
        echo
        if ! read -r -p "$(echo -e ${C_PROMPT}"> Select an option: "${C_RESET})" tg_act; then
            return
        fi
        case "$tg_act" in
            1)
                read -r -p "$(echo -e "${C_BLUE}👉 Enter Telegram Bot Token: ${C_RESET}")" input_token
                read -r -p "$(echo -e "${C_BLUE}👉 Enter Telegram Admin Chat ID: ${C_RESET}")" input_chat
                if [[ -n "$input_token" && -n "$input_chat" ]]; then
                    mkdir -p "/etc/firewallfalcon" 2>/dev/null
                    cat <<EOF > "$TELEGRAM_CONF"
BOT_TOKEN="$input_token"
CHAT_ID="$input_chat"
NOTIFY_ENABLED="true"
EOF
                    echo -e "\n${C_GREEN}✅ Telegram Bot configured successfully!${C_RESET}"
                    send_telegram_msg "👑 <b>DAHOOM Bot Connected!</b>%0AServer IP: $(curl -s -4 icanhazip.com 2>/dev/null)"
                fi
                press_enter
                ;;
            2)
                echo -e "\n${C_BLUE}Sending test message to Telegram...${C_RESET}"
                send_telegram_msg "🚀 <b>DAHOOM Test Message</b>%0ATime: $(date)"
                echo -e "${C_GREEN}✅ Test message sent! Check your Telegram chat.${C_RESET}"
                press_enter
                ;;
            3)
                echo -e "\n${C_BLUE}Creating backup and sending to Telegram...${C_RESET}"
                local auto_name="/root/ff_backup_$(date +%F-%H%M).tar.gz"
                mkdir -p "$DB_DIR" 2>/dev/null
                tar -czf "$auto_name" -C "$(dirname "$DB_DIR")" "$(basename "$DB_DIR")" 2>/dev/null
                send_telegram_doc "$auto_name" "💾 DAHOOM Backup - $(date +%F)"
                echo -e "${C_GREEN}✅ Backup created and sent to Telegram!${C_RESET}"
                press_enter
                ;;
            4)
                if [[ "$enabled" == "true" ]]; then
                    sed -i 's/NOTIFY_ENABLED="true"/NOTIFY_ENABLED="false"/' "$TELEGRAM_CONF" 2>/dev/null
                    echo -e "\n${C_YELLOW}Notifications disabled.${C_RESET}"
                else
                    sed -i 's/NOTIFY_ENABLED="false"/NOTIFY_ENABLED="true"/' "$TELEGRAM_CONF" 2>/dev/null
                    echo -e "\n${C_GREEN}✅ Notifications enabled.${C_RESET}"
                fi
                press_enter
                ;;
            0) return ;;
            *) invalid_option ;;
        esac
    done
}

# ── ANTI-MULTILOGIN ENGINE HELPERS & MENU ──────────────────────────────
MULTILOGIN_CONF="/etc/firewallfalcon/multilogin.conf"

check_and_kill_multilogin() {
    [[ -s "$DB_FILE" ]] || return
    local lock_file="/tmp/.ff_multilogin.lock"
    [[ -f "$lock_file" ]] && return
    touch "$lock_file" 2>/dev/null

    refresh_ssh_session_cache

    while IFS=: read -r user pass expiry limit bandwidth_gb _extra; do
        [[ -z "$user" || -z "$limit" ]] && continue
        [[ "$limit" =~ ^[0-9]+$ && "$limit" -gt 0 ]] || continue

        local active_count="${SSH_SESSION_COUNTS[$user]:-0}"
        if [[ "$active_count" -gt "$limit" ]]; then
            local user_pids=()
            for pid in "${!SSH_SESSION_PIDS[@]}"; do
                if [[ "${SSH_SESSION_PIDS[$pid]}" == "$user" ]]; then
                    user_pids+=("$pid")
                fi
            done

            local excess=$((active_count - limit))
            if [[ ${#user_pids[@]} -gt 0 ]]; then
                for ((i=0; i<excess && i<${#user_pids[@]}; i++)); do
                    local kill_pid="${user_pids[$i]}"
                    kill -9 "$kill_pid" 2>/dev/null
                done
                _log_action "MULTILOGIN_KILLED" "$user" "killed=$excess active=$active_count limit=$limit"
                send_telegram_msg "⚠️ <b>Anti-MultiLogin Triggered</b>%0AUser: <b>$user</b>%0AKilled excess sessions ($active_count / $limit allowed)."
            fi
        fi
    done < "$DB_FILE"

    rm -f "$lock_file" 2>/dev/null
}

anti_multilogin_menu() {
    while true; do
        clear; show_banner
        echo
        menu_section "ANTI-MULTILOGIN ENGINE" "$C_TITLE"
        echo
        local status="Disabled"
        if (crontab -l 2>/dev/null | grep -q "_run_multilogin"); then
            status="${C_GREEN}Active (Automated Background Protection)${C_RESET}"
        else
            status="${C_RED}Disabled${C_RESET}"
        fi

        echo -e "  ${C_CYAN}Status:${C_RESET} $status"
        echo
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[1]" "Enable Automated Anti-MultiLogin Guard"
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[2]" "Disable Anti-MultiLogin Guard"
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[3]" "Run Instant Multi-Session Scan & Kill"
        echo
        printf "  ${C_DANGER}%-4s${C_RESET} %s\n" "[0]" "Return"
        echo
        if ! read -r -p "$(echo -e ${C_PROMPT}"> Select an option: "${C_RESET})" ml_act; then
            return
        fi
        case "$ml_act" in
            1)
                (crontab -l 2>/dev/null | grep -v "_run_multilogin") | crontab -
                (crontab -l 2>/dev/null; echo "* * * * * bash /usr/local/bin/menu _run_multilogin &>/dev/null") | crontab -
                echo -e "\n${C_GREEN}✅ Automated Anti-MultiLogin Guard enabled (runs every minute).${C_RESET}"
                press_enter
                ;;
            2)
                (crontab -l 2>/dev/null | grep -v "_run_multilogin") | crontab -
                echo -e "\n${C_GREEN}✅ Anti-MultiLogin Guard disabled.${C_RESET}"
                press_enter
                ;;
            3)
                echo -e "\n${C_BLUE}Running instant multi-session scan...${C_RESET}"
                check_and_kill_multilogin
                echo -e "${C_GREEN}✅ Scan completed.${C_RESET}"
                press_enter
                ;;
            0) return ;;
            *) invalid_option ;;
        esac
    done
}

ssh_banner_menu() {
    while true; do
        clear; show_banner
        echo
        menu_section "SSH & SERVER LOGIN BANNER" "$C_TITLE"
        echo
        local motd_status="${C_RED}Default System MOTD${C_RESET}"
        if is_falcon_server_motd_enabled; then
            motd_status="${C_GREEN}Active (DAHOOM Dynamic)${C_RESET}"
        fi

        local banner_mode; banner_mode=$(get_ssh_banner_mode)
        local banner_status
        case "$banner_mode" in
            dynamic) banner_status="${C_GREEN}Dynamic (Per-User)${C_RESET}" ;;
            static) banner_status="${C_YELLOW}Static${C_RESET}" ;;
            *) banner_status="${C_RED}Disabled${C_RESET}" ;;
        esac

        echo -e "  ${C_CYAN}Server Login MOTD :${C_RESET} ${motd_status}"
        echo -e "  ${C_CYAN}User SSH Banner   :${C_RESET} ${banner_status}"
        echo
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[1]" "Enable / Refresh Server Login Banner (MOTD)"
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[2]" "Restore Default System MOTD (Disable Custom)"
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[3]" "Preview Server Login Banner"
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[4]" "Enable Dynamic Per-User SSH Banner"
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[5]" "Set Static SSH Banner"
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[6]" "View Static SSH Banner"
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[7]" "Disable All User SSH Banners"
        echo
        printf "  ${C_DANGER}%-4s${C_RESET} %s\n" "[0]" "Return"
        echo
        if ! read -r -p "$(echo -e ${C_PROMPT}"> Select an option: "${C_RESET})" choice; then
            return
        fi
        case $choice in
            1)
                setup_falcon_server_motd
                echo -e "\n${C_GREEN}✅ DAHOOM dynamic server login banner enabled.${C_RESET}"
                press_enter
                ;;
            2)
                restore_default_server_motd
                echo -e "\n${C_GREEN}✅ Default system MOTD restored.${C_RESET}"
                press_enter
                ;;
            3)
                clear
                if [[ -x "/etc/update-motd.d/01-falcon-banner" ]]; then
                    /etc/update-motd.d/01-falcon-banner
                else
                    setup_falcon_server_motd
                    /etc/update-motd.d/01-falcon-banner
                fi
                press_enter
                ;;
            4)
                if setup_ssh_login_info; then
                    echo -e "\n${C_GREEN}✅ Dynamic account banner enabled.${C_RESET}"
                    echo -e "${C_DIM}Users will now see their account info banner.${C_RESET}"
                fi
                press_enter
                ;;
            5) set_ssh_banner_paste ;;
            6) view_ssh_banner ;;
            7) remove_ssh_banner ;;
            0) return ;;
            *) invalid_option ;;
        esac
    done
}

auto_reboot_menu() {
    clear; show_banner
    echo
    menu_section "AUTO REBOOT" "$C_TITLE"
    echo
    local cur_cron; cur_cron=$(crontab -l 2>/dev/null | grep -i "reboot\|shutdown" | head -1)
    if [[ -n "$cur_cron" ]]; then
        echo -e "  ${C_CYAN}Schedule:${C_RESET} ${C_GREEN}Daily Midnight (00:00)${C_RESET}"
    else
        echo -e "  ${C_CYAN}Schedule:${C_RESET} ${C_RED}Disabled${C_RESET}"
    fi
    echo
    printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[1]" "Daily Reboot (00:00)"
    printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[2]" "Disable Reboot"
    echo
    printf "  ${C_DANGER}%-4s${C_RESET} %s\n" "[0]" "Return"
    echo
    read -p "$(echo -e ${C_PROMPT}"> Select an option: "${C_RESET})" r_choice
    
    case $r_choice in
        1)
            # Remove existing to prevent duplicates
            (crontab -l 2>/dev/null | grep -v "systemctl reboot") | crontab -
            # Add new job
            (crontab -l 2>/dev/null; echo "0 0 * * * systemctl reboot") | crontab -
            echo -e "\n${C_GREEN}✅ Auto-reboot scheduled for every day at 00:00.${C_RESET}"
            press_enter
            ;;
        2)
            (crontab -l 2>/dev/null | grep -v "systemctl reboot") | crontab -
            echo -e "\n${C_GREEN}✅ Auto-reboot disabled.${C_RESET}"
            press_enter
            ;;
        *) return ;;
    esac
}


press_enter() {
    echo -e "\n  ${C_FRAME}────────────────────────────────────────────────────────${C_RESET}"
    echo -en "  ${C_CYAN}${C_BOLD}▸${C_RESET} ${C_GRAY}Press${C_RESET} ${C_CYAN}Enter${C_RESET} ${C_GRAY}to return${C_RESET} " && read -r || true
}
invalid_option() {
    echo -e "\n${C_RED}❌ Invalid option.${C_RESET}" && sleep 1
}

# --- Display-width helpers: emoji count as 2 columns, variation selectors as 0 ---
disp_width() {
    local s="$1" i c w=0
    for ((i=0; i<${#s}; i++)); do
        c="${s:i:1}"
        [[ "$c" == $'\xEF\xB8\x8F' ]] && continue
        # ASCII (<= 0x7F) = 1 column; any multibyte char (emoji etc.) = 2 columns
        if [[ "$c" < $'\x80' ]]; then
            w=$((w+1))
        else
            w=$((w+2))
        fi
    done
    echo "$w"
}

# Right-pad a string to exactly W display columns
pad_right() {
    local s="$1" w="$2" dw
    dw=$(disp_width "$s")
    if (( dw < w )); then
        printf '%s%*s' "$s" "$((w - dw))" ""
    else
        printf '%s' "$s"
    fi
}

# --- Clean centered section header for the main menu ---
menu_section() {
    local title="$1" color="$2" total=54 rule i
    local tlen=${#title}
    # ▌ TITLE ───────────  : accent bar, title, then a rule filling the remainder
    local used=$(( 2 + tlen + 1 ))
    local rlen=$(( total - used )); (( rlen < 2 )) && rlen=2
    rule=""
    for ((i=0; i<rlen; i++)); do rule+="─"; done
    echo -e "  ${color}${C_BOLD}▌${C_RESET} ${color}${C_BOLD}${title}${C_RESET} ${C_FRAME}${rule}${C_RESET}"
}

report_issue_dialog() {
    clear; show_banner
    menu_section "REPORT AN ISSUE & SUPPORT" "$C_TITLE"
    echo
    echo -e "  ✈️  ${C_CYAN}Telegram Channel :${C_RESET} ${C_GREEN}@aljailan${C_RESET} (${C_CYAN}https://t.me/aljailan${C_RESET})"
    echo -e "  📦  ${C_CYAN}Bug Tracker      :${C_RESET} ${C_CYAN}https://github.com/mooa322/fm/issues${C_RESET}"
    echo
    echo -e "${C_BLUE}  ─────────────────────────────────────────────────────────${C_RESET}"
    echo
    printf "  ${C_DANGER}%-4s${C_RESET} %s\n" "[0]" "Return"
    echo
    read -r -p "$(echo -e ${C_PROMPT}"> Press [0] or [Enter] to return: "${C_RESET})" _
}

get_update_branch() {
    if [ -f "/etc/firewallfalcon/channel" ]; then
        local ch; ch=$(cat "/etc/firewallfalcon/channel" 2>/dev/null | tr -d '[:space:]')
        if [[ "$ch" == "dev" || "$ch" == "beta2" || "$ch" == "main" ]]; then
            echo "$ch"
            return
        fi
    fi
    mkdir -p "/etc/firewallfalcon" 2>/dev/null
    echo "dev" > "/etc/firewallfalcon/channel" 2>/dev/null || true
    echo "dev"
}

trigger_standalone_update_page() {
    clear
    local cur_ver; cur_ver=$(get_current_version_tag)
    local cur_sha; cur_sha=$(get_installed_sha)
    local branch_name; branch_name=$(get_update_branch)
    local friendly_branch="Stable"
    [[ "$branch_name" == "beta2" ]] && friendly_branch="Beta"
    [[ "$branch_name" == "dev" ]] && friendly_branch="Development"

    # Always fetch fresh from API — do not rely on stale banner cache
    local api_json remote_sha
    api_json=$(curl -s --max-time 5 "https://api.github.com/repos/mooa322/fm/branches/${branch_name}" 2>/dev/null)
    if [[ -n "$api_json" ]]; then
        remote_sha=$(echo "$api_json" | jq -r '.commit.sha' 2>/dev/null | cut -c1-7)
    fi
    # Fallback to banner cache only if API fails
    if [[ -z "$remote_sha" || "$remote_sha" == "null" || ${#remote_sha} -ne 7 ]]; then
        remote_sha="${BANNER_CACHE_REMOTE_VER##*4.6.0_}"
        remote_sha="${remote_sha##*dev_}"
        remote_sha="${remote_sha##*beta_}"
        remote_sha="${remote_sha:0:7}"
    fi
    # If still empty, treat as same (up to date)
    [[ -z "$remote_sha" || ${#remote_sha} -ne 7 ]] && remote_sha="$cur_sha"

    # Warm the banner cache with this fresh result
    local now_ts; now_ts=$(date +%s 2>/dev/null || echo 0)
    [[ ${#remote_sha} -eq 7 ]] && echo "$now_ts $remote_sha" > "$UPDATE_CACHE_FILE" 2>/dev/null

    local remote_ver="4.6.0_${remote_sha}"
    [[ "$branch_name" == "beta2" ]] && remote_ver="4.6.0_beta_${remote_sha}"
    [[ "$branch_name" == "dev" ]] && remote_ver="4.6.0_dev_${remote_sha}"

    # If update is available -> UPDATE IMMEDIATELY ON THE SPOT!
    if [[ -n "$cur_sha" && ${#cur_sha} -eq 7 && -n "$remote_sha" && ${#remote_sha} -eq 7 && "$cur_sha" != "$remote_sha" ]]; then
        echo
        menu_section "UPDATE MANAGER" "$C_TITLE"
        echo
        echo -e "  🚀 ${C_YELLOW}New update detected (${friendly_branch}):${C_RESET} ${C_GREEN}${remote_ver}${C_RESET} (Current: ${C_GRAY}${cur_ver}${C_RESET})"
        echo

        show_progress_bar "1/3 Downloading ${friendly_branch} update payload from GitHub..." 20 0.02
        local tmp_menu="/tmp/menu_update_$$"
        if _fm_pull_src && cp -f "$FM_SRC/menu.sh" "$tmp_menu" && [[ -s "$tmp_menu" ]]; then
            show_progress_bar "2/3 Verifying permissions & structure..." 15 0.02
            chmod +x "$tmp_menu"
            sed -i 's/\r$//' "$tmp_menu" 2>/dev/null || true
            mkdir -p "/etc/firewallfalcon" 2>/dev/null
            echo "$remote_sha" > "$VERSION_FILE"
            echo "$now_ts $remote_sha" > "$UPDATE_CACHE_FILE"
            mv "$tmp_menu" "/usr/local/bin/menu"
            chmod +x "/usr/local/bin/menu"

            show_progress_bar "3/3 Finalizing update & reloading menu..." 15 0.02
            echo -e "  ${C_GREEN}✅ Updated successfully to version: ${remote_ver}${C_RESET}\n"
            sleep 0.8
            exec bash /usr/local/bin/menu
        else
            echo -e "  ${C_RED}❌ Download failed. Please verify internet connection.${C_RESET}\n"
            rm -f "$tmp_menu" 2>/dev/null
            press_enter
        fi
    else
        echo
        menu_section "UPDATE MANAGER" "$C_TITLE"
        echo
        echo -e "  ${C_CYAN}Installed Version:${C_RESET} ${C_YELLOW}${cur_ver}${C_RESET}"
        echo -e "  ${C_CYAN}Status           :${C_RESET} ${C_GREEN}✅ Up to date${C_RESET}"
        echo -e "  ${C_CYAN}Update Channel   :${C_RESET} ${C_CYAN}${friendly_branch} (${branch_name})${C_RESET}"
        echo
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[1]" "Reinstall / Force Repair (${branch_name})"
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[2]" "Update Web Control Panel"
        printf "  ${C_CHOICE}%-4s${C_RESET} %s\n" "[3]" "Switch Update Channel [Stable / Beta / Dev]"
        echo
        printf "  ${C_DANGER}%-4s${C_RESET} %s\n" "[0]" "Return"
        echo
        read -r -p "$(echo -e ${C_PROMPT}"> Select an option [0]: "${C_RESET})" no_up_act
        no_up_act=${no_up_act:-0}
        if [[ "$no_up_act" == "1" ]]; then
            echo
            show_progress_bar "Re-downloading core binaries from GitHub (${branch_name})..." 20 0.02
            local tmp_menu="/tmp/menu_update_$$"
            _fm_pull_src && cp -f "$FM_SRC/menu.sh" "$tmp_menu"
            chmod +x "$tmp_menu"
            sed -i 's/\r$//' "$tmp_menu" 2>/dev/null || true
            mkdir -p "/etc/firewallfalcon" 2>/dev/null
            echo "$remote_sha" > "$VERSION_FILE"
            echo "$now_ts $remote_sha" > "$UPDATE_CACHE_FILE"
            mv "$tmp_menu" "/usr/local/bin/menu"
            chmod +x "/usr/local/bin/menu"

            echo -e "\n  ${C_GREEN}✅ Repaired successfully from ${branch_name}!${C_RESET}\n"
            sleep 1
            exec bash /usr/local/bin/menu
        elif [[ "$no_up_act" == "2" ]]; then
            echo
            show_progress_bar "Updating Web Control Panel from new_panel branch..." 20 0.02
            { _fm_pull_src && bash "$FM_SRC/update_panel.sh"; }
            press_enter
            trigger_standalone_update_page
        elif [[ "$no_up_act" == "3" ]]; then
            echo
            echo -e "  ${C_BOLD}Select Update Channel:${C_RESET}"
            echo -e "  ${C_GREEN}[1] Stable Channel (main)${C_RESET}"
            echo -e "  ${C_YELLOW}[2] Beta Channel (beta2)${C_RESET}"
            echo -e "  ${C_PURPLE}[3] Development Channel (dev - Bleeding Edge)${C_RESET}"
            echo -e "  ${C_DANGER}[0] Cancel${C_RESET}"
            echo
            read -r -p "$(echo -e ${C_PROMPT}"> Choose channel: "${C_RESET})" ch_sel
            case "$ch_sel" in
                1)
                    echo "main" > /etc/firewallfalcon/channel
                    echo -e "\n  ${C_GREEN}✅ Switched to Stable channel (main).${C_RESET}"
                    ;;
                2)
                    echo "beta2" > /etc/firewallfalcon/channel
                    echo -e "\n  ${C_YELLOW}🚀 Switched to Beta channel (beta2).${C_RESET}"
                    ;;
                3)
                    echo "dev" > /etc/firewallfalcon/channel
                    echo -e "\n  ${C_PURPLE}🧪 Switched to Development channel (dev).${C_RESET}"
                    ;;
                *)
                    echo -e "\n  ${C_GRAY}Cancelled.${C_RESET}"
                    ;;
            esac
            sleep 1
            trigger_standalone_update_page
        fi
    fi
}

main_menu() {
    while true; do
        export UNINSTALL_MODE="interactive"
        show_banner
        
        local up_badge=""
        if $BANNER_CACHE_HAS_UPDATE; then
            up_badge=" ${C_YELLOW}${C_BOLD}(🚀 Update Available)${C_RESET}"
        fi

        echo
        menu_section "USER MANAGEMENT" "$C_TITLE"
        printf "  ${C_CHOICE}%-4s${C_RESET} %-22s ${C_CHOICE}%-4s${C_RESET} %s\n" "[1]" "Create User" "[2]" "Delete User"
        printf "  ${C_CHOICE}%-4s${C_RESET} %-22s ${C_CHOICE}%-4s${C_RESET} %s\n" "[3]" "Renew User" "[4]" "Lock User"
        printf "  ${C_CHOICE}%-4s${C_RESET} %-22s ${C_CHOICE}%-4s${C_RESET} %s\n" "[5]" "Unlock User" "[6]" "Edit User"
        printf "  ${C_CHOICE}%-4s${C_RESET} %-22s ${C_CHOICE}%-4s${C_RESET} %s\n" "[7]" "List Users" "[8]" "Trial Account"
        printf "  ${C_CHOICE}%-4s${C_RESET} %-22s ${C_CHOICE}%-4s${C_RESET} %s\n" "[9]" "User Bandwidth" "[10]" "Bulk Create"
        printf "  ${C_CHOICE}%-4s${C_RESET} %-22s ${C_CHOICE}%-4s${C_RESET} %s\n" "[11]" "Per-User Speed" "[12]" "Live Monitor"
        printf "  ${C_CHOICE}%-4s${C_RESET} %-22s ${C_CHOICE}%-4s${C_RESET} %s\n" "[13]" "Conn Logs" "[14]" "Client Config"
        echo
        menu_section "V2RAY & XRAY PROTOCOLS" "$C_TITLE"
        printf "  ${C_CHOICE}%-4s${C_RESET} %-22s ${C_CHOICE}%-4s${C_RESET} %s\n" "[15]" "V2Ray Core" "[16]" "Create V2Ray User"
        printf "  ${C_CHOICE}%-4s${C_RESET} %-22s ${C_CHOICE}%-4s${C_RESET} %s\n" "[17]" "List V2Ray Users" "[18]" "V2Ray Links & QR"
        printf "  ${C_CHOICE}%-4s${C_RESET} %-22s ${C_CHOICE}%-4s${C_RESET} %s\n" "[19]" "Renew V2Ray User" "[20]" "Delete V2Ray User"
        printf "  ${C_CHOICE}%-4s${C_RESET} %-22s\n" "[21]" "Import SSH Users"
        echo
        menu_section "VPN & PROTOCOLS" "$C_TITLE"
        printf "  ${C_CHOICE}%-4s${C_RESET} %-22s ${C_CHOICE}%-4s${C_RESET} %s\n" "[22]" "Protocols" "[23]" "Traffic Monitor"
        printf "  ${C_CHOICE}%-4s${C_RESET} %-22s ${C_CHOICE}%-4s${C_RESET} %s\n" "[24]" "Anti-Torrent" "[25]" "Anti-MultiLogin"
        echo
        menu_section "SYSTEM SETTINGS" "$C_TITLE"
        printf "  ${C_CHOICE}%-4s${C_RESET} %-22s ${C_CHOICE}%-4s${C_RESET} %s\n" "[26]" "Domain & DNS" "[27]" "SSH Banner"
        printf "  ${C_CHOICE}%-4s${C_RESET} %-22s ${C_CHOICE}%-4s${C_RESET} %s\n" "[28]" "Auto-Reboot" "[29]" "Backup Data"
        printf "  ${C_CHOICE}%-4s${C_RESET} %-22s ${C_CHOICE}%-4s${C_RESET} %s\n" "[30]" "Restore Data" "[31]" "Cleanup Expired"
        printf "  ${C_CHOICE}%-4s${C_RESET} %-22s ${C_CHOICE}%-4s${C_RESET} %s\n" "[32]" "Web Panel" "[33]" "Telegram Bot"
        printf "  ${C_CHOICE}%-4s${C_RESET} %-22s ${C_CHOICE}%-4s${C_RESET} %s\n" "[34]" "Auto-Healing" "[35]" "Speed Limiter"
        printf "  ${C_CHOICE}%-4s${C_RESET} %-22s ${C_CHOICE}%-4s${C_RESET} %s\n" "[36]" "IP Firewall" "[37]" "Logs Hub"
        printf "  ${C_CHOICE}%-4s${C_RESET} %-22s ${C_CHOICE}%-4s${C_RESET} %s\n" "[97]" "Report Issue" "[98]" "Updates${up_badge}"
        echo
        menu_section "DANGER ZONE" "$C_DANGER"
        printf "  ${C_DANGER}%-4s${C_RESET} %-22s ${C_WARN}%-4s${C_RESET} %s\n" "[99]" "Uninstall" "[0]" "Exit"
        echo
        if ! read -r -p "$(echo -e ${C_PROMPT}"> Select an option: "${C_RESET})" choice; then
            echo
            exit 0
        fi
        case $choice in
            1) create_user; press_enter ;;
            2) delete_user; press_enter ;;
            3) renew_user; press_enter ;;
            4) lock_user; press_enter ;;
            5) unlock_user; press_enter ;;
            6) edit_user; press_enter ;;
            7) list_users; press_enter ;;
            8) create_trial_account; press_enter ;;
            9) view_user_bandwidth; press_enter ;;
            10) bulk_create_users; press_enter ;;
            11) user_speed_menu ;;
            12) live_session_monitor ;;
            13) connection_logs_menu ;;
            14) client_config_menu; press_enter ;;

            15) vless_reality_menu ;;
            16) v2ray_create_user_cli ;;
            17) v2ray_list_users_cli ;;
            18) v2ray_show_user_links_cli ;;
            19) v2ray_renew_user_cli ;;
            20) v2ray_delete_user_cli ;;
            21) v2ray_import_ssh_cli ;;

            22) protocol_menu ;;
            23) traffic_monitor_menu ;;
            24) torrent_block_menu ;;
            25) anti_multilogin_menu ;;

            26) dns_menu; press_enter ;;
            27) ssh_banner_menu ;;
            28) auto_reboot_menu ;;
            29) backup_user_data; press_enter ;;
            30) restore_user_data; press_enter ;;
            31) cleanup_expired; press_enter ;;
            32) web_panel_menu ;;
            33) telegram_bot_menu ;;
            34) auto_healing_menu ;;
            35) speed_limiter_menu ;;
            36) ip_firewall_menu ;;
            37) advanced_logs_menu ;;

            97) report_issue_dialog ;;
            98|[uU]) trigger_standalone_update_page ;;
            99) uninstall_script ;;
            0) exit 0 ;;
            *) invalid_option ;;
        esac
    done
}

if [[ "$1" == "_run_multilogin" ]]; then
    check_and_kill_multilogin
    exit 0
fi

if [[ "$1" == "_run_auto_healing" ]]; then
    run_auto_healing_check
    exit 0
fi

if [[ "$1" == "--install-setup" ]]; then
    initial_setup
    exit 0
fi

if [[ "$1" == "--uninstall" ]]; then
    require_interactive_terminal
    uninstall_script
    exit 0
fi

UPDATE_CACHE_FILE="/tmp/.ff_remote_ver_cache"
VERSION_FILE="/etc/firewallfalcon/.version"

get_installed_sha() {
    local sha=""
    if [[ -f "$VERSION_FILE" && -s "$VERSION_FILE" ]]; then
        sha=$(cat "$VERSION_FILE" 2>/dev/null | tr -d ' \r\n')
        sha="${sha##*beta_}"
        sha="${sha##*4.6.0_}"
        sha="${sha##*4.5.0_}"
        sha="${sha##*beta-}"
        sha="${sha:0:7}"
    fi
    if [[ -z "$sha" || ${#sha} -ne 7 ]]; then
        sha="2272381"
        mkdir -p "/etc/firewallfalcon" 2>/dev/null
        echo "$sha" > "$VERSION_FILE" 2>/dev/null
    fi
    echo "$sha"
}

get_current_version_tag() {
    local sha; sha=$(get_installed_sha)
    local branch_name; branch_name=$(get_update_branch)
    if [[ -n "$sha" ]]; then
        if [[ "$branch_name" == "dev" ]]; then
            echo "4.6.0_dev_${sha}"
        elif [[ "$branch_name" == "beta2" ]]; then
            echo "4.6.0_beta_${sha}"
        else
            echo "4.6.0_${sha}"
        fi
    else
        if [[ "$branch_name" == "dev" ]]; then
            echo "4.6.0_dev_installed"
        elif [[ "$branch_name" == "beta2" ]]; then
            echo "4.6.0_beta_installed"
        else
            echo "4.6.0_installed"
        fi
    fi
}

_check_remote_ver_bg() {
    local lock_file="/tmp/.ff_ver_check.lock"
    local now_ts; now_ts=$(date +%s 2>/dev/null || echo 0)
    local last_check=0
    if [[ -f "$UPDATE_CACHE_FILE" ]]; then
        read -r last_check _ < "$UPDATE_CACHE_FILE" 2>/dev/null
    fi

    if (( now_ts - last_check >= 60 )) && [[ ! -f "$lock_file" ]]; then
        touch "$lock_file" 2>/dev/null
        (
            local branch_name; branch_name=$(get_update_branch)
            local api_j c_sha
            api_j=$(curl -s --max-time 3 "https://api.github.com/repos/mooa322/fm/branches/${branch_name}" 2>/dev/null)
            if [[ -n "$api_j" ]]; then
                c_sha=$(echo "$api_j" | jq -r '.commit.sha' 2>/dev/null | cut -c1-7)
                if [[ -n "$c_sha" && "$c_sha" != "null" && ${#c_sha} -eq 7 ]]; then
                    echo "$now_ts $c_sha" > "$UPDATE_CACHE_FILE"
                fi
            fi
            rm -f "$lock_file" 2>/dev/null
        ) &>/dev/null &
    fi
}

check_auto_update() {
    local branch_name; branch_name=$(get_update_branch)
    local cur_sha; cur_sha=$(get_installed_sha)
    local api_json remote_sha=""
    
    # Fast synchronous check on startup against default channel (max 2.5 seconds)
    api_json=$(curl -s --max-time 3 "https://api.github.com/repos/mooa322/fm/branches/${branch_name}" 2>/dev/null)
    if [[ -n "$api_json" ]]; then
        remote_sha=$(echo "$api_json" | jq -r '.commit.sha' 2>/dev/null | cut -c1-7)
    fi
    
    if [[ -n "$remote_sha" && "$remote_sha" != "null" && ${#remote_sha} -eq 7 ]]; then
        local now_ts; now_ts=$(date +%s 2>/dev/null || echo 0)
        echo "$now_ts $remote_sha" > "$UPDATE_CACHE_FILE" 2>/dev/null
        
        if [[ -n "$cur_sha" && ${#cur_sha} -eq 7 && "$cur_sha" != "$remote_sha" ]]; then
            BANNER_CACHE_HAS_UPDATE=true
            BANNER_CACHE_REMOTE_VER="4.6.0_${remote_sha}"
            [[ "$branch_name" == "beta2" ]] && BANNER_CACHE_REMOTE_VER="4.6.0_beta_${remote_sha}"
            [[ "$branch_name" == "dev" ]] && BANNER_CACHE_REMOTE_VER="4.6.0_dev_${remote_sha}"
            
            local friendly_branch="Stable"
            [[ "$branch_name" == "beta2" ]] && friendly_branch="Beta"
            [[ "$branch_name" == "dev" ]] && friendly_branch="Development"
            
            clear
            echo
            echo -e "${C_PURPLE}  ╭───────────────────────────────────────────────────────────╮${C_RESET}"
            echo -e "${C_PURPLE}  │${C_RESET} ${C_YELLOW}${C_BOLD}🚀 NEW UPDATE AVAILABLE!${C_RESET}                                 ${C_PURPLE}│${C_RESET}"
            echo -e "${C_PURPLE}  │${C_RESET}                                                           ${C_PURPLE}│${C_RESET}"
            echo -e "${C_PURPLE}  │${C_RESET}  ${C_CYAN}Installed Version :${C_RESET} $(get_current_version_tag)"
            echo -e "${C_PURPLE}  │${C_RESET}  ${C_CYAN}Latest Version    :${C_RESET} ${C_GREEN}${BANNER_CACHE_REMOTE_VER}${C_RESET}"
            echo -e "${C_PURPLE}  │${C_RESET}  ${C_CYAN}Default Channel   :${C_RESET} ${C_CYAN}${friendly_branch} (${branch_name})${C_RESET}"
            echo -e "${C_PURPLE}  │${C_RESET}                                                           ${C_PURPLE}│${C_RESET}"
            echo -e "${C_PURPLE}  ╰───────────────────────────────────────────────────────────╯${C_RESET}"
            echo
            echo -e "  ${C_CHOICE}[1]${C_RESET} Update Tool Now"
            echo -e "  ${C_CHOICE}[2]${C_RESET} Continue to Main Menu"
            echo
            local u_choice="2"
            read -r -t 8 -p "$(echo -e "${C_PROMPT}> Select an option [2] (Auto-continue in 8s): ${C_RESET}")" u_choice || u_choice="2"
            u_choice=${u_choice:-2}
            if [[ "$u_choice" == "1" || "$u_choice" =~ ^[uU]$ ]]; then
                trigger_standalone_update_page
            fi
        fi
    else
        _check_remote_ver_bg
    fi
}

_fm_license_check
require_interactive_terminal
sync_runtime_components_if_needed
check_auto_update
main_menu
