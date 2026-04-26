#!/bin/bash

clear
echo "===== VPN MANAGER AUTO INSTALL ====="

[ "$(id -u)" != "0" ] && echo "Ejecuta como root" && exit

BASE="/opt/vpnmanager"
REPO="https://raw.githubusercontent.com/satanas66666/vpn-manager/main"

read -p "Puerto API (ej: 7080): " PORT

apt update -y
apt install apache2 wget -y

a2enmod cgi

# Configurar puerto correctamente
sed -i "s/Listen 80/Listen $PORT/g" /etc/apache2/ports.conf
sed -i "s/<VirtualHost \*:80>/<VirtualHost \*:$PORT>/g" /etc/apache2/sites-enabled/000-default.conf

# Activar CGI en web root
cat <<EOF >> /etc/apache2/sites-enabled/000-default.conf

<Directory "/var/www/html">
    Options +ExecCGI
    AddHandler cgi-script .cgi .sh
    Require all granted
</Directory>

ScriptAlias /checkUser /var/www/html/checkUser.cgi

EOF

timedatectl set-timezone America/Mexico_City

mkdir -p $BASE
touch $BASE/usuarios.db
chmod 777 $BASE/usuarios.db

cd $BASE

wget -q -O manager.sh $REPO/manager.sh
wget -q -O api_check.sh $REPO/api_check.sh
wget -q -O expire.sh $REPO/expire.sh

chmod +x manager.sh api_check.sh expire.sh

# API directa sin /cgi-bin
cp api_check.sh /var/www/html/checkUser.cgi
chmod +x /var/www/html/checkUser.cgi

# comando global
echo -e "#!/bin/bash\nbash $BASE/manager.sh" > /usr/bin/checkuser
chmod +x /usr/bin/checkuser

# cron
(crontab -l 2>/dev/null; echo "0 * * * * bash $BASE/expire.sh") | crontab -

systemctl restart apache2

echo "================================="
echo " INSTALADO CORRECTAMENTE"
echo "================================="
echo "URL API:"
echo "http://IP:$PORT/checkUser"
echo "================================="

