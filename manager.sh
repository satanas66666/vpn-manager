#!/bin/bash

clear

DATA_FILE="/etc/vpn_users"

# Crear archivo si no existe
[ ! -f $DATA_FILE ] && touch $DATA_FILE

pause(){
    echo ""
    read -p "Presiona ENTER para continuar..."
}

menu(){
    clear
    echo "========== VPN MANAGER PRO =========="
    echo "1) Crear usuario"
    echo "2) Renovar usuario"
    echo "3) Eliminar usuario"
    echo "4) Listar usuarios"
    echo "0) Salir"
    echo "====================================="
    read -p "Seleccione una opción: " op
}

listar(){
    clear
    echo "====== LISTA DE USUARIOS ======"
    if [ ! -s $DATA_FILE ]; then
        echo "No hay usuarios registrados"
    else
        nl -w2 -s') ' $DATA_FILE
    fi
    echo "==============================="
}

crear(){
    clear
    echo "====== CREAR USUARIO ======"
    read -p "Usuario: " user
    read -p "Duración (días): " dias

    exp=$(date -d "+$dias days" +"%Y-%m-%d")
    token=$(openssl rand -hex 4)

    echo "$user|$exp|$token" >> $DATA_FILE

    echo ""
    echo "✔ Usuario creado"
    echo "Usuario: $user"
    echo "Expira: $exp"
    echo "Token: $token"
    pause
}

seleccionar_usuario(){
    listar
    echo ""
    read -p "Seleccione número: " num

    user_line=$(sed -n "${num}p" $DATA_FILE)

    if [ -z "$user_line" ]; then
        echo "❌ Opción inválida"
        pause
        return 1
    fi

    return 0
}

renovar(){
    seleccionar_usuario || return

    user=$(echo $user_line | cut -d'|' -f1)
    read -p "Días a agregar: " dias

    nueva_fecha=$(date -d "+$dias days" +"%Y-%m-%d")

    sed -i "${num}s|.*|$user|$nueva_fecha|$(echo $user_line | cut -d'|' -f3)|" $DATA_FILE

    echo ""
    echo "✔ Usuario renovado"
    echo "Nueva fecha: $nueva_fecha"
    pause
}

eliminar(){
    seleccionar_usuario || return

    user=$(echo $user_line | cut -d'|' -f1)
    token=$(echo $user_line | cut -d'|' -f3)

    echo ""
    read -p "¿Eliminar usuario $user? (y/n): " confirm

    if [[ "$confirm" == "y" ]]; then
        sed -i "${num}d" $DATA_FILE
        echo "✔ Usuario eliminado"
        echo "Token liberado: $token"
    else
        echo "Cancelado"
    fi

    pause
}

# LOOP PRINCIPAL
while true; do
    menu
    case $op in
        1) crear ;;
        2) renovar ;;
        3) eliminar ;;
        4) listar; pause ;;
        0) exit ;;
        *) echo "Opción inválida"; pause ;;
    esac
done

