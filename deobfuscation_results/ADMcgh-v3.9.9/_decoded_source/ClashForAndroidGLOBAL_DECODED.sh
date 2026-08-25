#Autor: Henry Chumo 
#Alias : ChumoGH
#SCRIPT OFICIAL ChumoGH|Plus
# Formato Creado por @ChumoGH | '593987072611 Whatsapp Personal
rm -rf /tmp/* &>/dev/null
#script_name=$(basename "$0")
#rm -f $(pwd)/${script_name}
clear&&clear
fun_ip () {
  if [[ -e /bin/ejecutar/IPcgh ]]; then
    IP="$(cat /bin/ejecutar/IPcgh)"
  else
    MEU_IP=$(ip addr | grep 'inet' | grep -v inet6 | grep -vE '127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | grep -o -E '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)
    MEU_IP2=$(wget -qO- ipv4.icanhazip.com)
    [[ "$MEU_IP" != "$MEU_IP2" ]] && IP="$MEU_IP2" && echo "$MEU_IP2" || IP="$MEU_IP" && echo "$MEU_IP"
    echo "$MEU_IP2" > /bin/ejecutar/IPcgh
	IP="$MEU_IP2"
  fi
[[ -z ${portFTP} ]] && portFTP='X0'
local _netCAT="$(netstat -tunlp)"
trojanport=`echo -e "${_netCAT}" | grep tcp | awk '/trojan/ && /0.0.0.0:/ {print substr($4, 9)}' | head -1`;
[[ -z ${trojanport} ]] && {
[[ -e /usr/local/etc/trojan/config.json ]] && {
trojanport=$(cat /usr/local/etc/trojan/config.json | jq -r .local_port)
troport=$(cat /usr/local/etc/trojan/config.json | jq -r .local_port)
}
} || troport=${trojanport}
_SFTP="$(lsof -V -i tcp -P -n | grep -v "ESTABLISHED" |grep -v "COMMAND" | grep "LISTEN" | grep apache2)"
[[ -z ${_SFTP} ]] && _SFTP="$(lsof -V -i tcp -P -n | grep -v "ESTABLISHED" |grep -v "COMMAND" | grep "LISTEN" | grep nginx)"
portFTP=$(echo -e "$_SFTP" |cut -d: -f2 | cut -d' ' -f1 | uniq)
portFTP=$(echo ${portFTP} | sed 's/\s\+/,/g' | cut -d , -f1)
}

install_ini () {
add-apt-repository universe
apt update -y; apt upgrade -y
clear
msg -bar3
echo -e "\033[92m        -- INSTALANDO PAQUETES NECESARIOS -- "
msg -bar3
#bc
[[ $(dpkg --get-selections|grep -w "golang-go"|head -1) ]] || apt-get install golang-go -y &>/dev/null
[[ $(dpkg --get-selections|grep -w "golang-go"|head -1) ]] || ESTATUS=`echo -e "\033[91mFALLO DE INSTALACION"` &>/dev/null
[[ $(dpkg --get-selections|grep -w "golang-go"|head -1) ]] && ESTATUS=`echo -e "\033[92mINSTALADO"` &>/dev/null
echo -e "\033[97m  # apt-get install golang-go............ $ESTATUS "
#jq
[[ $(dpkg --get-selections|grep -w "jq"|head -1) ]] || apt-get install jq -y &>/dev/null
[[ $(dpkg --get-selections|grep -w "jq"|head -1) ]] || ESTATUS=`echo -e "\033[91mFALLO DE INSTALACION"` &>/dev/null
[[ $(dpkg --get-selections|grep -w "jq"|head -1) ]] && ESTATUS=`echo -e "\033[92mINSTALADO"` &>/dev/null
echo -e "\033[97m  # apt-get install jq................... $ESTATUS "
#at
[[ $(dpkg --get-selections|grep -w "at"|head -1) ]] || apt-get install at -y &>/dev/null
[[ $(dpkg --get-selections|grep -w "at"|head -1) ]] || ESTATUS=`echo -e "\033[91mFALLO DE INSTALACION"` &>/dev/null
[[ $(dpkg --get-selections|grep -w "at"|head -1) ]] && ESTATUS=`echo -e "\033[92mINSTALADO"` &>/dev/null
echo -e "\033[97m  # apt-get install at................... $ESTATUS "
#curl
[[ $(dpkg --get-selections|grep -w "curl"|head -1) ]] || apt-get install curl -y &>/dev/null
[[ $(dpkg --get-selections|grep -w "curl"|head -1) ]] || ESTATUS=`echo -e "\033[91mFALLO DE INSTALACION"` &>/dev/null
[[ $(dpkg --get-selections|grep -w "curl"|head -1) ]] && ESTATUS=`echo -e "\033[92mINSTALADO"` &>/dev/null
echo -e "\033[97m  # apt-get install curl................. $ESTATUS "
#npm
[[ $(dpkg --get-selections|grep -w "npm"|head -1) ]] || apt-get install npm -y &>/dev/null
[[ $(dpkg --get-selections|grep -w "npm"|head -1) ]] || ESTATUS=`echo -e "\033[91mFALLO DE INSTALACION"` &>/dev/null
[[ $(dpkg --get-selections|grep -w "npm"|head -1) ]] && ESTATUS=`echo -e "\033[92mINSTALADO"` &>/dev/null
echo -e "\033[97m  # apt-get install npm.................. $ESTATUS "
#nodejs
[[ $(dpkg --get-selections|grep -w "nodejs"|head -1) ]] || apt-get install nodejs -y &>/dev/null
[[ $(dpkg --get-selections|grep -w "nodejs"|head -1) ]] || ESTATUS=`echo -e "\033[91mFALLO DE INSTALACION"` &>/dev/null
[[ $(dpkg --get-selections|grep -w "nodejs"|head -1) ]] && ESTATUS=`echo -e "\033[92mINSTALADO"` &>/dev/null
echo -e "\033[97m  # apt-get install nodejs............... $ESTATUS "
#socat
[[ $(dpkg --get-selections|grep -w "socat"|head -1) ]] || apt-get install socat -y &>/dev/null
[[ $(dpkg --get-selections|grep -w "socat"|head -1) ]] || ESTATUS=`echo -e "\033[91mFALLO DE INSTALACION"` &>/dev/null
[[ $(dpkg --get-selections|grep -w "socat"|head -1) ]] && ESTATUS=`echo -e "\033[92mINSTALADO"` &>/dev/null
echo -e "\033[97m  # apt-get install socat................ $ESTATUS "
#netcat
[[ $(dpkg --get-selections|grep -w "netcat"|head -1) ]] || apt-get install netcat -y &>/dev/null
[[ $(dpkg --get-selections|grep -w "netcat"|head -1) ]] || ESTATUS=`echo -e "\033[91mFALLO DE INSTALACION"` &>/dev/null
[[ $(dpkg --get-selections|grep -w "netcat"|head -1) ]] && ESTATUS=`echo -e "\033[92mINSTALADO"` &>/dev/null
echo -e "\033[97m  # apt-get install netcat............... $ESTATUS "
#net-tools
[[ $(dpkg --get-selections|grep -w "net-tools"|head -1) ]] || apt-get net-tools -y &>/dev/null
[[ $(dpkg --get-selections|grep -w "net-tools"|head -1) ]] || ESTATUS=`echo -e "\033[91mFALLO DE INSTALACION"` &>/dev/null
[[ $(dpkg --get-selections|grep -w "net-tools"|head -1) ]] && ESTATUS=`echo -e "\033[92mINSTALADO"` &>/dev/null
echo -e "\033[97m  # apt-get install net-tools............ $ESTATUS "
#figlet
[[ $(dpkg --get-selections|grep -w "figlet"|head -1) ]] || apt-get install figlet -y &>/dev/null
[[ $(dpkg --get-selections|grep -w "figlet"|head -1) ]] || ESTATUS=`echo -e "\033[91mFALLO DE INSTALACION"` &>/dev/null
[[ $(dpkg --get-selections|grep -w "figlet"|head -1) ]] && ESTATUS=`echo -e "\033[92mINSTALADO"` &>/dev/null
echo -e "\033[97m  # apt-get install figlet............... $ESTATUS "
msg -bar3
echo -e "\033[92m La instalacion de paquetes necesarios a finalizado"
msg -bar3
echo -e "\033[97m Si la instalacion de paquetes tiene fallas"
echo -ne "\033[97m Puede intentar de nuevo [s/n]: "
read inst
[[ $inst = @(s|S|y|Y) ]] && install_ini
echo -ne "\033[97m Deseas agregar Menu Clash Rapido [s/n]: "
read insta
[[ $insta = @(s|S|y|Y) ]] && enttrada
}

fun_insta(){
fun_ip
install_ini
msg -bar3
killall clash 1> /dev/null 2> /dev/null
echo -e " ➣ Creando Directorios y Archivos"
msg -bar3 
[[ -d /root/.config ]] && rm -rf /root/.config/* || mkdir /root/.config 
mkdir /root/.config/clash 1> /dev/null 2> /dev/null
last_version=$(curl -Ls "https://api.github.com/repos/Dreamacro/clash/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
arch=$(arch)
if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
  arch="amd64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
  arch="arm64"
else
  arch="amd64"
fi
wget -N --no-check-certificate -O /root/.config/clash/clash.gz https://github.com/Dreamacro/clash/releases/download/${last_version}/clash-linux-${arch}-${last_version}.gz
gzip -d /root/.config/clash/clash.gz
chmod +x /root/.config/clash/clash
echo -e " ➣ Clonando Repositorio Original Dreamacro "
go get -u -v github.com/Dreamacro/clash
clear
}


[[ -e /bin/ejecutar/msg ]] && source /bin/ejecutar/msg || source <(curl -sSL https://raw.githubusercontent.com/ChumoGH/ADMcgh/main/Plugins/system/styles.cpp)
numero='^[0-9]+$'
hora=$(printf '%(%H:%M:%S)T') 
fecha=$(printf '%(%D)T')
[[ ! -d /bin/ejecutar/clashFiles ]] && mkdir /bin/ejecutar/clashFiles
clashFiles='/bin/ejecutar/clashFiles/'

INITClash(){
msg -bar3
conFIN
#read -p "Ingrese Nombre del Poster WEB de la configuracion: " cocolon
cocolon=${srvip}
[[ -e /root/.config/clash/config.yaml ]] && sed -i "s%_dAtE%${fecha}%g" /root/.config/clash/config.yaml
[[ -e /root/.config/clash/config.yaml ]] && sed -i "s/_h0rA/${hora}/g" /root/.config/clash/config.yaml
[[ -e /root/.config/clash/config.yaml ]] && sed -i "s/NAMEFILE/${cocolon}/g" /root/.config/clash/config.yaml
cp /root/.config/clash/config.yaml /var/www/html/$cocolon.yaml && chmod +x /var/www/html/$cocolon.yaml
[[ $(dpkg --get-selections|grep -w "apache2"|head -1) ]] && service apache2 restart &>/dev/null
[[ $(dpkg --get-selections|grep -w "nginx"|head -1) ]] && service nginx restart &>/dev/null
echo -e "[\033[1;31m-\033[1;33m]\033[1;31m \033[1;33m"
echo -e "\033[1;33mClash Server Instalado"
echo -e "-------------------------------------------------------"
echo -e "		\033[4;31mNOTA importante\033[0m"
echo -e "Recuerda Descargar el Fichero, o cargarlo como URL!!"
echo -e "-------------------------------------------------------"
echo -e " \033[0;31mSi Usas Clash For Android, Ultima Version  "
echo -e "  Para luego usar el Link del Fichero, y puedas ."
echo -e " Descargarlo desde cualquier sitio con acceso WEB"
echo -e "        Link Clash Valido por 30 minutos "
echo -e "    Link : \033[1;42m  http://$IP:${portFTP}/$cocolon.yaml\033[0m"
echo -e "-------------------------------------------------------"
#read -p "PRESIONA ENTER PARA CARGAR ONLINE"
echo -e "\033[1;32mRuta de Configuracion: /root/.config/clash/config.yaml"
echo -e "\033[1;31mPRESIONE ENTER PARA CONTINUAR\033[0m"
scr=$(echo $(($RANDOM*3))|head -c 3)
unset yesno
echo -e " ENLACE VALIDO POR 30 MINUTOS? " 
while [[ ${yesno} != @(s|S|y|Y|n|N) ]]; do
read -p "[S/N]: " yesno
tput cuu1 && tput dl1
done
[[ ${yesno} = @(s|S|y|Y) ]] &&  { 
killall clash > /dev/null &1>&2
cat << atnow > /root/.config/clash/$cocolon.sh
#!/bin/bash
mv /var/www/html/$cocolon.yaml ${clashFiles}$cocolon.yaml
echo "Fichero removido a ${clashFiles}$cocolon.yaml"
rm -f /root/.config/clash/$cocolon.sh
atnow
at now +30 minutes <<< "bash /root/.config/clash/$cocolon.sh" && echo -e " ACTIVO POR 30 MINUTOS "  || echo " Validacion Incorrecta "
} 
echo -e "Proceso Finalizado"
}

configINIT_rule () {
mode=$1
[[ -z ${mode} ]] && exit
unset tropass
echo '#SCRIPT OFICIAL ChumoGH|Plus
# Formato Creado por @ChumoGH | +593987072611 Whatsapp Personal
# Creado el _dAtE - _h0rA | CONFIG REGLAS ${mode}
port: 8080
socks-port: 7891
redir-port: 7892
allow-lan: true
bind-address: "*"
mode: rule
log-level: info
external-controller: "0.0.0.0:9090"
secret: ""

dns:
  enable: true
  listen: :53
  enhanced-mode: fake-ip
  nameserver:
    - 114.114.114.114
    - 223.5.5.5
    - 8.8.8.8
    - 45.71.185.100
    - 204.199.156.138
    - 1.1.1.1
  fallback: []
  fake-ip-filter:
    - +.stun.*.*
    - +.stun.*.*.*
    - +.stun.*.*.*.*
    - +.stun.*.*.*.*.*
    - "*.n.n.srv.nintendo.net"
    - +.stun.playstation.net
    - xbox.*.*.microsoft.com
    - "*.*.xboxlive.com"
    - "*.msftncsi.com"
    - "*.msftconnecttest.com"
    - WORKGROUP    
tun:
  enable: true
  stack: gvisor
  auto-route: true
  auto-detect-interface: true
  dns-hijack:
    - any:53

# Clash for Windows
cfw-bypass:
  - qq.com
  - music.163.com
  - "*.music.126.net"
  - localhost
  - 127.*
  - 10.*
  - 172.16.*
  - 172.17.*
  - 172.18.*
  - 172.19.*
  - 172.20.*
  - 172.21.*
  - 172.22.*
  - 172.23.*
  - 172.24.*
  - 172.25.*
  - 172.26.*
  - 172.27.*
  - 172.28.*
  - 172.29.*
  - 172.30.*
  - 172.31.*
  - 192.168.*
  - <local>
cfw-latency-timeout: 5000
    
proxy-groups:
- name: "ADMcgh+"
  type: select
  proxies:    ' > /root/.config/clash/config.yaml
#sed -i "s/+/'/g"  /root/.config/clash/config.yaml
foc=1
_rules=''
[[ -e /usr/local/etc/trojan/config.json ]] && ConfTrojINI
unset yesno
foc=1
[[ -e /etc/v2ray/config.json ]] && ConfV2RINI
unset yesno
foc=1								
[[ -e /etc/xray/config.json ]] && ConfXRINI
}


configINIT_auto () {
local hora=$(printf '%(%H:%M:%S)T') 
local fecha=$(printf '%(%D)T')
mode=$1
[[ -z ${mode} ]] && exit
unset tropass
cat << EOF > /root/.config/clash/config.yaml 
# SCRIPT OFICIAL ChumoGH|Plus
# Formato Creado por @ChumoGH | +593987072611 Whatsapp Personal
# Creado el _dAtE - _h0rA | CONFIG AUTO ${mode}
port: 8080
socks-port: 7891
redir-port: 7892
allow-lan: true
bind-address: "*"
mode: rule
log-level: info
external-controller: "0.0.0.0:9090"
secret: ""

dns:
  enable: true
  listen: :53
  enhanced-mode: fake-ip
  nameserver:
    - 114.114.114.114
    - 223.5.5.5
    - 8.8.8.8
    - 45.71.185.100
    - 204.199.156.138
    - 1.1.1.1
  fallback: []
  fake-ip-filter:
    - +.stun.*.*
    - +.stun.*.*.*
    - +.stun.*.*.*.*
    - +.stun.*.*.*.*.*
    - "*.n.n.srv.nintendo.net"
    - +.stun.playstation.net
    - xbox.*.*.microsoft.com
    - "*.*.xboxlive.com"
    - "*.msftncsi.com"
    - "*.msftconnecttest.com"
    - WORKGROUP    
tun:
  enable: true
  stack: gvisor
  auto-route: true
  auto-detect-interface: true
  dns-hijack:
    - any:53

# Clash for Windows
cfw-bypass:
  - qq.com
  - music.163.com
  - "*.music.126.net"
  - localhost
  - 127.*
  - 10.*
  - 172.16.*
  - 172.17.*
  - 172.18.*
  - 172.19.*
  - 172.20.*
  - 172.21.*
  - 172.22.*
  - 172.23.*
  - 172.24.*
  - 172.25.*
  - 172.26.*
  - 172.27.*
  - 172.28.*
  - 172.29.*
  - 172.30.*
  - 172.31.*
  - 192.168.*
  - <local>
cfw-latency-timeout: 5000
    
proxy-groups:
- name: "ADMcgh+"
  type: select
  proxies:
    - "⚡ AUTO 📶"
    - "NAMEFILE"
EOF
#sed -i "s/+/'/g"  /root/.config/clash/config.yaml
foc=1
_auto=''
[[ -e /usr/local/etc/trojan/config.json ]] && ConfTrojINI
unset yesno
foc=1
[[ -e /etc/v2ray/config.json ]] && ConfV2RINI
unset yesno
foc=1
[[ -e /etc/xray/config.json ]] && ConfXRINI
}


configINIT_global () {
mode=$1
[[ -z ${mode} ]] && exit
unset tropass
echo '#SCRIPT OFICIAL ChumoGH|Plus
# Formato Creado por @ChumoGH | +593987072611 Whatsapp Personal
# Creado el _dAtE - _h0rA | CONFIG GLOBAL ${mode}
port: 8080
socks-port: 7891
redir-port: 7892
allow-lan: true
bind-address: "*"
mode: global
log-level: info
external-controller: "0.0.0.0:9090"
secret: ""
dns:
  enable: true
  listen: :53
  enhanced-mode: fake-ip
  nameserver:
    - 114.114.114.114
    - 223.5.5.5
    - 8.8.8.8
    - 45.71.185.100
    - 204.199.156.138
    - 1.1.1.1
  fallback: []
  fake-ip-filter:
    - +.stun.*.*
    - +.stun.*.*.*
    - +.stun.*.*.*.*
    - +.stun.*.*.*.*.*
    - "*.n.n.srv.nintendo.net"
    - +.stun.playstation.net
    - xbox.*.*.microsoft.com
    - "*.*.xboxlive.com"
    - "*.msftncsi.com"
    - "*.msftconnecttest.com"
    - WORKGROUP    
tun:
  enable: true
  stack: gvisor
  auto-route: true
  auto-detect-interface: true
  dns-hijack:
    - any:53

# Clash for Windows
cfw-bypass:
  - qq.com
  - music.163.com
  - "*.music.126.net"
  - localhost
  - 127.*
  - 10.*
  - 172.16.*
  - 172.17.*
  - 172.18.*
  - 172.19.*
  - 172.20.*
  - 172.21.*
  - 172.22.*
  - 172.23.*
  - 172.24.*
  - 172.25.*
  - 172.26.*
  - 172.27.*
  - 172.28.*
  - 172.29.*
  - 172.30.*
  - 172.31.*
  - 192.168.*
  - <local>
cfw-latency-timeout: 5000   
 ' > /root/.config/clash/config.yaml
#sed -i "s/+/'/g"  /root/.config/clash/config.yaml
foc=1
[[ -e /usr/local/etc/trojan/config.json ]] && ConfTrojINI
unset yesno
foc=1
[[ -e /etc/v2ray/config.json ]] && ConfV2RINI
unset yesno
foc=1
[[ -e /etc/xray/config.json ]] && ConfXRINI
}

proxyTRO() {
fun_ip
[[ $mode = 1 ]] && {
_rules+="    - $1
"
echo -e "    - $1" >> /root/.config/clash/config.yaml
}
[[ $mode = 3 ]] && _auto+="    - $1
" #>> /root/.config/clash/config.yaml
proTRO+="- name: $1\n  type: trojan\n  server: ${IP}\n  port: ${troport}\n  password: "$2"\n  udp: true\n  sni: $3\n  alpn:\n  - h2\n  - http/1.1\n  skip-cert-verify: true\n\n" 
  }

ConfTrojINI() {
echo -e " DESEAS AÑADIR TU ${foc} CONFIG TROJAN " 
while [[ ${yesno} != @(s|S|y|Y|n|N) ]]; do
read -p " [S/N]: " yesno

tput cuu1 && tput dl1
done
[[ ${yesno} = @(s|S|y|Y) ]] &&  { 
unset yesno
foc=$(($foc + 1))
echo -ne "\033[1;33m ➣ PERFIL TROJAN CLASH "
read -p ": " nameperfil
msg -bar3
[[ -z ${UUID} ]] && view_usert || { 
echo -e " USER ${Usr} : ${UUID}"
msg -bar3
}
echo -ne "\033[1;33m ➣ SNI o HOST "
read -p ": " trosni
msg -bar3
proxyTRO ${nameperfil} ${UUID} ${trosni}
ConfTrojINI
								}
}

proxyV2R() {
#proxyV2R ${nameperfil} ${trosni} ${uid} ${aluuiid} ${net} ${parche} ${v2port}
fun_ip
[[ $mode = 1 ]] && {
_rules+="    - $1
"
echo -e "    - $1" >> /root/.config/clash/config.yaml
}

[[ $mode = 3 ]] && _auto+="    - $1
" #>> /root/.config/clash/config.yaml
proV2R+="- name: $1\n  type: vmess\n  server: ${IP}\n  port: $7\n  uuid: $3\n  alterId: $4\n  cipher: auto\n  udp: true\n  tls: true\n  skip-cert-verify: true\n  servername: $2\n  network: $5\n  ws-opts:  \n       path: $6\n       headers:\n         Host: $2\n  \n\n" 
  }
  
proxyV2Rgprc() {
#config=/usr/local/x-ui/bin/config.json
#cat $config | jq .inbounds[].settings.clients | grep id
#proxyV2R ${nameperfil} ${trosni} ${uid} ${aluuiid} ${net} ${parche} ${v2port}
fun_ip
[[ $mode = 3 ]] && _auto+="    - $1
" #>> /root/.config/clash/config.yaml
[[ $mode = 1 ]] && {
_rules+="    - $1
"
echo -e "    - $1" >> /root/.config/clash/config.yaml
}

proV2R+="
- name: $1\n  server: ${IP}\n  port: $7\n  type: vmess\n  uuid: $3\n  alterId: $4\n  cipher: auto\n  tls: true\n  skip-cert-verify: true\n  network: grpc\n  servername: $2\n  grpc-opts:\n    grpc-mode: gun\n    grpc-service-name: $6\n  udp: true \n\n"
  }
proxyXR() {
#proxyV2R ${nameperfil} ${trosni} ${uid} ${aluuiid} ${net} ${parche} ${v2port}
fun_ip
[[ $mode = 1 ]] && {
_rules+="    - $1
"
echo -e "    - $1" >> /root/.config/clash/config.yaml
}

[[ $mode = 3 ]] && _auto+="    - $1
" #>> /root/.config/clash/config.yaml
proXR+="- name: $1\n  type: vmess\n  server: ${IP}\n  port: $7\n  uuid: $3\n  alterId: $4\n  cipher: auto\n  udp: true\n  tls: true\n  skip-cert-verify: true\n  servername: $2\n  network: $5\n  ws-opts:  \n       path: $6\n       headers:\n         Host: $2\n  \n\n" 
  }
  
proxyXRgprc() {
#config=/usr/local/x-ui/bin/config.json
#cat $config | jq .inbounds[].settings.clients | grep id
#proxyV2R ${nameperfil} ${trosni} ${uid} ${aluuiid} ${net} ${parche} ${v2port}
fun_ip
[[ $mode = 1 ]] && {
_rules+="    - $1
"
echo -e "    - $1" >> /root/.config/clash/config.yaml
}

[[ $mode = 3 ]] && _auto+="    - $1
" #>> /root/.config/clash/config.yaml
proXR+="
- name: $1\n  server: ${IP}\n  port: $7\n  type: vmess\n  uuid: $3\n  alterId: $4\n  cipher: auto\n  tls: true\n  skip-cert-verify: true\n  network: grpc\n  servername: $2\n  grpc-opts:\n    grpc-mode: gun\n    grpc-service-name: $6\n  udp: true \n\n"
  }

ConfV2RINI() {
clear&&clear
msg -bar3
echo -e " DESEAS AÑADIR TU ${foc} CONFIG V2RAY " 
while [[ ${yesno} != @(s|S|y|Y|n|N) ]]; do
read -p "[S/N]: " yesno
tput cuu1 && tput dl1
tput cuu1 && tput dl1
done
[[ ${yesno} = @(s|S|y|Y) ]] &&  { 
unset yesno
foc=$(($foc + 1))
echo -ne "\033[1;33m ➣ PERFIL V2RAY CLASH "
read -p ": " nameperfil
msg -bar3
[[ -z ${uid} ]] && view_user || { 
echo -e " USER ${ps}"
msg -bar3
}
echo -ne "\033[1;33m ➣ SNI o HOST "
read -p ": " trosni
msg -bar3

		ps=$(jq .inbounds[].settings.clients[$opcion].email $config) && [[ $ps = null ]] && ps="default"
		uid=$(jq .inbounds[].settings.clients[$opcion].id $config)
		aluuiid=$(jq .inbounds[].settings.clients[$opcion].alterId $config)
		add=$(jq '.inbounds[].domain' $config) && [[ $add = null ]] && add=$(wget -qO- ipv4.icanhazip.com)
		host=$(jq '.inbounds[].streamSettings.wsSettings.headers.Host' $config) && [[ $host = null ]] && host=''
		net=$(jq '.inbounds[].streamSettings.network' $config)
		parche=$(jq -r .inbounds[].streamSettings.wsSettings.path $config) && [[ $path = null ]] && parche='' 
		v2port=$(jq '.inbounds[].port' $config)
		tls=$(jq '.inbounds[].streamSettings.security' $config)
		[[ $net = '"grpc"' ]] && path=$(jq '.inbounds[].streamSettings.grpcSettings.serviceName'  $config) || path=$(jq '.inbounds[].streamSettings.wsSettings.path' $config)
		addip=$(wget -qO- ifconfig.me)

[[ $net = '"grpc"' ]] && {
proxyV2Rgprc ${nameperfil} ${trosni} ${uid} ${aluuiid} ${net} ${path} ${v2port}
} || {
proxyV2R ${nameperfil} ${trosni} ${uid} ${aluuiid} ${net} ${parche} ${v2port}
}

ConfV2RINI
	} 
}

ConfXRINI() {
clear&&clear
msg -bar3
echo -e " DESEAS AÑADIR TU ${foc} CONFIG XRAY " 
while [[ ${yesno} != @(s|S|y|Y|n|N) ]]; do
read -p "[S/N]: " yesno
tput cuu1 && tput dl1
done
[[ ${yesno} = @(s|S|y|Y) ]] &&  { 
unset yesno
foc=$(($foc + 1))
echo -ne "\033[1;33m ➣ PERFIL XRAY CLASH "
read -p ": " nameperfilX
msg -bar3
[[ -z ${uidX} ]] && _view_userXR || { 
echo -e " USER ${ps} XRAY"
msg -bar3
}
echo -ne "\033[1;33m ➣ SNI o HOST "
read -p ": " trosniX
msg -bar3
		psX=$(jq .inbounds[].settings.clients[$opcion].email $config) && [[ $ps = null ]] && ps="default"
		uidX=$(jq .inbounds[].settings.clients[$opcion].id $config)
		aluuiidX=$(jq .inbounds[].settings.clients[$opcion].alterId $config)
		addX=$(jq '.inbounds[].domain' $config) && [[ $add = null ]] && addX=$(wget -qO- ipv4.icanhazip.com)
		hostX=$(jq '.inbounds[].streamSettings.wsSettings.headers.Host' $config) && [[ $host = null ]] && host=''
		netX=$(jq '.inbounds[].streamSettings.network' $config)
		parcheX=$(jq -r .inbounds[].streamSettings.wsSettings.path $config) && [[ $pathX = null ]] && parcheX='' 
		v2portX=$(jq '.inbounds[].port' $config)
		tlsX=$(jq '.inbounds[].streamSettings.security' $config)
		[[ $netX = '"grpc"' ]] && pathX=$(jq '.inbounds[].streamSettings.grpcSettings.serviceName'  $config) || pathX=$(jq '.inbounds[].streamSettings.wsSettings.path' $config)
		addip=$(wget -qO- ifconfig.me)

[[ $netX = '"grpc"' ]] && {
proxyXRgprc ${nameperfilX} ${trosniX} ${uidX} ${aluuiidX} ${netX} ${pathX} ${v2portX}
} || {
proxyXR ${nameperfilX} ${trosniX} ${uidX} ${aluuiidX} ${netX} ${parcheX} ${v2portX}
}

ConfXRINI
							}
}

confRULE() {
[[ $mode = 1 ]] && cat << RULES >> /root/.config/clash/config.yaml 
  url: http://www.gstatic.com/generate_204
  interval: 300

- name: "NAMEFILE"
  type: select
  proxies: 
${_rules}

  url: http://www.gstatic.com/generate_204
  interval: 300

Rules:
# Unbreak
# > Google
- DOMAIN-SUFFIX,googletraveladservices.com,ADMcgh+
- DOMAIN,dl.google.com,ADMcgh+
- DOMAIN,mtalk.google.com,ADMcgh+

# Internet Service Providers ADMcgh+ 运营商劫持
- DOMAIN-SUFFIX,17gouwuba.com,ADMcgh+
- DOMAIN-SUFFIX,186078.com,ADMcgh+
- DOMAIN-SUFFIX,189zj.cn,ADMcgh+
- DOMAIN-SUFFIX,285680.com,ADMcgh+
- DOMAIN-SUFFIX,3721zh.com,ADMcgh+
- DOMAIN-SUFFIX,4336wang.cn,ADMcgh+
- DOMAIN-SUFFIX,51chumoping.com,ADMcgh+
- DOMAIN-SUFFIX,51mld.cn,ADMcgh+
- DOMAIN-SUFFIX,51mypc.cn,ADMcgh+
- DOMAIN-SUFFIX,58mingri.cn,ADMcgh+
- DOMAIN-SUFFIX,58mingtian.cn,ADMcgh+
- DOMAIN-SUFFIX,5vl58stm.com,ADMcgh+
- DOMAIN-SUFFIX,6d63d3.com,ADMcgh+
- DOMAIN-SUFFIX,7gg.cc,ADMcgh+
- DOMAIN-SUFFIX,91veg.com,ADMcgh+
- DOMAIN-SUFFIX,9s6q.cn,ADMcgh+
- DOMAIN-SUFFIX,adsame.com,ADMcgh+
- DOMAIN-SUFFIX,aiclk.com,ADMcgh+
- DOMAIN-SUFFIX,akuai.top,ADMcgh+
- DOMAIN-SUFFIX,atplay.cn,ADMcgh+
- DOMAIN-SUFFIX,baiwanchuangyi.com,ADMcgh+
- DOMAIN-SUFFIX,beerto.cn,ADMcgh+
- DOMAIN-SUFFIX,beilamusi.com,ADMcgh+
- DOMAIN-SUFFIX,benshiw.net,ADMcgh+
- DOMAIN-SUFFIX,bianxianmao.com,ADMcgh+
- DOMAIN-SUFFIX,bryonypie.com,ADMcgh+
- DOMAIN-SUFFIX,cishantao.com,ADMcgh+
- DOMAIN-SUFFIX,cszlks.com,ADMcgh+
- DOMAIN-SUFFIX,cudaojia.com,ADMcgh+
- DOMAIN-SUFFIX,dafapromo.com,ADMcgh+
- DOMAIN-SUFFIX,daitdai.com,ADMcgh+
- DOMAIN-SUFFIX,dsaeerf.com,ADMcgh+
- DOMAIN-SUFFIX,dugesheying.com,ADMcgh+
- DOMAIN-SUFFIX,dv8c1t.cn,ADMcgh+
- DOMAIN-SUFFIX,echatu.com,ADMcgh+
- DOMAIN-SUFFIX,erdoscs.com,ADMcgh+
- DOMAIN-SUFFIX,fan-yong.com,ADMcgh+
- DOMAIN-SUFFIX,feih.com.cn,ADMcgh+
- DOMAIN-SUFFIX,fjlqqc.com,ADMcgh+
- DOMAIN-SUFFIX,fkku194.com,ADMcgh+
- DOMAIN-SUFFIX,freedrive.cn,ADMcgh+
- DOMAIN-SUFFIX,gclick.cn,ADMcgh+
- DOMAIN-SUFFIX,goufanli100.com,ADMcgh+
- DOMAIN-SUFFIX,goupaoerdai.com,ADMcgh+
- DOMAIN-SUFFIX,gouwubang.com,ADMcgh+
- DOMAIN-SUFFIX,gzxnlk.com,ADMcgh+
- DOMAIN-SUFFIX,haoshengtoys.com,ADMcgh+
- DOMAIN-SUFFIX,hyunke.com,ADMcgh+
- DOMAIN-SUFFIX,ichaosheng.com,ADMcgh+
- DOMAIN-SUFFIX,ishop789.com,ADMcgh+
- DOMAIN-SUFFIX,jdkic.com,ADMcgh+
- DOMAIN-SUFFIX,jiubuhua.com,ADMcgh+
- DOMAIN-SUFFIX,jsncke.com,ADMcgh+
- DOMAIN-SUFFIX,junkucm.com,ADMcgh+
- DOMAIN-SUFFIX,jwg365.cn,ADMcgh+
- DOMAIN-SUFFIX,kawo77.com,ADMcgh+
- DOMAIN-SUFFIX,kualianyingxiao.cn,ADMcgh+
- DOMAIN-SUFFIX,kumihua.com,ADMcgh+
- DOMAIN-SUFFIX,ltheanine.cn,ADMcgh+
- DOMAIN-SUFFIX,maipinshangmao.com,ADMcgh+
- DOMAIN-SUFFIX,minisplat.cn,ADMcgh+
- DOMAIN-SUFFIX,mkitgfs.com,ADMcgh+
- DOMAIN-SUFFIX,mlnbike.com,ADMcgh+
- DOMAIN-SUFFIX,mobjump.com,ADMcgh+
- DOMAIN-SUFFIX,nbkbgd.cn,ADMcgh+
- DOMAIN-SUFFIX,newapi.com,ADMcgh+
- DOMAIN-SUFFIX,pinzhitmall.com,ADMcgh+
- DOMAIN-SUFFIX,poppyta.com,ADMcgh+
- DOMAIN-SUFFIX,qianchuanghr.com,ADMcgh+
- DOMAIN-SUFFIX,qichexin.com,ADMcgh+
- DOMAIN-SUFFIX,qinchugudao.com,ADMcgh+
- DOMAIN-SUFFIX,quanliyouxi.cn,ADMcgh+
- DOMAIN-SUFFIX,qutaobi.com,ADMcgh+
- DOMAIN-SUFFIX,ry51w.cn,ADMcgh+
- DOMAIN-SUFFIX,sg536.cn,ADMcgh+
- DOMAIN-SUFFIX,sifubo.cn,ADMcgh+
- DOMAIN-SUFFIX,sifuce.cn,ADMcgh+
- DOMAIN-SUFFIX,sifuda.cn,ADMcgh+
- DOMAIN-SUFFIX,sifufu.cn,ADMcgh+
- DOMAIN-SUFFIX,sifuge.cn,ADMcgh+
- DOMAIN-SUFFIX,sifugu.cn,ADMcgh+
- DOMAIN-SUFFIX,sifuhe.cn,ADMcgh+
- DOMAIN-SUFFIX,sifuhu.cn,ADMcgh+
- DOMAIN-SUFFIX,sifuji.cn,ADMcgh+
- DOMAIN-SUFFIX,sifuka.cn,ADMcgh+
- DOMAIN-SUFFIX,smgru.net,ADMcgh+
- DOMAIN-SUFFIX,taoggou.com,ADMcgh+
- DOMAIN-SUFFIX,tcxshop.com,ADMcgh+
- DOMAIN-SUFFIX,tjqonline.cn,ADMcgh+
- DOMAIN-SUFFIX,topitme.com,ADMcgh+
- DOMAIN-SUFFIX,tt3sm4.cn,ADMcgh+
- DOMAIN-SUFFIX,tuia.cn,ADMcgh+
- DOMAIN-SUFFIX,tuipenguin.com,ADMcgh+
- DOMAIN-SUFFIX,tuitiger.com,ADMcgh+
- DOMAIN-SUFFIX,websd8.com,ADMcgh+
- DOMAIN-SUFFIX,wsgblw.com,ADMcgh+
- DOMAIN-SUFFIX,wx16999.com,ADMcgh+
- DOMAIN-SUFFIX,xchmai.com,ADMcgh+
- DOMAIN-SUFFIX,xiaohuau.xyz,ADMcgh+
- DOMAIN-SUFFIX,ygyzx.cn,ADMcgh+
- DOMAIN-SUFFIX,yinmong.com,ADMcgh+
- DOMAIN-SUFFIX,yitaopt.com,ADMcgh+
- DOMAIN-SUFFIX,yjqiqi.com,ADMcgh+
- DOMAIN-SUFFIX,yukhj.com,ADMcgh+
- DOMAIN-SUFFIX,zhaozecheng.cn,ADMcgh+
- DOMAIN-SUFFIX,zhenxinet.com,ADMcgh+
- DOMAIN-SUFFIX,zlne800.com,ADMcgh+
- DOMAIN-SUFFIX,zunmi.cn,ADMcgh+
- DOMAIN-SUFFIX,zzd6.com,ADMcgh+
- IP-CIDR,39.107.15.115/32,ADMcgh+,no-resolve
- IP-CIDR,47.89.59.182/32,ADMcgh+,no-resolve
- IP-CIDR,103.49.209.27/32,ADMcgh+,no-resolve
- IP-CIDR,123.56.152.96/32,ADMcgh+,no-resolve
# > ChinaTelecom
- IP-CIDR,61.160.200.223/32,ADMcgh+,no-resolve
- IP-CIDR,61.160.200.242/32,ADMcgh+,no-resolve
- IP-CIDR,61.160.200.252/32,ADMcgh+,no-resolve
- IP-CIDR,61.174.50.214/32,ADMcgh+,no-resolve
- IP-CIDR,111.175.220.163/32,ADMcgh+,no-resolve
- IP-CIDR,111.175.220.164/32,ADMcgh+,no-resolve
- IP-CIDR,122.229.8.47/32,ADMcgh+,no-resolve
- IP-CIDR,122.229.29.89/32,ADMcgh+,no-resolve
- IP-CIDR,124.232.160.178/32,ADMcgh+,no-resolve
- IP-CIDR,175.6.223.15/32,ADMcgh+,no-resolve
- IP-CIDR,183.59.53.237/32,ADMcgh+,no-resolve
- IP-CIDR,218.93.127.37/32,ADMcgh+,no-resolve
- IP-CIDR,221.228.17.152/32,ADMcgh+,no-resolve
- IP-CIDR,221.231.6.79/32,ADMcgh+,no-resolve
- IP-CIDR,222.186.61.91/32,ADMcgh+,no-resolve
- IP-CIDR,222.186.61.95/32,ADMcgh+,no-resolve
- IP-CIDR,222.186.61.96/32,ADMcgh+,no-resolve
- IP-CIDR,222.186.61.97/32,ADMcgh+,no-resolve
# > ChinaUnicom
- IP-CIDR,106.75.231.48/32,ADMcgh+,no-resolve
- IP-CIDR,119.4.249.166/32,ADMcgh+,no-resolve
- IP-CIDR,220.196.52.141/32,ADMcgh+,no-resolve
- IP-CIDR,221.6.4.148/32,ADMcgh+,no-resolve
# > ChinaMobile
- IP-CIDR,114.247.28.96/32,ADMcgh+,no-resolve
- IP-CIDR,221.179.131.72/32,ADMcgh+,no-resolve
- IP-CIDR,221.179.140.145/32,ADMcgh+,no-resolve
# > Dr.Peng
# - IP-CIDR,10.72.25.0/24,ADMcgh+,no-resolve
- IP-CIDR,115.182.16.79/32,ADMcgh+,no-resolve
- IP-CIDR,118.144.88.126/32,ADMcgh+,no-resolve
- IP-CIDR,118.144.88.215/32,ADMcgh+,no-resolve
- IP-CIDR,118.144.88.216/32,ADMcgh+,no-resolve
- IP-CIDR,120.76.189.132/32,ADMcgh+,no-resolve
- IP-CIDR,124.14.21.147/32,ADMcgh+,no-resolve
- IP-CIDR,124.14.21.151/32,ADMcgh+,no-resolve
- IP-CIDR,180.166.52.24/32,ADMcgh+,no-resolve
- IP-CIDR,211.161.101.106/32,ADMcgh+,no-resolve
- IP-CIDR,220.115.251.25/32,ADMcgh+,no-resolve
- IP-CIDR,222.73.156.235/32,ADMcgh+,no-resolve

# Malware 恶意网站
# > 快压
# https://zhuanlan.zhihu.com/p/39534279
- DOMAIN-SUFFIX,kuaizip.com,ADMcgh+
# > MacKeeper
# https://www.lizhi.io/blog/40002904
- DOMAIN-SUFFIX,mackeeper.com,ADMcgh+
- DOMAIN-SUFFIX,zryydi.com,ADMcgh+
# > Adobe Flash China Special Edition
# https://www.zhihu.com/question/281163698/answer/441388130
- DOMAIN-SUFFIX,flash.cn,ADMcgh+
- DOMAIN,geo2.adobe.com,ADMcgh+
# > C&J Marketing 思杰马克丁软件
# https://www.zhihu.com/question/46746200
- DOMAIN-SUFFIX,4009997658.com,ADMcgh+
- DOMAIN-SUFFIX,abbyychina.com,ADMcgh+
- DOMAIN-SUFFIX,bartender.cc,ADMcgh+
- DOMAIN-SUFFIX,betterzip.net,ADMcgh+
- DOMAIN-SUFFIX,betterzipcn.com,ADMcgh+
- DOMAIN-SUFFIX,beyondcompare.cc,ADMcgh+
- DOMAIN-SUFFIX,bingdianhuanyuan.cn,ADMcgh+
- DOMAIN-SUFFIX,chemdraw.com.cn,ADMcgh+
- DOMAIN-SUFFIX,cjmakeding.com,ADMcgh+
- DOMAIN-SUFFIX,cjmkt.com,ADMcgh+
- DOMAIN-SUFFIX,codesoftchina.com,ADMcgh+
- DOMAIN-SUFFIX,coreldrawchina.com,ADMcgh+
- DOMAIN-SUFFIX,crossoverchina.com,ADMcgh+
- DOMAIN-SUFFIX,dongmansoft.com,ADMcgh+
- DOMAIN-SUFFIX,earmasterchina.cn,ADMcgh+
- DOMAIN-SUFFIX,easyrecoverychina.com,ADMcgh+
- DOMAIN-SUFFIX,ediuschina.com,ADMcgh+
- DOMAIN-SUFFIX,flstudiochina.com,ADMcgh+
- DOMAIN-SUFFIX,formysql.com,ADMcgh+
- DOMAIN-SUFFIX,guitarpro.cc,ADMcgh+
- DOMAIN-SUFFIX,huishenghuiying.com.cn,ADMcgh+
- DOMAIN-SUFFIX,hypersnap.net,ADMcgh+
- DOMAIN-SUFFIX,iconworkshop.cn,ADMcgh+
- DOMAIN-SUFFIX,imindmap.cc,ADMcgh+
- DOMAIN-SUFFIX,jihehuaban.com.cn,ADMcgh+
- DOMAIN-SUFFIX,keyshot.cc,ADMcgh+
- DOMAIN-SUFFIX,kingdeecn.cn,ADMcgh+
- DOMAIN-SUFFIX,logoshejishi.com,ADMcgh+
- DOMAIN-SUFFIX,luping.net.cn,ADMcgh+
- DOMAIN-SUFFIX,mairuan.cn,ADMcgh+
- DOMAIN-SUFFIX,mairuan.com,ADMcgh+
- DOMAIN-SUFFIX,mairuan.com.cn,ADMcgh+
- DOMAIN-SUFFIX,mairuan.net,ADMcgh+
- DOMAIN-SUFFIX,mairuanwang.com,ADMcgh+
- DOMAIN-SUFFIX,makeding.com,ADMcgh+
- DOMAIN-SUFFIX,mathtype.cn,ADMcgh+
- DOMAIN-SUFFIX,mindmanager.cc,ADMcgh+
- DOMAIN-SUFFIX,mindmanager.cn,ADMcgh+
- DOMAIN-SUFFIX,mindmapper.cc,ADMcgh+
- DOMAIN-SUFFIX,mycleanmymac.com,ADMcgh+
- DOMAIN-SUFFIX,nicelabel.cc,ADMcgh+
- DOMAIN-SUFFIX,ntfsformac.cc,ADMcgh+
- DOMAIN-SUFFIX,ntfsformac.cn,ADMcgh+
- DOMAIN-SUFFIX,overturechina.com,ADMcgh+
- DOMAIN-SUFFIX,passwordrecovery.cn,ADMcgh+
- DOMAIN-SUFFIX,pdfexpert.cc,ADMcgh+
- DOMAIN-SUFFIX,photozoomchina.com,ADMcgh+
- DOMAIN-SUFFIX,shankejingling.com,ADMcgh+
- DOMAIN-SUFFIX,ultraiso.net,ADMcgh+
- DOMAIN-SUFFIX,vegaschina.cn,ADMcgh+
- DOMAIN-SUFFIX,xmindchina.net,ADMcgh+
- DOMAIN-SUFFIX,xshellcn.com,ADMcgh+
- DOMAIN-SUFFIX,yihuifu.cn,ADMcgh+
- DOMAIN-SUFFIX,yuanchengxiezuo.com,ADMcgh+
- DOMAIN-SUFFIX,zbrushcn.com,ADMcgh+
- DOMAIN-SUFFIX,zhzzx.com,ADMcgh+

# Global Area Network
# (ADMcgh+)
# (Music)
# > Deezer
# USER-AGENT,Deezer*,ADMcgh+
- DOMAIN-SUFFIX,deezer.com,ADMcgh+
- DOMAIN-SUFFIX,dzcdn.net,ADMcgh+
# > KKBOX
- DOMAIN-SUFFIX,kkbox.com,ADMcgh+
- DOMAIN-SUFFIX,kkbox.com.tw,ADMcgh+
- DOMAIN-SUFFIX,kfs.io,ADMcgh+
# > JOOX
# USER-AGENT,WeMusic*,ADMcgh+
# USER-AGENT,JOOX*,ADMcgh+
- DOMAIN-SUFFIX,joox.com,ADMcgh+
# > Pandora
# USER-AGENT,Pandora*,ADMcgh+
- DOMAIN-SUFFIX,pandora.com,ADMcgh+
# > SoundCloud
# USER-AGENT,SoundCloud*,ADMcgh+
- DOMAIN-SUFFIX,p-cdn.us,ADMcgh+
- DOMAIN-SUFFIX,sndcdn.com,ADMcgh+
- DOMAIN-SUFFIX,soundcloud.com,ADMcgh+
# > Spotify
# USER-AGENT,Spotify*,ADMcgh+
- DOMAIN-SUFFIX,pscdn.co,ADMcgh+
- DOMAIN-SUFFIX,scdn.co,ADMcgh+
- DOMAIN-SUFFIX,spotify.com,ADMcgh+
- DOMAIN-SUFFIX,spoti.fi,ADMcgh+
- DOMAIN-KEYWORD,spotify.com,ADMcgh+
- DOMAIN-KEYWORD,-spotify-com,ADMcgh+
# > TIDAL
# USER-AGENT,TIDAL*,ADMcgh+
- DOMAIN-SUFFIX,tidal.com,ADMcgh+
# > YouTubeMusic
# USER-AGENT,com.google.ios.youtubemusic*,ADMcgh+
# USER-AGENT,YouTubeMusic*,ADMcgh+
# (Video)
# > All4
# USER-AGENT,All4*,ADMcgh+
- DOMAIN-SUFFIX,c4assets.com,ADMcgh+
- DOMAIN-SUFFIX,channel4.com,ADMcgh+
# > AbemaTV
# USER-AGENT,AbemaTV*,ADMcgh+
- DOMAIN-SUFFIX,abema.io,ADMcgh+
- DOMAIN-SUFFIX,ameba.jp,ADMcgh+
- DOMAIN-SUFFIX,abema.tv,ADMcgh+
- DOMAIN-SUFFIX,hayabusa.io,ADMcgh+
- DOMAIN,abematv.akamaized.net,ADMcgh+
- DOMAIN,ds-linear-abematv.akamaized.net,ADMcgh+
- DOMAIN,ds-vod-abematv.akamaized.net,ADMcgh+
- DOMAIN,linear-abematv.akamaized.net,ADMcgh+
# > Amazon Prime Video
# USER-AGENT,InstantVideo.US*,ADMcgh+
# USER-AGENT,Prime%20Video*,ADMcgh+
- DOMAIN-SUFFIX,aiv-cdn.net,ADMcgh+
- DOMAIN-SUFFIX,aiv-delivery.net,ADMcgh+
- DOMAIN-SUFFIX,amazonvideo.com,ADMcgh+
- DOMAIN-SUFFIX,primevideo.com,ADMcgh+
- DOMAIN,avodmp4s3ww-a.akamaihd.net,ADMcgh+
- DOMAIN,d25xi40x97liuc.cloudfront.net,ADMcgh+
- DOMAIN,dmqdd6hw24ucf.cloudfront.net,ADMcgh+
- DOMAIN,d22qjgkvxw22r6.cloudfront.net,ADMcgh+
- DOMAIN,d1v5ir2lpwr8os.cloudfront.net,ADMcgh+
- DOMAIN-KEYWORD,avoddashs,ADMcgh+
# > Bahamut
# USER-AGENT,Anime*,ADMcgh+
- DOMAIN-SUFFIX,bahamut.com.tw,ADMcgh+
- DOMAIN-SUFFIX,gamer.com.tw,ADMcgh+
- DOMAIN,gamer-cds.cdn.hinet.net,ADMcgh+
- DOMAIN,gamer2-cds.cdn.hinet.net,ADMcgh+
# > BBC iPlayer
# USER-AGENT,BBCiPlayer*,ADMcgh+
- DOMAIN-SUFFIX,bbc.co.uk,ADMcgh+
- DOMAIN-SUFFIX,bbci.co.uk,ADMcgh+
- DOMAIN-KEYWORD,bbcfmt,ADMcgh+
- DOMAIN-KEYWORD,uk-live,ADMcgh+
# > DAZN
# USER-AGENT,DAZN*,ADMcgh+
- DOMAIN-SUFFIX,dazn.com,ADMcgh+
- DOMAIN-SUFFIX,dazn-api.com,ADMcgh+
- DOMAIN,d151l6v8er5bdm.cloudfront.net,ADMcgh+
- DOMAIN-KEYWORD,voddazn,ADMcgh+
# > Disney+
# USER-AGENT,Disney+*,ADMcgh+
- DOMAIN-SUFFIX,bamgrid.com,ADMcgh+
- DOMAIN-SUFFIX,disney-plus.net,ADMcgh+
- DOMAIN-SUFFIX,disneyplus.com,ADMcgh+
- DOMAIN-SUFFIX,dssott.com,ADMcgh+
- DOMAIN,cdn.registerdisney.go.com,ADMcgh+
# > encoreTVB
# USER-AGENT,encoreTVB*,ADMcgh+
- DOMAIN-SUFFIX,encoretvb.com,ADMcgh+
- DOMAIN,edge.api.brightcove.com,ADMcgh+
- DOMAIN,bcbolt446c5271-a.akamaihd.net,ADMcgh+
# > FOX NOW
# USER-AGENT,FOX%20NOW*,ADMcgh+
- DOMAIN-SUFFIX,fox.com,ADMcgh+
- DOMAIN-SUFFIX,foxdcg.com,ADMcgh+
- DOMAIN-SUFFIX,theplatform.com,ADMcgh+
- DOMAIN-SUFFIX,uplynk.com,ADMcgh+
# > HBO NOW
# USER-AGENT,HBO%20NOW*,ADMcgh+
- DOMAIN-SUFFIX,hbo.com,ADMcgh+
- DOMAIN-SUFFIX,hbogo.com,ADMcgh+
- DOMAIN-SUFFIX,hbonow.com,ADMcgh+
# > HBO GO HKG
# USER-AGENT,HBO%20GO%20PROD%20HKG*,ADMcgh+
- DOMAIN-SUFFIX,hbogoasia.com,ADMcgh+
- DOMAIN-SUFFIX,hbogoasia.hk,ADMcgh+
- DOMAIN,bcbolthboa-a.akamaihd.net,ADMcgh+
- DOMAIN,players.brightcove.net,ADMcgh+
- DOMAIN,s3-ap-southeast-1.amazonaws.com,ADMcgh+
- DOMAIN,dai3fd1oh325y.cloudfront.net,ADMcgh+
- DOMAIN,44wilhpljf.execute-api.ap-southeast-1.amazonaws.com,ADMcgh+
- DOMAIN,hboasia1-i.akamaihd.net,ADMcgh+
- DOMAIN,hboasia2-i.akamaihd.net,ADMcgh+
- DOMAIN,hboasia3-i.akamaihd.net,ADMcgh+
- DOMAIN,hboasia4-i.akamaihd.net,ADMcgh+
- DOMAIN,hboasia5-i.akamaihd.net,ADMcgh+
- DOMAIN,cf-images.ap-southeast-1.prod.boltdns.net,ADMcgh+
# > 华文电视
# USER-AGENT,HWTVMobile*,ADMcgh+
- DOMAIN-SUFFIX,5itv.tv,ADMcgh+
- DOMAIN-SUFFIX,ocnttv.com,ADMcgh+
# > Hulu
- DOMAIN-SUFFIX,hulu.com,ADMcgh+
- DOMAIN-SUFFIX,huluim.com,ADMcgh+
- DOMAIN-SUFFIX,hulustream.com,ADMcgh+
# > Hulu(フールー)
- DOMAIN-SUFFIX,happyon.jp,ADMcgh+
- DOMAIN-SUFFIX,hulu.jp,ADMcgh+
# > ITV
# USER-AGENT,ITV_Player*,ADMcgh+
- DOMAIN-SUFFIX,itv.com,ADMcgh+
- DOMAIN-SUFFIX,itvstatic.com,ADMcgh+
- DOMAIN,itvpnpmobile-a.akamaihd.net,ADMcgh+
# > KKTV
# USER-AGENT,KKTV*,ADMcgh+
# USER-AGENT,com.kktv.ios.kktv*,ADMcgh+
- DOMAIN-SUFFIX,kktv.com.tw,ADMcgh+
- DOMAIN-SUFFIX,kktv.me,ADMcgh+
- DOMAIN,kktv-theater.kk.stream,ADMcgh+
# > Line TV
# USER-AGENT,LINE%20TV*,ADMcgh+
- DOMAIN-SUFFIX,linetv.tw,ADMcgh+
- DOMAIN,d3c7rimkq79yfu.cloudfront.net,ADMcgh+
# > LiTV
- DOMAIN-SUFFIX,litv.tv,ADMcgh+
- DOMAIN,litvfreemobile-hichannel.cdn.hinet.net,ADMcgh+
# > My5
# USER-AGENT,My5*,ADMcgh+
- DOMAIN-SUFFIX,channel5.com,ADMcgh+
- DOMAIN-SUFFIX,my5.tv,ADMcgh+
- DOMAIN,d349g9zuie06uo.cloudfront.net,ADMcgh+
# > myTV SUPER
# USER-AGENT,mytv*,ADMcgh+
- DOMAIN-SUFFIX,mytvsuper.com,ADMcgh+
- DOMAIN-SUFFIX,tvb.com,ADMcgh+
# > Netflix
# USER-AGENT,Argo*,ADMcgh+
- DOMAIN-SUFFIX,netflix.com,ADMcgh+
- DOMAIN-SUFFIX,netflix.net,ADMcgh+
- DOMAIN-SUFFIX,nflxext.com,ADMcgh+
- DOMAIN-SUFFIX,nflximg.com,ADMcgh+
- DOMAIN-SUFFIX,nflximg.net,ADMcgh+
- DOMAIN-SUFFIX,nflxso.net,ADMcgh+
- DOMAIN-SUFFIX,nflxvideo.net,ADMcgh+
- DOMAIN-SUFFIX,netflixdnstest0.com,ADMcgh+
- DOMAIN-SUFFIX,netflixdnstest1.com,ADMcgh+
- DOMAIN-SUFFIX,netflixdnstest2.com,ADMcgh+
- DOMAIN-SUFFIX,netflixdnstest3.com,ADMcgh+
- DOMAIN-SUFFIX,netflixdnstest4.com,ADMcgh+
- DOMAIN-SUFFIX,netflixdnstest5.com,ADMcgh+
- DOMAIN-SUFFIX,netflixdnstest6.com,ADMcgh+
- DOMAIN-SUFFIX,netflixdnstest7.com,ADMcgh+
- DOMAIN-SUFFIX,netflixdnstest8.com,ADMcgh+
- DOMAIN-SUFFIX,netflixdnstest9.com,ADMcgh+
- IP-CIDR,23.246.0.0/18,ADMcgh+,no-resolve
- IP-CIDR,37.77.184.0/21,ADMcgh+,no-resolve
- IP-CIDR,45.57.0.0/17,ADMcgh+,no-resolve
- IP-CIDR,64.120.128.0/17,ADMcgh+,no-resolve
- IP-CIDR,66.197.128.0/17,ADMcgh+,no-resolve
- IP-CIDR,108.175.32.0/20,ADMcgh+,no-resolve
- IP-CIDR,192.173.64.0/18,ADMcgh+,no-resolve
- IP-CIDR,198.38.96.0/19,ADMcgh+,no-resolve
- IP-CIDR,198.45.48.0/20,ADMcgh+,no-resolve
# > niconico
# USER-AGENT,Niconico*,ADMcgh+
- DOMAIN-SUFFIX,dmc.nico,ADMcgh+
- DOMAIN-SUFFIX,nicovideo.jp,ADMcgh+
- DOMAIN-SUFFIX,nimg.jp,ADMcgh+
- DOMAIN-SUFFIX,socdm.com,ADMcgh+
# > PBS
# USER-AGENT,PBS*,ADMcgh+
- DOMAIN-SUFFIX,pbs.org,ADMcgh+
# > Pornhub
- DOMAIN-SUFFIX,phncdn.com,ADMcgh+
- DOMAIN-SUFFIX,pornhub.com,ADMcgh+
- DOMAIN-SUFFIX,pornhubpremium.com,ADMcgh+
# > 台湾好
# USER-AGENT,TaiwanGood*,ADMcgh+
- DOMAIN-SUFFIX,skyking.com.tw,ADMcgh+
- DOMAIN,hamifans.emome.net,ADMcgh+
# > Twitch
- DOMAIN-SUFFIX,twitch.tv,ADMcgh+
- DOMAIN-SUFFIX,twitchcdn.net,ADMcgh+
- DOMAIN-SUFFIX,ttvnw.net,ADMcgh+
- DOMAIN-SUFFIX,jtvnw.net,ADMcgh+
# > ViuTV
# USER-AGENT,Viu*,ADMcgh+
# USER-AGENT,ViuTV*,ADMcgh+
- DOMAIN-SUFFIX,viu.com,ADMcgh+
- DOMAIN-SUFFIX,viu.tv,ADMcgh+
- DOMAIN,api.viu.now.com,ADMcgh+
- DOMAIN,d1k2us671qcoau.cloudfront.net,ADMcgh+
- DOMAIN,d2anahhhmp1ffz.cloudfront.net,ADMcgh+
- DOMAIN,dfp6rglgjqszk.cloudfront.net,ADMcgh+
# > YouTube
# USER-AGENT,com.google.ios.youtube*,ADMcgh+
# USER-AGENT,YouTube*,ADMcgh+
- DOMAIN-SUFFIX,googlevideo.com,ADMcgh+
- DOMAIN-SUFFIX,youtube.com,ADMcgh+
- DOMAIN,youtubei.googleapis.com,ADMcgh+

# (ADMcgh+)
# > 愛奇藝台灣站
- DOMAIN,cache.video.iqiyi.com,ADMcgh+
# > bilibili
- DOMAIN-SUFFIX,bilibili.com,ADMcgh+
- DOMAIN,upos-hz-mirrorakam.akamaized.net,ADMcgh+

# (DNS Cache Pollution Protection)
# > Google
- DOMAIN-SUFFIX,ampproject.org,ADMcgh+
- DOMAIN-SUFFIX,appspot.com,ADMcgh+
- DOMAIN-SUFFIX,blogger.com,ADMcgh+
- DOMAIN-SUFFIX,getoutline.org,ADMcgh+
- DOMAIN-SUFFIX,gvt0.com,ADMcgh+
- DOMAIN-SUFFIX,gvt1.com,ADMcgh+
- DOMAIN-SUFFIX,gvt3.com,ADMcgh+
- DOMAIN-SUFFIX,xn--ngstr-lra8j.com,ADMcgh+
- DOMAIN-KEYWORD,google,ADMcgh+
- DOMAIN-KEYWORD,blogspot,ADMcgh+
# > Microsoft
- DOMAIN-SUFFIX,onedrive.live.com,ADMcgh+
- DOMAIN-SUFFIX,xboxlive.com,ADMcgh+
# > Facebook
- DOMAIN-SUFFIX,cdninstagram.com,ADMcgh+
- DOMAIN-SUFFIX,fb.com,ADMcgh+
- DOMAIN-SUFFIX,fb.me,ADMcgh+
- DOMAIN-SUFFIX,fbaddins.com,ADMcgh+
- DOMAIN-SUFFIX,fbcdn.net,ADMcgh+
- DOMAIN-SUFFIX,fbsbx.com,ADMcgh+
- DOMAIN-SUFFIX,fbworkmail.com,ADMcgh+
- DOMAIN-SUFFIX,instagram.com,ADMcgh+
- DOMAIN-SUFFIX,m.me,ADMcgh+
- DOMAIN-SUFFIX,messenger.com,ADMcgh+
- DOMAIN-SUFFIX,oculus.com,ADMcgh+
- DOMAIN-SUFFIX,oculuscdn.com,ADMcgh+
- DOMAIN-SUFFIX,rocksdb.org,ADMcgh+
- DOMAIN-SUFFIX,whatsapp.com,ADMcgh+
- DOMAIN-SUFFIX,whatsapp.net,ADMcgh+
- DOMAIN-KEYWORD,facebook,ADMcgh+
- IP-CIDR,3.123.36.126/32,ADMcgh+,no-resolve
- IP-CIDR,35.157.215.84/32,ADMcgh+,no-resolve
- IP-CIDR,35.157.217.255/32,ADMcgh+,no-resolve
- IP-CIDR,52.58.209.134/32,ADMcgh+,no-resolve
- IP-CIDR,54.93.124.31/32,ADMcgh+,no-resolve
- IP-CIDR,54.162.243.80/32,ADMcgh+,no-resolve
- IP-CIDR,54.173.34.141/32,ADMcgh+,no-resolve
- IP-CIDR,54.235.23.242/32,ADMcgh+,no-resolve
- IP-CIDR,169.45.248.118/32,ADMcgh+,no-resolve
# > Twitter
- DOMAIN-SUFFIX,pscp.tv,ADMcgh+
- DOMAIN-SUFFIX,periscope.tv,ADMcgh+
- DOMAIN-SUFFIX,t.co,ADMcgh+
- DOMAIN-SUFFIX,twimg.co,ADMcgh+
- DOMAIN-SUFFIX,twimg.com,ADMcgh+
- DOMAIN-SUFFIX,twitpic.com,ADMcgh+
- DOMAIN-SUFFIX,vine.co,ADMcgh+
- DOMAIN-KEYWORD,twitter,ADMcgh+
# > Telegram
- DOMAIN-SUFFIX,t.me,ADMcgh+
- DOMAIN-SUFFIX,tdesktop.com,ADMcgh+
- DOMAIN-SUFFIX,telegra.ph,ADMcgh+
- DOMAIN-SUFFIX,telegram.me,ADMcgh+
- DOMAIN-SUFFIX,telegram.org,ADMcgh+
- IP-CIDR,91.108.4.0/22,ADMcgh+,no-resolve
- IP-CIDR,91.108.8.0/22,ADMcgh+,no-resolve
- IP-CIDR,91.108.12.0/22,ADMcgh+,no-resolve
- IP-CIDR,91.108.16.0/22,ADMcgh+,no-resolve
- IP-CIDR,91.108.56.0/22,ADMcgh+,no-resolve
- IP-CIDR,149.154.160.0/20,ADMcgh+,no-resolve
# > Line
- DOMAIN-SUFFIX,line.me,ADMcgh+
- DOMAIN-SUFFIX,line-apps.com,ADMcgh+
- DOMAIN-SUFFIX,line-scdn.net,ADMcgh+
- DOMAIN-SUFFIX,naver.jp,ADMcgh+
- IP-CIDR,103.2.30.0/23,ADMcgh+,no-resolve
- IP-CIDR,125.209.208.0/20,ADMcgh+,no-resolve
- IP-CIDR,147.92.128.0/17,ADMcgh+,no-resolve
- IP-CIDR,203.104.144.0/21,ADMcgh+,no-resolve
# > Other
- DOMAIN-SUFFIX,4shared.com,ADMcgh+
- DOMAIN-SUFFIX,520cc.cc,ADMcgh+
- DOMAIN-SUFFIX,881903.com,ADMcgh+
- DOMAIN-SUFFIX,9cache.com,ADMcgh+
- DOMAIN-SUFFIX,9gag.com,ADMcgh+
- DOMAIN-SUFFIX,abc.com,ADMcgh+
- DOMAIN-SUFFIX,abc.net.au,ADMcgh+
- DOMAIN-SUFFIX,abebooks.com,ADMcgh+
- DOMAIN-SUFFIX,amazon.co.jp,ADMcgh+
- DOMAIN-SUFFIX,apigee.com,ADMcgh+
- DOMAIN-SUFFIX,apk-dl.com,ADMcgh+
- DOMAIN-SUFFIX,apkfind.com,ADMcgh+
- DOMAIN-SUFFIX,apkmirror.com,ADMcgh+
- DOMAIN-SUFFIX,apkmonk.com,ADMcgh+
- DOMAIN-SUFFIX,apkpure.com,ADMcgh+
- DOMAIN-SUFFIX,aptoide.com,ADMcgh+
- DOMAIN-SUFFIX,archive.is,ADMcgh+
- DOMAIN-SUFFIX,archive.org,ADMcgh+
- DOMAIN-SUFFIX,arte.tv,ADMcgh+
- DOMAIN-SUFFIX,artstation.com,ADMcgh+
- DOMAIN-SUFFIX,arukas.io,ADMcgh+
- DOMAIN-SUFFIX,ask.com,ADMcgh+
- DOMAIN-SUFFIX,avg.com,ADMcgh+
- DOMAIN-SUFFIX,avgle.com,ADMcgh+
- DOMAIN-SUFFIX,badoo.com,ADMcgh+
- DOMAIN-SUFFIX,bandwagonhost.com,ADMcgh+
- DOMAIN-SUFFIX,bbc.com,ADMcgh+
- DOMAIN-SUFFIX,behance.net,ADMcgh+
- DOMAIN-SUFFIX,bibox.com,ADMcgh+
- DOMAIN-SUFFIX,biggo.com.tw,ADMcgh+
- DOMAIN-SUFFIX,binance.com,ADMcgh+
- DOMAIN-SUFFIX,bitcointalk.org,ADMcgh+
- DOMAIN-SUFFIX,bitfinex.com,ADMcgh+
- DOMAIN-SUFFIX,bitmex.com,ADMcgh+
- DOMAIN-SUFFIX,bit-z.com,ADMcgh+
- DOMAIN-SUFFIX,bloglovin.com,ADMcgh+
- DOMAIN-SUFFIX,bloomberg.cn,ADMcgh+
- DOMAIN-SUFFIX,bloomberg.com,ADMcgh+
- DOMAIN-SUFFIX,blubrry.com,ADMcgh+
- DOMAIN-SUFFIX,book.com.tw,ADMcgh+
- DOMAIN-SUFFIX,booklive.jp,ADMcgh+
- DOMAIN-SUFFIX,books.com.tw,ADMcgh+
- DOMAIN-SUFFIX,boslife.net,ADMcgh+
- DOMAIN-SUFFIX,box.com,ADMcgh+
- DOMAIN-SUFFIX,businessinsider.com,ADMcgh+
- DOMAIN-SUFFIX,bwh1.net,ADMcgh+
- DOMAIN-SUFFIX,castbox.fm,ADMcgh+
- DOMAIN-SUFFIX,cbc.ca,ADMcgh+
- DOMAIN-SUFFIX,cdw.com,ADMcgh+
- DOMAIN-SUFFIX,change.org,ADMcgh+
- DOMAIN-SUFFIX,channelnewsasia.com,ADMcgh+
- DOMAIN-SUFFIX,ck101.com,ADMcgh+
- DOMAIN-SUFFIX,clarionproject.org,ADMcgh+
- DOMAIN-SUFFIX,clyp.it,ADMcgh+
- DOMAIN-SUFFIX,cna.com.tw,ADMcgh+
- DOMAIN-SUFFIX,comparitech.com,ADMcgh+
- DOMAIN-SUFFIX,conoha.jp,ADMcgh+
- DOMAIN-SUFFIX,crucial.com,ADMcgh+
- DOMAIN-SUFFIX,cts.com.tw,ADMcgh+
- DOMAIN-SUFFIX,cw.com.tw,ADMcgh+
- DOMAIN-SUFFIX,cyberctm.com,ADMcgh+
- DOMAIN-SUFFIX,dailymotion.com,ADMcgh+
- DOMAIN-SUFFIX,dailyview.tw,ADMcgh+
- DOMAIN-SUFFIX,daum.net,ADMcgh+
- DOMAIN-SUFFIX,daumcdn.net,ADMcgh+
- DOMAIN-SUFFIX,dcard.tw,ADMcgh+
- DOMAIN-SUFFIX,deepdiscount.com,ADMcgh+
- DOMAIN-SUFFIX,depositphotos.com,ADMcgh+
- DOMAIN-SUFFIX,deviantart.com,ADMcgh+
- DOMAIN-SUFFIX,disconnect.me,ADMcgh+
- DOMAIN-SUFFIX,discordapp.com,ADMcgh+
- DOMAIN-SUFFIX,discordapp.net,ADMcgh+
- DOMAIN-SUFFIX,disqus.com,ADMcgh+
- DOMAIN-SUFFIX,dlercloud.com,ADMcgh+
- DOMAIN-SUFFIX,dns2go.com,ADMcgh+
- DOMAIN-SUFFIX,dowjones.com,ADMcgh+
- DOMAIN-SUFFIX,dropbox.com,ADMcgh+
- DOMAIN-SUFFIX,dropboxusercontent.com,ADMcgh+
- DOMAIN-SUFFIX,duckduckgo.com,ADMcgh+
- DOMAIN-SUFFIX,dw.com,ADMcgh+
- DOMAIN-SUFFIX,dynu.com,ADMcgh+
- DOMAIN-SUFFIX,earthcam.com,ADMcgh+
- DOMAIN-SUFFIX,ebookservice.tw,ADMcgh+
- DOMAIN-SUFFIX,economist.com,ADMcgh+
- DOMAIN-SUFFIX,edgecastcdn.net,ADMcgh+
- DOMAIN-SUFFIX,edu,ADMcgh+
- DOMAIN-SUFFIX,elpais.com,ADMcgh+
- DOMAIN-SUFFIX,enanyang.my,ADMcgh+
- DOMAIN-SUFFIX,encyclopedia.com,ADMcgh+
- DOMAIN-SUFFIX,esoir.be,ADMcgh+
- DOMAIN-SUFFIX,etherscan.io,ADMcgh+
- DOMAIN-SUFFIX,euronews.com,ADMcgh+
- DOMAIN-SUFFIX,evozi.com,ADMcgh+
- DOMAIN-SUFFIX,feedly.com,ADMcgh+
- DOMAIN-SUFFIX,firech.at,ADMcgh+
- DOMAIN-SUFFIX,flickr.com,ADMcgh+
- DOMAIN-SUFFIX,flitto.com,ADMcgh+
- DOMAIN-SUFFIX,foreignpolicy.com,ADMcgh+
- DOMAIN-SUFFIX,freebrowser.org,ADMcgh+
- DOMAIN-SUFFIX,freewechat.com,ADMcgh+
- DOMAIN-SUFFIX,freeweibo.com,ADMcgh+
- DOMAIN-SUFFIX,friday.tw,ADMcgh+
- DOMAIN-SUFFIX,ftchinese.com,ADMcgh+
- DOMAIN-SUFFIX,ftimg.net,ADMcgh+
- DOMAIN-SUFFIX,gate.io,ADMcgh+
- DOMAIN-SUFFIX,getlantern.org,ADMcgh+
- DOMAIN-SUFFIX,getsync.com,ADMcgh+
- DOMAIN-SUFFIX,globalvoices.org,ADMcgh+
- DOMAIN-SUFFIX,goo.ne.jp,ADMcgh+
- DOMAIN-SUFFIX,goodreads.com,ADMcgh+
- DOMAIN-SUFFIX,gov,ADMcgh+
- DOMAIN-SUFFIX,gov.tw,ADMcgh+
- DOMAIN-SUFFIX,greatfire.org,ADMcgh+
- DOMAIN-SUFFIX,gumroad.com,ADMcgh+
- DOMAIN-SUFFIX,hbg.com,ADMcgh+
- DOMAIN-SUFFIX,heroku.com,ADMcgh+
- DOMAIN-SUFFIX,hightail.com,ADMcgh+
- DOMAIN-SUFFIX,hk01.com,ADMcgh+
- DOMAIN-SUFFIX,hkbf.org,ADMcgh+
- DOMAIN-SUFFIX,hkbookcity.com,ADMcgh+
- DOMAIN-SUFFIX,hkej.com,ADMcgh+
- DOMAIN-SUFFIX,hket.com,ADMcgh+
- DOMAIN-SUFFIX,hkgolden.com,ADMcgh+
- DOMAIN-SUFFIX,hootsuite.com,ADMcgh+
- DOMAIN-SUFFIX,hudson.org,ADMcgh+
- DOMAIN-SUFFIX,hyread.com.tw,ADMcgh+
- DOMAIN-SUFFIX,ibtimes.com,ADMcgh+
- DOMAIN-SUFFIX,i-cable.com,ADMcgh+
- DOMAIN-SUFFIX,icij.org,ADMcgh+
- DOMAIN-SUFFIX,icoco.com,ADMcgh+
- DOMAIN-SUFFIX,imgur.com,ADMcgh+
- DOMAIN-SUFFIX,initiummall.com,ADMcgh+
- DOMAIN-SUFFIX,insecam.org,ADMcgh+
- DOMAIN-SUFFIX,ipfs.io,ADMcgh+
- DOMAIN-SUFFIX,issuu.com,ADMcgh+
- DOMAIN-SUFFIX,istockphoto.com,ADMcgh+
- DOMAIN-SUFFIX,japantimes.co.jp,ADMcgh+
- DOMAIN-SUFFIX,jiji.com,ADMcgh+
- DOMAIN-SUFFIX,jinx.com,ADMcgh+
- DOMAIN-SUFFIX,jkforum.net,ADMcgh+
- DOMAIN-SUFFIX,joinmastodon.org,ADMcgh+
- DOMAIN-SUFFIX,justmysocks.net,ADMcgh+
- DOMAIN-SUFFIX,justpaste.it,ADMcgh+
- DOMAIN-SUFFIX,kakao.com,ADMcgh+
- DOMAIN-SUFFIX,kakaocorp.com,ADMcgh+
- DOMAIN-SUFFIX,kik.com,ADMcgh+
- DOMAIN-SUFFIX,kobo.com,ADMcgh+
- DOMAIN-SUFFIX,kobobooks.com,ADMcgh+
- DOMAIN-SUFFIX,kodingen.com,ADMcgh+
- DOMAIN-SUFFIX,lemonde.fr,ADMcgh+
- DOMAIN-SUFFIX,lepoint.fr,ADMcgh+
- DOMAIN-SUFFIX,lihkg.com,ADMcgh+
- DOMAIN-SUFFIX,listennotes.com,ADMcgh+
- DOMAIN-SUFFIX,livestream.com,ADMcgh+
- DOMAIN-SUFFIX,logmein.com,ADMcgh+
- DOMAIN-SUFFIX,mail.ru,ADMcgh+
- DOMAIN-SUFFIX,mailchimp.com,ADMcgh+
- DOMAIN-SUFFIX,marc.info,ADMcgh+
- DOMAIN-SUFFIX,matters.news,ADMcgh+
- DOMAIN-SUFFIX,maying.co,ADMcgh+
- DOMAIN-SUFFIX,medium.com,ADMcgh+
- DOMAIN-SUFFIX,mega.nz,ADMcgh+
- DOMAIN-SUFFIX,mil,ADMcgh+
- DOMAIN-SUFFIX,mingpao.com,ADMcgh+
- DOMAIN-SUFFIX,mobile01.com,ADMcgh+
- DOMAIN-SUFFIX,myspace.com,ADMcgh+
- DOMAIN-SUFFIX,myspacecdn.com,ADMcgh+
- DOMAIN-SUFFIX,nanyang.com,ADMcgh+
- DOMAIN-SUFFIX,naver.com,ADMcgh+
- DOMAIN-SUFFIX,neowin.net,ADMcgh+
- DOMAIN-SUFFIX,newstapa.org,ADMcgh+
- DOMAIN-SUFFIX,nexitally.com,ADMcgh+
- DOMAIN-SUFFIX,nhk.or.jp,ADMcgh+
- DOMAIN-SUFFIX,nicovideo.jp,ADMcgh+
- DOMAIN-SUFFIX,nii.ac.jp,ADMcgh+
- DOMAIN-SUFFIX,nikkei.com,ADMcgh+
- DOMAIN-SUFFIX,nofile.io,ADMcgh+
- DOMAIN-SUFFIX,now.com,ADMcgh+
- DOMAIN-SUFFIX,nrk.no,ADMcgh+
- DOMAIN-SUFFIX,nyt.com,ADMcgh+
- DOMAIN-SUFFIX,nytchina.com,ADMcgh+
- DOMAIN-SUFFIX,nytcn.me,ADMcgh+
- DOMAIN-SUFFIX,nytco.com,ADMcgh+
- DOMAIN-SUFFIX,nytimes.com,ADMcgh+
- DOMAIN-SUFFIX,nytimg.com,ADMcgh+
- DOMAIN-SUFFIX,nytlog.com,ADMcgh+
- DOMAIN-SUFFIX,nytstyle.com,ADMcgh+
- DOMAIN-SUFFIX,ok.ru,ADMcgh+
- DOMAIN-SUFFIX,okex.com,ADMcgh+
- DOMAIN-SUFFIX,on.cc,ADMcgh+
- DOMAIN-SUFFIX,orientaldaily.com.my,ADMcgh+
- DOMAIN-SUFFIX,overcast.fm,ADMcgh+
- DOMAIN-SUFFIX,paltalk.com,ADMcgh+
- DOMAIN-SUFFIX,pao-pao.net,ADMcgh+
- DOMAIN-SUFFIX,parsevideo.com,ADMcgh+
- DOMAIN-SUFFIX,pbxes.com,ADMcgh+
- DOMAIN-SUFFIX,pcdvd.com.tw,ADMcgh+
- DOMAIN-SUFFIX,pchome.com.tw,ADMcgh+
- DOMAIN-SUFFIX,pcloud.com,ADMcgh+
- DOMAIN-SUFFIX,picacomic.com,ADMcgh+
- DOMAIN-SUFFIX,pinimg.com,ADMcgh+
- DOMAIN-SUFFIX,pixiv.net,ADMcgh+
- DOMAIN-SUFFIX,player.fm,ADMcgh+
- DOMAIN-SUFFIX,plurk.com,ADMcgh+
- DOMAIN-SUFFIX,po18.tw,ADMcgh+
- DOMAIN-SUFFIX,potato.im,ADMcgh+
- DOMAIN-SUFFIX,potatso.com,ADMcgh+
- DOMAIN-SUFFIX,prism-break.org,ADMcgh+
- DOMAIN-SUFFIX,proxifier.com,ADMcgh+
- DOMAIN-SUFFIX,pt.im,ADMcgh+
- DOMAIN-SUFFIX,pts.org.tw,ADMcgh+
- DOMAIN-SUFFIX,pubu.com.tw,ADMcgh+
- DOMAIN-SUFFIX,pubu.tw,ADMcgh+
- DOMAIN-SUFFIX,pureapk.com,ADMcgh+
- DOMAIN-SUFFIX,quora.com,ADMcgh+
- DOMAIN-SUFFIX,quoracdn.net,ADMcgh+
- DOMAIN-SUFFIX,rakuten.co.jp,ADMcgh+
- DOMAIN-SUFFIX,readingtimes.com.tw,ADMcgh+
- DOMAIN-SUFFIX,readmoo.com,ADMcgh+
- DOMAIN-SUFFIX,redbubble.com,ADMcgh+
- DOMAIN-SUFFIX,reddit.com,ADMcgh+
- DOMAIN-SUFFIX,redditmedia.com,ADMcgh+
- DOMAIN-SUFFIX,resilio.com,ADMcgh+
- DOMAIN-SUFFIX,reuters.com,ADMcgh+
- DOMAIN-SUFFIX,reutersmedia.net,ADMcgh+
- DOMAIN-SUFFIX,rfi.fr,ADMcgh+
- DOMAIN-SUFFIX,rixcloud.com,ADMcgh+
- DOMAIN-SUFFIX,roadshow.hk,ADMcgh+
- DOMAIN-SUFFIX,scmp.com,ADMcgh+
- DOMAIN-SUFFIX,scribd.com,ADMcgh+
- DOMAIN-SUFFIX,seatguru.com,ADMcgh+
- DOMAIN-SUFFIX,shadowsocks.org,ADMcgh+
- DOMAIN-SUFFIX,shopee.tw,ADMcgh+
- DOMAIN-SUFFIX,slideshare.net,ADMcgh+
- DOMAIN-SUFFIX,softfamous.com,ADMcgh+
- DOMAIN-SUFFIX,soundcloud.com,ADMcgh+
- DOMAIN-SUFFIX,ssrcloud.org,ADMcgh+
- DOMAIN-SUFFIX,startpage.com,ADMcgh+
- DOMAIN-SUFFIX,steamcommunity.com,ADMcgh+
- DOMAIN-SUFFIX,steemit.com,ADMcgh+
- DOMAIN-SUFFIX,steemitwallet.com,ADMcgh+
- DOMAIN-SUFFIX,t66y.com,ADMcgh+
- DOMAIN-SUFFIX,tapatalk.com,ADMcgh+
- DOMAIN-SUFFIX,teco-hk.org,ADMcgh+
- DOMAIN-SUFFIX,teco-mo.org,ADMcgh+
- DOMAIN-SUFFIX,teddysun.com,ADMcgh+
- DOMAIN-SUFFIX,textnow.me,ADMcgh+
- DOMAIN-SUFFIX,theguardian.com,ADMcgh+
- DOMAIN-SUFFIX,theinitium.com,ADMcgh+
- DOMAIN-SUFFIX,thetvdb.com,ADMcgh+
- DOMAIN-SUFFIX,tineye.com,ADMcgh+
- DOMAIN-SUFFIX,torproject.org,ADMcgh+
- DOMAIN-SUFFIX,tumblr.com,ADMcgh+
- DOMAIN-SUFFIX,turbobit.net,ADMcgh+
- DOMAIN-SUFFIX,tutanota.com,ADMcgh+
- DOMAIN-SUFFIX,tvboxnow.com,ADMcgh+
- DOMAIN-SUFFIX,udn.com,ADMcgh+
- DOMAIN-SUFFIX,unseen.is,ADMcgh+
- DOMAIN-SUFFIX,upmedia.mg,ADMcgh+
- DOMAIN-SUFFIX,uptodown.com,ADMcgh+
- DOMAIN-SUFFIX,urbandictionary.com,ADMcgh+
- DOMAIN-SUFFIX,ustream.tv,ADMcgh+
- DOMAIN-SUFFIX,uwants.com,ADMcgh+
- DOMAIN-SUFFIX,v2ray.com,ADMcgh+
- DOMAIN-SUFFIX,viber.com,ADMcgh+
- DOMAIN-SUFFIX,videopress.com,ADMcgh+
- DOMAIN-SUFFIX,vimeo.com,ADMcgh+
- DOMAIN-SUFFIX,voachinese.com,ADMcgh+
- DOMAIN-SUFFIX,voanews.com,ADMcgh+
- DOMAIN-SUFFIX,voxer.com,ADMcgh+
- DOMAIN-SUFFIX,vzw.com,ADMcgh+
- DOMAIN-SUFFIX,w3schools.com,ADMcgh+
- DOMAIN-SUFFIX,washingtonpost.com,ADMcgh+
- DOMAIN-SUFFIX,wattpad.com,ADMcgh+
- DOMAIN-SUFFIX,whoer.net,ADMcgh+
- DOMAIN-SUFFIX,wikimapia.org,ADMcgh+
- DOMAIN-SUFFIX,wikipedia.org,ADMcgh+
- DOMAIN-SUFFIX,wikiquote.org,ADMcgh+
- DOMAIN-SUFFIX,wikiwand.com,ADMcgh+
- DOMAIN-SUFFIX,winudf.com,ADMcgh+
- DOMAIN-SUFFIX,wire.com,ADMcgh+
- DOMAIN-SUFFIX,wordpress.com,ADMcgh+
- DOMAIN-SUFFIX,workflow.is,ADMcgh+
- DOMAIN-SUFFIX,worldcat.org,ADMcgh+
- DOMAIN-SUFFIX,wsj.com,ADMcgh+
- DOMAIN-SUFFIX,wsj.net,ADMcgh+
- DOMAIN-SUFFIX,xhamster.com,ADMcgh+
- DOMAIN-SUFFIX,xn--90wwvt03e.com,ADMcgh+
- DOMAIN-SUFFIX,xn--i2ru8q2qg.com,ADMcgh+
- DOMAIN-SUFFIX,xnxx.com,ADMcgh+
- DOMAIN-SUFFIX,xvideos.com,ADMcgh+
- DOMAIN-SUFFIX,yahoo.com,ADMcgh+
- DOMAIN-SUFFIX,yandex.ru,ADMcgh+
- DOMAIN-SUFFIX,ycombinator.com,ADMcgh+
- DOMAIN-SUFFIX,yesasia.com,ADMcgh+
- DOMAIN-SUFFIX,yes-news.com,ADMcgh+
- DOMAIN-SUFFIX,yomiuri.co.jp,ADMcgh+
- DOMAIN-SUFFIX,you-get.org,ADMcgh+
- DOMAIN-SUFFIX,zaobao.com,ADMcgh+
- DOMAIN-SUFFIX,zb.com,ADMcgh+
- DOMAIN-SUFFIX,zello.com,ADMcgh+
- DOMAIN-SUFFIX,zeronet.io,ADMcgh+
- DOMAIN-SUFFIX,zoom.us,ADMcgh+
- DOMAIN-KEYWORD,github,ADMcgh+
- DOMAIN-KEYWORD,jav,ADMcgh+
- DOMAIN-KEYWORD,pinterest,ADMcgh+
- DOMAIN-KEYWORD,porn,ADMcgh+
- DOMAIN-KEYWORD,wikileaks,ADMcgh+

# (Region-Restricted Access Denied)
- DOMAIN-SUFFIX,apartmentratings.com,ADMcgh+
- DOMAIN-SUFFIX,apartments.com,ADMcgh+
- DOMAIN-SUFFIX,bankmobilevibe.com,ADMcgh+
- DOMAIN-SUFFIX,bing.com,ADMcgh+
- DOMAIN-SUFFIX,booktopia.com.au,ADMcgh+
- DOMAIN-SUFFIX,cccat.io,ADMcgh+
- DOMAIN-SUFFIX,centauro.com.br,ADMcgh+
- DOMAIN-SUFFIX,clearsurance.com,ADMcgh+
- DOMAIN-SUFFIX,costco.com,ADMcgh+
- DOMAIN-SUFFIX,crackle.com,ADMcgh+
- DOMAIN-SUFFIX,depositphotos.cn,ADMcgh+
- DOMAIN-SUFFIX,dish.com,ADMcgh+
- DOMAIN-SUFFIX,dmm.co.jp,ADMcgh+
- DOMAIN-SUFFIX,dmm.com,ADMcgh+
- DOMAIN-SUFFIX,dnvod.tv,ADMcgh+
- DOMAIN-SUFFIX,esurance.com,ADMcgh+
- DOMAIN-SUFFIX,extmatrix.com,ADMcgh+
- DOMAIN-SUFFIX,fastpic.ru,ADMcgh+
- DOMAIN-SUFFIX,flipboard.com,ADMcgh+
- DOMAIN-SUFFIX,fnac.be,ADMcgh+
- DOMAIN-SUFFIX,fnac.com,ADMcgh+
- DOMAIN-SUFFIX,funkyimg.com,ADMcgh+
- DOMAIN-SUFFIX,fxnetworks.com,ADMcgh+
- DOMAIN-SUFFIX,gettyimages.com,ADMcgh+
- DOMAIN-SUFFIX,go.com,ADMcgh+
- DOMAIN-SUFFIX,here.com,ADMcgh+
- DOMAIN-SUFFIX,jcpenney.com,ADMcgh+
- DOMAIN-SUFFIX,jiehua.tv,ADMcgh+
- DOMAIN-SUFFIX,mailfence.com,ADMcgh+
- DOMAIN-SUFFIX,nationwide.com,ADMcgh+
- DOMAIN-SUFFIX,nbc.com,ADMcgh+
- DOMAIN-SUFFIX,nexon.com,ADMcgh+
- DOMAIN-SUFFIX,nordstrom.com,ADMcgh+
- DOMAIN-SUFFIX,nordstromimage.com,ADMcgh+
- DOMAIN-SUFFIX,nordstromrack.com,ADMcgh+
- DOMAIN-SUFFIX,superpages.com,ADMcgh+
- DOMAIN-SUFFIX,target.com,ADMcgh+
- DOMAIN-SUFFIX,thinkgeek.com,ADMcgh+
- DOMAIN-SUFFIX,tracfone.com,ADMcgh+
- DOMAIN-SUFFIX,unity3d.com,ADMcgh+
- DOMAIN-SUFFIX,uploader.jp,ADMcgh+
- DOMAIN-SUFFIX,vevo.com,ADMcgh+
- DOMAIN-SUFFIX,viu.tv,ADMcgh+
- DOMAIN-SUFFIX,vk.com,ADMcgh+
- DOMAIN-SUFFIX,vsco.co,ADMcgh+
- DOMAIN-SUFFIX,xfinity.com,ADMcgh+
- DOMAIN-SUFFIX,zattoo.com,ADMcgh+
# USER-AGENT,Roam*,ADMcgh+

# (The Most Popular Sites)
# > ADMcgh+
# >> TestFlight
- DOMAIN,testflight.apple.com,ADMcgh+
# >> ADMcgh+ URL Shortener
- DOMAIN-SUFFIX,appsto.re,ADMcgh+
# >> iBooks Store download
- DOMAIN,books.itunes.apple.com,ADMcgh+
# >> iTunes Store Moveis Trailers
- DOMAIN,hls.itunes.apple.com,ADMcgh+
# >> App Store Preview
- DOMAIN,apps.apple.com,ADMcgh+
- DOMAIN,itunes.apple.com,ADMcgh+
# >> Spotlight
- DOMAIN,api-glb-sea.smoot.apple.com,ADMcgh+
# >> Dictionary
- DOMAIN,lookup-api.apple.com,ADMcgh+
# > Google
- DOMAIN-SUFFIX,abc.xyz,ADMcgh+
- DOMAIN-SUFFIX,android.com,ADMcgh+
- DOMAIN-SUFFIX,androidify.com,ADMcgh+
- DOMAIN-SUFFIX,dialogflow.com,ADMcgh+
- DOMAIN-SUFFIX,autodraw.com,ADMcgh+
- DOMAIN-SUFFIX,capitalg.com,ADMcgh+
- DOMAIN-SUFFIX,certificate-transparency.org,ADMcgh+
- DOMAIN-SUFFIX,chrome.com,ADMcgh+
- DOMAIN-SUFFIX,chromeexperiments.com,ADMcgh+
- DOMAIN-SUFFIX,chromestatus.com,ADMcgh+
- DOMAIN-SUFFIX,chromium.org,ADMcgh+
- DOMAIN-SUFFIX,creativelab5.com,ADMcgh+
- DOMAIN-SUFFIX,debug.com,ADMcgh+
- DOMAIN-SUFFIX,deepmind.com,ADMcgh+
- DOMAIN-SUFFIX,firebaseio.com,ADMcgh+
- DOMAIN-SUFFIX,getmdl.io,ADMcgh+
- DOMAIN-SUFFIX,ggpht.com,ADMcgh+
- DOMAIN-SUFFIX,gmail.com,ADMcgh+
- DOMAIN-SUFFIX,gmodules.com,ADMcgh+
- DOMAIN-SUFFIX,godoc.org,ADMcgh+
- DOMAIN-SUFFIX,golang.org,ADMcgh+
- DOMAIN-SUFFIX,gstatic.com,ADMcgh+
- DOMAIN-SUFFIX,gv.com,ADMcgh+
- DOMAIN-SUFFIX,gwtproject.org,ADMcgh+
- DOMAIN-SUFFIX,itasoftware.com,ADMcgh+
- DOMAIN-SUFFIX,madewithcode.com,ADMcgh+
- DOMAIN-SUFFIX,material.io,ADMcgh+
- DOMAIN-SUFFIX,polymer-project.org,ADMcgh+
- DOMAIN-SUFFIX,admin.recaptcha.net,ADMcgh+
- DOMAIN-SUFFIX,recaptcha.net,ADMcgh+
- DOMAIN-SUFFIX,shattered.io,ADMcgh+
- DOMAIN-SUFFIX,synergyse.com,ADMcgh+
- DOMAIN-SUFFIX,tensorflow.org,ADMcgh+
- DOMAIN-SUFFIX,tfhub.dev,ADMcgh+
- DOMAIN-SUFFIX,tiltbrush.com,ADMcgh+
- DOMAIN-SUFFIX,waveprotocol.org,ADMcgh+
- DOMAIN-SUFFIX,waymo.com,ADMcgh+
- DOMAIN-SUFFIX,webmproject.org,ADMcgh+
- DOMAIN-SUFFIX,webrtc.org,ADMcgh+
- DOMAIN-SUFFIX,whatbrowser.org,ADMcgh+
- DOMAIN-SUFFIX,widevine.com,ADMcgh+
- DOMAIN-SUFFIX,x.company,ADMcgh+
- DOMAIN-SUFFIX,youtu.be,ADMcgh+
- DOMAIN-SUFFIX,yt.be,ADMcgh+
- DOMAIN-SUFFIX,ytimg.com,ADMcgh+
# > Microsoft
# >> Microsoft OneDrive
- DOMAIN-SUFFIX,1drv.com,ADMcgh+
- DOMAIN-SUFFIX,1drv.ms,ADMcgh+
- DOMAIN-SUFFIX,blob.core.windows.net,ADMcgh+
- DOMAIN-SUFFIX,livefilestore.com,ADMcgh+
- DOMAIN-SUFFIX,onedrive.com,ADMcgh+
- DOMAIN-SUFFIX,storage.live.com,ADMcgh+
- DOMAIN-SUFFIX,storage.msn.com,ADMcgh+
- DOMAIN,oneclient.sfx.ms,ADMcgh+
# > Other
- DOMAIN-SUFFIX,0rz.tw,ADMcgh+
- DOMAIN-SUFFIX,4bluestones.biz,ADMcgh+
- DOMAIN-SUFFIX,9bis.net,ADMcgh+
- DOMAIN-SUFFIX,allconnected.co,ADMcgh+
- DOMAIN-SUFFIX,aol.com,ADMcgh+
- DOMAIN-SUFFIX,bcc.com.tw,ADMcgh+
- DOMAIN-SUFFIX,bit.ly,ADMcgh+
- DOMAIN-SUFFIX,bitshare.com,ADMcgh+
- DOMAIN-SUFFIX,blog.jp,ADMcgh+
- DOMAIN-SUFFIX,blogimg.jp,ADMcgh+
- DOMAIN-SUFFIX,blogtd.org,ADMcgh+
- DOMAIN-SUFFIX,broadcast.co.nz,ADMcgh+
- DOMAIN-SUFFIX,camfrog.com,ADMcgh+
- DOMAIN-SUFFIX,cfos.de,ADMcgh+
- DOMAIN-SUFFIX,citypopulation.de,ADMcgh+
- DOMAIN-SUFFIX,cloudfront.net,ADMcgh+
- DOMAIN-SUFFIX,ctitv.com.tw,ADMcgh+
- DOMAIN-SUFFIX,cuhk.edu.hk,ADMcgh+
- DOMAIN-SUFFIX,cusu.hk,ADMcgh+
- DOMAIN-SUFFIX,discord.gg,ADMcgh+
- DOMAIN-SUFFIX,discuss.com.hk,ADMcgh+
- DOMAIN-SUFFIX,dropboxapi.com,ADMcgh+
- DOMAIN-SUFFIX,duolingo.cn,ADMcgh+
- DOMAIN-SUFFIX,edditstatic.com,ADMcgh+
- DOMAIN-SUFFIX,flickriver.com,ADMcgh+
- DOMAIN-SUFFIX,focustaiwan.tw,ADMcgh+
- DOMAIN-SUFFIX,free.fr,ADMcgh+
- DOMAIN-SUFFIX,gigacircle.com,ADMcgh+
- DOMAIN-SUFFIX,hk-pub.com,ADMcgh+
- DOMAIN-SUFFIX,hosting.co.uk,ADMcgh+
- DOMAIN-SUFFIX,hwcdn.net,ADMcgh+
- DOMAIN-SUFFIX,ifixit.com,ADMcgh+
- DOMAIN-SUFFIX,iphone4hongkong.com,ADMcgh+
- DOMAIN-SUFFIX,iphonetaiwan.org,ADMcgh+
- DOMAIN-SUFFIX,iptvbin.com,ADMcgh+
- DOMAIN-SUFFIX,linksalpha.com,ADMcgh+
- DOMAIN-SUFFIX,manyvids.com,ADMcgh+
- DOMAIN-SUFFIX,myactimes.com,ADMcgh+
- DOMAIN-SUFFIX,newsblur.com,ADMcgh+
- DOMAIN-SUFFIX,now.im,ADMcgh+
- DOMAIN-SUFFIX,nowe.com,ADMcgh+
- DOMAIN-SUFFIX,redditlist.com,ADMcgh+
- DOMAIN-SUFFIX,s3.amazonaws.com,ADMcgh+
- DOMAIN-SUFFIX,signal.org,ADMcgh+
- DOMAIN-SUFFIX,smartmailcloud.com,ADMcgh+
- DOMAIN-SUFFIX,sparknotes.com,ADMcgh+
- DOMAIN-SUFFIX,streetvoice.com,ADMcgh+
- DOMAIN-SUFFIX,supertop.co,ADMcgh+
- DOMAIN-SUFFIX,tv.com,ADMcgh+
- DOMAIN-SUFFIX,typepad.com,ADMcgh+
- DOMAIN-SUFFIX,udnbkk.com,ADMcgh+
- DOMAIN-SUFFIX,urbanairship.com,ADMcgh+
- DOMAIN-SUFFIX,whispersystems.org,ADMcgh+
- DOMAIN-SUFFIX,wikia.com,ADMcgh+
- DOMAIN-SUFFIX,wn.com,ADMcgh+
- DOMAIN-SUFFIX,wolframalpha.com,ADMcgh+
- DOMAIN-SUFFIX,x-art.com,ADMcgh+
- DOMAIN-SUFFIX,yimg.com,ADMcgh+
- DOMAIN,api.steampowered.com,ADMcgh+
- DOMAIN,store.steampowered.com,ADMcgh+

# China Area Network
# > 360
- DOMAIN-SUFFIX,qhres.com,ADMcgh+
- DOMAIN-SUFFIX,qhimg.com,ADMcgh+
# > Akamai
- DOMAIN-SUFFIX,akadns.net,ADMcgh+
# - DOMAIN-SUFFIX,akamai.net,ADMcgh+
# - DOMAIN-SUFFIX,akamaiedge.net,ADMcgh+
# - DOMAIN-SUFFIX,akamaihd.net,ADMcgh+
# - DOMAIN-SUFFIX,akamaistream.net,ADMcgh+
# - DOMAIN-SUFFIX,akamaized.net,ADMcgh+
# > Alibaba
# USER-AGENT,%E4%BC%98%E9%85%B7*,ADMcgh+
- DOMAIN-SUFFIX,alibaba.com,ADMcgh+
- DOMAIN-SUFFIX,alicdn.com,ADMcgh+
- DOMAIN-SUFFIX,alikunlun.com,ADMcgh+
- DOMAIN-SUFFIX,alipay.com,ADMcgh+
- DOMAIN-SUFFIX,amap.com,ADMcgh+
- DOMAIN-SUFFIX,autonavi.com,ADMcgh+
- DOMAIN-SUFFIX,dingtalk.com,ADMcgh+
- DOMAIN-SUFFIX,mxhichina.com,ADMcgh+
- DOMAIN-SUFFIX,soku.com,ADMcgh+
- DOMAIN-SUFFIX,taobao.com,ADMcgh+
- DOMAIN-SUFFIX,tmall.com,ADMcgh+
- DOMAIN-SUFFIX,tmall.hk,ADMcgh+
- DOMAIN-SUFFIX,ykimg.com,ADMcgh+
- DOMAIN-SUFFIX,youku.com,ADMcgh+
- DOMAIN-SUFFIX,xiami.com,ADMcgh+
- DOMAIN-SUFFIX,xiami.net,ADMcgh+
# > Baidu
- DOMAIN-SUFFIX,baidu.com,ADMcgh+
- DOMAIN-SUFFIX,baidubcr.com,ADMcgh+
- DOMAIN-SUFFIX,bdstatic.com,ADMcgh+
- DOMAIN-SUFFIX,yunjiasu-cdn.net,ADMcgh+
# > bilibili
- DOMAIN-SUFFIX,acgvideo.com,ADMcgh+
- DOMAIN-SUFFIX,biliapi.com,ADMcgh+
- DOMAIN-SUFFIX,biliapi.net,ADMcgh+
- DOMAIN-SUFFIX,bilibili.com,ADMcgh+
- DOMAIN-SUFFIX,bilibili.tv,ADMcgh+
- DOMAIN-SUFFIX,hdslb.com,ADMcgh+
# > Blizzard
- DOMAIN-SUFFIX,blizzard.com,ADMcgh+
- DOMAIN-SUFFIX,battle.net,ADMcgh+
- DOMAIN,blzddist1-a.akamaihd.net,ADMcgh+
# > ByteDance
- DOMAIN-SUFFIX,feiliao.com,ADMcgh+
- DOMAIN-SUFFIX,pstatp.com,ADMcgh+
- DOMAIN-SUFFIX,snssdk.com,ADMcgh+
- DOMAIN-SUFFIX,iesdouyin.com,ADMcgh+
- DOMAIN-SUFFIX,toutiao.com,ADMcgh+
# > CCTV
- DOMAIN-SUFFIX,cctv.com,ADMcgh+
- DOMAIN-SUFFIX,cctvpic.com,ADMcgh+
- DOMAIN-SUFFIX,livechina.com,ADMcgh+
# > DiDi
- DOMAIN-SUFFIX,didialift.com,ADMcgh+
- DOMAIN-SUFFIX,didiglobal.com,ADMcgh+
- DOMAIN-SUFFIX,udache.com,ADMcgh+
# > 蛋蛋赞
- DOMAIN-SUFFIX,343480.com,ADMcgh+
- DOMAIN-SUFFIX,baduziyuan.com,ADMcgh+
- DOMAIN-SUFFIX,com-hs-hkdy.com,ADMcgh+
- DOMAIN-SUFFIX,czybjz.com,ADMcgh+
- DOMAIN-SUFFIX,dandanzan.com,ADMcgh+
- DOMAIN-SUFFIX,fjhps.com,ADMcgh+
- DOMAIN-SUFFIX,kuyunbo.club,ADMcgh+
# > ChinaNet
- DOMAIN-SUFFIX,21cn.com,ADMcgh+
# > HunanTV
- DOMAIN-SUFFIX,hitv.com,ADMcgh+
- DOMAIN-SUFFIX,mgtv.com,ADMcgh+
# > iQiyi
- DOMAIN-SUFFIX,iqiyi.com,ADMcgh+
- DOMAIN-SUFFIX,iqiyipic.com,ADMcgh+
- DOMAIN-SUFFIX,71.am.com,ADMcgh+
# > JD
- DOMAIN-SUFFIX,jd.com,ADMcgh+
- DOMAIN-SUFFIX,jd.hk,ADMcgh+
- DOMAIN-SUFFIX,jdpay.com,ADMcgh+
- DOMAIN-SUFFIX,360buyimg.com,ADMcgh+
# > Kingsoft
- DOMAIN-SUFFIX,iciba.com,ADMcgh+
- DOMAIN-SUFFIX,ksosoft.com,ADMcgh+
# > Meitu
- DOMAIN-SUFFIX,meitu.com,ADMcgh+
- DOMAIN-SUFFIX,meitudata.com,ADMcgh+
- DOMAIN-SUFFIX,meitustat.com,ADMcgh+
- DOMAIN-SUFFIX,meipai.com,ADMcgh+
# > MI
- DOMAIN-SUFFIX,duokan.com,ADMcgh+
- DOMAIN-SUFFIX,mi-img.com,ADMcgh+
- DOMAIN-SUFFIX,miui.com,ADMcgh+
- DOMAIN-SUFFIX,miwifi.com,ADMcgh+
- DOMAIN-SUFFIX,xiaomi.com,ADMcgh+
# > Microsoft
- DOMAIN-SUFFIX,microsoft.com,ADMcgh+
- DOMAIN-SUFFIX,msecnd.net,ADMcgh+
- DOMAIN-SUFFIX,office365.com,ADMcgh+
- DOMAIN-SUFFIX,outlook.com,ADMcgh+
- DOMAIN-SUFFIX,s-microsoft.com,ADMcgh+
- DOMAIN-SUFFIX,visualstudio.com,ADMcgh+
- DOMAIN-SUFFIX,windows.com,ADMcgh+
- DOMAIN-SUFFIX,windowsupdate.com,ADMcgh+
- DOMAIN,officecdn-microsoft-com.akamaized.net,ADMcgh+
# > NetEase
# USER-AGENT,NeteaseMusic*,ADMcgh+
# USER-AGENT,%E7%BD%91%E6%98%93%E4%BA%91%E9%9F%B3%E4%B9%90*,ADMcgh+
- DOMAIN-SUFFIX,163.com,ADMcgh+
- DOMAIN-SUFFIX,126.net,ADMcgh+
- DOMAIN-SUFFIX,127.net,ADMcgh+
- DOMAIN-SUFFIX,163yun.com,ADMcgh+
- DOMAIN-SUFFIX,lofter.com,ADMcgh+
- DOMAIN-SUFFIX,netease.com,ADMcgh+
- DOMAIN-SUFFIX,ydstatic.com,ADMcgh+
# > Sina
- DOMAIN-SUFFIX,sina.com,ADMcgh+
- DOMAIN-SUFFIX,weibo.com,ADMcgh+
- DOMAIN-SUFFIX,weibocdn.com,ADMcgh+
# > Sohu
- DOMAIN-SUFFIX,sohu.com,ADMcgh+
- DOMAIN-SUFFIX,sohucs.com,ADMcgh+
- DOMAIN-SUFFIX,sohu-inc.com,ADMcgh+
- DOMAIN-SUFFIX,v-56.com,ADMcgh+
# > Sogo
- DOMAIN-SUFFIX,sogo.com,ADMcgh+
- DOMAIN-SUFFIX,sogou.com,ADMcgh+
- DOMAIN-SUFFIX,sogoucdn.com,ADMcgh+
# > Steam
- DOMAIN-SUFFIX,steampowered.com,ADMcgh+
- DOMAIN-SUFFIX,steam-chat.com,ADMcgh+
- DOMAIN-SUFFIX,steamgames.com,ADMcgh+
- DOMAIN-SUFFIX,steamusercontent.com,ADMcgh+
- DOMAIN-SUFFIX,steamcontent.com,ADMcgh+
- DOMAIN-SUFFIX,steamstatic.com,ADMcgh+
- DOMAIN-SUFFIX,steamcdn-a.akamaihd.net,ADMcgh+
- DOMAIN-SUFFIX,steamstat.us,ADMcgh+
# > Tencent
# USER-AGENT,MicroMessenger%20Client,ADMcgh+
# USER-AGENT,WeChat*,ADMcgh+
- DOMAIN-SUFFIX,gtimg.com,ADMcgh+
- DOMAIN-SUFFIX,idqqimg.com,ADMcgh+
- DOMAIN-SUFFIX,igamecj.com,ADMcgh+
- DOMAIN-SUFFIX,myapp.com,ADMcgh+
- DOMAIN-SUFFIX,myqcloud.com,ADMcgh+
- DOMAIN-SUFFIX,qq.com,ADMcgh+
- DOMAIN-SUFFIX,tencent.com,ADMcgh+
- DOMAIN-SUFFIX,tencent-cloud.net,ADMcgh+
# > YYeTs
# USER-AGENT,YYeTs*,ADMcgh+
- DOMAIN-SUFFIX,jstucdn.com,ADMcgh+
- DOMAIN-SUFFIX,zimuzu.io,ADMcgh+
- DOMAIN-SUFFIX,zimuzu.tv,ADMcgh+
- DOMAIN-SUFFIX,zmz2019.com,ADMcgh+
- DOMAIN-SUFFIX,zmzapi.com,ADMcgh+
- DOMAIN-SUFFIX,zmzapi.net,ADMcgh+
- DOMAIN-SUFFIX,zmzfile.com,ADMcgh+
# > Content Delivery Network
- DOMAIN-SUFFIX,ccgslb.com,ADMcgh+
- DOMAIN-SUFFIX,ccgslb.net,ADMcgh+
- DOMAIN-SUFFIX,chinanetcenter.com,ADMcgh+
- DOMAIN-SUFFIX,meixincdn.com,ADMcgh+
- DOMAIN-SUFFIX,ourdvs.com,ADMcgh+
- DOMAIN-SUFFIX,staticdn.net,ADMcgh+
- DOMAIN-SUFFIX,wangsu.com,ADMcgh+
# > IP Query
- DOMAIN-SUFFIX,ipip.net,ADMcgh+
- DOMAIN-SUFFIX,ip.la,ADMcgh+
- DOMAIN-SUFFIX,ip-cdn.com,ADMcgh+
- DOMAIN-SUFFIX,ipv6-test.com,ADMcgh+
- DOMAIN-SUFFIX,test-ipv6.com,ADMcgh+
- DOMAIN-SUFFIX,whatismyip.com,ADMcgh+
# > Speed Test
# - DOMAIN-SUFFIX,speedtest.net,ADMcgh+
- DOMAIN-SUFFIX,netspeedtestmaster.com,ADMcgh+
- DOMAIN,speedtest.macpaw.com,ADMcgh+
# > Private Tracker
- DOMAIN-SUFFIX,awesome-hd.me,ADMcgh+
- DOMAIN-SUFFIX,broadcasthe.net,ADMcgh+
- DOMAIN-SUFFIX,chdbits.co,ADMcgh+
- DOMAIN-SUFFIX,classix-unlimited.co.uk,ADMcgh+
- DOMAIN-SUFFIX,empornium.me,ADMcgh+
- DOMAIN-SUFFIX,gazellegames.net,ADMcgh+
- DOMAIN-SUFFIX,hdchina.org,ADMcgh+
- DOMAIN-SUFFIX,hdsky.me,ADMcgh+
- DOMAIN-SUFFIX,icetorrent.org,ADMcgh+
- DOMAIN-SUFFIX,jpopsuki.eu,ADMcgh+
- DOMAIN-SUFFIX,keepfrds.com,ADMcgh+
- DOMAIN-SUFFIX,madsrevolution.net,ADMcgh+
- DOMAIN-SUFFIX,m-team.cc,ADMcgh+
- DOMAIN-SUFFIX,nanyangpt.com,ADMcgh+
- DOMAIN-SUFFIX,ncore.cc,ADMcgh+
- DOMAIN-SUFFIX,open.cd,ADMcgh+
- DOMAIN-SUFFIX,ourbits.club,ADMcgh+
- DOMAIN-SUFFIX,passthepopcorn.me,ADMcgh+
- DOMAIN-SUFFIX,privatehd.to,ADMcgh+
- DOMAIN-SUFFIX,redacted.ch,ADMcgh+
- DOMAIN-SUFFIX,springsunday.net,ADMcgh+
- DOMAIN-SUFFIX,tjupt.org,ADMcgh+
- DOMAIN-SUFFIX,totheglory.im,ADMcgh+
# > Scholar
- DOMAIN-SUFFIX,acm.org,ADMcgh+
- DOMAIN-SUFFIX,acs.org,ADMcgh+
- DOMAIN-SUFFIX,aip.org,ADMcgh+
- DOMAIN-SUFFIX,ams.org,ADMcgh+
- DOMAIN-SUFFIX,annualreviews.org,ADMcgh+
- DOMAIN-SUFFIX,aps.org,ADMcgh+
- DOMAIN-SUFFIX,ascelibrary.org,ADMcgh+
- DOMAIN-SUFFIX,asm.org,ADMcgh+
- DOMAIN-SUFFIX,asme.org,ADMcgh+
- DOMAIN-SUFFIX,astm.org,ADMcgh+
- DOMAIN-SUFFIX,bmj.com,ADMcgh+
- DOMAIN-SUFFIX,cambridge.org,ADMcgh+
- DOMAIN-SUFFIX,cas.org,ADMcgh+
- DOMAIN-SUFFIX,clarivate.com,ADMcgh+
- DOMAIN-SUFFIX,ebscohost.com,ADMcgh+
- DOMAIN-SUFFIX,emerald.com,ADMcgh+
- DOMAIN-SUFFIX,engineeringvillage.com,ADMcgh+
- DOMAIN-SUFFIX,icevirtuallibrary.com,ADMcgh+
- DOMAIN-SUFFIX,ieee.org,ADMcgh+
- DOMAIN-SUFFIX,imf.org,ADMcgh+
- DOMAIN-SUFFIX,iop.org,ADMcgh+
- DOMAIN-SUFFIX,jamanetwork.com,ADMcgh+
- DOMAIN-SUFFIX,jhu.edu,ADMcgh+
- DOMAIN-SUFFIX,jstor.org,ADMcgh+
- DOMAIN-SUFFIX,karger.com,ADMcgh+
- DOMAIN-SUFFIX,libguides.com,ADMcgh+
- DOMAIN-SUFFIX,madsrevolution.net,ADMcgh+
- DOMAIN-SUFFIX,mpg.de,ADMcgh+
- DOMAIN-SUFFIX,myilibrary.com,ADMcgh+
- DOMAIN-SUFFIX,nature.com,ADMcgh+
- DOMAIN-SUFFIX,oecd-ilibrary.org,ADMcgh+
- DOMAIN-SUFFIX,osapublishing.org,ADMcgh+
- DOMAIN-SUFFIX,oup.com,ADMcgh+
- DOMAIN-SUFFIX,ovid.com,ADMcgh+
- DOMAIN-SUFFIX,oxfordartonline.com,ADMcgh+
- DOMAIN-SUFFIX,oxfordbibliographies.com,ADMcgh+
- DOMAIN-SUFFIX,oxfordmusiconline.com,ADMcgh+
- DOMAIN-SUFFIX,pnas.org,ADMcgh+
- DOMAIN-SUFFIX,proquest.com,ADMcgh+
- DOMAIN-SUFFIX,rsc.org,ADMcgh+
- DOMAIN-SUFFIX,sagepub.com,ADMcgh+
- DOMAIN-SUFFIX,sciencedirect.com,ADMcgh+
- DOMAIN-SUFFIX,sciencemag.org,ADMcgh+
- DOMAIN-SUFFIX,scopus.com,ADMcgh+
- DOMAIN-SUFFIX,siam.org,ADMcgh+
- DOMAIN-SUFFIX,spiedigitallibrary.org,ADMcgh+
- DOMAIN-SUFFIX,springer.com,ADMcgh+
- DOMAIN-SUFFIX,springerlink.com,ADMcgh+
- DOMAIN-SUFFIX,tandfonline.com,ADMcgh+
- DOMAIN-SUFFIX,un.org,ADMcgh+
- DOMAIN-SUFFIX,uni-bielefeld.de,ADMcgh+
- DOMAIN-SUFFIX,webofknowledge.com,ADMcgh+
- DOMAIN-SUFFIX,westlaw.com,ADMcgh+
- DOMAIN-SUFFIX,wiley.com,ADMcgh+
- DOMAIN-SUFFIX,worldbank.org,ADMcgh+
- DOMAIN-SUFFIX,worldscientific.com,ADMcgh+
# > Plex Media Server
- DOMAIN-SUFFIX,plex.tv,ADMcgh+
# > Other
- DOMAIN-SUFFIX,cn,ADMcgh+
- DOMAIN-SUFFIX,360in.com,ADMcgh+
- DOMAIN-SUFFIX,51ym.me,ADMcgh+
- DOMAIN-SUFFIX,8686c.com,ADMcgh+
- DOMAIN-SUFFIX,abchina.com,ADMcgh+
- DOMAIN-SUFFIX,accuweather.com,ADMcgh+
- DOMAIN-SUFFIX,aicoinstorge.com,ADMcgh+
- DOMAIN-SUFFIX,air-matters.com,ADMcgh+
- DOMAIN-SUFFIX,air-matters.io,ADMcgh+
- DOMAIN-SUFFIX,aixifan.com,ADMcgh+
- DOMAIN-SUFFIX,amd.com,ADMcgh+
- DOMAIN-SUFFIX,b612.net,ADMcgh+
- DOMAIN-SUFFIX,bdatu.com,ADMcgh+
- DOMAIN-SUFFIX,beitaichufang.com,ADMcgh+
- DOMAIN-SUFFIX,bjango.com,ADMcgh+
- DOMAIN-SUFFIX,booking.com,ADMcgh+
- DOMAIN-SUFFIX,bstatic.com,ADMcgh+
- DOMAIN-SUFFIX,cailianpress.com,ADMcgh+
- DOMAIN-SUFFIX,camera360.com,ADMcgh+
- DOMAIN-SUFFIX,chinaso.com,ADMcgh+
- DOMAIN-SUFFIX,chua.pro,ADMcgh+
- DOMAIN-SUFFIX,chuimg.com,ADMcgh+
- DOMAIN-SUFFIX,chunyu.mobi,ADMcgh+
- DOMAIN-SUFFIX,chushou.tv,ADMcgh+
- DOMAIN-SUFFIX,cmbchina.com,ADMcgh+
- DOMAIN-SUFFIX,cmbimg.com,ADMcgh+
- DOMAIN-SUFFIX,ctrip.com,ADMcgh+
- DOMAIN-SUFFIX,dfcfw.com,ADMcgh+
- DOMAIN-SUFFIX,docschina.org,ADMcgh+
- DOMAIN-SUFFIX,douban.com,ADMcgh+
- DOMAIN-SUFFIX,doubanio.com,ADMcgh+
- DOMAIN-SUFFIX,douyu.com,ADMcgh+
- DOMAIN-SUFFIX,dxycdn.com,ADMcgh+
- DOMAIN-SUFFIX,dytt8.net,ADMcgh+
- DOMAIN-SUFFIX,eastmoney.com,ADMcgh+
- DOMAIN-SUFFIX,eudic.net,ADMcgh+
- DOMAIN-SUFFIX,feng.com,ADMcgh+
- DOMAIN-SUFFIX,fengkongcloud.com,ADMcgh+
- DOMAIN-SUFFIX,frdic.com,ADMcgh+
- DOMAIN-SUFFIX,futu5.com,ADMcgh+
- DOMAIN-SUFFIX,futunn.com,ADMcgh+
- DOMAIN-SUFFIX,gandi.net,ADMcgh+
- DOMAIN-SUFFIX,geilicdn.com,ADMcgh+
- DOMAIN-SUFFIX,getpricetag.com,ADMcgh+
- DOMAIN-SUFFIX,gifshow.com,ADMcgh+
- DOMAIN-SUFFIX,godic.net,ADMcgh+
- DOMAIN-SUFFIX,hicloud.com,ADMcgh+
- DOMAIN-SUFFIX,hongxiu.com,ADMcgh+
- DOMAIN-SUFFIX,hostbuf.com,ADMcgh+
- DOMAIN-SUFFIX,huxiucdn.com,ADMcgh+
- DOMAIN-SUFFIX,huya.com,ADMcgh+
- DOMAIN-SUFFIX,infinitynewtab.com,ADMcgh+
- DOMAIN-SUFFIX,ithome.com,ADMcgh+
- DOMAIN-SUFFIX,java.com,ADMcgh+
- DOMAIN-SUFFIX,jidian.im,ADMcgh+
- DOMAIN-SUFFIX,kaiyanapp.com,ADMcgh+
- DOMAIN-SUFFIX,kaspersky-labs.com,ADMcgh+
- DOMAIN-SUFFIX,keepcdn.com,ADMcgh+
- DOMAIN-SUFFIX,kkmh.com,ADMcgh+
- DOMAIN-SUFFIX,licdn.com,ADMcgh+
- DOMAIN-SUFFIX,linkedin.com,ADMcgh+
- DOMAIN-SUFFIX,loli.net,ADMcgh+
- DOMAIN-SUFFIX,luojilab.com,ADMcgh+
- DOMAIN-SUFFIX,maoyan.com,ADMcgh+
- DOMAIN-SUFFIX,maoyun.tv,ADMcgh+
- DOMAIN-SUFFIX,meituan.com,ADMcgh+
- DOMAIN-SUFFIX,meituan.net,ADMcgh+
- DOMAIN-SUFFIX,mobike.com,ADMcgh+
- DOMAIN-SUFFIX,moke.com,ADMcgh+
- DOMAIN-SUFFIX,mubu.com,ADMcgh+
- DOMAIN-SUFFIX,myzaker.com,ADMcgh+
- DOMAIN-SUFFIX,nim-lang-cn.org,ADMcgh+
- DOMAIN-SUFFIX,nvidia.com,ADMcgh+
- DOMAIN-SUFFIX,oracle.com,ADMcgh+
- DOMAIN-SUFFIX,paypal.com,ADMcgh+
- DOMAIN-SUFFIX,paypalobjects.com,ADMcgh+
- DOMAIN-SUFFIX,qdaily.com,ADMcgh+
- DOMAIN-SUFFIX,qidian.com,ADMcgh+
- DOMAIN-SUFFIX,qyer.com,ADMcgh+
- DOMAIN-SUFFIX,qyerstatic.com,ADMcgh+
- DOMAIN-SUFFIX,raychase.net,ADMcgh+
- DOMAIN-SUFFIX,ronghub.com,ADMcgh+
- DOMAIN-SUFFIX,ruguoapp.com,ADMcgh+
- DOMAIN-SUFFIX,s-reader.com,ADMcgh+
- DOMAIN-SUFFIX,sankuai.com,ADMcgh+
- DOMAIN-SUFFIX,scomper.me,ADMcgh+
- DOMAIN-SUFFIX,seafile.com,ADMcgh+
- DOMAIN-SUFFIX,sm.ms,ADMcgh+
- DOMAIN-SUFFIX,smzdm.com,ADMcgh+
- DOMAIN-SUFFIX,snapdrop.net,ADMcgh+
- DOMAIN-SUFFIX,snwx.com,ADMcgh+
- DOMAIN-SUFFIX,sspai.com,ADMcgh+
- DOMAIN-SUFFIX,takungpao.com,ADMcgh+
- DOMAIN-SUFFIX,teamviewer.com,ADMcgh+
- DOMAIN-SUFFIX,tianyancha.com,ADMcgh+
- DOMAIN-SUFFIX,udacity.com,ADMcgh+
- DOMAIN-SUFFIX,uning.com,ADMcgh+
- DOMAIN-SUFFIX,vmware.com,ADMcgh+
- DOMAIN-SUFFIX,weather.com,ADMcgh+
- DOMAIN-SUFFIX,weico.cc,ADMcgh+
- DOMAIN-SUFFIX,weidian.com,ADMcgh+
- DOMAIN-SUFFIX,xiachufang.com,ADMcgh+
- DOMAIN-SUFFIX,ximalaya.com,ADMcgh+
- DOMAIN-SUFFIX,xinhuanet.com,ADMcgh+
- DOMAIN-SUFFIX,xmcdn.com,ADMcgh+
- DOMAIN-SUFFIX,yangkeduo.com,ADMcgh+
- DOMAIN-SUFFIX,zhangzishi.cc,ADMcgh+
- DOMAIN-SUFFIX,zhihu.com,ADMcgh+
- DOMAIN-SUFFIX,zhimg.com,ADMcgh+
- DOMAIN-SUFFIX,zhuihd.com,ADMcgh+
- DOMAIN,download.jetbrains.com,ADMcgh+
- DOMAIN,images-cn.ssl-images-amazon.com,ADMcgh+

# > ADMcgh+
- DOMAIN-SUFFIX,aaplimg.com,ADMcgh+
- DOMAIN-SUFFIX,apple.co,ADMcgh+
- DOMAIN-SUFFIX,apple.com,ADMcgh+
- DOMAIN-SUFFIX,apple-cloudkit.com,ADMcgh+
- DOMAIN-SUFFIX,appstore.com,ADMcgh+
- DOMAIN-SUFFIX,cdn-apple.com,ADMcgh+
- DOMAIN-SUFFIX,crashlytics.com,ADMcgh+
- DOMAIN-SUFFIX,icloud.com,ADMcgh+
- DOMAIN-SUFFIX,icloud-content.com,ADMcgh+
- DOMAIN-SUFFIX,me.com,ADMcgh+
- DOMAIN-SUFFIX,mzstatic.com,ADMcgh+
- DOMAIN,www-cdn.icloud.com.akadns.net,ADMcgh+
- DOMAIN,clash.razord.top,ADMcgh+
- DOMAIN,v2ex.com,ADMcgh+
- IP-CIDR,17.0.0.0/8,ADMcgh+,no-resolve

# Local Area Network
- IP-CIDR,192.168.0.0/16,ADMcgh+
- IP-CIDR,10.0.0.0/8,ADMcgh+
- IP-CIDR,172.16.0.0/12,ADMcgh+
- IP-CIDR,127.0.0.0/8,ADMcgh+
- IP-CIDR,100.64.0.0/10,ADMcgh+

# DNSPod Public DNS+
- IP-CIDR,119.28.28.28/32,ADMcgh+,no-resolve
# GeoIP China
- GEOIP,CN,ADMcgh+

- MATCH,ADMcgh+

proxies:
RULES
[[ $mode = 2 ]] && cat << GLOBAL >> /root/.config/clash/config.yaml 
proxies:
GLOBAL
[[ $mode = 3 ]] && cat << AUTO >> /root/.config/clash/config.yaml 
# FIN SELECTOR BASE
  url: http://www.gstatic.com/generate_204
  interval: 300
  
# GRUPO DE LISTAS PROXY

- name: "⚡ AUTO 📶"
  type: fallback
  proxies: 
${_auto}

# Create for NAMEFILE  
  url: http://www.gstatic.com/generate_204
  interval: 300

- name: "NAMEFILE"
  type: select
  proxies: 
${_auto}

Rule:

- MATCH,ADMcgh+

proxies:
AUTO
}

conFIN() {
confRULE
[[ ! -z ${proTRO} ]] && echo -e "${proTRO}" >> /root/.config/clash/config.yaml
[[ ! -z ${proV2R} ]] && echo -e "${proV2R}" >> /root/.config/clash/config.yaml
[[ ! -z ${proXR} ]] && echo -e "${proXR}" >> /root/.config/clash/config.yaml

#echo ''

echo "#POWER BY @ChumoGH" >> /root/.config/clash/config.yaml
}

enon(){
		clear
		msg -bar3
		blanco " Se ha agregado un autoejecutor en el Sector de Inicios Rapidos"
		msg -bar3
		blanco "	  Para Acceder al menu Rapido \n	     Utilize * clash.sh * !!!"
		msg -bar3
		echo -e "		\033[4;31mNOTA importante\033[0m"
		echo -e " \033[0;31mSi deseas desabilitar esta opcion, apagala"
		echo -e " Y te recomiendo, no alterar nada en este menu, para"
		echo -e "             Evitar Errores Futuros"
		echo -e " y causar problemas en futuras instalaciones.\033[0m"
		msg -bar3
		continuar
		read foo
}
enoff(){
rm -f /bin/clash.sh
		msg -bar3
		echo -e "		\033[4;31mNOTA importante\033[0m"
		echo -e " \033[0;31mSe ha Desabilitado el menu Rapido de clash.sh"
		echo -e " Y te recomiendo, no alterar nada en este menu, para"
		echo -e "             Evitar Errores Futuros"
		echo -e " y causar problemas en futuras instalaciones.\033[0m"
		msg -bar3
		continuar
		read foo
}

enttrada () {
echo 'source <(curl -sSL https://raw.githubusercontent.com/ChumoGH/ScriptCGH/main/HTools/CLASH/ClashForAndroidGLOBAL.sh)' > /bin/clash.sh && chmod +x /bin/clash.sh
}

blanco(){
	[[ !  $2 = 0 ]] && {
		echo -e "\033[1;37m$1\033[0m"
	} || {
		echo -ne " \033[1;37m$1:\033[0m "
	}
}
title(){
	msg -bar3
	blanco "$1"
	msg -bar3
}
col(){
	nom=$(printf '%-55s' "\033[0;92m${1} \033[0;31m>> \033[1;37m${2}")
	echo -e "	$nom\033[0;31m${3}   \033[0;92m${4}\033[0m"
}
col2(){
	echo -e " \033[1;91m$1\033[0m \033[1;37m$2\033[0m"
}
vacio(){
blanco "\n no se puede ingresar campos vacios..."
}
cancelar(){
echo -e "\n \033[3;49;31minstalacion cancelada...\033[0m"
}
continuar(){
echo -e " \033[3;49;32mEnter para continuar...\033[0m"
}
userDat(){
	blanco "	NÂ°    Usuarios 		  fech exp   dias"
	msg -bar3
}
view_usert(){
configt="/usr/local/etc/trojan/config.json"
tempt="/etc/trojan/temp.json"
trojdirt="/etc/trojan" 
user_conf="/etc/trojan/user"
backdirt="/etc/trojan/back" 
tmpdirt="$backdir/tmp"
	unset seg
	seg=$(date +%s)
	while :
	do
	nick="$(cat $configt | grep ',"')"
	users="$(cat $configt | jq -r .password[])"
		title "	ESCOJE USUARIO TROJAN"
		userDat

		n=1
		for i in $users
		do
			unset DateExp
			unset seg_exp
			unset exp

			[[ $i = chumoghscript ]] && {
				Usr="Admin"
				DateExp=" Ilimitado"
			} || {
			Usr="$(cat ${user_conf}|grep -w "${i}"|cut -d'|' -f1)"
				DateExp="$(cat ${user_conf}|grep -w "${i}"|cut -d'|' -f3)"
				seg_exp=$(date +%s --date="$DateExp")
				exp="[$(($(($seg_exp - $seg)) / 86400))]"
			}
			col "$n)" "${Usr}" "$DateExp" "$exp"
			let n++
		done
		msg -bar3
		col "0)" "VOLVER"
		msg -bar3
		blanco "SELECCIONA USUARIO" 0
		read opcion
		[[ -z $opcion ]] && vacio && sleep 0.3s && continue
		[[ $opcion = 0 ]] && tropass="user_null" && break
		n=1
		unset i
		for i in $users
		do
		[[ $n = $opcion ]] && tropass=$i
			let n++
		done
		let opcion--
		addip=$(wget -qO- ifconfig.me)
		host=$(cat $configt | jq -r .ssl.sni)
		trojanport=$(cat $configt | jq -r .local_port)
		UUID=$(cat $configt | jq -r .password[$opcion])
		Usr="$(cat ${user_conf}|grep -w "${UUID}"|cut -d'|' -f1)"
		echo "USER ${Usr} : $UUID " 
		break
	done
}

view_user(){
config="/etc/v2ray/config.json"
temp="/etc/v2ray/temp.json"
v2rdir="/etc/v2r" && [[ ! -d $v2rdir ]] && mkdir $v2rdir
user_conf="/etc/v2r/user" && [[ ! -e $user_conf ]] && touch $user_conf
backdir="/etc/v2r/back" && [[ ! -d ${backdir} ]] && mkdir ${backdir}
tmpdir="$backdir/tmp"
	unset seg
	seg=$(date +%s)
	while :
	do
		users=$(cat $config | jq .inbounds[].settings.clients[] | jq -r .email)

		title "	VER USUARIO V2RAY REGISTRADO"
		userDat

		n=1
		for i in $users
		do
			unset DateExp
			unset seg_exp
			unset exp

			[[ $i = null ]] && {
				i="Admin"
				DateExp=" Ilimitado"
			} || {
				DateExp="$(cat ${user_conf}|grep -w "${i}"|cut -d'|' -f3)"
				seg_exp=$(date +%s --date="$DateExp")
				exp="[$(($(($seg_exp - $seg)) / 86400))]"
			}

			col "$n)" "$i" "$DateExp" "$exp"
			let n++
		done

		msg -bar3
		col "0)" "VOLVER"
		msg -bar3
		blanco "Escoje Tu Usuario : " 0
		read opcion
		[[ -z $opcion ]] && vacio && sleep 0.3s && continue
		[[ $opcion = 0 ]] && break
		let opcion--
		ps=$(jq .inbounds[].settings.clients[$opcion].email $config) && [[ $ps = null ]] && ps="default"
		uid=$(jq .inbounds[].settings.clients[$opcion].id $config)
		aluuiid=$(jq .inbounds[].settings.clients[$opcion].alterId $config)
		add=$(jq '.inbounds[].domain' $config) && [[ $add = null ]] && add=$(wget -qO- ipv4.icanhazip.com)
		host=$(jq '.inbounds[].streamSettings.wsSettings.headers.Host' $config) && [[ $host = null ]] && host=''
		net=$(jq '.inbounds[].streamSettings.network' $config)
		parche=$(jq -r .inbounds[].streamSettings.wsSettings.path $config) && [[ $path = null ]] && parche='' 
		v2port=$(jq '.inbounds[].port' $config)
		tls=$(jq '.inbounds[].streamSettings.security' $config)
		[[ $net = '"grpc"' ]] && path=$(jq '.inbounds[].streamSettings.grpcSettings.serviceName'  $config) || path=$(jq '.inbounds[].streamSettings.wsSettings.path' $config)
		addip=$(wget -qO- ifconfig.me)
		echo "Usuario $ps Seleccionado" 
		break
	done
}

_view_userXR(){
config="/etc/xray/config.json"
temp="/etc/xray/temp.json"
v2rdir="/etc/xr" && [[ ! -d $v2rdir ]] && mkdir $v2rdir
user_conf="/etc/xr/user" && [[ ! -e $user_conf ]] && touch $user_conf
backdir="/etc/xr/back" && [[ ! -d ${backdir} ]] && mkdir ${backdir}
tmpdir="$backdir/tmp"
	unset seg
	seg=$(date +%s)
	while :
	do
		users=$(cat $config | jq .inbounds[].settings.clients[] | jq -r .email)

		title "	VER USUARIO XRAY REGISTRADO"
		userDat

		n=1
		for i in $users
		do
			unset DateExp
			unset seg_exp
			unset exp

			[[ $i = null ]] && {
				i="Admin"
				DateExp=" Ilimitado"
			} || {
				DateExp="$(cat ${user_conf}|grep -w "${i}"|cut -d'|' -f3)"
				seg_exp=$(date +%s --date="$DateExp")
				exp="[$(($(($seg_exp - $seg)) / 86400))]"
			}

			col "$n)" "$i" "$DateExp" "$exp"
			let n++
		done

		msg -bar3
		col "0)" "VOLVER"
		msg -bar3
		blanco "Escoje Tu Usuario : " 0
		read opcion
		[[ -z $opcion ]] && vacio && sleep 0.3s && continue
		[[ $opcion = 0 ]] && break
		let opcion--
		psX=$(jq .inbounds[].settings.clients[$opcion].email $config) && [[ $psX = null ]] && ps="default"
		uidX=$(jq .inbounds[].settings.clients[$opcion].id $config)
		aluuiidX=$(jq .inbounds[].settings.clients[$opcion].alterId $config)
		addX=$(jq '.inbounds[].domain' $config) && [[ $addX = null ]] && add=$(wget -qO- ipv4.icanhazip.com)
		hostX=$(jq '.inbounds[].streamSettings.wsSettings.headers.Host' $config) && [[ $hostX = null ]] && hostX=''
		netX=$(jq '.inbounds[].streamSettings.network' $config)
		parcheX=$(jq -r .inbounds[].streamSettings.wsSettings.path $config) && [[ $pathX = null ]] && parcheX='' 
		v2portX=$(jq '.inbounds[].port' $config)
		tlsX=$(jq '.inbounds[].streamSettings.security' $config)
		[[ $netX = '"grpc"' ]] && pathX=$(jq '.inbounds[].streamSettings.grpcSettings.serviceName'  $config) || pathX=$(jq '.inbounds[].streamSettings.wsSettings.path' $config)
		addipX=$(wget -qO- ifconfig.me)
		echo "Usuario XRAY SERA  $psX Seleccionado" 
		break
	done
}

[[ ! -d /root/.config/clash ]] && fun_insta || fun_ip
clear
tittle
fileon=$(ls -la /var/www/html | grep "yaml" | wc -l)
filelo=$(ls -la /root/.config/clash | grep "yaml" | wc -l)
cd
echo -e "\033[1;37m ${TTcent}  Linux Dist: $(less /etc/issue.net)\033[0m"
msg -bar3
echo -e "\033[1;37m ${TTcent} Ficheros Online:	$fileon  ${TTcent} Ficheros Locales: $filelo\033[0m"
msg -bar3
echo -e "\033[1;37m - Menu Iterativo Clash for Android - ChumoGH \033[0m"
msg -bar3
echo -e "\033[1;37m Para Salir Ctrl + C o N Para SALIR\033[1;33m"
unset yesno
msg -bar3
echo -e " DESEAS CONTINUAR CON LA CARGA DE CONFIG CLASH?"
msg -bar3
while [[ ${yesno} != @(s|S|y|Y|n|N) ]]; do
read -p "[S/N]: " yesno
tput cuu1 && tput dl1
done
if [[ ${yesno} = @(s|S|y|Y) ]]; then
unset yesno numwt
#[[ -e /root/name ]] && figlet -p -f slant < /root/name || echo -e "\033[7;49;35m    =====>>â–ºâ–º ðŸ² New ChumoGHðŸ’¥VPS ðŸ² â—„â—„<<=====      \033[0m"
#echo -e "[\033[1;31m-\033[1;33m]\033[1;31m \033[1;33m"
#echo -e "\033[1;33m ${TTcent} Ingresa tu Whatsapp junto a tu codigo de Pais"
#read -p " Ejemplo: +593987072611 : " numwt
#if [[ -z $numwt ]]; then
#numwt='+593987072611'
#fi
clear&&clear
msg -bar3
print_center -verd '  \e[97m\033[1;41m NOMBRE DE FICHERO WEB FILE\033[0m' 
msg -bar3
print_center -verm2 ' Este nombre saldra como SELECTOR \n en la APP Clash For Android (META) \n Recuerda no colocar Espacios, ya que \n tambien sera el nombre del fichero WEB'
msg -bar3
echo -ne "[\033[1;31m${TTcent}\033[1;33m]\033[1;31m \033[1;33m"
echo -e "\033[1;33mINGRESA NOMBRE DEL FICHERO ( UsuarioXYZ ) "
msg -bar3
read -p " Ejemplo: ChumoGH : " srvip
[[ -z $srvip ]] && srvip='NewADM'
	while :
	do
	[[ -z ${opcion} ]] || break
		clear
		msg -bar3
		print_center -verd  " ESCOJE TU METODO DE SELECCION "
		msg -bar3
		print_center -verm2 ' Este es e tipo de SELECTOR que saldra \n en la APP Clash For Android (META) \n El comun es RULES, pero si presentas BUGs \n ESCOJE LA OPCION 2'
		msg -bar3
		echo -e "  "
		echo -e " SINO CONOCES DE ESTO, ESCOJE 2 "
		echo -e "  "
		msg -bar3
		echo -e "\033[0;35m [${cor[2]}01\033[0;35m]\033[0;33m ${flech}${cor[3]} SELECTOR RULES         \033[0;31m[ $(msg -verm2 'On Bugs') \033[0;31m]" 
		echo -e "\033[0;35m [${cor[2]}02\033[0;35m]\033[0;33m ${flech}${cor[3]} SELECTOR GLOBAL        \033[0;31m[ $(msg -verd 'NO Bugs') \033[0;31m]" 
		echo -e "\033[0;35m [${cor[2]}03\033[0;35m]\033[0;33m ${flech}${cor[3]} SELECTOR AUTOMATICO    \033[0;31m[ $(msg -verd 'NO Bugs') \033[0;31m]" 
		msg -bar3
		echo -ne "$(msg -verd "  [0]") $(msg -verm2 "=>>") " && msg -bra "\033[1;41m SALIR "
		msg -bar3
		read -p " ESCOJE : " opcion
		case $opcion in
			1)configINIT_rule "$opcion"
			break;;
			2)configINIT_global "$opcion"
			break;;
			3)configINIT_auto "${opcion}"
			break;;
			0) break;;
			*) echo -e "\n selecione una opcion del 0 al 2" && sleep 0.3s;;
		esac
	done
INITClash
fi
