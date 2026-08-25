#!/bin/bash



telegran_bot () {
clear&&clear
cd /etc/adm-lite
#if [[ "$(ps x | grep "ultimatebot" | grep -v "grep")" = "" ]]; then
msg -bar3
echo -e " INGRESA TUS CREDENCIALES DE ACCESO AL BOT"
msg -bar3
[[ -e /bin/ejecutar/TKBot ]] && read -p " TELEGRAN BOT TOKEN: " -e -i "$(cat < /bin/ejecutar/TKBot)" tokenxx || read -p " TELEGRAN BOT TOKEN: " tokenxx
[[ -e ./bottokens ]] && read -p " TELEGRAN BOT LOGUIN: " -e -i "$(cat < ./bottokens| cut -d ':' -f1)" loguin || read -p " TELEGRAN BOT LOGUIN: " loguin
[[ -e ./bottokens ]] && read -p " TELEGRAN BOT PASS: " -e -i "$(cat < ./bottokens| cut -d ':' -f2)" pass || read -p " TELEGRAN BOT PASS: " pass
read -p " IDIOMA DEL BOT [ES]: " lang
[[ -z $lang ]] && lang="es"
msg -bar3
echo -e "${loguin}:${pass}" > ./bottokens
echo -e "${tokenxx}" > /bin/ejecutar/TKBot
echo > /bin/ejecutar/demos
#screen -dmS telebotusr bash ./ultimatebot "$tokenxx" "$lang" > /dev/null 2>&1
cat <<EOF > /etc/systemd/system/BotSSH.service
[Unit]
Description=BotGenSSH Service by @ChumoGH
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
User=root
WorkingDirectory=/etc/adm-lite
ExecStart=$(which bash) /etc/adm-lite/ultimatebot $tokenxx $lang
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF


systemctl daemon-reload &>/dev/null
systemctl enable BotSSH.service &>/dev/null 
sudo systemctl start BotSSH.service &>/dev/null 
echo -e " INICIANDO CONFIGURACION DEL BOT, ESPERE"
sleep .5
if [[ $(systemctl is-active BotSSH) = "active" ]]; then
echo -e "${tokenxx}" > /bin/ejecutar/TKBot
print_center -verd " Bot Telegram SSH Control INICIADO !!!" 
#print_center -verd "CTL Con Exito!!!"       
msg -bar3   
#[[ $(ps x | grep "ultimatebot" | grep -v "grep" | awk '{print $1}') ]] && {
#echo -e "${tokenxx}" > /bin/ejecutar/TKBot
#echo -e " \033[0;32mBot Telegram SSH Control INICIADO !!!" 
#screen -dmS telebotusr bash ./ultimatebot "$tokenxx" "$lang"
#[[ $(grep -wc "ultimatebot" /bin/autoboot) = '0' ]] && {
#			echo -e " REACTICADOR DE BotSSH ACTIVADO !! " && sleep 1s
#			tput cuu1 && tput dl1
#			echo -e "ps aux | grep 'ultimatebot' | grep -v 'grep' | awk '{print $1}' > /dev/null || { cd $(pwd) && screen -dmS telebotusr bash $(pwd)/ultimatebot $tokenxx $lang ; }" >>/bin/autoboot
#			} || {
#			sed -i '/ultimatebot/d' /bin/autoboot
#			echo -e " AUTOREINICIO EN INACTIVIDAD REACTIVADO !! " && sleep 1s
#			tput cuu1 && tput dl1
#			echo -e "ps aux | grep 'ultimatebot' | grep -v 'grep' | awk '{print $1}' > /dev/null || { cd $(pwd) && screen -dmS telebotusr bash $(pwd)/ultimatebot $tokenxx $lang ; }" >>/bin/autoboot
#}
msg -bar3
echo -e ""
echo -e " SE ENCONTRO LINEAS DE ACCESOS ANTIGUOS .."
echo -e " DESEAS REINICIARLOS??."
echo -ne "Esta SEGURO QUE DESEAS CONTINUAR ?:"
read -p " [S/N]: " -e -i n rac
[[ "$rac" = @(s|S|y|Y) ]] && {
rm -f /etc/adm-lite/liberados
echo -e " ESTADISTICAS Y ACCESOS REMOVIDOS!!!"
msg -bar3
}
echo -e " RECUERDA QUE EL PRIMER ACCESO ES SUPER ADMIN"
msg -bar3
echo -e " COLOCA TUS CREDENCIALES EN EL BOT HACI :"
echo -e "   "
echo -e "   /access $loguin $pass"
echo -e "   "
#echo -e "   /access $loguin $pass"
msg -bar3
else
print_center -verm " ERROR AL INICIAR EL BOT !!!" 
#print_center -verm "CTL No Activo!!!"       
msg -bar3 
fi
read -p " PRESIONA ENTER PARA CONTINUAR"
[[ ! -e /bin/ejecutar/token ]] && {
clear&&clear
msg -bar3
echo -e " NO POSEES UNA CLAVE TOKEN PARA APP'S"
echo -e " ESTA CLAVE ES ESCLUSIVA PARA APPS"
read -p " CONTRASEÑA TOKEN : " _tk
echo -e "${_tk}" > /bin/ejecutar/token
msg -bar3
read -p " PRESIONA ENTER PARA CONTINUAR"
}
cd $HOME
return 0
}

# Función para mostrar el menú
mostrar_menu() {
[[ -e /bin/ejecutar/notyadd ]] && _x="\033[0;31m[\033[0;32mON\033[0;31m]" || _x="\033[1;31m[OFF]"
msg -bar3
[[ $(ps x | grep -v grep | grep "ultimatebot") ]] && local _pid="\033[0;31m[\033[0;32mON\033[0;31m]" || local _pid="\033[1;31m[OFF]"
[[ -e /etc/systemd/system/BotWASSH.service ]] && local _wa="\033[0;31m[\033[0;32mON\033[0;31m]" || local _wa="\033[1;31m[OFF]"
tittle
msg -ama "         INSTALADOR BotSSH | @ChumoGH${p1t0}Plus"
msg -bar3
menu_func "$(msg -verd "INSTALAR BotSSH") ${_pid}" "$(msg -ama "Reiniciar BotSSH")" "ACTUALIZAR BINARIO" "Notificar CREADOS ${_x}" "Mostrar Creados Reseller" "Limitar Creadores" "$(msg -verm2 "DESINSTALAR BotSSH")" "$(msg -verd "INSTALAR BotSSH 🪀 WHATSAPP 🪀")" " REACTIVAR BOT WHASTAPP ( ${_wa} )"
msg -bar3
echo -ne "$(msg -verd "  [0]") $(msg -verm2 "=>>") " && msg -bra "\033[1;41m Volver "
msg -bar3
}

on_off_create(){

[[ -e /bin/ejecutar/notyadd ]] && rm -f /bin/ejecutar/notyadd || touch /bin/ejecutar/notyadd

}
bt_wts() {
    # --- Función interna para instalar Node 18 ---
    install_node_ver() {
        echo -e "🔍 Verificando versión de Node.js..."
        
        # Obtenemos la versión actual (si existe)
        local current_ver=$(node -v 2>/dev/null | grep -oE "v[0-9]+")

        if [[ "$current_ver" == "v18"* ]]; then
            echo -e "✅ Node.js v18 ya está instalado ($current_ver)."
            return 0
        fi

        echo -e "⚠️ Versión incorrecta o no detectada ($current_ver). Instalando Node 18..."
        
        # Limpieza de versiones viejas para evitar conflictos
        sudo apt-get remove -y nodejs npm &>/dev/null
        sudo apt-get purge -y nodejs &>/dev/null
        sudo rm -rf /etc/apt/sources.list.d/nodesource.list

        # Instalación del repo oficial
        curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
        sudo apt-get install -y nodejs
        
        # Verificación post-instalación
        local new_ver=$(node -v 2>/dev/null | grep -oE "v[0-9]+")
        if [[ "$new_ver" == "v18"* ]]; then
            echo -e "✅ Node.js 18 instalado correctamente."
            return 0
        else
            return 1
        fi
    }

    msg -bar3
    echo -e "Instalando dependencias del Sistema..."
    sudo apt-get update
    # Eliminé nodejs/npm de aquí para evitar conflictos con versiones viejas de repos base
    sudo apt-get install -y libgbm-dev wget unzip fontconfig locales gconf-service libasound2 libatk1.0-0 libc6 libcairo2 libcups2 libdbus-1-3 libexpat1 libfontconfig1 libgcc1 libgconf-2-4 libgdk-pixbuf2.0-0 libglib2.0-0 libgtk-3-0 libnspr4 libpango-1.0-0 libpangocairo-1.0-0 libstdc++6 libx11-6 libx11-xcb1 libxcb1 libxcomposite1 libxcursor1 libxdamage1 libxext6 libxfixes3 libxi6 libxrandr2 libxrender1 libxss1 libxtst6 ca-certificates fonts-liberation libappindicator1 libnss3 lsb-release xdg-utils git
    
    # Bucle de reintento para Node 18
    while true; do
        if install_node_ver; then
            break
        else
            msg -bar3
            echo -e "❌ ERROR CRÍTICO: NO SE PUDO INSTALAR NODE JS 18 AUTOMÁTICAMENTE"
            echo -e ""
            echo -e "Por favor, ejecuta estos comandos manualmente en otra terminal:"
            echo -e "-------------------------------------------------------"
            echo -e "1. sudo apt-get remove -y nodejs npm"
            echo -e "2. curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -"
            echo -e "3. sudo apt-get install -y nodejs"
            echo -e "-------------------------------------------------------"
            echo -e ""
            read -p "Presiona [ENTER] una vez que hayas instalado Node 18 manualmente para REINTENTAR..."
            echo -e "Reintentando verificación..."
        fi
    done

    msg -bar3
    echo -e "📂 Preparando directorio del Bot..."
    # Directorio de trabajo
    DIR="/etc/adm-lite/whabot"
    [[ ! -d "$DIR" ]] && mkdir -p "$DIR" || rm -rf "$DIR"/*
    cd "$DIR"

    echo -e "⬇️ Descargando archivos del Bot..."
    # Descarga Handler (Ojo con las comillas en URLs con query params)
    wget -q -O handler.sh "https://www.dropbox.com/scl/fi/lplq139set7g0rwnwf1zi/handler.sh?rlkey=2u8i05tiqxh32g0xb272zoydq" && chmod +x handler.sh
    
    # Descarga Script Files
    wget -q -O /tmp/files.tar.gz "https://www.dropbox.com/scl/fi/nvrvzp36exy6vxt522sk9/SCRIPT.tar.gz?rlkey=gqdvhcz51mu0j8xk6k0ynfru9"
    
    if [[ -e /tmp/files.tar.gz ]]; then
        tar -xzvf /tmp/files.tar.gz -C "$DIR" &> /dev/null
        echo -e "✅ ARCHIVOS EXTRAÍDOS EN $DIR"
    else
        echo -e "❌ ERROR: NO SE PUDO DESCARGAR EL ARCHIVO TAR.GZ"
        return 1
    fi

    echo -e "📦 Instalando módulos NPM (esto puede tardar)..."
    rm -rf auth_info_baileys node_modules package-lock.json
    npm install
    
    msg -bar3
    echo "✅ Instalación completa."
    echo ""
    echo "⚠️  ATENCIÓN: AHORA DEBES ESCANEAR EL CÓDIGO QR ⚠️"
    echo "    1. Abre WhatsApp -> Dispositivos vinculados"
    echo "    2. Espera a que aparezca el mensaje 'BOT CONECTADO'"
    echo "    3. Una vez conectado, presiona Ctrl + C para enviarlo a segundo plano."
    echo ""
    msg -bar3
    
    # Ejecución interactiva para el QR
    node index.js
    
    msg -bar3
    echo -e "⚙️ CONFIGURANDO EJECUCIÓN EN SEGUNDO PLANO..."
    
    # Matamos sesiones previas si existen para evitar duplicados
    screen -X -S BotWA quit 2>/dev/null
    
    if screen -dmS BotWA node index.js; then
        # Pequeña pausa para verificar si no crasheó inmediatamente
        sleep 2
        if screen -list | grep -q "BotWA"; then
            echo -e "✅ SERVICIO INICIADO CON ÉXITO (Screen: BotWA)"
        else
            echo -e "❌ El servicio se inició pero se cerró inesperadamente."
            echo -e "   Revisa los logs ejecutando: node $DIR/index.js"
        fi
    else
        echo -e "❌ SERVICIO NO SE PUDO ACTIVAR CON SCREEN"
        echo -e "   Prueba ejecutar: node $DIR/index.js &"
    fi
    
    echo ''
    msg -bar
    read -p "Presiona Enter para continuar..."
}

# Función para instalar
instalar() {
echo "Instalando..."
#[[ ! -e "/bin/ShellBot.sh" ]] && wget -O /bin/ShellBot.sh https://raw.githubusercontent.com/ChumoGH/ADMcgh/main/BINARIOS/ShellBot/ShellBot.sh &> /dev/null
[[ ! -e "/bin/ShellBot.sh" ]] && wget -O /bin/ShellBot.sh https://raw.githubusercontent.com/shellscriptx/shellbot/refs/heads/master/ShellBot.sh &> /dev/null
chmod +x /bin/ShellBot.sh
[[ ! -d /etc/ADMcgh ]] && mkdir /etc/ADMcgh
[[ ! -d /etc/adm-lite ]] && mkdir /etc/adm-lite
#wget -q -O /etc/adm-lite/ultimatebot https://www.dropbox.com/s/kqx37io7pdccvou/ultimatebot-ant.sh && chmod +x /etc/adm-lite/ultimatebot &> /dev/null
wget -q -O /etc/adm-lite/ultimatebot https://www.dropbox.com/scl/fi/wqd4btgpvr607s6acb4gh/ultimate_botv2.sh?rlkey=kbkmuy5o1zupylvq6wyhbd8nv && chmod +x /etc/adm-lite/ultimatebot &> /dev/null
wget -O /etc/adm-lite/trans https://raw.githubusercontent.com/ChumoGH/chumogh-gmail.com/master/trans -o /dev/null 2>&1
chmod +x /etc/adm-lite/trans
rm -f $(which trans) &>/dev/null
[[ ! -e /bin/trans ]] && ln -s /etc/adm-lite/trans /bin/trans

wget -q -O /etc/adm-lite/bot_codes https://www.dropbox.com/s/23cjojjxaaun6f1/bot_codes-ant.sh && chmod +x /etc/adm-lite/bot_codes &> /dev/null
[[ $(dpkg --get-selections|grep -w "at"|head -1) ]] || apt-get install at -y &>/dev/null
[[ ! -e /bin/UserAll ]] && {
[[ $(uname -m 2> /dev/null) != x86_64 ]] && rm_rf="https://raw.githubusercontent.com/ChumoGH/ADMcgh/main/BINARIOS/aarch64/UserAll.bin" || local rm_rf="https://raw.githubusercontent.com/ChumoGH/ADMcgh/main/BINARIOS/x86_64/UserAll.bin"
[[ -e /bin/UserAll ]] && rm -f /bin/UserAll
if wget -O /etc/adm-lite/UserAll "${rm_rf}" &>/dev/null ; then
		chmod +x /etc/adm-lite/UserAll
		[[ ! -e /bin/UserAll ]] && ln -s /etc/adm-lite/UserAll /bin/UserAll
fi
}
echo "Instalación completada."
}

# Función para reiniciar
reiniciar() {
    echo "Reiniciando..."
    systemctl restart BotSSH
    echo "Reinicio completado."
	read -p " PRESS TO ENTER TO CONTINUED" 
}

edit_admins(){
echo -e "HOLA"
}

limit_creadores(){
[[ -e /etc/adm-lite/registerBOT.log ]] && rm -f /etc/adm-lite/registerBOT.log || touch /etc/adm-lite/registerBOT.log

}

# Función para desinstalar
desinstalar() {
    echo "Desinstalando..."
    systemctl daemon-reload &>/dev/null
	systemctl disable BotSSH.service &>/dev/null 
	sed -i '/ultimatebot/d' /bin/autoboot &>/dev/null 
	systemctl stop BotSSH.service &>/dev/null 
	rm -f /etc/systemd/system/BotSSH.service
	kill -9 $(ps x | grep "ultimatebot" | grep -v "grep" | awk '{print $1}') > /dev/null 2>&1
	kill $(ps x | grep "telebotusr" | grep -v "grep" | awk '{print $1}') > /dev/null 2>&1
	[[ -e ./bottokens ]] && rm ./bottokens
	msg -bar3
	echo -e " ESTAMOS DETENIENDO EL BOT"
	msg -bar3
	[[ -e /etc/adm-lite/ShellBot.sh ]] && rm /etc/adm-lite/ShellBot.sh 
	[[ -e /etc/adm-lite/ultimatebot ]] && rm /etc/adm-lite/ultimatebot 
	[[ -e /etc/adm-lite/bot_codes ]] && rm /etc/adm-lite/bot_codes
	[[ -e /etc/adm-lite/liberados ]] && rm /etc/adm-lite/liberados
    echo "Desinstalación completada."
enter
}

create_restart() {
    echo "CREANDO PROCESO DE REESTABLECIMIENTO..."
    systemctl daemon-reload &>/dev/null
[[ -e /etc/systemd/system/BotWASSH.service ]] && {
systemctl stop BotWASSH.service &>/dev/null 
systemctl disable BotWASSH.service &>/dev/null 
rm -rf /etc/systemd/system/BotWASSH.service
} || {
cat <<EOF > /etc/systemd/system/BotWASSH.service
[Unit]
Description=BotWASSH Service by @ChumoGH
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
User=root
WorkingDirectory=/etc/adm-lite/whabot
ExecStart=$(which node) /etc/adm-lite/whabot/index.js 
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    echo "INSYTALACION completada."
    systemctl daemon-reload &>/dev/null
	systemctl enable BotWASSH.service &>/dev/null 	
	systemctl start BotWASSH.service &>/dev/null 	
	echo -e "RECUEDA QUE EL PROCESO SYSTEM ES *BotWASSH*"
}
enter
}

# Bucle para mostrar el menú hasta que el usuario elija salir
while true; do
clear&&clear
    mostrar_menu
    read -p " OPCION : " opcion

    case $opcion in
        1)
			instalar
            telegran_bot
            ;;
        2)
            reiniciar
            ;;
        3)
            instalar
			reiniciar
            ;;
		4)
		on_off_create
		;;
		5)
		edit_admins
		;;
		6)
		limit_creadores
		;;
		7)
            desinstalar
            ;;
		8)
            bt_wts
            ;;
		9)
            create_restart
            ;;
        0)
            echo "Saliendo del menú..."
            break
            ;;
        *)
            echo "Opción no válida. Inténtalo de nuevo."
            ;;
    esac

    echo ""  # Línea vacía para mejor legibilidad
done



return 0