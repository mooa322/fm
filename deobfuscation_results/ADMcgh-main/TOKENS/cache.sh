#!/bin/sh
#Autor: Henry Chumo 
#Alias : ChumoGH
## 1 - "LIMPEZA DE DNS"
ip -s -s neigh flush all &> /dev/null
#sysctl -w net.ipv6.conf.all.disable_ipv6=1 &> /dev/null
#sysctl -w net.ipv6.conf.default.disable_ipv6=1 &> /dev/null
#sysctl -w net.ipv6.conf.lo.disable_ipv6=1 &> /dev/null
#sysctl -w net.ipv6.conf.all.autoconf=0 &> /dev/null
#sysctl -w net.ipv6.conf.all.accept_ra=0 &> /dev/null
ip neigh flush dev $(ip route | grep default | awk '{print $5}' | head -1) &> /dev/null
## 2 - "CACHE DO SISTEMA"
echo 3 > /proc/sys/vm/drop_caches &> /dev/null
## 2 - "LIMPAR LOGS"
echo > /var/log/messages
echo > /var/log/kern.log
echo > /var/log/daemon.log
echo > /var/log/kern.log
echo > /var/log/dpkg.log
echo > /var/log/syslog
#echo > /var/log/auth.log
swapoff -a && swapon -a &> /dev/null
killall kswapd0 &> /dev/null
[[ $1 = '--free' ]] && {
echo $(free -h | grep Mem | sed 's/\s\+/,/g' | cut -d , -f4) > /bin/ejecutar/raml
wget -O /bin/ejecutar/v-new.log https://raw.githubusercontent.com/ChumoGH/ADMcgh/main/TOKENS/v-new.log &>/dev/null
}
