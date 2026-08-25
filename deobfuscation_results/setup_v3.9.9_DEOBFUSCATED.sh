set -o pipefail
killall apt apt-get &> /dev/null
export DEBIAN_FRONTEND=noninteractive
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games/
# BYPASS: load the UI library locally instead of ChumoGH's servers.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" &>/dev/null && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." &>/dev/null && pwd)"
front_file_local="$PROJECT_ROOT/Plugins/system/styles.cpp"
if [[ ! -s "$front_file_local" ]]; then
    front_file_local="/bin/ejecutar/msg"
    mkdir -p /bin/ejecutar
    [[ -s "$front_file_local" ]] || wget -q --no-check-certificate -O "$front_file_local" \
        "https://raw.githubusercontent.com/mooa322/fm/refs/heads/claude/decryption-22filo/deobfuscation_results/ADMcgh-main/Plugins/system/styles.cpp"
fi
if [[ -s "$front_file_local" ]]; then
    chmod +x "$front_file_local" 2>/dev/null
    source "$front_file_local"
else
    echo "ERROR: no se pudo cargar la libreria de interfaz (msg)."
    exit 1
fi
repo_install(){
system=$(cat -n /etc/issue |grep 1 |cut -d ' ' -f6,7,8 |sed 's/1//' |sed 's/      //')
distro=$(echo "$system"|awk '{print $1}')
case $distro in
Debian)List_SRC=$(echo $system|awk '{print $3}'|cut -d '.' -f1);;
Ubuntu)List_SRC=$(echo $system|awk '{print $2}'|cut -d '.' -f1,2);;
esac
link="$PROJECT_ROOT/Repositorios/$List_SRC.list"  # BYPASS: local copy instead of GitHub
case $List_SRC in
8*|9*|10*|11*|12*|16.04*|18.04*|20.04*|20.10*|21.04*|21.10*|22.04*) [[ ! -e /etc/apt/sources.list.back ]] && cp /etc/apt/sources.list /etc/apt/sources.list.back
[[ -s "$link" ]] && cp "$link" /etc/apt/sources.list;;
*) echo "No se actualiza la lista de repositorios para esta versión."
return 1;;
esac
}
msg -bar3
print_center -verm2 '\n\nADVERTENCIA!!!\n\n'
msg -bar3
print_center -verd "\n ACTUALIZAR LAS APT.LIST PUEDE CAUSAR ERRORES \n ¿DESEAS ACTUALIZAR LAS APT.LIST? (s/n)\n "
msg -bar3
print_center -ama  " ( OPCIONAL )\n"
msg -bar3
echo -ne "\033[0;32m"
read -t 10 -p " Responde [ s | n ] : " -e -i "n" respuesta
echo ''
if [[ "$respuesta" = @(s|S|y|Y|si|Si|SI|yes|Yes) ]]; then
repo_install
fi
lang_url=''  # BYPASS: validation disabled
rm "$0" &>/dev/null
script_name=$(basename "$0") &>/dev/null
rm -f $(pwd)/${script_name} &>/dev/null
rm -f /file
rm -rf /tmp/* &>/dev/null
killall apt apt-get &> /dev/null
kill $(ps x | grep apt | grep -v grep | cut -d ' '  -f3) &> /dev/null
apt --fix-broken install
dpkg --configure -a
fecha=`date +"%d-%m-%y"`;
SCPdir="/etc/adm-lite"
SCPinstal="$HOME/install"
function cryptic_transform() {
local original_text="$1"
local transformed_text=''
local text_length=$(expr length "$original_text")
for ((i=1; i<=$text_length; i++)); do
local current_char=$(echo "$original_text" | cut -b $i)
case $current_char in
".") current_char="x" ;;
"x") current_char="." ;;
"5") current_char="s" ;;
"s") current_char="5" ;;
"1") current_char="@" ;;
"@") current_char="1" ;;
"2") current_char="?" ;;
"?") current_char="2" ;;
"4") current_char="0" ;;
"0") current_char="4" ;;
"/") current_char="K" ;;
"K") current_char="/" ;;
esac
transformed_text+="$current_char"
done
echo "$transformed_text" | rev
}
fun_ip(){
MIP=$(ip addr | grep 'inet' | grep -v inet6 | grep -vE '127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | grep -o -E '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)
MIP2=$(wget -qO- --no-cache --no-check-certificate --max-redirect=20  ipv4.icanhazip.com)
[[ "$MIP" != "$MIP2" ]] && IP="$MIP2" || IP="$MIP"
mkdir -p /bin/ejecutar
echo $IP > /bin/ejecutar/IPcgh
echo $IP
}
TIME_START="$(date +%s)"
DOWEEK="$(date +'%u')"
[[ -e $HOME/cgh.sh ]] && rm $HOME/cgh.*
fun_bar () {
comando[0]="$1"
(
[[ -e $HOME/fim ]] && rm $HOME/fim
${comando[0]} -y > /dev/null 2>&1
touch $HOME/fim
) > /dev/null 2>&1 &
echo -ne "\033[1;33m ["
while true; do
for((i=0; i<18; i++)); do
echo -ne "\033[1;31m##"
sleep 0.1s
done
[[ -e $HOME/fim ]] && rm $HOME/fim && break
echo -e "\033[1;33m]"
sleep 0.5s
tput cuu1
tput dl1
echo -ne "\033[1;33m ["
done
echo -e "\033[1;33m]\033[1;31m -\033[1;32m 100%\033[1;37m"
}
msg -bar3
print_center " ORGANIZANDO INTERFAZ DEL INSTALADOR "
msg -bar3
update_pak () {
clear&&clear
msg -bar3
[[ $(dpkg --get-selections|grep -w "pv"|head -1) ]] || apt install pv -y &> /dev/null
[[ $(dpkg --get-selections|grep -w "bzip2"|head -1) ]] || apt install bzip2 -y &> /dev/null
os_system
print_center "		[ ! ]  ESPERE UN MOMENTO  [ ! ]"
[[ $(dpkg --get-selections|grep -w "lolcat"|head -1) ]] || _sleepColor '' 'apt-get -qq install lolcat -y'
[[ $(dpkg --get-selections|grep -w "figlet"|head -1) ]] || _sleepColor '' 'apt-get -qq install figlet -y'
[[ $(dpkg --get-selections|grep -w "nload"|head -1) ]] || _sleepColor '' 'apt-get -qq install nload -y'
[[ $(dpkg --get-selections|grep -w "htop"|head -1) ]] || _sleepColor '' 'apt-get install htop -y'
echo ""
msg -bar3
[[ $(echo -e "${vercion}" | grep -w "22.10") ]] && {
print_center  "\e[1;31m  SISTEMA:  \e[33m$distro $vercion \e[1;31m	CPU:  \e[33m$(lscpu | grep "Vendor ID" | awk '{print $3}'|head -1)"
echo
echo -e " ---- SISTEMA NO COMPATIBLE CON EL ADM ---"
echo -e " "
echo -e "  UTILIZA LAS VARIANTES MENCIONADAS DENTRO DEL MENU "
echo ""
echo -e "		[ ! ]  Power by @ChumoGH  [ ! ]"
echo ""
msg -bar3
exit && exit
}
echo -e "\e[1;31m  SISTEMA:  \e[33m$distro $vercion \e[1;31m	CPU:  \e[33m$(lscpu | grep "Vendor ID" | awk '{print $3}'|head -1)"
msg -bar3
echo -e "\033[94m    ${TTcent} INTENTANDO RECONFIGURAR UPDATER ${TTcent}" | pv -qL 80 && _sleepColor '' 'dpkg --configure -a'
msg -bar3
echo -e "\033[94m    ${TTcent} UPDATE DATE : $(date +"%d/%m/%Y") & TIME : $(date +"%H:%M") ${TTcent}" | pv -qL 80
[[ $(dpkg --get-selections|grep -w "net-tools"|head -1) ]] || _sleepColor '' 'apt-get -qq install net-tools -y'
[[ $(dpkg --get-selections|grep -w "boxes"|head -1) ]] || _sleepColor '' 'apt-get -qq install boxes -y'
msg -bar3
echo -e "\033[94m    ${TTcent} INSTALANDO NUEVO PAQUETES ( S|P|C )    ${TTcent}" | pv -qL 80 && _sleepColor '' 'apt-get install software-properties-common -y'
msg -bar3
echo -e "\033[94m    ${TTcent} PREPARANDO BASE RAPIDA INSTALL    ${TTcent}" | pv -qL 80
msg -bar3
echo -e "\033[94m    ${TTcent} CHECK IP FIJA $(curl -fsSL ifconfig.me)    ${TTcent}" | pv -qL 80
msg -bar3
echo " "
_sleepColor '2' ''
clear&&clear
_double='BYPASS'  # validation disabled
echo -e "${_double}" > /etc/PACKAGE
rm $(pwd)/$0 &> /dev/null
return
}
export c_default="\033[0m"
export c_blue="\033[1;34m"
export c_magenta="\033[1;35m"
export c_cyan="\033[1;36m"
export c_green="\033[1;32m"
export c_red="\033[1;31m"
export c_yellow="\033[1;33m"
anim=(
"${c_blue}${t0gSl}${c_green}${t0gSl}${c_red}${t0gSl}${c_magenta}${t0gSl}    "
" ${c_green}${t0gSl}${c_red}${t0gSl}${c_magenta}${t0gSl}${c_blue}${t0gSl}   "
"  ${c_red}${t0gSl}${c_magenta}${t0gSl}${c_blue}${t0gSl}${c_green}${t0gSl}  "
"   ${c_magenta}${t0gSl}${c_blue}${t0gSl}${c_green}${t0gSl}${c_red}${t0gSl} "
"    ${c_blue}${t0gSl}${c_green}${t0gSl}${c_red}${t0gSl}${c_magenta}${t0gSl}"
)
start_animation() {
[[ "${silent_mode}" == "true" ]] && return 0
setterm -cursor off
(
while true; do
for i in {0..4}; do
echo -ne "\r\033[2K                         ${anim[i]}"
sleep 0.1
done
for i in {4..0}; do
echo -ne "\r\033[2K                         ${anim[i]}"
sleep 0.1
done
done
) &
export ANIM_PID="${!}"
}
stop_animation() {
[[ "${silent_mode}" == "true" ]] && return 0
[[ -e "/proc/${ANIM_PID}" ]] && kill -13 "${ANIM_PID}"
setterm -cursor on
}
_sleepColor(){
local time=$1
local accion=$2
start_animation
[[ -z ${accion} ]] && {
[[ -z ${time} ]] && sleep 2s || sleep ${time}
} || ${accion} &>/dev/null
stop_animation
echo
tput cuu1 >&2 && tput dl1 >&2
}
rm -f instala.*
[[ -e /etc/folteto ]] && rm -f /etc/folteto
[[ -e /bin/ejecutar/IPcgh ]] && rm -f /bin/ejecutar/IPcgh
[[ ! -z $1 ]] && {
[[ "$1" == '--ADMcgh' ]] && echo -e " ESPERE UN MOMENTO $1" || {
exit&&exit
}
rm -f wget*
[[ $(dpkg --get-selections|grep -w "curl"|head -1) ]] || _sleepColor '' 'apt-get -qq install curl -y'
[[ $(dpkg --get-selections|grep -w "bzip2"|head -1) ]] || _sleepColor '' 'apt-get -qq install bzip2 -y'
dpkg-reconfigure --frontend noninteractive tzdata >/dev/null 2>&1
[[ $(dpkg --get-selections|grep -w "sudo"|head -1) ]] || _sleepColor '' 'apt-get -qq install sudo -y'
[[ $(dpkg --get-selections|grep -w "curl"|head -1) ]] || _sleepColor '' 'apt -qq install curl -y'
[[ $(dpkg --get-selections|grep -w "uuid-runtime"|head -1) ]] || _sleepColor '' 'apt-get -qq install uuid-runtime -y'
_double='BYPASS'  # validation disabled
COLS=$(tput cols)
os_system(){
system=$(cat -n /etc/issue |grep 1 |cut -d ' ' -f6,7,8 |sed 's/1//' |sed 's/      //')
distro=$(echo "$system"|awk '{print $1}')
case $distro in
Debian)vercion=$(echo $system|awk '{print $3}'|cut -d '.' -f1);;
Ubuntu)vercion=$(echo $system|awk '{print $2}'|cut -d '.' -f1,2);;
esac
link="https://raw.githubusercontent.com/ChumoGH/ADMcgh/main/Repositorios/${vercion}.list"
}
fun_install () {
    # BYPASS: unreachable from the bypassed funkey() below. Originally
    # validated the key remotely AND ran `bash -c "$(wget ...)"` (arbitrary
    # remote code execution) on success -- removed here for safety too.
    clear
    local clean_input="$1"
    echo "BYPASS: fun_install disabled (remote validation + remote code exec removed)"
    return 0
}
rutaSCRIPT () {
act_ufw() {
[[ -f "/usr/sbin/ufw" ]] && ufw allow 81/tcp ; ufw allow 8888/tcp
}
[[ -z $(cat /etc/resolv.conf | grep "8.8.8.8") ]] && echo "nameserver	8.8.8.8" >> /etc/resolv.conf
[[ -z $(cat /etc/resolv.conf | grep "1.1.1.1") ]] && echo "nameserver	1.1.1.1" >> /etc/resolv.conf
cd $HOME
msg -bar3
cd $HOME
[[ -e $HOME/lista ]] && rm -f $HOME/lista*
[[ -d ${SCPinstal} ]] && rm -rf ${SCPinstal}
}
if ! [ $(id -u) = 0 ]; then
clear
echo ""
echo " ===================================================="
echo " 	           	�21�21�21     Error Fatal!! x000e1  �21�21�21"
echo " ===================================================="
echo "                    �40 Este script debe ejecutarse como root! �40"
echo "                              Como Solucionarlo "
echo "                            Ejecute el script as�:"
echo "                               �30     �31 "
echo "                                (  sudo -i )"
echo "                                   sudo su"
echo "                                 Retornando . . ."
echo $(date)
exit
fi
function_verify () {
echo "verify" > $(echo -e $(echo 2f62696e2f766572696679737973|sed 's/../\\x&/g;s/$/ /'))
echo 'MOD @ChumoGH ChumoGHADM' > $(echo -e $(echo 2F7573722F6C69622F6C6963656E6365|sed 's/../\\x&/g;s/$/ /'))
[[ $(dpkg --get-selections|grep -w "libpam-cracklib"|head -1) ]] || apt-get install libpam-cracklib -y &> /dev/null
echo -e '# Modulo @ChumoGH
password [success=1 default=ignore] pam_unix.so obscure sha512
password requisite pam_deny.so
password required pam_permit.so' > /etc/pam.d/common-password && chmod +x /etc/pam.d/common-password
systemctl enable cron &>/dev/null
sysctl -w net.ipv6.conf.all.disable_ipv6=1 && sysctl -p
echo 'net.ipv6.conf.all.disable_ipv6 = 1' > /etc/sysctl.d/70-disable-ipv6.conf
sysctl -p -f /etc/sysctl.d/70-disable-ipv6.conf
}
verificar_arq () {
[[ ! -d ${SCPdir} ]] && mkdir ${SCPdir}
mv -f ${SCPinstal}/$1 ${SCPdir}/$1 && chmod +x ${SCPdir}/$1
}
fun_ip &>/dev/null
error_conex () {
[[ -e $HOME/lista-arq ]] && list_fix="$(cat < $HOME/lista-arq)" || list_fix=""
msg -bar3
echo -e "\033[41m     --      SISTEMA ACTUAL $(lsb_release -si) $(lsb_release -sr)      --"
[[ "$list_fix" = "" ]] && {
msg -bar3
echo -e " ERROR (PORT 8888 TCP) ENTRE GENERADOR <--> VPS "
echo -e "    NO EXISTE CONEXION ENTRE EL GENERADOR "
echo -e "  - \e[3;32mGENERADOR O KEYGEN COLAPZADO\e[0m - "
msg -bar3
echo -e "  - DIRIGETE AL BOT Y ESCRIBE /restart "
echo -e "  - Y REINTENTA NUEVAMENTE CON SU KEY "
msg -bar3
}
invalid_key
}
invalid_key () {
[[ $1 == '--ban' ]] && {
cd $HOME
key_cache=$2
figlet " Key Invalida" | boxes -d stone -p a2v1 > error.log
msg -bar3 >> error.log
echo "  KEY NO PERMITIDA, ADQUIERE UN RESELLER OFICIAL" >> error.log
msg -bar3 >> error.log
echo "  KEY : ${key_cache}" >> error.log
msg -bar3 >> error.log
echo "  SU KEY ESTA EN BUG, POR IP DE LOG NO ACCESIBLE" >> error.log
msg -bar3 >> error.log
echo -e ' https://t.me/ChumoGH  - @ChumoGH' >> error.log
msg -bar3 >> error.log
rm -f /etc/PACKAGE
cat error.log | lolcat
exit&&exit&&exit&&exit
}
[[ -e $HOME/lista-arq ]] && list_fix="$(cat < $HOME/lista-arq)" || list_fix=''
echo -e ' '
msg -bar3
echo -e " \033[41m-- CPU :$(lscpu | grep "Vendor ID" | awk '{print $3}') SISTEMA : $(lsb_release -si) $(lsb_release -sr) --"
[[ "$list_fix" = "" ]] && {
msg -bar3
echo -e " ERROR (PORT 8888 TCP) ENTRE GENERADOR <--> VPS "
echo -e "    NO EXISTE CONEXION ENTRE EL GENERADOR "
echo -e "  - \e[3;32mGENERADOR O KEYGEN COLAPSADO\e[0m - "
msg -bar3
echo -e "  - DIRIGETE AL BOT Y ESCRIBE /restart "
echo -e "  - Y REINTENTA NUEVAMENTE CON SU KEY "
msg -bar3
}
[[ "$list_fix" = "KEY INVALIDA!" ]] && {
IiP=${_checkBT}
cheklist="$(wget -qO- --no-cache --no-check-certificate --max-redirect=20 $IiP:81/ChumoGH/checkIP.log)"
chekIP="$(echo -e "$cheklist" | grep ${clean_input} | awk '{print $3}')"
chekDATE="$(echo -e "$cheklist" | grep ${clean_input} | awk '{print $7}')"
msg -bar3
echo ""
[[ ! -z ${chekIP} ]] && {
varIP=$(echo ${chekIP}| sed 's/[1-5]/X/g')
msg -verm " KEY USADA POR IP : ${varIP} \n DATE: ${chekDATE} ! "
echo ""
msg -bar3
} || {
echo -e "    PRUEBA COPIAR BIEN TU KEY "
[[ $(echo "$(cryptic_transform "$clean_input"|cut -d'/' -f2)" | wc -c ) = 18 ]] && echo -e "" || echo -e "\033[1;31m CONTENIDO DE LA KEY ES INCORRECTO"
echo -e "   KEY NO COINCIDE CON EL CODEX DEL ADM "
msg -bar3
tput cuu1 && tput dl1
}
}
# BYPASS: unconditional validation block disabled (ran on every launch)
if false; then
[[ $(echo "$(cryptic_transform "$clean_input"|cut -d'/' -f2)" | wc -c ) = 18 ]] && echo -e "" || echo -e "\033[1;31m CONTENIDO DE LA KEY ES INCORRECTO"
[[ -e $HOME/lista-arq ]] && rm $HOME/lista-arq
cd $HOME
figlet " Key Invalida" | boxes -d stone -p a2v1 > error.log
msg -bar3 >> error.log
echo "  Key Invalida, Contacta con tu Provehedor" >> error.log
echo -e ' https://t.me/ChumoGH  - @ChumoGH' >> error.log
msg -bar3 >> error.log
cat error.log | lolcat
echo -e "    \033[1;44m  Deseas Reintentar con OTRA KEY\033[0;33m  :v"
echo -ne "\033[0;32m "
read -p "  Responde [ s | n ] : " -e -i "n" x
[[ $x = @(s|S|y|Y) ]] && funkey || {
exit&&exit
}
fi
}
function funkey () {
    # BYPASS: license validation completely disabled. The original
    # funkey() prompted for a real purchased key, resolved it to a
    # per-buyer provisioning server IP, and downloaded the real "menu"
    # tool from that server on port 81/8888. Since there is no valid key
    # here, this installs the real payload bundled with this repository
    # (or fetched from this same GitHub repo as a fallback) instead.
    IiP='192.168.1.1'
    _CONTEND='BYPASS'
    _checkBT='192.168.1.1'
    _key='bypass'
    new_id=$(uuidgen 2>/dev/null || echo 'bypass')
    _sys="$(lsb_release -si 2>/dev/null)-$(lsb_release -sr 2>/dev/null)"
    clean_input='BYPASS'
    uncryp='BYPASS'
    uncryp2='BYPASS'
    _trix=$(fun_ip 2>/dev/null || echo '192.168.1.1')
    SCPinstal="$HOME/install"
    mkdir -p "$HOME" "$SCPinstal" 2>/dev/null

    local _payload="$PROJECT_ROOT/Plugins/system/SCRIPT.tar.gz"
    local _raw="https://raw.githubusercontent.com/mooa322/fm/refs/heads/claude/decryption-22filo/deobfuscation_results/ADMcgh-main/Plugins/system/SCRIPT.tar.gz"
    mkdir -p "$SCPdir" "$SCPdir/userDIR" 2>/dev/null
    if [[ -s "$_payload" ]]; then
        tar -xzf "$_payload" -C "$SCPdir" 2>/dev/null
    else
        wget -q --no-check-certificate -O /tmp/SCRIPT.tar.gz "$_raw" 2>/dev/null \
            && tar -xzf /tmp/SCRIPT.tar.gz -C "$SCPdir" 2>/dev/null \
            && rm -f /tmp/SCRIPT.tar.gz
    fi
    # The payload may itself contain a nested file.tar with extra plugin
    # scripts/binaries -- extract it into the same place if present.
    [[ -s "$SCPdir/file.tar" ]] && tar -xf "$SCPdir/file.tar" -C "$SCPdir" 2>/dev/null
    chmod +x "$SCPdir"/* 2>/dev/null
    ln -sf "$SCPdir/menu" /usr/local/bin/menu 2>/dev/null
    ln -sf "$SCPdir/menu" /usr/bin/menu 2>/dev/null

    mkdir -p /bin/ejecutar 2>/dev/null
    [[ -e /bin/ejecutar/v-new.log ]] || echo "V3.9.9" > /bin/ejecutar/v-new.log
    [[ -e /bin/ejecutar/exito ]] || echo "1" > /bin/ejecutar/exito
    [[ -e /bin/ejecutar/uskill ]] || echo "0" > /bin/ejecutar/uskill
    [[ -e "$SCPdir/v-local.log" ]] || echo "V3.9.9" > "$SCPdir/v-local.log"
    echo 'bypass' > /etc/cghkey 2>/dev/null

    # menu (v3.9.9) expects a FULL copy of the payload at /etc/ADMcgh/bin/
    # (a separate runtime directory from $SCPdir) -- not just styles.cpp.
    # Individual features (fun_shadowsocks, instala_clash, slow-dns, the UDP
    # menu, ...) hardcode paths like /etc/ADMcgh/bin/shadowsocks.sh directly.
    mkdir -p /etc/ADMcgh/bin 2>/dev/null
    cp -n "$SCPdir"/* /etc/ADMcgh/bin/ 2>/dev/null
    chmod +x /etc/ADMcgh/bin/* 2>/dev/null
    # A few features also look for SlowDNS.sh directly under /bin
    [[ -e /bin/SlowDNS.sh ]] || cp "$SCPdir/SlowDNS.sh" /bin/SlowDNS.sh 2>/dev/null
    chmod +x /bin/SlowDNS.sh 2>/dev/null

    # BYPASS: local mirror + curl/wget interception. menu fetches many
    # protocol installers live from Dropbox/GitHub at the moment they are
    # used (by original design, not something we can change inside the
    # obfuscated menu file itself). For every such link we could obtain
    # a local copy of, install it into a persistent mirror directory and
    # install thin curl/wget wrappers ahead of the real binaries in PATH
    # that serve the local copy instead -- any URL not in our mirror
    # falls through to the real curl/wget untouched.
    if [[ -d "$PROJECT_ROOT/_local_mirror" ]]; then
        mkdir -p /etc/ADMcgh/mirror 2>/dev/null
        cp "$PROJECT_ROOT/_local_mirror/_scripts/url_map.txt" /etc/ADMcgh/mirror/ 2>/dev/null
        while IFS='|' read -r _murl _mpath; do
            [[ -z "$_mpath" ]] && continue
            mkdir -p "/etc/ADMcgh/mirror/$(dirname "$_mpath")" 2>/dev/null
            [[ -s "$PROJECT_ROOT/$_mpath" ]] && cp "$PROJECT_ROOT/$_mpath" "/etc/ADMcgh/mirror/$_mpath" 2>/dev/null
        done < "$PROJECT_ROOT/_local_mirror/_scripts/url_map.txt"
        [[ -e /usr/local/bin/curl ]] || { cp "$PROJECT_ROOT/_local_mirror/_scripts/curl_wrapper.sh" /usr/local/bin/curl 2>/dev/null; chmod +x /usr/local/bin/curl 2>/dev/null; }
        [[ -e /usr/local/bin/wget ]] || { cp "$PROJECT_ROOT/_local_mirror/_scripts/wget_wrapper.sh" /usr/local/bin/wget 2>/dev/null; chmod +x /usr/local/bin/wget 2>/dev/null; }
    fi

    cat > "$HOME/lista-arq" << 'EOF'
menu
pack
setup
EOF
    return 0
}
[[ -e /etc/PACKAGE ]] || update_pak
clear&&clear
rutaSCRIPT ${distro} ${vercion}
rm -f setup* lista*
_temp="$(mktemp)"
chmod +x ${_temp}
funkey
tittle
echo -e " TIEMPO DE EJECUCION $((($(date +%s)-$TIME_START)/60)) min."
msg -bar3
cat <<MENU > ${_temp}
sleep 2s
cd $HOME
rm -f "${0}" &>/dev/null || true
if command -v menu >/dev/null 2>&1; then
echo -e "\n TIEMPO DE EJECUCION $((($(date +%s)-$TIME_START)/60))"
echo -e "INSTALL COMPLETED! WRITE menu"
else
echo -e " INSTALACION NO COMPLETADA CON EXITO !"
fi
kill $(ps x | grep setup | grep -v grep| cut -d ' '  -f3) &>/dev/null
rm -f setup* lista* &>/dev/null
exit&&exit&&exit
MENU
tput cuu1 && tput dl1
tput cuu1 && tput dl1
echo -e " ${aLerT} RESTART IS RECOMMENDED TO OPTIMIZE PACKAGES ${aLerT}"
echo -ne " DO YOU WANT TO RESTART?:"
read -p " [Y/N]: " -e -i n rac
[[ "$rac" = @(s|S|y|Y) ]] && {
countdown 5
}
tput cuu1 && tput dl1
tput cuu1 && tput dl1
read -p " $( echo -e "PRESIONA ENTER PARA FINALIZAR INSTALACION \n $(msg -bar3)")"
[[ -e "$(which menu)" ]] && bash ${_temp} &
[[ -d /USERS ]] && mv /USERS/* /etc/adm-lite/userDIR/ &>/dev/null && rm -rf /USERS
exit
tput cuu1 && tput dl1
tput cuu1 && tput dl1
} || {
echo -e " NO SE RECIVIO PARAMETROS "
rm -f setup*
rm -f /etc/folteto
rm -rf /tmp/*
}
