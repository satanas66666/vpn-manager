#!/bin/bash

clear
echo "===== VPN MANAGER AUTO INSTALL PRO ====="

BASE="/opt/vpnmanager"
REPO="https://raw.githubusercontent.com/satanas66666/vpn-manager/main"

read -p "Puerto API (ej: 8090): " PORT

echo "Instalando dependencias..."
apt update -y
apt install apache2 -y

a2enmod cgi rewrite

echo "Configurando puerto..."
sed -i "s/80/$PORT/g" /etc/apache2/ports.conf
sed -i "s/<VirtualHost \*:80>/<VirtualHost \*:$PORT>/g" /etc/apache2/sites-enabled/000-default.conf

echo "Configurando zona horaria México..."
timedatectl set-timezone America/Mexico_City

echo "Creando base..."
mkdir -p $BASE
touch $BASE/usuarios.db
chmod 777 $BASE/usuarios.db

cd $BASE

echo "Descargando scripts..."
wget -O manager.sh $REPO/manager.sh
wget -O api_check.sh $REPO/api_check.sh
wget -O expire.sh $REPO/expire.sh

chmod +x *.sh

echo "Instalando API limpia..."

cat > /usr/lib/cgi-bin/checkUser <<'EOF'
#!/bin/bash

echo "Content-type: text/plain"
echo ""

read INPUT
USER=$(echo $INPUT | grep -oP '"user":"\K[^"]+')

DB="/opt/vpnmanager/usuarios.db"

LINE=$(grep "^$USER|" $DB)

if [ -z "$LINE" ]; then
    echo "Not exist"
else
    FECHA=$(echo $LINE | cut -d'|' -f2)
    echo "$FECHA"
fi
EOF

chmod +x /usr/lib/cgi-bin/checkUser

echo "Activando URL limpia /checkUser..."

cat >> /etc/apache2/sites-enabled/000-default.conf <<EOF

ScriptAlias /checkUser /usr/lib/cgi-bin/checkUser

<Directory "/usr/lib/cgi-bin">
    AllowOverride None
    Options +ExecCGI
    Require all granted
</Directory>
EOF

echo "Creando comando global..."
echo -e "#!/bin/bash\nbash $BASE/manager.sh" > /usr/bin/checkuser
chmod +x /usr/bin/checkuser

echo "Configurando auto-expiración..."
(crontab -l 2>/dev/null; echo "0 * * * * bash $BASE/expire.sh") | crontab -

echo "Abriendo puerto..."
ufw allow $PORT/tcp 2>/dev/null

systemctl restart apache2

echo ""
echo "===== INSTALADO CORRECTAMENTE ====="
echo "Comando: checkuser"
echo "API lista en:"
echo "http://IP:$PORT/checkUser"

