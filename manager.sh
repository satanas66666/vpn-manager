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

# ===== CREAR =====
crear(){
clear
echo "===== CREAR USUARIO ====="
read -p "Token: " user
read -p "Días: " dias

fecha=$(date -d "+$dias days" +"%d%m%Y")

echo "$user|$fecha" >> $DB

echo ""
echo "✔ Usuario creado correctamente"
sleep 2
menu
}

# ===== VER =====
ver(){
clear
echo "===== LISTA DE USUARIOS ====="

if [ ! -s "$DB" ]; then
echo "No hay usuarios registrados"
else
nl -w2 -s'. ' $DB
fi

echo ""
read -p "Enter para volver..."
menu
}

# ===== AGREGAR DÍAS =====
agregar(){
clear
echo "===== AGREGAR DÍAS ====="

if [ ! -s "$DB" ]; then
echo "No hay usuarios"
sleep 2
menu
fi

nl -w2 -s'. ' $DB
echo ""

read -p "Token: " user

line=$(grep "^$user|" $DB)

if [ -z "$line" ]; then
echo "❌ Usuario no existe"
sleep 2
menu
fi

read -p "Días a agregar: " dias

fecha_actual=$(echo $line | cut -d'|' -f2)

fecha_nueva=$(date -d "${fecha_actual:0:2}/${fecha_actual:2:2}/${fecha_actual:4:4} +$dias days" +"%d%m%Y")

sed -i "s/^$user|.*/$user|$fecha_nueva/" $DB

echo "✔ Días agregados correctamente"
sleep 2
menu
}

# ===== ELIMINAR =====
eliminar(){
clear
echo "===== ELIMINAR USUARIO ====="

if [ ! -s "$DB" ]; then
echo "No hay usuarios"
sleep 2
menu
fi

nl -w2 -s'. ' $DB
echo ""

read -p "Token a eliminar: " user

if grep -q "^$user|" $DB; then
sed -i "/^$user|/d" $DB
echo "✔ Usuario eliminado"
else
echo "❌ Usuario no encontrado"
fi

sleep 2
menu
}

# ===== BACKUP =====
backup(){
cp $DB $DB.bak
echo "✔ Backup creado en $DB.bak"
sleep 2
menu
}

menu

