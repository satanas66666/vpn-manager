#!/bin/bash

BASE="/opt/vpnmanager"
DB="$BASE/usuarios.db"
PORT=$(cat $BASE/puerto.txt)

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

menu() {
clear
echo -e "${CYAN}====== VPN MANAGER PRO ======${NC}"
echo "1) Crear usuario"
echo "2) Renovar usuario"
echo "3) Eliminar usuario"
echo "4) Listar usuarios"
echo "5) Usuarios activos"
echo "6) Cambiar puerto API"
echo "0) Salir"
echo "================================"
echo "Puerto API: $PORT"
echo "================================"
read -p "Seleccione: " op
case $op in
1) crear ;;
2) renovar ;;
3) eliminar ;;
4) listar ;;
5) activos ;;
6) puerto ;;
0) exit ;;
*) menu ;;
esac
}

crear() {
read -p "Usuario: " user
read -p "Días: " dias
read -p "Límite: " limit

exp=$(date -d "+$dias days" +"%d%m%Y")

echo "$user|$exp|0|$limit" >> $DB

echo -e "${GREEN}Usuario creado${NC}"
sleep 2
menu
}

renovar() {
read -p "Usuario: " user
read -p "Días extra: " dias

exp=$(date -d "+$dias days" +"%d%m%Y")

sed -i "/^$user|/d" $DB
echo "$user|$exp|0|1" >> $DB

echo -e "${GREEN}Renovado${NC}"
sleep 2
menu
}

eliminar() {
read -p "Usuario: " user
sed -i "/^$user|/d" $DB

echo -e "${RED}Eliminado${NC}"
sleep 2
menu
}

listar() {
clear
echo "====== USUARIOS ======"

while IFS="|" read user exp used limit; do
echo "User: $user | Exp: $exp | Activos: $used/$limit"
done < $DB

read -p "Enter para volver..."
menu
}

activos() {
clear
TOTAL=0

while IFS="|" read user exp used limit; do
TOTAL=$((TOTAL+used))
done < $DB

echo "Usuarios activos: $TOTAL"
read -p "Enter..."
menu
}

puerto() {
read -p "Nuevo puerto: " newp

sed -i "s/$PORT/$newp/g" /etc/apache2/ports.conf
sed -i "s/$PORT/$newp/g" /etc/apache2/sites-enabled/000-default.conf

echo "$newp" > $BASE/puerto.txt

systemctl restart apache2

echo "Puerto cambiado a $newp"
sleep 2
menu
}

menu
