#!/bin/bash

_Key='/etc/cghkey'
[[ $(dpkg --get-selections|grep -w "apache2"|head -1) ]] && apt purge apache2 -y &>/dev/null
clear
_SFTP="$(lsof -V -i tcp -P -n | grep -v "ESTABLISHED" |grep -v "COMMAND" | grep "LISTEN" | grep apache2)"
[[ -z ${_SFTP} ]] && _SFTP="$(lsof -V -i tcp -P -n | grep -v "ESTABLISHED" |grep -v "COMMAND" | grep "LISTEN" | grep nginx)"
portFTP=$(echo -e "$_SFTP" |cut -d: -f2 | cut -d' ' -f1 | uniq)
portFTP=$(echo ${portFTP} | sed 's/\s\+/,/g' | cut -d , -f1)

[[ ! -e ${_Key} ]] && exit 

[[ -e /bin/ejecutar/autt ]] || exit
dir_user="/userDIR"
dir="/etc/adm-lite"
name=$(cat < /bin/ejecutar/autt)

bc="$HOME/$name"
arquivo_move="$name"
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
}



removeonline(){
i=1
    [[ -d /var/www/html ]] && [[ -e /var/www/html/$arquivo_move ]] && rm -rf /var/www/html/$arquivo_move > /dev/null 2>&1
    [[ -e /var/www/$arquivo_move ]] && rm -rf /var/www/$arquivo_move > /dev/null 2>&1
    echo -e "${cor[5]}Extraxion Exitosa Exitosa"
    echo -e "$barra"
echo "SUBIENDO"
subironline
}   
subironline(){
[ ! -d /var ] && mkdir /var
[ ! -d /var/www ] && mkdir /var/www
[ ! -d /var/www/html ] && mkdir /var/www/html
[ ! -e /var/www/html/index.html ] && touch /var/www/html/index.html
[ ! -e /var/www/index.html ] && touch /var/www/index.html
chmod -R 755 /var/www
cp $HOME/$arquivo_move /var/www/$arquivo_move
cp $HOME/$arquivo_move /var/www/html/$arquivo_move
#portFTP=$(lsof -V -i tcp -P -n | grep apache2 | grep -v "ESTABLISHED" |grep -v "COMMAND" | grep "LISTEN" | cut -d: -f2 | cut -d' ' -f1 | uniq)
local portFTP=$(echo -e "$_SFTP" |cut -d: -f2 | cut -d' ' -f1 | uniq)
local portFTP=$(echo ${portFTP} | sed 's/\s\+/,/g' | cut -d , -f1)
#_pFTP="$(lsof -V -i tcp -P -n | grep -v "ESTABLISHED" |grep -v "COMMAND" | grep "LISTEN" | grep apache2 | cut -d " " -f1 | uniq)"
[[ -z ${_SFTP} ]] && echo -e "SERVICIO FTP NO ACTIVO " || {
echo -e "\033[1;36m http://$(cat /bin/ejecutar/IPcgh):${portFTP}/$arquivo_move\033[0m"
echo -e "$barra"
echo -e "${cor[5]}Carga Exitosa!"
echo -e "$barra"
}
}

function backup_de_usuarios(){
clear
i=1
[[ -e $bc ]] && rm $bc
echo -e "\033[1;37mHaciendo Backup de Usuarios...\033[0m"
[[ -e /bin/ejecutar/token ]] && passTK=$(cat < /bin/ejecutar/token)
#for user in `awk -F : '$3 > 900 { print $1 }' /etc/passwd |grep -v "nobody" |grep -vi polkitd |grep -vi systemd-[a-z] |grep -vi systemd-[0-9] |sort`
for user in `cat "/etc/passwd"|grep 'home'|grep 'false'|grep -v 'syslog' | cut -d: -f1 |sort`
do
[[ -e $dir$dir_user/$user ]] && {
####################VALIDACION DE SCRIPT#####################
pass="$(cat $dir$dir_user/$user | grep "senha" | awk '{print $2}')"
limite=$(cat $dir$dir_user/$user | grep "limite" | awk '{print $2}')
[[ $limite = @(HWID|TOKEN) ]] && NameTKID=${pass} || NameTKID=${pass}
data=$(cat $dir$dir_user/$user | grep "data" | awk '{print $2}')
data_sec=$(date +%s)
data_user=$(chage -l "$user" |grep -i co |awk -F ":" '{print $2}')
data_user_sec=$(date +%s --date="$data_user")
variavel_soma=$(($data_user_sec - $data_sec))
dias_use=$(($variavel_soma / 86400))
if [[ "$dias_use" -le 0 ]]; 
then
dias_use=0
fi
sl=$((dias_use + 1))
i=$((i + 1))
[[ -z "$limite" ]] && limite="5"
echo -e "\033[1;31m [ SCRIPT ] \033[1;37m "
####################VALIDACION DE SCRIPT#####################
} || {
####################VALIDACION DE PASSWD#####################
linea=$(cat /etc/passwd | grep -w ${user})
limite="$(cat /etc/passwd | grep -w ${user} | awk -F ':' '{split($5, a, ","); print a[1]}')"
if [[ "${linea}" =~ ,([^:]+): ]]; then
        NameTKID="${BASH_REMATCH[1]}"
fi
[[ -z "$limite" ]] && limite="5"
data_sec=$(date +%s)
data_user=$(chage -l "$user" |grep -i co |awk -F ":" '{print $2}')
data_user_sec=$(date +%s --date="$data_user")
variavel_soma=$(($data_user_sec - $data_sec))
dias_use=$(($variavel_soma / 86400))
[[ "$dias_use" -le 0 ]] && dias_use=0
sl=$((dias_use + 1))
i=$((i + 1))
echo -e "\033[1;31m [ SYSTEM ] \033[1;37m"
####################VALIDACION DE PASSWD#####################
}
[[ $(echo $limite) = "HWID" ]] && echo "$user:$user:HWID:$sl:$NameTKID" >> $bc && echo -e "\033[1;37mUser $NameTKID \033[0;35m [\033[0;36m$limite\033[0;35m]\033[0;31m Backup [\033[1;31mOK\033[1;37m] con $sl DIAS\033[0m"
[[ $(echo $limite) = "TOKEN" ]] && echo "$user:$passTK:TOKEN:$sl:$NameTKID" >> $bc && echo -e "\033[1;37mUser $NameTKID \033[0;35m [\033[0;36m$limite\033[0;35m]\033[0;31m Backup [\033[1;31mOK\033[1;37m] con $sl DIAS\033[0m"
[[ "$limite" =~ ^[0-9]+$ ]] && echo "$user:$NameTKID:$limite:$sl:$NameTKID" >> $bc && echo -e "\033[1;37mUser $user \033[0;35m [\033[0;36mSSH\033[0;35m]\033[0;31m Backup [\033[1;31mOK\033[1;37m] con $sl DIAS\033[0m"
#sleep .2s
done
echo " "
echo -e "\033[1;31mBackup Completado !!!\033[0m"
echo " "
echo -e "\033[1;37mLa informacion de los usuarios $i se encuentra en el archivo \033[1;31m $bc \033[1;37m"
}
backup_de_usuarios
[[ -z ${_SFTP} ]] && echo -e "SERVICIO FTP NO ACTIVO / REMOVIDO " || removeonline
rm $HOME/$arquivo_move