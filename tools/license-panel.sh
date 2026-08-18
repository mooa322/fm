#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#  DAHOOM · License Panel — interactive license management
#  A menu-driven front-end over licenses.json. No commands to memorize:
#  issue, revoke, unbind and list, all from arrow-free numbered prompts,
#  with git commit & push handled automatically after every change.
#
#  Usage:  ./tools/license-panel.sh
# ═══════════════════════════════════════════════════════════════════
set -uo pipefail
cd "$(dirname "$0")/.."

# ── Aurora palette (same as the tool's own terminal UI) ──────────────
C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
C_CYAN=$'\033[38;5;51m'; C_ICE=$'\033[38;5;87m'; C_VIOLET=$'\033[38;5;177m'
C_GREEN=$'\033[38;5;79m'; C_RED=$'\033[38;5;204m'; C_YELLOW=$'\033[38;5;222m'
C_GRAY=$'\033[38;5;245m'; C_WHITE=$'\033[38;5;255m'; C_FRAME=$'\033[38;5;60m'

FILE="licenses.json"
[ -f "$FILE" ] || echo '{}' > "$FILE"
command -v python3 >/dev/null 2>&1 || { echo -e "${C_RED}python3 is required.${C_RESET}"; exit 1; }
command -v git >/dev/null 2>&1 || { echo -e "${C_RED}git is required.${C_RESET}"; exit 1; }

pause() { echo; read -r -p "$(echo -e "  ${C_GRAY}Press Enter to continue...${C_RESET}")" _ || exit 0; }

banner() {
    clear
    echo -e "  ${C_BOLD}${C_ICE}╭──────────────────────────────────────────────────────────╮${C_RESET}"
    echo -e "  ${C_BOLD}${C_ICE}│${C_RESET}  ${C_BOLD}🦅 DAHOOM${C_RESET}  ${C_GRAY}License Panel${C_RESET}$(printf '%*s' 35 '')${C_BOLD}${C_ICE}│${C_RESET}"
    echo -e "  ${C_BOLD}${C_ICE}╰──────────────────────────────────────────────────────────╯${C_RESET}"
    echo
}

show_list() {
    python3 - "$FILE" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
CYAN="\033[38;5;51m"; GRAY="\033[38;5;245m"; GREEN="\033[38;5;79m"; RED="\033[38;5;204m"; RESET="\033[0m"; BOLD="\033[1m"
ID_W, ST_W, IP_W = 22, 11, 17
if not d:
    print(f"  {GRAY}no licenses yet{RESET}")
else:
    print(f"  {BOLD}{'ID':<{ID_W}}{'STATUS':<{ST_W}}{'IP':<{IP_W}}ISSUED{RESET}")
    for id, rec in sorted(d.items()):
        revoked = rec.get("revoked")
        label = "revoked" if revoked else "active"
        colour = RED if revoked else GREEN
        st_field = f"{colour}{label}{RESET}" + " " * (ST_W - len(label))
        ip_field = f"{(rec.get('ip') or '-'):<{IP_W}}"
        print(f"  {CYAN}{id:<{ID_W}}{RESET}{st_field}{ip_field}{rec.get('issued','')}")
PY
}

git_publish() {
    local msg="$1"
    read -r -p "$(echo -e "  ${C_YELLOW}Push this change to GitHub now? [Y/n]: ${C_RESET}")" ans
    ans=${ans:-Y}
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        git add "$FILE" >/dev/null 2>&1
        if git diff --cached --quiet -- "$FILE"; then
            echo -e "  ${C_GRAY}Nothing to push (no change).${C_RESET}"
            return
        fi
        git commit -q -m "$msg" >/dev/null 2>&1
        local n=0
        until git push origin "$(git branch --show-current)" 2>/dev/null; do
            n=$((n+1)); [ $n -ge 4 ] && { echo -e "  ${C_RED}Push failed after retries. Run 'git push' manually.${C_RESET}"; return 1; }
            sleep $((2**n))
        done
        echo -e "  ${C_GREEN}✅ Pushed. Live in ~1 minute.${C_RESET}"
    else
        echo -e "  ${C_GRAY}Not pushed — remember: git add licenses.json && git commit && git push${C_RESET}"
    fi
}

do_issue() {
    banner
    echo -e "  ${C_BOLD}Issue a new license${C_RESET}\n"
    read -r -p "$(echo -e "  ${C_CYAN}License ID (letters/digits/-/_): ${C_RESET}")" id
    [[ "$id" =~ ^[A-Za-z0-9_-]+$ ]] || { echo -e "\n  ${C_RED}Invalid id.${C_RESET}"; pause; return; }
    if python3 -c "import json,sys; sys.exit(0 if '$id' in json.load(open('$FILE')) else 1)" 2>/dev/null; then
        echo -e "\n  ${C_YELLOW}'${id}' already exists — this will overwrite it.${C_RESET}"
    fi
    echo -e "  ${C_GRAY}Lock to one server's IP now, or leave blank to allow any server${C_RESET}"
    echo -e "  ${C_GRAY}(you can lock it later once the client sends you their IP).${C_RESET}"
    read -r -p "$(echo -e "  ${C_CYAN}Server IP (optional): ${C_RESET}")" ip

    python3 - "$FILE" "$id" "$ip" <<'PY'
import json, sys, datetime
f, id, ip = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(f))
d[id] = {"ip": ip.strip() or None, "issued": datetime.date.today().isoformat(), "revoked": False}
json.dump(d, open(f, "w"), indent=2, ensure_ascii=False)
PY
    echo
    echo -e "  ${C_GREEN}✅ Issued '${id}'${ip:+ locked to $ip}.${C_RESET}"
    echo -e "  ${C_BOLD}Give the client this ONE line:${C_RESET}"
    echo -e "  ${C_ICE}FM_ID=${id} bash <(curl -sL https://raw.githubusercontent.com/mooa322/fm/main/install.sh)${C_RESET}"
    git_publish "license: issue ${id}"
    pause
}

do_revoke() {
    banner
    echo -e "  ${C_BOLD}Revoke a license${C_RESET}\n"
    show_list
    echo
    read -r -p "$(echo -e "  ${C_CYAN}License ID to revoke: ${C_RESET}")" id
    [ -n "$id" ] || return
    if ! python3 -c "import json,sys; sys.exit(0 if '$id' in json.load(open('$FILE')) else 1)" 2>/dev/null; then
        echo -e "\n  ${C_RED}'${id}' not found.${C_RESET}"; pause; return
    fi
    python3 - "$FILE" "$id" <<'PY'
import json, sys
f, id = sys.argv[1], sys.argv[2]
d = json.load(open(f)); d[id]["revoked"] = True
json.dump(d, open(f, "w"), indent=2, ensure_ascii=False)
PY
    echo -e "\n  ${C_GREEN}✅ Revoked '${id}'.${C_RESET} It stops working within ~1 minute of pushing."
    git_publish "license: revoke ${id}"
    pause
}

do_unbind() {
    banner
    echo -e "  ${C_BOLD}Unbind a license from its server${C_RESET}\n"
    show_list
    echo
    read -r -p "$(echo -e "  ${C_CYAN}License ID to unbind: ${C_RESET}")" id
    [ -n "$id" ] || return
    if ! python3 -c "import json,sys; sys.exit(0 if '$id' in json.load(open('$FILE')) else 1)" 2>/dev/null; then
        echo -e "\n  ${C_RED}'${id}' not found.${C_RESET}"; pause; return
    fi
    python3 - "$FILE" "$id" <<'PY'
import json, sys
f, id = sys.argv[1], sys.argv[2]
d = json.load(open(f)); d[id]["ip"] = None
json.dump(d, open(f, "w"), indent=2, ensure_ascii=False)
PY
    echo -e "\n  ${C_GREEN}✅ '${id}' unbound.${C_RESET} Its next install can bind to a new server."
    git_publish "license: unbind ${id}"
    pause
}

do_list() {
    banner
    echo -e "  ${C_BOLD}All licenses${C_RESET}\n"
    show_list
    pause
}

main_menu() {
    while true; do
        banner
        show_list
        echo
        echo -e "  ${C_VIOLET}${C_BOLD}▌${C_RESET} ${C_VIOLET}${C_BOLD}MENU${C_RESET} ${C_FRAME}────────────────────────────────────────────${C_RESET}"
        echo
        echo -e "  ${C_CYAN}[1]${C_RESET} Issue a new license"
        echo -e "  ${C_CYAN}[2]${C_RESET} Revoke a license"
        echo -e "  ${C_CYAN}[3]${C_RESET} Unbind a license (move to new server)"
        echo -e "  ${C_CYAN}[4]${C_RESET} List all licenses"
        echo -e "  ${C_RED}[0]${C_RESET} Exit"
        echo
        if ! read -r -p "$(echo -e "  ${C_ICE}> Select an option: ${C_RESET}")" choice; then
            echo -e "\n  ${C_GRAY}Goodbye.${C_RESET}\n"; exit 0
        fi
        case "$choice" in
            1) do_issue ;;
            2) do_revoke ;;
            3) do_unbind ;;
            4) do_list ;;
            0) echo -e "\n  ${C_GRAY}Goodbye.${C_RESET}\n"; exit 0 ;;
            *) ;;
        esac
    done
}

main_menu
