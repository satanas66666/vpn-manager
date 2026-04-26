#!/bin/bash

DB="/opt/vpnmanager/usuarios.db"
PORT_FILE="/opt/vpnmanager/port.conf"

# Colores
verde="\e[1;32m"
rojo="\e[1;31m"
azul="\e[1;34m"
amarillo="\e[1;33m"
reset="\e[0m"

# Obtener puerto
get_port() {
    if [ -f "$PORT_FILE" ]; then
        cat $PORT_FILE
    else
        echo "80"
    fi
}

# Contar usuarios activos
usuarios_activos() {
    HOY=$(date +%d%m%Y)
    awk -F "|" -v hoy="$HOY" '$2 >= hoy {count++} END {print count+0}' $DB
}

# Listar usuarios
listar_usuarios() {
    echo -e "${azul}==== USUARIOS ====${reset}"
    if [ ! -s "$DB" ]; then
        echo "No hay usuarios"
        return
    fi

    while IFS="|" read user exp; do
        echo -e "👤 $user | Expira: $exp"
    done < "$DB"
}

# Crear usuario
crear_usuario() {
    read -p "Usuario: " user

    if grep -q "^$user|" "$DB"; then
        echo -e "${rojo}Usuario ya existe${reset}"
        return
    fi

    read -p "Días: " dias

    exp=$(date -d "+$dias days" +%d%m%Y)

    echo "$user|$exp" >> $DB

    echo -e "${verde}Usuario creado correctamente${reset}"
}

# Renovar usuario
renovar_usuario() {
    listar_usuarios
    echo ""

    read -p "Usuario a renovar: " user

    if ! grep -q "^$user|" "$DB"; then
        echo -e "${rojo}No existe${reset}"
        return
    fi

    read -p "Días a agregar: " dias

    exp_actual=$(grep "^$user|" "$DB" | cut -d "|" -f2)
    nueva_fecha=$(date -d "${exp_actual} +$dias days" +%d%m%Y 2>/dev/null)

    sed -i "s/^$user|.*/$user|$nueva_fecha/" $DB

    echo -e "${verde}Renovado correctamente${reset}"
}

# Eliminar usuario
eliminar_usuario() {
    listar_usuarios
    echo ""

    read -p "Usuario a eliminar: " user

    if ! grep -q "^$user|" "$DB"; then
        echo -e "${rojo}No existe${reset}"
        return
    fi

    sed -i "/^$user|/d" $DB

    echo -e "${verde}Usuario eliminado${reset}"
}

# Cambiar puerto
cambiar_puerto() {
    read -p "Nuevo puerto: " nuevo

    if ! [[ "$nuevo" =~ ^[0-9]+$ ]]; then
        echo -e "${rojo}Puerto inválido${reset}"
        return
    fi

    echo $nuevo > $PORT_FILE

    sed -i "s/Listen .*/Listen $nuevo/" /etc/apache2/ports.conf
    sed -i "s/<VirtualHost \*:.*/<VirtualHost *:$nuevo>/" /etc/apache2/sites-enabled/000-default.conf

    systemctl restart apache2

    echo -e "${verde}Puerto cambiado a $nuevo${reset}"
}

# Menú principal
menu() {
    while true; do
        clear

        PORT=$(get_port)
        ACTIVOS=$(usuarios_activos)

        echo -e "${verde}====== VPN MANAGER PRO ======${reset}"
        echo -e "1) Crear usuario"
        echo -e "2) Renovar usuario"
        echo -e "3) Eliminar usuario"
        echo -e "4) Listar usuarios"
        echo -e "5) Usuarios activos: ${amarillo}$ACTIVOS${reset}"
        echo -e "6) Cambiar puerto API"
        echo -e "0) Salir"
        echo "=============================="
        echo -e "Puerto API: ${azul}$PORT${reset}"
        echo "=============================="

        read -p "Seleccione: " op

        case $op in
            1) crear_usuario ;;
            2) renovar_usuario ;;
            3) eliminar_usuario ;;
            4) listar_usuarios ;;
            5) 
                echo -e "${amarillo}Usuarios activos: $ACTIVOS${reset}"
                read -p "Enter para continuar..."
            ;;
            6) cambiar_puerto ;;
            0) exit ;;
            *) echo "Opción inválida" ;;
        esac

        echo ""
        read -p "Presiona Enter para continuar..."
    done
}

menu

