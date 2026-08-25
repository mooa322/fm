#!/bin/sh
#Autor: Henry Chumo 
#Alias : ChumoGH
config="/etc/v2ray/config.json"
temp="/etc/v2ray/temp.json"
v2rdir="/etc/v2r" && [[ ! -d $v2rdir ]] && mkdir $v2rdir
user_conf="/etc/v2r/user" && [[ ! -e $user_conf ]] && touch $user_conf
backdir="/etc/v2r/back" && [[ ! -d ${backdir} ]] && mkdir ${backdir}
tmpdir="$backdir/tmp"
[[ ! -e $v2rdir/conf ]] && echo "autBackup 0" > $v2rdir/conf
if [[ $(cat $v2rdir/conf | grep "autBackup") = "" ]]; then
	echo "autBackup 0" >> $v2rdir/conf
fi
barra="\033[0;31m=====================================================\033[0m"
numero='^[0-9]+$'
hora=$(printf '%(%H:%M:%S)T') 
fecha=$(printf '%(%D)T')

 
on_off_res(){
	if [[ $(cat $v2rdir/conf | grep "autBackup" | cut -d " " -f2) = "0" ]]; then
		echo -e "\033[0;31m[off]"
	else
		echo -e "\033[1;92m[on]"
	fi
 }

blanco(){
	[[ !  $2 = 0 ]] && {
		echo -e "\033[1;37m$1\033[0m"
	} || {
		echo -ne " \033[1;37m$1:\033[0m "
	}
}

verde(){
	[[ !  $2 = 0 ]] && {
		echo -e "\033[1;32m$1\033[0m"
	} || {
		echo -ne " \033[1;32m$1:\033[0m "
	}
}

rojo(){
	[[ !  $2 = 0 ]] && {
		echo -e "\033[1;31m$1\033[0m"
	} || {
		echo -ne " \033[1;31m$1:\033[0m "
	}
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

title2(){
	v1=$(cat /etc/adm-lite/v-local.log)
	v2=$(cat /bin/ejecutar/v-new.log)
	echo -e $barra
	[[ $v1 = $v2 ]] && echo -e "   \e[97m\033[1;41m V2ray by @Rufu99 Remasterizado @ChumoGH [$v1] \033[0m" || echo -e " \e[97m\033[1;41m V2ray by @Rufu99 Remasterizado @ChumoGH [$v1] >> \033[1;92m[$v2] \033[0m"
}

title(){
	echo -e $barra
	blanco "$1"
	echo -e $barra
}

userDat(){
	blanco "	N°    Usuarios 		  fech exp   dias"
	echo -e $barra
}


restart_v2r(){
	v2ray restart
	#echo "reiniciando"
}

add_user(){
	users="$(cat $config | jq -r .inbounds[].settings.clients[].email)"
	opcion=$name
	dias=$tdias
	espacios=$(echo "$opcion" | tr -d '[[:space:]]')
	opcion=$espacios
	mv $config $temp
	num=$(jq '.inbounds[].settings.clients | length' $temp)
	new=".inbounds[].settings.clients[$num]"
	new_id=$(uuidgen)
	new_mail="email:\"$opcion\""
	aid=$(jq '.inbounds[].settings.clients[0].alterId' $temp)
	echo jq \'$new += \{alterId:${aid},id:\"$new_id\","$new_mail"\}\' $temp \> $config | bash
	echo "$opcion | $new_id | $(date '+%y-%m-%d' -d " +$dias days")" >> $user_conf
	chmod 777 $config
	rm $temp
	restart_v2r
	view_user $opcion
	}


view_user(){
[[ ! -d /bin/ejecutar ]] && mkdir /bin/ejecutar
name=$1
	unset seg
	seg=$(date +%s)
	while :
	do
		users=$(cat $config | jq .inbounds[].settings.clients[] | jq -r .email)
		n=1
		for i in $users
		do
			unset DateExp
			unset seg_exp
			unset exp
			[[ $name = "$i" ]] && escopt="$n"
			let n++
		done
		opcion=$escopt
		let opcion--
		[[ -z ${IP} ]] && IP=$(cat < /bin/ejecutar/IPcgh)
		ps=$(jq .inbounds[].settings.clients[$opcion].email $config) && [[ $ps = null ]] && ps="default"
		tput cuu1 >&2 && tput dl1 >&2
		tput cuu1 >&2 && tput dl1 >&2
		blanco $barra
		blanco "              VMESS LINK CONFIG"
		blanco $barra
		vmess ${opcion}
		blanco $barra
		[[ -e /bin/ejecutar/${name}_vmess_qr.png ]] && {
		mv /bin/ejecutar/${name}_vmess_qr.png /var/www/html/${name}_vmess_qr.png 
		echo -e "QR Code : http://$(${IP}):81/${name}_vmess_qr.png "
		} || echo -e "ERROR AL CREAR QR"
		blanco $barra
		break
	done
}

 vmess(){
 local _pid=$1
 local protocol="$(cat $config | jq -r .inbounds[].protocol)"
 [[ ${_pid} = 0 ]] && return
#[[ $net = '"grpc"' ]] && echo -e "\033[3;32mvmess://$(echo {\"v\": \"2\", \"ps\": $ps, \"add\": $addip, \"port\": $port, \"aid\": $aid, \"type\": \"none\", \"net\": $net, \"path\": $path, \"host\": $host, \"id\": $id, \"tls\": $tls} | base64 -w 0)\033[3;32m" || {
#[[ $net = '"ws"' ]] && echo -e "\033[3;32mvmess://$(echo {\"v\": \"2\", \"ps\": $ps, \"add\": $addip, \"port\": $port, \"aid\": $aid, \"type\": \"gun\", \"net\": $net, \"path\": $path, \"host\": $host, \"id\": $id, \"tls\": $tls} | base64 -w 0)\033[3;32m"	
 	ps=$(jq -r .inbounds[].settings.clients[$1].email $config) && [[ $ps = null ]] && ps="default"
	[[ -z ${IP} ]] && IP=$(cat < /bin/ejecutar/IPcgh)
	[[ -z ${IP} ]] && IP=$(curl -sSL ifconfig.me)
	local id=$(jq -r .inbounds[].settings.clients[$1].id $config)
	local aid=$(jq .inbounds[].settings.clients[$1].alterId $config)
	local add=$(jq -r .inbounds[].domain $config) && [[ $add = null ]] && add=$(cat < /bin/ejecutar/IPcgh)
	local host=$(jq -r .inbounds[].streamSettings.wsSettings.headers.Host $config) && [[ $host = null ]] && host='tu.sni.aqui'
	local net=$(jq -r .inbounds[].streamSettings.network $config)
	local port=$(jq .inbounds[].port $config)
	local tls=$(jq -r .inbounds[].streamSettings.security $config)
	local cryp=$(jq -r .inbounds[].settings.decryption $config)
	if [[ $net == "grpc" ]]; then
	local hType='gun'
	local path=$(jq -r '.inbounds[].streamSettings.grpcSettings.serviceName'  $config) 
	else
	local path=$(jq -r '.inbounds[].streamSettings.wsSettings.path' $config)
	local hType='none'
	fi
	#path=$(jq -r .inbounds[].streamSettings.wsSettings.path $config) && [[ $path = null ]] && path=''

	[[ ${protocol} = "vless" ]] && col2 "Encryption:" "$cryp"
	[[ ! $host = '' ]] && col2 "Host/SNI:" "$host"
	col2 "Head Type:" "$hType"
	#[[ ! $path = '' ]] && col2 "Path:" "$path"
	[[ $net == "grpc" ]] && col2 "ServiceName:" "$path" || col2 "Path:" "$path"
	msg -bar3
	[[ ${protocol} = "vless" ]] && {
	local var="${id}@${add}:${port}?encryption=${cryp}&security=${tls}&type=${net}&serviceName=${path}&mode=${hType}&sni=null#${ps}%3A${port}"
	msg -ama "${protocol}://$(echo "$var")"
	echo -e "${protocol}://$(echo "$var")" > /bin/ejecutar/${ps}_vmess.txt
	} || {
	local var="{\"v\":\"2\",\"ps\":\"$ps\",\"add\":\"$IP\",\"port\":$port,\"aid\":$aid,\"type\":\"$hType\",\"net\":\"$net\",\"path\":\"$path\",\"host\":\"$host\",\"id\":\"$id\",\"tls\":\"$tls\"}"
	msg -ama "${protocol}://$(echo "$var"|jq -r '.|@base64')"
	echo -e "${protocol}://$(echo "$var"|jq -r '.|@base64')" > /bin/ejecutar/${ps}_vmess.txt
	}
 }

[[ $1 = "" && $2 = "" ]] && {
	echo -e "PARAMETRO NOMBRE Y DIAS NO DEFINIDOS"
	exit
} || {
	name="$1"
	tdias="$2"
	add_user
	return 0
}
