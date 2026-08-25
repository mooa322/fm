#!/bin/bash

# Detectar distribución de Linux
if [ -f /etc/os-release ]; then
    # Obtener el nombre de la distribución
    . /etc/os-release
    DISTRO=$ID
else
    echo "No se pudo detectar la distribución de Linux."
    exit 1
fi

# Función para instalar Fail2ban
install_fail2ban() {
    if [ "$DISTRO" == "ubuntu" ] || [ "$DISTRO" == "debian" ]; then
        echo "Instalando Fail2ban en una distribución basada en Debian..."
        sudo apt update
        sudo apt install -y fail2ban
    elif [ "$DISTRO" == "centos" ] || [ "$DISTRO" == "fedora" ] || [ "$DISTRO" == "rhel" ]; then
        echo "Instalando Fail2ban en una distribución basada en Red Hat..."
        sudo yum install -y epel-release
        sudo yum install -y fail2ban
        # Si estás en Fedora, usa dnf en lugar de yum
        # sudo dnf install -y fail2ban
    else
        echo "Distribución no soportada para instalación automática."
        exit 1
    fi
}

# Función para configurar Fail2ban
configure_fail2ban() {
    echo "Configurando Fail2ban..."

    # Crear el archivo de configuración local
    sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local

    # Configurar protección para SSH
    sudo bash -c 'cat <<EOT >> /etc/fail2ban/jail.local

[sshd]
enabled = true
port = ssh
logpath = %(sshd_log)s
maxretry = 3
bantime = 600

EOT'

    # Configurar protección para Apache2
    if [ -d "/etc/apache2" ]; then
        sudo bash -c 'cat <<EOT >> /etc/fail2ban/jail.local

[apache]
enabled = true
port = http,https
logpath = %(apache_error_log)s
maxretry = 3
bantime = 600

EOT'
    fi

    # Configurar protección para Nginx
    if [ -d "/etc/nginx" ]; then
        sudo bash -c 'cat <<EOT >> /etc/fail2ban/jail.local

[nginx-http-auth]
enabled = true
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 3
bantime = 600

EOT'
    fi

    # Configurar protección para Squid
    if [ -d "/etc/squid" ]; then
        sudo bash -c 'cat <<EOT >> /etc/fail2ban/jail.local

[squid]
enabled = true
port = 3128
logpath = /var/log/squid/access.log
maxretry = 3
bantime = 600

EOT'
    fi

    # Configurar protección para Dropbear
    if [ -f "/etc/default/dropbear" ]; then
        sudo bash -c 'cat <<EOT >> /etc/fail2ban/jail.local

[dropbear]
enabled = true
port = ssh
logpath = /var/log/auth.log
maxretry = 3
bantime = 600

EOT'
    fi

    # Reiniciar Fail2ban para aplicar cambios
    sudo systemctl restart fail2ban
    sudo systemctl enable fail2ban
}

# Función principal
main() {
    install_fail2ban
    configure_fail2ban

    echo "Fail2ban se ha instalado y configurado exitosamente."
}

# Ejecutar la función principal
main
