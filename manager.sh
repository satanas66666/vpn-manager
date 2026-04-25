#!/bin/bash

export TZ="America/Mexico_City"
DB="/opt/vpnmanager/usuarios.db"

fecha(){ date -d "+$1 days" +"%d%m%Y"; }

echo "====== VPN MANAGER ======"
echo "1) Crear usuario"
echo "2) Renovar usuario"
echo "3) Eliminar usuario"
echo "4) Listar usuarios"
echo "0) Salir"
read op

case $op in

1)
read -p "Token: " t
read -p "Dias: " d
read -p "Password: " p

echo "$t|$(fecha $d)" >> $DB

useradd -m $t 2>/dev/null
echo "$t:$p" | chpasswd

echo "Usuario creado"
;;

2)
read -p "Token: " t
read -p "Dias: " d

f=$(grep "^$t|" $DB | cut -d'|' -f2)
n=$(date -d "${f:0:2}-${f:2:2}-${f:4:4} +$d days" +"%d%m%Y")

sed -i "s/^$t|.*/$t|$n/" $DB

echo "Renovado"
;;

3)
read -p "Token: " t

userdel -r $t 2>/dev/null
sed -i "/^$t|/d" $DB

echo "Eliminado"
;;

4)
cat $DB
;;

0) exit;;

esac

