#!/bin/bash
#Autor: Henry Chumo 
#Alias : ChumoGH
[[ -e /bin/ejecutar/msg ]] && source /bin/ejecutar/msg || source <(curl -sSL https://raw.githubusercontent.com/ChumoGH/ChumoGH-Script/master/msg-bar/msg)
clear

function install(){
    if [ ! -f "$HOME/.nami/bin/nami" ] || [ ! -f "$HOME/.nami/bin/joker" ] || [ ! -f "$HOME/.nami/bin/brook" ] || [ ! -f "$HOME/.nami/bin/jinbe" ] || [ `echo $PATH | grep $HOME/.nami/bin | wc -l` -eq 0 ];then
        echo
        echo -e "$PC"'>>> bash <(curl https://bash.ooo/nami.sh)'"$NC"
        os=""
        arch=""
        if [ $(uname -s) = "Darwin" ]; then
            os="darwin"
        fi
        if [ $(uname -s) = "Linux" ]; then
            os="linux"
        fi
        if [ $(uname -s | grep "MINGW" | wc -l) -eq 1 ]; then
            os="windows"
        fi
        if [ $(uname -m) = "x86_64" ]; then
            arch="amd64"
        fi
        if [ $(uname -m) = "arm64" ]; then
            arch="arm64"
        fi
        if [ $(uname -m) = "aarch64" ]; then
            arch="arm64"
        fi
        if [ "$os" = "" -o "$arch" = "" ]; then
            echo "Nami does not support your OS/ARCH yet. Please submit issue or PR to https://github.com/txthinking/nami"
            exit
        fi
        sfx=""
        if [ $os = "windows" ]; then
            sfx=".exe"
        fi
        mkdir -p $HOME/.nami/bin
        curl -L -o $HOME/.nami/bin/nami$sfx "https://github.com/txthinking/nami/releases/latest/download/nami_${os}_${arch}$sfx"
        chmod +x $HOME/.nami/bin/nami
        echo 'export PATH=$HOME/.nami/bin:$PATH' >> $HOME/.bashrc
        echo 'export PATH=$HOME/.nami/bin:$PATH' >> $HOME/.bash_profile
        echo 'export PATH=$HOME/.nami/bin:$PATH' >> $HOME/.zshenv
        export PATH=$HOME/.nami/bin:$PATH
        echo
        echo -e "$PC"'>>> nami install joker brook jinbe'"$NC"
        nami install brook joker jinbe mad 
        restartsh="todo"
    fi
}

[[ ! -d $HOME/.nami/bin ]] && install

function installbrook () {
nami install brook 
nami install mad 
}

function aguarde() {
	sleep 1
	helice() {
		installbrook >/dev/null 2>&1 &
		tput civis
		while [ -d /proc/$! ]; do
			for i in / - \\ \|; do
				sleep .1
				echo -ne "\e[1D$i"
			done
		done
		tput cnorm
	}
	echo -ne "  \033[1;37mINSTALANDO \033[1;32mNAMI \033[1;37m& \033[1;32mBROOK JOKER\033[1;32m.\033[1;33m.\033[1;31m. \033[1;33m"
	helice
	echo -e "\e[1DDONE"
}

aguarde
killall brook 1> /dev/null 2> /dev/null
cd /bin/ejecutar/
rm /bin/ejecutar/WSSBrook.log 1> /dev/null 2> /dev/null
clear&&clear
msg -bar3
echo -e "\e[91m\e[43m  ==== SCRIPT MOD PLUS|ChumoGH|EDICION ====  \033[0m \033[0;33m[$v2]"
msg -bar3
echo -e "${cor[5]} 🍄  INSTALACION DE BROOK SERVER 🍄 "
msg -bar3 
echo -e "\033[1;31m - Configuracion de Servidor Brook -"
echo ""
echo " ANTES DE CONTINUAR DEBES TENER LIBRE EL PUERTO 443 " 
echo "         CASO CONTRARIO REGRESA AL MENU  " 
echo ""
echo -e " "
echo -e "[\033[1;31m-\033[1;33m]\033[1;31m \033[1;33m"
read -p "$(echo -e "\033[1;33m脦鈥?? ABREVIATURA DE SERVIDOR ( WTS|FB )")" srvip
tput cuu1 >&2 && tput dl1 >&2
[[ -z $srvip ]] && srvip='' || srvip="+${srvip}"
read -p "$(echo -e "\033[1;34m INGRESA TU DOMINIO ( admin.chumogh.com ) :")" domain
tput cuu1 >&2 && tput dl1 >&2
[[ -z $domain ]] && domain=$(wget -qO- ifconfig.me)
read -p "$(echo -e "\033[1;34m INGRESA PUERTO DEL SERVICIO ( 9999 ) :")" puerto
tput cuu1 >&2 && tput dl1 >&2
read -p "$(echo -e "\033[1;34m INGRESA CLAVE O PASSWD ( tuclave ) :")" password
password="$(echo $password|sed 'y/áÁàÀãÃâÂéÉêÊíÍóÓõÕôÔúÚñÑçÇªº/aAaAaAaAeEeEiIoOoOoOuUnNcCao/')" && password="$(echo $password|sed -e 's/[^a-z0-9 -]//ig')"
tput cuu1 >&2 && tput dl1 >&2
read -p "$(echo -e "\033[1;34m INGRESA TU HOST SNI ( whatsapp.net ) :")" sni
sni="$(echo $sni|sed 'y/áÁàÀãÃâÂéÉêÊíÍóÓõÕôÔúÚñÑçÇªº/aAaAaAaAeEeEiIoOoOoOuUnNcCao/')"
tput cuu1 >&2 && tput dl1 >&2
fun_hb () {
echo -e " -> INICIANDO CONFIGURACION " | pv -qL 40
msg -bar
echo -e " -> DOMINIO : $domain" 
echo -e " -> PUERTO : $puerto" 
echo -e " -> CONTRASEÑA : $password" 
echo -e " -> HOST/SNI : $sni" 
echo -ne " HABILITANDO CONFIGURACION DEL WSS BROOK -> " | pv -qL 30
}
echo -e "[\033[1;31m-\033[1;33m]\033[1;31m ───────────────────────────────────────\033[1;33m"
echo -e "\033[1;31m - Creando Certificados -\033[0m"
mad ca --ca ./ca.pem --key ./ca_key.pem
mad cert --ca ./ca.pem --ca_key ./ca_key.pem --cert ./sni_cert.crt --key ./sni_key.key --domain $sni
echo -e "[\033[1;31m-\033[1;33m]\033[1;31m ───────────────────────────────────────\033[1;33m"
echo -e "\033[1;31m - Iniciando servidor en puerto:\033[1;32m $puerto\033[0m"
fun_hb
sleep 2
screen -dmS brok brook wssserver --domainaddress $sni:$puerto --password $password --cert /bin/ejecutar/sni_cert.crt --certkey /bin/ejecutar/sni_key.key && echo -e "\033[0;31m[\033[0;32mEXITOSAMENTE\033[0;31m]" || echo -e "\033[1;31m[FALLIDA]" 
brooklink=`brook link --server wss://$sni:443 --password $password --address $domain:$puerto --insecure --name '𝘾𝙝𝙪𝙢𝙤𝙂𝙃|𝙋𝙇𝙐𝙎${srvip}'`
brook link --server wss://$sni:443 --password $password --address $domain:$puerto --insecure --name '𝘾𝙝𝙪𝙢𝙤𝙂𝙃|𝙋𝙇𝙐𝙎${srvip}' >> /bin/ejecutar/WSSBrook.log
echo -e "\033[1;33m → Enlace Generado del Servidor Brook:\033[1;32m"
msg -bar3
echo -e " "
echo -e " $brooklink"
echo -e " "
msg -bar3
echo -e "\033[1;33mEl Enlace ha sido guardado en\033[1;32m /bin/ejecutar/WSSBrook.log"
echo -e "  ENLACE DE APP BROOK OFICIAL: https://github.com/txthinking/brook/releases"
echo -e "\033[1;33mPara ver nuevamente tu enlace, sal del script y teclea:\033[1;31m cat /bin/ejecutar/WSSBrook.log"
echo -e "[\033[1;31m-\033[1;33m]\033[1;31m ───────────────────────────────────────\033[1;33m"
return 0
