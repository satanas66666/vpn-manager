#!/bin/bash

BASE="/opt/vpnmanager"
DB="$BASE/usuarios.db"
PASS_FILE="$BASE/pass.txt"

# =========================
# 🔐 VALIDAR CONTRASEÑA
# =========================
check_password() {

    if [ ! -f "$PASS_FILE" ]; then
        return 0
    fi

    echo -ne "🔐 Ingrese contraseña: "
    read PASS

    SAVED_PASS=$(cat $PASS_FILE)

    if [ "$PASS" != "$SAVED_PASS" ]; then
        echo ""
        echo "❌ Contraseña incorrecta"
        sleep 2
        menu
        return 1
    fi

    return 0
}

# =========================
# 🔑 CREAR PASSWORD GLOBAL
# =========================
create_password() {

    if [ -f "$PASS_FILE" ]; then
        return
    fi

    echo ""
    echo "🔐 Crear contraseña global:"
    read PASS

    echo "$PASS" > $PASS_FILE
}

# =========================
# 🔁 CAMBIAR PASSWORD
# =========================
change_password() {

    check_password || return

    echo ""
    echo "🔁 Nueva contraseña:"
    read NEWPASS

    echo "$NEWPASS" > $PASS_FILE

    echo "✅ Contraseña actualizada"

    read -p "ENTER para volver..." tmp
    menu
}

# =========================
# ➕ CREAR USUARIO
# =========================
crear_usuario() {

    check_password || return

    clear
    echo "===== CREAR USUARIO ====="

    read -p "Usuario: " user
    read -p "Días de duración: " dias
    read -p "Límite de conexiones: " limit

    fecha=$(date -d "+$dias days" +"%d%m%Y")

    echo "$user|$fecha|$limit" >> $DB

    echo ""
    echo "✅ Usuario creado"
    echo "Usuario: $user"
    echo "Expira: $fecha"
    echo "Límite: $limit"

    read -p "ENTER para volver..." tmp
    menu
}

# =========================
# 🔄 RENOVAR USUARIO
# =========================
renovar_usuario() {

    check_password || return

    clear
    echo "===== RENOVAR USUARIO ====="
    cut -d '|' -f1 $DB

    echo ""
    read -p "Usuario: " user
    read -p "Días a agregar: " dias

    nueva_fecha=$(date -d "+$dias days" +"%d%m%Y")

    sed -i "s/^$user|.*/$user|$nueva_fecha|$(grep "^$user|" $DB | cut -d '|' -f3)/" $DB

    echo "✅ Renovado"

    read -p "ENTER para volver..." tmp
    menu
}

# =========================
# ❌ ELIMINAR USUARIO
# =========================
eliminar_usuario() {

    check_password || return

    clear
    echo "===== ELIMINAR USUARIO ====="
    cut -d '|' -f1 $DB

    echo ""
    read -p "Usuario a eliminar: " user

    sed -i "/^$user|/d" $DB

    echo "✅ Eliminado"

    read -p "ENTER para volver..." tmp
    menu
}

# =========================
# 📋 LISTAR USUARIOS
# =========================
listar_usuarios() {

    check_password || return

    clear
    echo "===== LISTA DE USUARIOS ====="
    echo ""

    if [ ! -s "$DB" ]; then
        echo "No hay usuarios"
    else
        awk -F'|' '{print "👤",$1,"| Expira:",$2,"| Límite:",$3}' $DB
    fi

    echo ""
    read -p "ENTER para volver..." tmp
    menu
}

# =========================
# 🚫 BLOQUEADOS (FUTURO)
# =========================
desbloquear_usuario() {

    check_password || return

    echo "Función en proceso..."

    read -p "ENTER para volver..." tmp
    menu
}

# =========================
# 📡 ESTADO API
# =========================
toggle_api() {

    check_password || return

    if systemctl is-active apache2 > /dev/null; then
        systemctl stop apache2
        echo "❌ API apagada"
    else
        systemctl start apache2
        echo "✅ API encendida"
    fi

    read -p "ENTER para volver..." tmp
    menu
}

# =========================
# 🔁 CAMBIAR PUERTO
# =========================
cambiar_puerto() {

    check_password || return

    read -p "Nuevo puerto: " PORT

    sed -i "s/Listen .*/Listen $PORT/" /etc/apache2/ports.conf
    sed -i "s/<VirtualHost \*:.*/<VirtualHost *:$PORT>/" /etc/apache2/sites-enabled/000-default.conf

    systemctl restart apache2

    echo "✅ Puerto cambiado a $PORT"

    read -p "ENTER para volver..." tmp
    menu
}

# =========================
# 🧠 MENÚ PRINCIPAL
# =========================
menu() {

    clear
    echo "====== VPN MANAGER PRO ======"
    echo "1) Crear usuario"
    echo "2) Renovar usuario"
    echo "3) Eliminar usuario"
    echo "4) Listar usuarios"
    echo "5) Cambiar contraseña"
    echo "6) Encender/Apagar API"
    echo "7) Cambiar puerto"
    echo "0) Salir"
    echo "============================="
    read -p "Seleccione: " op

    case $op in
        1) crear_usuario ;;
        2) renovar_usuario ;;
        3) eliminar_usuario ;;
        4) listar_usuarios ;;
        5) change_password ;;
        6) toggle_api ;;
        7) cambiar_puerto ;;
        0) exit ;;
        *) menu ;;
    esac
}

# =========================
# 🚀 INICIO
# =========================
create_password
menu

