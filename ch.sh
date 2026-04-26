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

echo "Buscando estructura correcta..."

BASE_DIR=""

for dir in $(find extract -type d); do
    if [ -f "$dir/index.php" ] && [ -d "$dir/chidito1" ]; then
        BASE_DIR="$dir"
        break
    fi
done

if [ -z "$BASE_DIR" ]; then
    echo "Error: estructura inválida"
    exit 1
fi

echo "Estructura detectada en: $BASE_DIR"

# BACKUP
if [ -d "$CARPETA_ETC" ]; then
    mv "$CARPETA_ETC" "${CARPETA_ETC}_backup_$(date +%s)"
fi

mkdir -p "$CARPETA_ETC"

cp -r "$BASE_DIR"/* "$CARPETA_ETC"

# VALIDACIÓN
if [ ! -f "$CARPETA_ETC/index.php" ]; then
    echo "Error final: falta index.php"
    exit 1
fi

if [ ! -d "$CARPETA_ETC/chidito1" ]; then
    echo "Error final: falta chidito1"
    exit 1
fi

# =========================
# 🔥 CREAR ROUTER (AQUÍ ESTÁ LA MAGIA)
# =========================

cat > $CARPETA_ETC/router.php <<'EOF'
<?php

$uri = urldecode(parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH));

// /checkUser → chidito1
if ($uri === '/checkUser' || $uri === '/checkUser/') {
    require __DIR__ . '/chidito1/index.php';
    return;
}

// Servir archivos normales
$file = __DIR__ . $uri;
if ($uri !== '/' && file_exists($file)) {
    return false;
}

// Default → index principal
require __DIR__ . '/index.php';
EOF

# =========================
# PUERTOS
# =========================

echo ""
read -p "Puerto checkUser: " PUERTO_CHECK
read -p "Puerto online: " PUERTO_ONLINE

# =========================
# SERVICIOS
# =========================

cat > /etc/systemd/system/chido-check.service <<EOF
[Unit]
Description=Chido CheckUser
After=network.target

[Service]
ExecStart=/usr/bin/php -S 0.0.0.0:$PUERTO_CHECK -t $CARPETA_ETC $CARPETA_ETC/router.php
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

clear
echo "======================================="
echo " INSTALADO CORRECTAMENTE 🚀"
echo "======================================="
echo ""
echo "CheckUser:"
echo "http://$IP:$PUERTO_CHECK/checkUser"
echo ""
echo "Online Users:"
echo "http://$IP:$PUERTO_ONLINE"
echo ""
echo "======================================="

