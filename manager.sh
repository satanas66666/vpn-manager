#!/bin/bash

DB="/opt/vpnmanager/usuarios.db"

menu(){
clear
echo "===== VPN MANAGER PRO ====="
echo "1) Crear usuario"
echo "2) Ver usuarios"
echo "3) Agregar días"
echo "4) Eliminar usuario"
echo "5) Backup"
echo "0) Salir"
echo ""
read -p "Opción: " op

case $op in
1) crear ;;
2) ver ;;
3) agregar ;;
4) eliminar ;;
5) backup ;;
0) exit ;;
*) menu ;;
esac
}

crear(){
read -p "Token: " user
read -p "Días: " dias

fecha=$(date -d "+$dias days" +"%d%m%Y")

echo "$user|$fecha" >> $DB

echo "✔ Usuario creado"
sleep 2
menu
}

ver(){
clear
echo "===== USUARIOS ====="
nl -w2 -s'. ' $DB
read -p "Enter para volver"
menu
}

agregar(){
read -p "Token: " user
read -p "Días a agregar: " dias

line=$(grep "^$user|" $DB)

if [ -z "$line" ]; then
echo "No existe"
sleep 2
menu
fi

fecha_actual=$(echo $line | cut -d'|' -f2)
fecha_nueva=$(date -d "${fecha_actual:0:2}/${fecha_actual:2:2}/${fecha_actual:4:4} +$dias days" +"%d%m%Y")

sed -i "s/^$user|.*/$user|$fecha_nueva/" $DB

echo "✔ Actualizado"
sleep 2
menu
}

eliminar(){
read -p "Token: " user

sed -i "/^$user|/d" $DB

echo "✔ Eliminado"
sleep 2
menu
}

backup(){
cp $DB $DB.bak
echo "✔ Backup creado"
sleep 2
menu
}

menu

