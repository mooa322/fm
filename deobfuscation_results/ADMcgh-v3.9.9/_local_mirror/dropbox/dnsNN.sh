#!/bin/bash

source <(curl -sL https://raw.githubusercontent.com/ChumoGH/ChumoGH-Script/master/msg-bar/msg)

dnsnetflix () {
cp /etc/resolv.conf /bin/ejecutar/resolv.conf
echo "$dnsp" >> /etc/resolv.conf
echo "$dnsp2" >> /etc/resolv.conf
#apt-get install resolvconf -y > /dev/null 2>&1
msg -bar2
#echo "$dnsp" >> /etc/resolvconf/resolv.conf.d/tail
#echo "$dnsp2" >> /etc/resolvconf/resolv.conf.d/tail
echo -e "${cor[4]}  DNS AGREGADOS CON EXITO"
echo -e "${cor[4]}  Reiniciando SYSTEM RESOLVED"
systemd-resolve --flush-caches
sudo systemctl restart systemd-resolved.service
cat /etc/resolv.conf | grep "nameserver"
sleep 2s
} 
clear
msg -bar2
echo -e "\033[1;93m     AGREGARDOR DE DNS PERSONALES "
msg -bar2
echo -e "\033[1;39m Esta funcion para que puedas ver Netflix con tu VPS"
msg -bar2
echo -e "\033[1;91m ¡ SOLO INGRESA LA IP DEL DNS O SERVIDOR CON SOPORTE"
echo -e "\033[1;39m         Instalara el DNS funcional para Netflix"
msg -bar2
echo -e "\033[1;93m Recuerde escojer entre 1 DNS \n       Que sea Valido ."
echo ""
read -p "Ingrese su DNS a usar: " dnsp
[ -z "$dnsp" ] && dnsp="" ||  dnsp="nameserver $dnsp"
echo ""
read -p "Ingrese su 2 DNS a usar: " dnsp2
[ -z "$dnsp2" ] && dnsp2="" ||  dnsp2="nameserver $dnsp2"
msg -bar2
read -p " Estas seguro de a?adir DNS?  [ S|s|N|n ]: " dd   
[[ "$dd" = "s" || "$dd" = "S" ]] && dnsnetflix
msg -bar2
