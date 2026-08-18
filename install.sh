#!/bin/bash
set -e

# ---- Colors ----
C_RESET=$'\033[0m'
C_BOLD=$'\033[1m'
C_DIM=$'\033[2m'
C_RED=$'\033[38;5;196m'      # Bright Red
C_GREEN=$'\033[38;5;46m'     # Neon Green
C_YELLOW=$'\033[38;5;226m'   # Bright Yellow
C_BLUE=$'\033[38;5;39m'      # Deep Sky Blue
C_PURPLE=$'\033[38;5;135m'   # Light Purple
C_CYAN=$'\033[38;5;51m'      # Cyan
C_WHITE=$'\033[38;5;255m'    # Bright White
C_GRAY=$'\033[38;5;245m'     # Gray
C_ORANGE=$'\033[38;5;208m'   # Orange

# ---- Paths ----
MENU_BIN="/usr/local/bin/menu"
FF_DIR="/etc/firewallfalcon"
INSTALL_FLAG="$FF_DIR/.install"
VERSION_FILE="$FF_DIR/.version"

# Branch Configuration (Dynamic)
BRANCH="dev"
VER_PREFIX="4.6_dev"

# Read existing channel if present
if [ -f "$FF_DIR/channel" ]; then
    BRANCH=$(cat "$FF_DIR/channel" | tr -d '[:space:]')
elif [ -f "/etc/firewallfalcon/channel" ]; then
    BRANCH=$(cat "/etc/firewallfalcon/channel" | tr -d '[:space:]')
fi

# Parse command line arguments
for arg in "$@"; do
    case $arg in
        --channel=dev|--dev)
            BRANCH="dev"
            ;;
        --channel=beta|--beta)
            BRANCH="beta2"
            ;;
        --channel=stable|--stable)
            BRANCH="main"
            ;;
    esac
done

if [[ "$BRANCH" == "dev" ]]; then
    VER_PREFIX="4.6_dev"
elif [[ "$BRANCH" == "beta2" ]]; then
    VER_PREFIX="4.6_beta"
else
    BRANCH="main"
    VER_PREFIX="4.6_stable"
fi

# URLs (GitHub is the authoritative source)
MENU_URL="https://raw.githubusercontent.com/mooa322/fm/${BRANCH}/menu.sh"
SSHD_URL="https://raw.githubusercontent.com/mooa322/fm/${BRANCH}/ssh"


# Must be root
if [[ $EUID -ne 0 ]]; then
   echo -e "${C_RED}[FAIL] Error: This script must be run as root.${C_RESET}"
   exit 1
fi

# ── License gate ─────────────────────────────────────────────────────
# The protected payload (menu.sh, ssh, panel, update_panel.sh) is not
# published in plaintext. It ships as a per-client encrypted bundle at
# clients/<id>.enc. This gate fetches that bundle, decrypts it with the
# client's key, and unpacks it to $FM_SRC for the installer to use.
FM_SRC="$FF_DIR/.src"
FM_LICENSE="$FF_DIR/.license"
CLIENTS_URL="https://raw.githubusercontent.com/mooa322/fm/main/clients"

fm_gate() {
    [ -n "${_FM_GATE_DONE:-}" ] && [ -f "$FM_SRC/menu.sh" ] && return 0

    if ! command -v openssl >/dev/null 2>&1; then
        (apt-get install -y -q openssl || yum install -y -q openssl || \
         dnf install -y -q openssl || apk add openssl || pacman -Sy --noconfirm openssl) >/dev/null 2>&1 || true
    fi
    command -v openssl >/dev/null 2>&1 || {
        echo -e "${C_RED}[FAIL] openssl is required and could not be installed.${C_RESET}"; exit 1; }

    local id="${FM_ID:-}" key="${FM_KEY:-}"
    if { [ -z "$id" ] || [ -z "$key" ]; } && [ -f "$FM_LICENSE" ]; then
        id="$(sed -n 's/^FM_ID=//p'  "$FM_LICENSE" 2>/dev/null)"
        key="$(sed -n 's/^FM_KEY=//p' "$FM_LICENSE" 2>/dev/null)"
    fi
    if [ -z "$id" ] || [ -z "$key" ]; then
        echo
        echo -e "  ${C_CYAN}┌── License Required ────────────────────────────────────┐${C_RESET}"
        echo -e "  ${C_CYAN}│${C_RESET}  ${C_WHITE}Enter the license you received to continue.${C_RESET}"
        echo -e "  ${C_CYAN}└────────────────────────────────────────────────────────┘${C_RESET}"
        [ -z "$id" ]  && read -r  -p "$(echo -e "  ${C_BLUE}License ID : ${C_RESET}")" id
        [ -z "$key" ] && read -rs -p "$(echo -e "  ${C_BLUE}License Key: ${C_RESET}")" key && echo
    fi
    [ -n "$id" ] && [ -n "$key" ] || {
        echo -e "${C_RED}[FAIL] No license provided.${C_RESET}"; exit 1; }

    local enc; enc="$(mktemp)"
    if ! curl -fsSL "$CLIENTS_URL/${id}.enc" -o "$enc" 2>/dev/null; then
        rm -f "$enc"
        echo -e "${C_RED}[FAIL] License '${id}' not found or has been revoked.${C_RESET}"
        echo -e "${C_YELLOW}       Contact the provider for a valid license.${C_RESET}"
        exit 1
    fi
    rm -rf "$FM_SRC"; mkdir -p "$FM_SRC"; chmod 700 "$FM_SRC"
    if ! openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -in "$enc" -pass "pass:${key}" 2>/dev/null \
         | tar -xzf - -C "$FM_SRC" 2>/dev/null || [ ! -f "$FM_SRC/menu.sh" ]; then
        rm -f "$enc"; rm -rf "$FM_SRC"
        echo -e "${C_RED}[FAIL] Wrong license key for '${id}'.${C_RESET}"
        exit 1
    fi
    rm -f "$enc"

    mkdir -p "$FF_DIR"
    printf 'FM_ID=%s\nFM_KEY=%s\n' "$id" "$key" > "$FM_LICENSE"
    chmod 600 "$FM_LICENSE"
    _FM_GATE_DONE=1
    echo -e "  ${C_GREEN}✅ License '${id}' verified.${C_RESET}"
}

fetch_remote_sha() {
    local api_json commit_sha
    if command -v jq &>/dev/null; then
        api_json=$(curl -s --max-time 4 "https://api.github.com/repos/mooa322/fm/branches/${BRANCH}" 2>/dev/null)
        if [[ -n "$api_json" ]]; then
            commit_sha=$(echo "$api_json" | jq -r '.commit.sha' 2>/dev/null | cut -c1-7)
            if [[ -n "$commit_sha" && "$commit_sha" != "null" ]]; then
                echo "$commit_sha"
                return
            fi
        fi
    fi
    echo ""
}

fetch_remote_version() {
    local sha; sha=$(fetch_remote_sha)
    if [[ -n "$sha" ]]; then
        echo "${VER_PREFIX}_${sha}"
    else
        echo "${VER_PREFIX}_latest"
    fi
}

get_installed_sha() {
    if [[ -f "$VERSION_FILE" && -s "$VERSION_FILE" ]]; then
        cat "$VERSION_FILE" 2>/dev/null | tr -d ' \r\n'
    else
        echo ""
    fi
}

get_installed_version() {
    local sha; sha=$(get_installed_sha)
    if [[ -n "$sha" ]]; then
        echo "${VER_PREFIX}_${sha}"
    else
        echo "${VER_PREFIX}_installed"
    fi
}

save_installed_version() {
    local ver="$1"
    local sha="${ver##*_}"
    mkdir -p "$FF_DIR" 2>/dev/null
    echo "$sha" > "$VERSION_FILE"
}

# Check whether DAHOOM is already installed
is_installed() {
    [[ -x "$MENU_BIN" && -f "$INSTALL_FLAG" ]]
}

# Helper to download files (supports both curl and wget)
download_file() {
    local dest=$1
    local url=$2
    if command -v curl &> /dev/null; then
        curl -sL -o "$dest" "$url"
    elif command -v wget &> /dev/null; then
        wget -q -O "$dest" "$url"
    else
        echo -e "${C_RED}[FAIL] Error: Neither curl nor wget is installed.${C_RESET}"
        exit 1
    fi
}

# Smooth interactive progress bar helper
show_progress_bar() {
    local label="$1"
    local steps="${2:-20}"
    local delay="${3:-0.02}"
    local width=28
    local i pct filled empty bar_str f e

    tput civis 2>/dev/null || true
    printf "  ${C_CYAN}⏳ %s${C_RESET}\n" "$label"
    for ((i=1; i<=steps; i++)); do
        pct=$(( (i * 100) / steps ))
        filled=$(( (pct * width) / 100 ))
        empty=$(( width - filled ))

        bar_str=""
        for ((f=0; f<filled; f++)); do bar_str+="█"; done
        for ((e=0; e<empty; e++)); do bar_str+="░"; done

        printf "\r  ${C_BLUE}❲${C_GREEN}%s${C_BLUE}❳${C_RESET} ${C_YELLOW}%3d%%${C_RESET}" "$bar_str" "$pct"
        sleep "$delay"
    done
    printf " ${C_GREEN}✔ Done${C_RESET}\n\n"
    tput cnorm 2>/dev/null || true
}

# Ensure the installed menu supports the --uninstall flag.
patch_menu_in_place() {
    local file=$1
    sed -i '/^if \[\[ .* == "--uninstall" \]\]; then$/{N;N;N;N;d}' "$file" 2>/dev/null || true
    if grep -qF -- 'if [[ "$1" == "--uninstall" ]]; then' "$file" 2>/dev/null; then
        return 0
    fi
    sed -i '/^main_menu$/i\
if [[ "$1" == "--uninstall" ]]; then\
    require_interactive_terminal\
    uninstall_script\
    exit 0\
fi' "$file"
    chmod +x "$file"
}

patch_menu_for_uninstall() {
    if grep -qF -- 'if [[ "$1" == "--uninstall" ]]; then' "$MENU_BIN" 2>/dev/null; then
        return
    fi
    local tmp_menu="${MENU_BIN}.patched.$$"
    if [ -f "$FM_SRC/menu.sh" ]; then
        cp -f "$FM_SRC/menu.sh" "$tmp_menu"
        patch_menu_in_place "$tmp_menu"
        mv -f "$tmp_menu" "$MENU_BIN"
    else
        rm -f "$tmp_menu"
        patch_menu_in_place "$MENU_BIN"
    fi
    chmod +x "$MENU_BIN"
    echo -e "${C_GRAY}${C_DIM}[INFO] Menu patched for uninstaller support.${C_RESET}"
}

# ---- Install DAHOOM ----
install_tool() {
    clear
    
    # If not silent and not pre-configured, prompt for channel
    local silent_install=false
    for arg in "$@"; do
        [[ "$arg" == "--silent" ]] && silent_install=true
    done

    if [ -f "/etc/firewallfalcon/channel" ]; then
        BRANCH=$(cat "/etc/firewallfalcon/channel" | tr -d '[:space:]')
        if [[ "$BRANCH" == "dev" ]]; then
            VER_PREFIX="4.6_dev"
        elif [[ "$BRANCH" == "beta2" ]]; then
            VER_PREFIX="4.6_beta"
        else
            BRANCH="main"
            VER_PREFIX="4.6_stable"
        fi
    elif [ "$silent_install" = "false" ]; then
        echo -e "  ${C_CYAN}┌────────────────────────────────────────────────────────┐${C_RESET}"
        echo -e "  ${C_CYAN}│${C_RESET}  ${C_BOLD}Select Update Channel:${C_RESET}                                ${C_CYAN}│${C_RESET}"
        echo -e "  ${C_CYAN}│${C_RESET}                                                        ${C_CYAN}│${C_RESET}"
        echo -e "  ${C_CYAN}│${C_RESET}  ${C_GREEN}[1] Stable Channel (Recommended)${C_RESET}                      ${C_CYAN}│${C_RESET}"
        echo -e "  ${C_CYAN}│${C_RESET}  ${C_YELLOW}[2] Beta Channel (Upcoming Features)${C_RESET}                 ${C_CYAN}│${C_RESET}"
        echo -e "  ${C_CYAN}│${C_RESET}  ${C_PURPLE}[3] Dev Channel (Bleeding Edge Experimental)${C_RESET}         ${C_CYAN}│${C_RESET}"
        echo -e "  ${C_CYAN}└────────────────────────────────────────────────────────┘${C_RESET}"
        echo
        read -p "👉 Choose channel [3]: " ch_choice
        ch_choice=${ch_choice:-3}
        if [[ "$ch_choice" == "1" ]]; then
            BRANCH="main"
            VER_PREFIX="4.6_stable"
            echo -e "\n  ${C_GREEN}✅ Stable channel selected.${C_RESET}\n"
        elif [[ "$ch_choice" == "2" ]]; then
            BRANCH="beta2"
            VER_PREFIX="4.6_beta"
            echo -e "\n  ${C_YELLOW}🚀 Beta channel selected.${C_RESET}\n"
        else
            BRANCH="dev"
            VER_PREFIX="4.6_dev"
            echo -e "\n  ${C_PURPLE}🧪 Dev channel (Bleeding-Edge) selected.${C_RESET}\n"
        fi
    fi

    # Redefine URLs with chosen branch
    MENU_URL="https://raw.githubusercontent.com/mooa322/fm/${BRANCH}/menu.sh"
    SSHD_URL="https://raw.githubusercontent.com/mooa322/fm/${BRANCH}/ssh"

    # Save the selected channel
    mkdir -p "/etc/firewallfalcon" 2>/dev/null
    echo "$BRANCH" > "/etc/firewallfalcon/channel"

    echo
    echo -e "  ${C_CYAN}┌── Installation ────────────────────────────────────────┐${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET}  ${C_PURPLE}${C_BOLD}Starting DAHOOM Installation...${C_RESET}"
    echo -e "  ${C_CYAN}└────────────────────────────────────────────────────────┘${C_RESET}"
    echo
    echo -e "  ${C_CYAN}┌── Installation in Progress ────────────────────────────┐${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET}  ${C_GREEN}${C_BOLD}Starting DAHOOM Installation...${C_RESET}"
    echo -e "  ${C_CYAN}└────────────────────────────────────────────────────────┘${C_RESET}"
    echo

    fm_gate

    show_progress_bar "[1/4] Installing core menu binary..." 20 0.02
    cp -f "$FM_SRC/menu.sh" "$MENU_BIN"
    chmod +x "$MENU_BIN"
    patch_menu_in_place "$MENU_BIN"

    show_progress_bar "[2/4] Applying DAHOOM SSH configurations..." 20 0.02
    SSHD_CONFIG="/etc/ssh/sshd_config"
    BACKUP="/etc/ssh/sshd_config.backup.$(date +%F-%H%M%S)"
    cp "$SSHD_CONFIG" "$BACKUP" 2>/dev/null || true
    cp -f "$FM_SRC/ssh" "$SSHD_CONFIG"
    chmod 600 "$SSHD_CONFIG"

    if ! sshd -t 2>/dev/null; then
        echo -e "  ${C_RED}❌ ERROR: SSH configuration is invalid!${C_RESET}"
        echo -e "  ${C_YELLOW}⚠️ Restoring previous configuration...${C_RESET}"
        cp "$BACKUP" "$SSHD_CONFIG" 2>/dev/null || true
        exit 1
    fi

    show_progress_bar "[3/4] Restarting SSH subsystem safely..." 15 0.02
    restart_ssh() {
        if command -v systemctl >/dev/null 2>&1; then
            systemctl restart sshd 2>/dev/null \
            || systemctl restart ssh 2>/dev/null \
            || return 1
        elif command -v service >/dev/null 2>&1; then
            service sshd restart 2>/dev/null \
            || service ssh restart 2>/dev/null \
            || return 1
        elif command -v rc-service >/dev/null 2>&1; then
            rc-service sshd restart 2>/dev/null \
            || rc-service ssh restart 2>/dev/null \
            || return 1
        elif [ -x /etc/init.d/sshd ]; then
            /etc/init.d/sshd restart >/dev/null 2>&1
        elif [ -x /etc/init.d/ssh ]; then
            /etc/init.d/ssh restart >/dev/null 2>&1
        else
            return 1
        fi
    }
    restart_ssh || true

    show_progress_bar "[4/4] Initializing active limiters, custom login banner & databases..." 25 0.02
    bash "$MENU_BIN" --install-setup >/dev/null 2>&1 || bash "$MENU_BIN" --install-setup
    local new_ver; new_ver=$(fetch_remote_version)
    save_installed_version "$new_ver"

    echo
    echo -e "  ${C_CYAN}┌── Installation Complete ────────────────────────────────┐${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET}  ${C_GREEN}✅ DAHOOM installed successfully!${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET}  ${C_YELLOW}Version: ${new_ver}${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET}  ${C_YELLOW}Type 'menu' anytime to launch the control panel.${C_RESET}"
    echo -e "  ${C_CYAN}└────────────────────────────────────────────────────────┘${C_RESET}"
    echo
    echo -e "  ${C_GREEN}[1]${C_RESET} Open DAHOOM Manager"
    echo -e "  ${C_GREEN}[2]${C_RESET} Return to Installer Menu"
    echo -e "  ${C_RED}[0]${C_RESET} Exit"
    echo
    read -p "$(echo -e "${C_BLUE}👉 Select action [1]: ${C_RESET}")" post_inst_action
    post_inst_action=${post_inst_action:-1}
    case "$post_inst_action" in
        1)
            run_menu
            ;;
        2)
            ;;
        0)
            echo -e "${C_GRAY}Goodbye!${C_RESET}"
            exit 0
            ;;
        *)
            ;;
    esac
}

# ---- Uninstall DAHOOM ----
uninstall_tool() {
    clear
    echo
    if ! is_installed; then
        echo -e "  ${C_YELLOW}⚠️ DAHOOM is not installed. Nothing to uninstall.${C_RESET}"
        sleep 1.5
        return
    fi
    echo -e "  ${C_CYAN}┌── Uninstallation ──────────────────────────────────────┐${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET}  ${C_RED}${C_BOLD}Starting DAHOOM Uninstallation...${C_RESET}"
    echo -e "  ${C_CYAN}└────────────────────────────────────────────────────────┘${C_RESET}"
    echo
    if [[ -x "$MENU_BIN" ]]; then
        patch_menu_for_uninstall
        echo -e "  ${C_BLUE}🗑️ Launching uninstaller...${C_RESET}"
        bash "$MENU_BIN" --uninstall
    else
        echo -e "  ${C_YELLOW}⚠️ Menu binary is missing — removing residual files...${C_RESET}"
        rm -rf "$FF_DIR"
        rm -f "/etc/update-motd.d/01-falcon-banner" "/usr/local/bin/falcon-motd" "/etc/profile.d/falcon_motd.sh"
        chmod +x /etc/update-motd.d/10-help-text /etc/update-motd.d/50-motd-news 2>/dev/null || true
        echo -e "  ${C_GREEN}✅ Residual files removed.${C_RESET}"
    fi
    echo
    echo -e "  ${C_CYAN}┌── Uninstallation Complete ─────────────────────────────┐${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET}  ${C_GREEN}✅ DAHOOM uninstalled successfully.${C_RESET}"
    echo -e "  ${C_CYAN}└────────────────────────────────────────────────────────┘${C_RESET}"
    echo
    echo -e "  ${C_GREEN}[1]${C_RESET} Return to Installer Menu"
    echo -e "  ${C_RED}[0]${C_RESET} Exit"
    echo
    read -p "$(echo -e "${C_BLUE}👉 Select action [1]: ${C_RESET}")" post_uninst_action
    post_uninst_action=${post_uninst_action:-1}
    if [[ "$post_uninst_action" == "0" ]]; then
        echo -e "${C_GRAY}Goodbye!${C_RESET}"
        exit 0
    fi
}

# ---- Open the installed DAHOOM menu ----
run_menu() {
    clear
    if [[ -x "$MENU_BIN" ]]; then
        bash "$MENU_BIN"
    else
        echo -e "  ${C_YELLOW}⚠️ Menu binary not found. Please install first.${C_RESET}"
        sleep 1.5
    fi
}

# ---- Update Tool Page ----
update_tool_page() {
    clear
    echo
    echo -e "  ${C_CYAN}┌── Update Manager ────────────────────────────┐${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET}  ${C_WHITE}${C_BOLD}Checking GitHub updates...${C_RESET}"
    echo -e "  ${C_CYAN}└──────────────────────────────────────────────┘${C_RESET}"
    echo
    show_progress_bar "Checking for latest updates on branch ($BRANCH)..." 15

    local cur_ver; cur_ver=$(get_installed_version)
    local latest_ver; latest_ver=$(fetch_remote_version)
    local cur_sha; cur_sha=$(get_installed_sha)
    local latest_sha; latest_sha=$(fetch_remote_sha)

    local has_update=false
    if [[ -n "$latest_sha" && -n "$cur_sha" && "$cur_sha" != "$latest_sha" ]]; then
        has_update=true
    fi

    clear
    echo
    echo -e "  ${C_CYAN}┌── Update Manager ────────────────────────────┐${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET}  ${C_WHITE}${C_BOLD}Current :${C_RESET} ${C_YELLOW}${cur_ver}${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET}  ${C_WHITE}${C_BOLD}Latest  :${C_RESET} ${C_GREEN}${latest_ver}${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET}  ${C_WHITE}${C_BOLD}Branch  :${C_RESET} ${C_CYAN}${BRANCH}${C_RESET}"

    if $has_update; then
        echo -e "  ${C_CYAN}│${C_RESET}  ${C_WHITE}${C_BOLD}Status  :${C_RESET} ${C_YELLOW}${C_BOLD}🚀 Update available${C_RESET}"
        echo -e "  ${C_CYAN}└──────────────────────────────────────────────┘${C_RESET}"
        echo
        echo -e "  ${C_GREEN}[1]${C_RESET} Update Tool"
        echo -e "  ${C_GREEN}[2]${C_RESET} Reinstall / Repair"
        echo -e "  ${C_RED}[0]${C_RESET} Back"
        echo
        read -p "$(echo -e "${C_BLUE}👉 Select action [1]: ${C_RESET}")" up_choice
        up_choice=${up_choice:-1}
        case "$up_choice" in
            1|2)
                echo
                fm_gate
                show_progress_bar "Installing core binaries..." 20
                cp -f "$FM_SRC/menu.sh" "$MENU_BIN"
                chmod +x "$MENU_BIN"
                patch_menu_in_place "$MENU_BIN"
                save_installed_version "$latest_ver"

                echo
                echo -e "  ${C_CYAN}┌── Update Complete ───────────────────────────┐${C_RESET}"
                echo -e "  ${C_CYAN}│${C_RESET}  ${C_GREEN}✅ Updated successfully!${C_RESET}"
                echo -e "  ${C_CYAN}│${C_RESET}  ${C_YELLOW}Version: ${latest_ver}${C_RESET}"
                echo -e "  ${C_CYAN}└──────────────────────────────────────────────┘${C_RESET}"
                echo
                read -p "$(echo -e "${C_BLUE}👉 Press [Enter] to return...${C_RESET}")" _
                ;;
            0|*)
                ;;
        esac
    else
        echo -e "  ${C_CYAN}│${C_RESET}  ${C_WHITE}${C_BOLD}Status  :${C_RESET} ${C_GREEN}${C_BOLD}✅ Up to date${C_RESET}"
        echo -e "  ${C_CYAN}└──────────────────────────────────────────────┘${C_RESET}"
        echo
        echo -e "  ${C_GREEN}✨ System is up to date${C_RESET}"
        echo
        echo -e "  ${C_GREEN}[1]${C_RESET} Reinstall / Repair"
        echo -e "  ${C_RED}[0]${C_RESET} Back"
        echo
        read -p "$(echo -e "${C_BLUE}👉 Select action [0]: ${C_RESET}")" no_up_choice
        no_up_choice=${no_up_choice:-0}
        if [[ "$no_up_choice" == "1" ]]; then
            echo
            fm_gate
            show_progress_bar "Re-installing core binaries..." 20
            cp -f "$FM_SRC/menu.sh" "$MENU_BIN"
            chmod +x "$MENU_BIN"
            patch_menu_in_place "$MENU_BIN"
            save_installed_version "$latest_ver"

            echo
            echo -e "  ${C_CYAN}┌── Repair Complete ───────────────────────────┐${C_RESET}"
            echo -e "  ${C_CYAN}│${C_RESET}  ${C_GREEN}✅ Repaired successfully!${C_RESET}"
            echo -e "  ${C_CYAN}└──────────────────────────────────────────────┘${C_RESET}"
            echo
            read -p "$(echo -e "${C_BLUE}👉 Press [Enter] to return...${C_RESET}")" _
        fi
    fi
}


# ---- Panel Arabic Update ----
panel_arabic_update() {
    clear
    echo
    echo -e "  ${C_CYAN}┌── Panel Arabic Update ─────────────────────────────────┐${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET}  ${C_PURPLE}${C_BOLD}Starting Panel Arabic Update (new_panel branch)...${C_RESET}"
    echo -e "  ${C_CYAN}└────────────────────────────────────────────────────────┘${C_RESET}"
    echo
    show_progress_bar "Downloading and updating Arabic Web Panel..." 15

    fm_gate
    bash "$FM_SRC/update_panel.sh"

    echo
    echo -e "  ${C_CYAN}┌── Update Complete ─────────────────────────────────────┐${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET}  ${C_GREEN}✅ Panel Arabic Update completed successfully!${C_RESET}"
    echo -e "  ${C_CYAN}└────────────────────────────────────────────────────────┘${C_RESET}"
    echo
    read -p "$(echo -e "${C_BLUE}👉 Press [Enter] to return to installer menu...${C_RESET}")" _
}

# ---- Details panel ----
show_details() {
    clear
    local cur_ver; cur_ver=$(get_installed_version)
    local latest_ver; latest_ver=$(fetch_remote_version 2>/dev/null || true)
    local cur_sha; cur_sha=$(get_installed_sha)
    local latest_sha; latest_sha=$(fetch_remote_sha 2>/dev/null || true)
    local update_badge=""
    local has_up=false

    if [[ -n "$latest_sha" && -n "$cur_sha" && "$cur_sha" != "$latest_sha" ]]; then
        has_up=true
        update_badge=" ${C_YELLOW}${C_BOLD}[🚀 New: ${latest_ver}]${C_RESET}"
    fi

    echo -e ""
    echo -e "${C_PURPLE}${C_BOLD}DAHOOM Installer${C_RESET}"
    echo -e "${C_GRAY}${C_DIM}──────────────────────────────────────────────${C_RESET}"
    echo -e "  ${C_WHITE}${C_BOLD}Name:${C_RESET}        DAHOOM"
    echo -e "  ${C_WHITE}${C_BOLD}Version:${C_RESET}     ${C_YELLOW}${cur_ver}${C_RESET}${update_badge}"
    echo -e "  ${C_WHITE}${C_BOLD}Type:${C_RESET}        SSH/VPN Manager"
    echo -e "  ${C_WHITE}${C_BOLD}Maintained by:${C_RESET} ${C_BLUE}aljailane (Abu Sultan)${C_RESET}"
    if is_installed; then
        echo -e "  ${C_WHITE}${C_BOLD}Status:${C_RESET}      ${C_GREEN}[OK] Installed${C_RESET}"
    else
        echo -e "  ${C_WHITE}${C_BOLD}Status:${C_RESET}      ${C_RED}[X] Not Installed${C_RESET}"
    fi
    if $has_up; then
        echo -e "  ${C_WHITE}${C_BOLD}Update:${C_RESET}      ${C_YELLOW}${C_BOLD}🚀 New version available! [2]${C_RESET}"
    fi
    echo -e "${C_GRAY}${C_DIM}──────────────────────────────────────────────${C_RESET}"
    echo -e "  ${C_GRAY}${C_DIM}Features:${C_RESET}"
    echo -e "   - SSH: Create, renew, lock & delete accounts"
    echo -e "   - VPN: DNSTT, UDP-Custom, BadVPN, HAProxy, Falcon"
    echo -e "   - Tools: Traffic monitor, trial & backups"
    echo -e "   - Web Panel: Control panel & deSEC DNS"
    echo -e "${C_GRAY}${C_DIM}──────────────────────────────────────────────${C_RESET}"
}

# ---- Main menu loop ----
installer_menu() {
    while true; do
        show_details
        local cur_ver; cur_ver=$(get_installed_version)
        local latest_ver; latest_ver=$(fetch_remote_version 2>/dev/null || true)
        local up_tag=""
        if [[ -n "$latest_ver" && "$cur_ver" != "$latest_ver" ]]; then
            up_tag=" ${C_YELLOW}${C_BOLD}(🚀 New Available)${C_RESET}"
        fi

        echo -e ""
        if is_installed; then
            echo -e "  ${C_CYAN}[1]${C_RESET} ${C_WHITE}${C_BOLD}Menu${C_RESET}"
            echo -e "  ${C_CYAN}[2]${C_RESET} ${C_WHITE}${C_BOLD}Update Tool${C_RESET}${up_tag}"
            echo -e "  ${C_CYAN}[3]${C_RESET} ${C_WHITE}${C_BOLD}Uninstall${C_RESET}"
            echo -e "  ${C_CYAN}[4]${C_RESET} ${C_WHITE}${C_BOLD}Panel Arabic Update${C_RESET}"
            echo -e "  ${C_CYAN}[5]${C_RESET} ${C_WHITE}${C_BOLD}Exit${C_RESET}"
        else
            echo -e "  ${C_CYAN}[1]${C_RESET} ${C_WHITE}${C_BOLD}Install${C_RESET}"
            echo -e "  ${C_CYAN}[2]${C_RESET} ${C_WHITE}${C_BOLD}Check Updates${C_RESET}${up_tag}"
            echo -e "  ${C_CYAN}[3]${C_RESET} ${C_WHITE}${C_BOLD}Panel Arabic Update${C_RESET}"
            echo -e "  ${C_CYAN}[4]${C_RESET} ${C_WHITE}${C_BOLD}Exit${C_RESET}"
        fi
        echo -e ""
        if ! read -r -p "$(echo -e "${C_BLUE}> Select option: ${C_RESET}")" choice; then
            echo -e ""
            exit 0
        fi
        if is_installed; then
            case $choice in
                1) run_menu ;;
                2) update_tool_page ;;
                3) uninstall_tool ;;
                4|panel|arabic) panel_arabic_update ;;
                5|0|q|Q|exit) echo -e "${C_GRAY}Goodbye!${C_RESET}"; exit 0 ;;
                *) echo -e "${C_YELLOW}[WARN] Invalid option, choose 1-5.${C_RESET}"; read -r -p "Press Enter to continue..." _ ;;
            esac
        else
            case $choice in
                1) install_tool ;;
                2) update_tool_page ;;
                3|panel|arabic) panel_arabic_update ;;
                4|0|q|Q|exit) echo -e "${C_GRAY}Goodbye!${C_RESET}"; exit 0 ;;
                *) echo -e "${C_YELLOW}[WARN] Invalid option, choose 1-4.${C_RESET}"; read -r -p "Press Enter to continue..." _ ;;
            esac
        fi
    done
}

installer_menu
