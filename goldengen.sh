#!/bin/bash
# Instalador Golden ADM - Compatible Ubuntu/Debian moderno

set -e

DIR="/tmp/golden"
DIR_SCRIPT="/etc/SCRIPT"
SOURCE="https://www.dropbox.com/s/zzvty98gv3ad1ne/golden.zip?dl=1"
SERVER="https://www.dropbox.com/s/63u1u9wg3bvrqiv/http-server.sh?dl=1"

# Validar root
if [[ $EUID -ne 0 ]]; then
  echo "Ejecuta como root"
  exit 1
fi

echo "Limpiando entorno..."
rm -rf "$DIR"
mkdir -p "$DIR"
cd "$DIR"

echo "Actualizando sistema..."
apt-get update -y
apt-get upgrade -y

echo "Instalando dependencias..."
apt-get install -y \
  bc screen nano zip unzip curl wget apache2 \
  netcat-openbsd

echo "Configurando Apache..."
sed -i "s/^Listen 80$/Listen 81/g" /etc/apache2/ports.conf || true
systemctl restart apache2

echo "Instalando scripts..."
rm -rf "$DIR_SCRIPT"
mkdir -p "$DIR_SCRIPT"

wget -O golden.zip "$SOURCE"
unzip -o golden.zip

cp golden/SCRIPT/* "$DIR_SCRIPT/"
chmod +x "$DIR_SCRIPT/"*

cp golden/gerar.sh /usr/bin/gerar
chmod +x /usr/bin/gerar

cp golden/gerar.sh /usr/bin/gerar.sh
chmod +x /usr/bin/gerar.sh

echo "Instalando servidor HTTP..."
wget -O http-server.sh "$SERVER"
mv http-server.sh /usr/bin/http-server.sh
chmod +x /usr/bin/http-server.sh

echo "Limpiando..."
cd ~
rm -rf "$DIR"

echo -e "\033[1;36m--------------------------------------------------------------------\033[0m"
echo -e "\033[1;33m Perfecto, usa el comando \033[1;31m gerar \033[1;33m para generar las keys"
echo -e "\033[1;36m--------------------------------------------------------------------\033[0m"

exit 0

