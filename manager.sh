#!/bin/bash

DB="/etc/vpnmanager"
PASS_FILE="$DB/password.txt"
USER_FILE="$DB/users.txt"
PORT_FILE="$DB/port.txt"

mkdir -p $DB
touch $USER_FILE

clear

function pause(){
    read -p "Presiona ENTER para continuar..."
}

# =========================
# 🔐 PASSWORD GLOBAL
# =========================
function get_password(){
    if [ ! -f "$PASS_FILE" ]; then
        echo "🔐 Crear contraseña global:"
        read -s pass
        echo "$pass" > $PASS_FILE
    fi
}

function verify_password(){
    if [ ! -f "$PASS_FILE" ]; then
        get_password
    fi

    echo "🔐 Ingrese contraseña:"
    read -s input

    saved=$(cat $PASS_FILE)

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
    read -s newpass

    echo "$newpass" > $PASS_FILE

    echo "✅ Contraseña actualizada"
    sleep 2
}

# =========================
# 👥 USUARIOS
# =========================
function listar(){
    echo "===== USUARIOS ====="
    nl -w2 -s'. ' $USER_FILE
}

function crear(){
    clear
    get_password

    echo "👤 Usuario:"
    read user

    echo "⏳ Días:"
    read days

    echo "$user|$(date -d "+$days days" +%Y-%m-%d)" >> $USER_FILE

    echo "✅ Usuario creado"
    sleep 2
}

function renovar(){
    clear
    verify_password || return

    listar
    echo ""
    echo "Selecciona número:"
    read num

    user=$(sed -n "${num}p" $USER_FILE | cut -d '|' -f1)

    if [ -z "$user" ]; then
        echo "❌ Usuario inválido"
        sleep 2
        return
    fi

    echo "⏳ Días a agregar:"
    read days

    newdate=$(date -d "+$days days" +%Y-%m-%d)

    sed -i "${num}s|.*|$user|$newdate|" $USER_FILE

    echo "✅ Renovado"
    sleep 2
}

function eliminar(){
    clear
    verify_password || return

    listar
    echo ""
    echo "Selecciona número:"
    read num

    sed -i "${num}d" $USER_FILE

    echo "🗑 Eliminado"
    sleep 2
}

# =========================
# 🌐 CONTROL CHECKUSER
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
# 🔌 CAMBIAR PUERTO
# =========================
function cambiar_puerto(){
    clear
    verify_password || return

    echo "Puerto actual:"
    grep -i listen /etc/apache2/ports.conf

    echo ""
    echo "Nuevo puerto:"
    read newport

    if [[ ! "$newport" =~ ^[0-9]+$ ]]; then
        echo "❌ Puerto inválido"
        sleep 2
        return
    fi

    # Cambiar puerto
    sed -i "s/Listen .*/Listen $newport/" /etc/apache2/ports.conf
    sed -i "s/<VirtualHost \*:.*/<VirtualHost *:$newport>/" /etc/apache2/sites-enabled/000-default.conf

    echo "$newport" > $PORT_FILE

    systemctl restart apache2

    echo "✅ Puerto cambiado a $newport"
    sleep 2
}

# =========================
# 🧠 MENU PRINCIPAL
# =========================
function menu(){
while true; do
    clear
    echo "======== VPN MANAGER PRO ========"
    estado_api
    echo "--------------------------------"
    echo "1) Crear usuario"
    echo "2) Renovar usuario"
    echo "3) Eliminar usuario"
    echo "4) Listar usuarios"
    echo "5) Cambiar contraseña"
    echo "6) Encender / Apagar API"
    echo "7) Cambiar puerto API"
    echo "0) Salir"
    echo "================================"
    read -p "Seleccione: " op

    case $op in
        1) crear ;;
        2) renovar ;;
        3) eliminar ;;
        4) clear; listar; pause ;;
        5) cambiar_password ;;
        6) toggle_api ;;
        7) cambiar_puerto ;;
        0) exit ;;
        *) echo "❌ Opción inválida"; sleep 1 ;;
    esac
done
}

menu

