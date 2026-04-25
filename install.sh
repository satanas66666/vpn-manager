#!/bin/bash

clear
echo "===== VPN MANAGER AUTO INSTALL ====="

# Verificar root
if [ "$(id -u)" != "0" ]; then
   echo "Ejecuta como root"
   exit 1
fi

BASE="/opt/vpnmanager"
REPO="https://raw.githubusercontent.com/satanas66666/vpn-manager/main"

read -p "Puerto para API (ej: 8080): " PORT

echo "Instalando dependencias..."
apt update -y
apt install apache2 wget -y

echo "Activando CGI..."
a2enmod cgi

echo "Configurando puerto seguro..."

# Cambiar puerto correctamente
sed -i "s/Listen 80/Listen $PORT/g" /etc/apache2/ports.conf
sed -i "s/<VirtualHost \*:80>/<VirtualHost \*:$PORT>/g" /etc/apache2/sites-enabled/000-default.conf

echo "Configurando zona horaria..."
timedatectl set-timezone America/Mexico_City

echo "Creando directorios..."
mkdir -p $BASE
touch $BASE/usuarios.db
chmod 777 $BASE/usuarios.db

cd $BASE || exit

echo "Descargando scripts..."

wget -q -O manager.sh $REPO/manager.sh
wget -q -O api_check.sh $REPO/api_check.sh
wget -q -O expire.sh $REPO/expire.sh

# Verificar descargas
if [ ! -s manager.sh ] || [ ! -s api_check.sh ]; then
    echo "Error descargando archivos"
    exit 1
fi

chmod +x manager.sh api_check.sh expire.sh

echo "Instalando API..."
cp api_check.sh /usr/lib/cgi-bin/checkUser
chmod +x /usr/lib/cgi-bin/checkUser

echo "Creando comando global..."
echo -e "#!/bin/bash\nbash $BASE/manager.sh" > /usr/bin/checkuser
chmod +x /usr/bin/checkuser

echo "Configurando auto-expiración..."

(crontab -l 2>/dev/null; echo "0 * * * * bash $BASE/expire.sh") | crontab -

echo "Reiniciando Apache..."
systemctl restart apache2

echo "=================================="
echo " INSTALACIÓN COMPLETA ✅"
echo "=================================="
echo "Comando: checkuser"
echo "API: http://IP:$PORT/cgi-bin/checkUser"
echo "=================================="

