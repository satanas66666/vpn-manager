#!/bin/bash

BASE="/opt/vpnmanager"
DB="$BASE/usuarios.db"
PORT_FILE="$BASE/puerto.txt"

# Colores
verde="\e[32m"
rojo="\e[31m"
amarillo="\e[33m"
azul="\e[36m"
reset="\e[0m"

# Obtener puerto
if [ -f "$PORT_FILE" ]; then
    PORT=$(cat $PORT_FILE)
else
    PORT="No definido"
fi

# Contador activos
usuarios_activos() {
    HOY=$(date +%d%m%Y)
    COUNT=0

    while IFS="|" read -r user exp pass limit used lock; do
        if [[ "$exp" -ge "$HOY" ]]; then
            ((COUNT++))
        fi
    done < "$DB"

    echo "$COUNT"
}

# Listar usuarios enumerados
listar_usuarios() {
    echo -e "${azul}==== USUARIOS ==== ${reset}"
    i=1
    while IFS="|" read -r user exp pass limit used lock; do
        echo -e "$i) 👤 $user | Expira: $exp"
        ((i++))
    done < "$DB"
}

# Crear usuario
crear_usuario() {
    echo -e "${verde}=== CREAR USUARIO ===${reset}"
    read -p "Usuario: " user

    if grep -q "^$user|" "$DB"; then
        echo -e "${rojo}Ya existe${reset}"
        sleep 1
        return
    fi

    read -p "Dias: " dias
    read -p "Contraseña (opcional): " pass

    exp=$(date -d "+$dias days" +%d%m%Y)

    echo "$user|$exp|$pass|1|0|0" >> "$DB"

    echo -e "${verde}Usuario creado ✔${reset}"
    sleep 1
}

# Renovar usuario
renovar_usuario() {
    listar_usuarios
    read -p "Numero de usuario: " num

    linea=$(sed -n "${num}p" "$DB")

    if [ -z "$linea" ]; then
        echo -e "${rojo}Invalido${reset}"
        sleep 1
        return
    fi

    user=$(echo "$linea" | cut -d'|' -f1)

    read -p "Dias a agregar: " dias

    nueva=$(date -d "+$dias days" +%d%m%Y)

    sed -i "${num}s|^[^|]*|$user|" "$DB"
    sed -i "${num}s|^[^|]*|$user|; ${num}s|$user|$user|; ${num}s|[0-9]\{8\}|$nueva|" "$DB"

    awk -F"|" -v n="$num" -v new="$nueva" 'BEGIN{OFS="|"} {if(NR==n){$2=new} print}' "$DB" > "$DB.tmp" && mv "$DB.tmp" "$DB"

    echo -e "${verde}Renovado ✔${reset}"
    sleep 1
}

# Eliminar usuario
eliminar_usuario() {
    listar_usuarios
    read -p "Numero de usuario a eliminar: " num

    total=$(wc -l < "$DB")

    if [ "$num" -gt "$total" ] || [ "$num" -le 0 ]; then
        echo -e "${rojo}Invalido${reset}"
        sleep 1
        return
    fi

    sed -i "${num}d" "$DB"

    echo -e "${rojo}Eliminado ✔${reset}"
    sleep 1
}

# Cambiar puerto
cambiar_puerto() {
    read -p "Nuevo puerto: " nuevo

    if [[ ! "$nuevo" =~ ^[0-9]+$ ]]; then
        echo "Invalido"
        sleep 1
        return
    fi

    sed -i "s/Listen .*/Listen $nuevo/" /etc/apache2/ports.conf
    sed -i "s/<VirtualHost \*:.*/<VirtualHost \*:$nuevo>/" /etc/apache2/sites-enabled/000-default.conf

    echo "$nuevo" > "$PORT_FILE"

    systemctl restart apache2

    echo -e "${verde}Puerto cambiado ✔${reset}"
    sleep 1
}

# MENU
while true; do
    clear
    echo -e "${azul}====== VPN MANAGER PRO ======${reset}"
    echo -e "${verde}1) Crear usuario${reset}"
    echo -e "${verde}2) Renovar usuario${reset}"
    echo -e "${verde}3) Eliminar usuario${reset}"
    echo -e "${verde}4) Listar usuarios${reset}"
    echo -e "${verde}5) Usuarios activos: $(usuarios_activos)${reset}"
    echo -e "${verde}6) Cambiar puerto API${reset}"
    echo -e "${rojo}0) Salir${reset}"
    echo "=================================="
    echo -e "Puerto API: ${amarillo}$PORT${reset}"
    echo "=================================="

    read -p "Seleccione: " op

    case $op in
        1) crear_usuario ;;
        2) renovar_usuario ;;
        3) eliminar_usuario ;;
        4) listar_usuarios; read -p "Enter para continuar..." ;;
        5) read -p "Activos: $(usuarios_activos) | Enter..." ;;
        6) cambiar_puerto ;;
        0) exit ;;
        *) echo "Opcion invalida"; sleep 1 ;;
    esac
done

