#!/bin/bash

clear

# =========================
# CONFIG
# =========================
ZIP_URL="https://raw.githubusercontent.com/satanas66666/vpn-manager/main/chido.zip"
CARPETA_ETC="/etc/chido"
TMP_DIR="/tmp/chido_install"

# =========================
# DEPENDENCIAS
# =========================
apt-get update -y > /dev/null
apt-get install -y unzip curl php > /dev/null

# =========================
# DESCARGA
# =========================
rm -rf $TMP_DIR
mkdir -p $TMP_DIR
cd $TMP_DIR

echo "Descargando archivos..."

curl -L $ZIP_URL -o chido.zip

if [ ! -f chido.zip ]; then
    echo "Error al descargar el zip"
    exit 1
fi

# =========================
# VALIDAR ZIP
# =========================
unzip -t chido.zip > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "El archivo zip está corrupto"
    exit 1
fi

# =========================
# BACKUP
# =========================
if [ -d "$CARPETA_ETC" ]; then
    echo "Creando backup..."
    mv "$CARPETA_ETC" "${CARPETA_ETC}_backup_$(date +%s)"
fi

# =========================
# INSTALAR
# =========================
mkdir -p "$CARPETA_ETC"

unzip -q chido.zip -d chido_temp

# Mover contenido (soporta cualquier estructura)
cp -r chido_temp/* "$CARPETA_ETC"

# Validación crítica
if [ ! -f "$CARPETA_ETC/index.php" ]; then
    echo "Error: falta index.php"
    exit 1
fi

if [ ! -d "$CARPETA_ETC/chidito1" ]; then
    echo "Error: falta carpeta chidito1"
    exit 1
fi

# =========================
# PUERTOS
# =========================
echo ""
read -p "Puerto checkUser: " PUERTO_CHECK
read -p "Puerto online: " PUERTO_ONLINE

# Validar números
if ! [[ "$PUERTO_CHECK" =~ ^[0-9]+$ ]] || ! [[ "$PUERTO_ONLINE" =~ ^[0-9]+$ ]]; then
    echo "Puertos inválidos"
    exit 1
fi

# =========================
# CREAR SERVICIOS
# =========================

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

# =========================
# ACTIVAR
# =========================
systemctl daemon-reexec
systemctl daemon-reload

systemctl enable chido-check
systemctl enable chido-online

systemctl restart chido-check
systemctl restart chido-online

# =========================
# LIMPIEZA
# =========================
rm -rf $TMP_DIR

# =========================
# RESULTADO
# =========================
IP=$(hostname -I | awk '{print $1}')

clear
echo "======================================="
echo " INSTALADO CORRECTAMENTE 🚀"
echo "======================================="
echo ""
echo "CheckUser:"
echo "http://$IP:$PUERTO_CHECK/chidito1"
echo ""
echo "Online Users:"
echo "http://$IP:$PUERTO_ONLINE"
echo ""
echo "======================================="
