#!/bin/bash

BASE="/opt/vpnmanager"
DB="$BASE/usuarios.db"
PORT_FILE="$BASE/port.cfg"

# COLORES
verde="\e[1;32m"
rojo="\e[1;31m"
azul="\e[1;34m"
amarillo="\e[1;33m"
reset="\e[0m"

# CREAR ARCHIVOS SI NO EXISTEN
mkdir -p $BASE
touch $DB
[ ! -f $PORT_FILE ] && echo "8787" > $PORT_FILE

PORT=$(cat $PORT_FILE)

# =========================
# FUNCIONES
# =========================

crear_usuario() {
    echo ""
    read -p "Usuario: " user
    read -p "Contraseña: " pass
    read -p "Dias: " dias

    if grep -q "^$user|" $DB; then
        echo -e "${rojo}Usuario ya existe${reset}"
        sleep 2
        return
    fi

    exp=$(date -d "+$dias days" +%d%m%Y)

    echo "$user|$exp|0|$pass" >> $DB

    echo -e "${verde}Usuario creado${reset}"
    sleep 2
}

renovar_usuario() {
    echo ""
    listar_usuarios
    read -p "Usuario: " user
    read -p "Dias a agregar: " dias

    line=$(grep "^$user|" $DB)

    if [ -z "$line" ]; then
        echo -e "${rojo}No existe${reset}"
        sleep 2
        return
    fi

    exp=$(echo $line | cut -d '|' -f2)
    newexp=$(date -d "${exp:4:4}-${exp:2:2}-${exp:0:2} +$dias days" +%d%m%Y)

    sed -i "s/^$user|.*/$user|$newexp|0|$(echo $line | cut -d '|' -f4)/" $DB

    echo -e "${verde}Renovado${reset}"
    sleep 2
}

listar_usuarios() {
    echo ""
    echo -e "${azul}==== USUARIOS ====${reset}"

    if [ ! -s "$DB" ]; then
        echo "Sin usuarios"
        return
    fi

    nl=1
    while IFS="|" read user exp used pass
    do
        echo -e "${amarillo}$nl) $user${reset} | Expira: $exp"
        ((nl++))
    done < $DB
}

eliminar_usuario() {
    echo ""
    listar_usuarios

    total=$(cat $DB | wc -l)

    if [ "$total" -eq 0 ]; then
        sleep 2
        return
    fi

    read -p "Numero a eliminar: " num

    user=$(sed -n "${num}p" $DB | cut -d '|' -f1)

    if [ -z "$user" ]; then
        echo -e "${rojo}Opcion invalida${reset}"
        sleep 2
        return
    fi

    sed -i "/^$user|/d" $DB

    echo -e "${verde}Eliminado: $user${reset}"
    sleep 2
}

usuarios_activos() {
    echo $(cut -d '|' -f3 $DB | awk '{sum+=$1} END {print sum}')
}

cambiar_puerto() {
    read -p "Nuevo puerto: " newport

    if [[ ! "$newport" =~ ^[0-9]+$ ]]; then
        echo -e "${rojo}Puerto invalido${reset}"
        sleep 2
        return
    fi

    sed -i "s/Listen .*/Listen $newport/" /etc/apache2/ports.conf
    sed -i "s/<VirtualHost \*:.*/<VirtualHost \*:$newport>/" /etc/apache2/sites-enabled/000-default.conf

    echo $newport > $PORT_FILE

    systemctl restart apache2

    PORT=$newport

    echo -e "${verde}Puerto cambiado a $newport${reset}"
    sleep 2
}

ver_api() {
    IP=$(curl -s ifconfig.me)

    if [ -z "$IP" ]; then
        IP=$(hostname -I | awk '{print $1}')
    fi

    echo ""
    echo -e "${azul}===== API CHECKUSER =====${reset}"
    echo -e "${verde}http://$IP:$PORT/cgi-bin/checkUser${reset}"
    echo ""
    read -p "Enter para continuar..."
}

# =========================
# MENU
# =========================

while true; do
    clear

    echo -e "${azul}====== VPN MANAGER PRO ======${reset}"
    echo -e "${verde}1) Crear usuario${reset}"
    echo -e "${verde}2) Renovar usuario${reset}"
    echo -e "${verde}3) Eliminar usuario${reset}"
    echo -e "${verde}4) Listar usuarios${reset}"
    echo -e "${verde}5) Usuarios activos: $(usuarios_activos)${reset}"
    echo -e "${verde}6) Cambiar puerto API${reset}"
    echo -e "${verde}7) Ver enlace API${reset}"
    echo -e "${rojo}0) Salir${reset}"
    echo "================================"

    echo -e "Puerto API: ${amarillo}$PORT${reset}"
    echo "================================"

    read -p "Seleccione: " op

    case $op in
        1) crear_usuario ;;
        2) renovar_usuario ;;
        3) eliminar_usuario ;;
        4) listar_usuarios; read -p "Enter..." ;;
        5) read -p "Activos: $(usuarios_activos)" ;;
        6) cambiar_puerto ;;
        7) ver_api ;;
        0) exit ;;
        *) echo "Opcion invalida"; sleep 1 ;;
    esac
done

