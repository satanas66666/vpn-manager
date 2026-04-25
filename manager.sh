#!/bin/bash

DB="/etc/vpnmanager"
PASS_FILE="$DB/password.txt"
USER_FILE="$DB/users.txt"
PORT_FILE="$DB/port.txt"
LIMIT_FILE="$DB/limits.txt"
BLOCK_FILE="$DB/blocked.txt"

mkdir -p $DB
touch $USER_FILE $LIMIT_FILE $BLOCK_FILE

# =========================
# 🔐 PASSWORD
# =========================
function get_password(){
    if [ ! -f "$PASS_FILE" ]; then
        echo "🔐 Crear contraseña global:"
        read pass
        printf "%s" "$pass" > $PASS_FILE
    fi
}

function verify_password(){
    if [ ! -f "$PASS_FILE" ]; then
        get_password
    fi

    echo "🔐 Ingrese contraseña:"
    read input

    saved=$(cat $PASS_FILE | tr -d '\r\n')

    if [ "$input" != "$saved" ]; then
        echo "❌ Contraseña incorrecta"
        sleep 2
        return 1
    fi
    return 0
}

function cambiar_password(){
    clear
    verify_password || return

    echo "🔑 Nueva contraseña:"
    read newpass

    printf "%s" "$newpass" > $PASS_FILE

    echo "✅ Contraseña actualizada"
    sleep 2
}

# =========================
# 👥 USUARIOS
# =========================
function crear(){
    clear
    get_password

    echo "👤 Usuario:"
    read user

    echo "⏳ Días:"
    read days

    echo "🔢 Límite de conexiones:"
    read limit

    exp=$(date -d "+$days days" +%Y-%m-%d)

    echo "$user|$exp" >> $USER_FILE
    echo "$user|$limit" >> $LIMIT_FILE

    echo "✅ Usuario creado con límite $limit"
    sleep 2
}

function listar(){
    echo "===== USUARIOS ====="
    while IFS="|" read u exp; do
        lim=$(grep "^$u|" $LIMIT_FILE | cut -d'|' -f2)
        echo "$u | Expira: $exp | Limite: $lim"
    done < $USER_FILE
}

function renovar(){
    clear
    verify_password || return

    listar
    echo "Usuario:"
    read user

    echo "Días extra:"
    read days

    newdate=$(date -d "+$days days" +%Y-%m-%d)

    sed -i "s|^$user|.*|$user|$newdate|" $USER_FILE

    echo "✅ Renovado"
    sleep 2
}

function eliminar(){
    clear
    verify_password || return

    listar
    echo "Usuario:"
    read user

    sed -i "/^$user|/d" $USER_FILE
    sed -i "/^$user|/d" $LIMIT_FILE
    sed -i "/^$user$/d" $BLOCK_FILE

    echo "🗑 Eliminado"
    sleep 2
}

# =========================
# 🔒 BLOQUEOS
# =========================
function ver_bloqueados(){
    echo "🚫 Usuarios bloqueados:"
    cat $BLOCK_FILE
    read -p "Enter para continuar"
}

function desbloquear(){
    clear
    verify_password || return

    ver_bloqueados

    echo "Usuario a desbloquear:"
    read user

    sed -i "/^$user$/d" $BLOCK_FILE

    echo "✅ Desbloqueado"
    sleep 2
}

# =========================
# 🌐 API
# =========================
function estado_api(){
    systemctl is-active apache2 >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "🟢 API ACTIVA"
    else
        echo "🔴 API DETENIDA"
    fi
}

function toggle_api(){
    clear
    verify_password || return

    systemctl is-active apache2 >/dev/null 2>&1

    if [ $? -eq 0 ]; then
        systemctl stop apache2
        echo "🔴 API DETENIDA"
    else
        systemctl start apache2
        echo "🟢 API INICIADA"
    fi

    sleep 2
}

# =========================
# 🔌 PUERTO
# =========================
function obtener_puerto(){
    if [ -f "$PORT_FILE" ]; then
        cat $PORT_FILE
    else
        grep -i listen /etc/apache2/ports.conf | awk '{print $2}'
    fi
}

function cambiar_puerto(){
    clear
    verify_password || return

    echo "Puerto actual: $(obtener_puerto)"
    echo "Nuevo puerto:"
    read newport

    sed -i "s/Listen .*/Listen $newport/" /etc/apache2/ports.conf
    sed -i "s/<VirtualHost \*:.*/<VirtualHost *:$newport>/" /etc/apache2/sites-enabled/000-default.conf

    echo "$newport" > $PORT_FILE

    systemctl restart apache2

    echo "✅ Puerto cambiado"
    sleep 2
}

# =========================
# 🧠 MENU
# =========================
while true; do
clear
echo "======== VPN MANAGER PRO ========"
estado_api
echo "Puerto: $(obtener_puerto)"
echo "--------------------------------"
echo "1) Crear usuario"
echo "2) Renovar usuario"
echo "3) Eliminar usuario"
echo "4) Listar usuarios"
echo "5) Cambiar contraseña"
echo "6) ON/OFF API"
echo "7) Cambiar puerto"
echo "8) Ver bloqueados"
echo "9) Desbloquear usuario"
echo "0) Salir"
echo "================================"
read -p "Opción: " op

case $op in
1) crear ;;
2) renovar ;;
3) eliminar ;;
4) clear; listar; read ;;
5) cambiar_password ;;
6) toggle_api ;;
7) cambiar_puerto ;;
8) clear; ver_bloqueados ;;
9) desbloquear ;;
0) exit ;;
*) echo "Opción inválida"; sleep 1 ;;
esac

done

