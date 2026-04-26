#!/bin/bash

clear

ZIP_URL="https://raw.githubusercontent.com/satanas66666/vpn-manager/main/chido.zip"
CARPETA_ETC="/etc/chido"
TMP_DIR="/tmp/chido_install"

apt-get update -y > /dev/null
apt-get install -y unzip curl php > /dev/null

rm -rf $TMP_DIR
mkdir -p $TMP_DIR
cd $TMP_DIR

echo "Descargando archivos..."
curl -L $ZIP_URL -o chido.zip

if [ ! -f chido.zip ]; then
    echo "Error al descargar"
    exit 1
fi

unzip -q chido.zip -d extract

# 🔥 DETECCIÓN INTELIGENTE
echo "Buscando estructura correcta..."

RUTA=$(find extract -type f -name "index.php" | head -n 1)

if [ -z "$RUTA" ]; then
    echo "Error: no se encontró index.php en el zip"
    exit 1
fi

BASE_DIR=$(dirname "$RUTA")

echo "Estructura detectada en: $BASE_DIR"

# BACKUP
if [ -d "$CARPETA_ETC" ]; then
    mv "$CARPETA_ETC" "${CARPETA_ETC}_backup_$(date +%s)"
fi

mkdir -p "$CARPETA_ETC"

cp -r "$BASE_DIR"/* "$CARPETA_ETC"

# VALIDAR chidito1
if [ ! -d "$CARPETA_ETC/chidito1" ]; then
    echo "Error: falta carpeta chidito1"
    exit 1
fi

# PUERTOS
echo ""
read -p "Puerto checkUser: " PUERTO_CHECK
read -p "Puerto online: " PUERTO_ONLINE

# SERVICIOS
cat > /etc/systemd/system/chido-check.service <<EOF
[Unit]
Description=Chido CheckUser
After=network.target

[Service]
ExecStart=/usr/bin/php -S 0.0.0.0:$PUERTO_CHECK -t $CARPETA_ETC/chidito1
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/chido-online.service <<EOF
[Unit]
Description=Chido Online Users
After=network.target

[Service]
ExecStart=/usr/bin/php -S 0.0.0.0:$PUERTO_ONLINE -t $CARPETA_ETC
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl daemon-reload

systemctl enable chido-check
systemctl enable chido-online

systemctl restart chido-check
systemctl restart chido-online

rm -rf $TMP_DIR

IP=$(hostname -I | awk '{print $1}')

echo ""
echo "======================================="
echo " INSTALADO CORRECTAMENTE 🚀"
echo "======================================="
echo "CheckUser:"
echo "http://$IP:$PUERTO_CHECK/chidito1"
echo ""
echo "Online Users:"
echo "http://$IP:$PUERTO_ONLINE"
echo "======================================="

