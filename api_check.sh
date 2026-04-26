#!/bin/bash

echo "Content-type: text/plain"
echo ""

export TZ="America/Mexico_City"

DB="/opt/vpnmanager/usuarios.db"
SESS="/opt/vpnmanager/sessions.db"

mkdir -p /opt/vpnmanager
touch $DB
touch $SESS

# =========================
# OBTENER IP REAL
# =========================

IP="$REMOTE_ADDR"

# Evitar localhost o pruebas
if [[ "$IP" == "127.0.0.1" ]]; then
    echo "Test mode"
    exit
fi

# =========================
# DETECTAR NAVEGADOR
# =========================

UA="$HTTP_USER_AGENT"

if echo "$UA" | grep -qiE "mozilla|chrome|safari"; then
    echo "Access denied"
    exit
fi

# =========================
# OBTENER USUARIO
# =========================

if [ "$REQUEST_METHOD" = "GET" ]; then
    USER=$(echo "$QUERY_STRING" | sed -n 's/^user=\([^&]*\).*$/\1/p')
else
    read INPUT
    USER=$(echo "$INPUT" | grep -oP '"user"\s*:\s*"\K[^"]+')
fi

# Validar usuario
if [[ ! "$USER" =~ ^[a-zA-Z0-9]+$ ]]; then
    echo "Not exist"
    exit
fi

# Buscar usuario
LINE=$(grep "^$USER|" "$DB")

if [ -z "$LINE" ]; then
    echo "Not exist"
    exit
fi

# =========================
# DATOS
# =========================

EXP=$(echo "$LINE" | cut -d '|' -f2)
LIMIT=$(echo "$LINE" | cut -d '|' -f3)

HOY=$(date +%d%m%Y)
NOW=$(date +%s)

# Expirado
if [ "$EXP" -lt "$HOY" ]; then
    echo "Expired"
    exit
fi

# =========================
# LIMPIAR SESIONES VIEJAS (5 min)
# =========================

awk -v now="$NOW" '$3 > now {print}' $SESS > $SESS.tmp && mv $SESS.tmp $SESS

# =========================
# CONTAR SESIONES ACTIVAS DEL USER
# =========================

ACTIVE=$(grep "^$USER|" $SESS | wc -l)

# =========================
# VERIFICAR SI IP YA EXISTE
# =========================

EXIST=$(grep "^$USER|$IP|" $SESS)

if [ -n "$EXIST" ]; then
    # renovar sesión
    EXP_TIME=$((NOW + 300))
    sed -i "s|^$USER|$IP|.*|$USER|$IP|$EXP_TIME|" $SESS
    echo "$EXP"
    exit
fi

# =========================
# VALIDAR LIMITE
# =========================

if [ "$ACTIVE" -ge "$LIMIT" ]; then
    echo "Limit reached"
    exit
fi

# =========================
# AGREGAR SESIÓN
# =========================

EXP_TIME=$((NOW + 300))
echo "$USER|$IP|$EXP_TIME" >> $SESS

echo "$EXP"
