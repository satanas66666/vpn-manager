#!/bin/bash

clear
echo "===== VPN MANAGER AUTO INSTALL ====="

BASE="/opt/vpnmanager"
REPO="https://raw.githubusercontent.com/TU-USUARIO/vpn-manager/main"

read -p "Puerto para API (ej: 8080): " PORT

echo "Instalando dependencias..."
apt update -y
apt install apache2 -y

a2enmod cgi

echo "Configurando puerto..."
sed -i "s/80/$PORT/g" /etc/apache2/ports.conf
sed -i "s/<VirtualHost \*:80>/<VirtualHost \*:$PORT>/g" /etc/apache2/sites-enabled/000-default.conf

echo "Configurando zona horaria..."
timedatectl set-timezone America/Mexico_City

echo "Creando directorios..."
mkdir -p $BASE
touch $BASE/usuarios.db
chmod 777 $BASE/usuarios.db

cd $BASE

echo "Descargando scripts..."
wget -O manager.sh $REPO/manager.sh
wget -O api_check.sh $REPO/api_check.sh
wget -O expire.sh $REPO/expire.sh

chmod +x manager.sh api_check.sh expire.sh

echo "Instalando API..."
cp api_check.sh /usr/lib/cgi-bin/checkUser
chmod +x /usr/lib/cgi-bin/checkUser

echo "Creando comando global..."
echo -e "#!/bin/bash\nbash $BASE/manager.sh" > /usr/bin/checkuser
chmod +x /usr/bin/checkuser

echo "Configurando auto-expiración..."
(crontab -l 2>/dev/null; echo "0 * * * * bash $BASE/expire.sh") | crontab -

systemctl restart apache2

echo "===== INSTALACIÓN COMPLETA ====="
echo "Comando: checkuser"
echo "API: http://IP:$PORT/cgi-bin/checkUser"

