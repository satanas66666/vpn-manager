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
# IP REAL
# =========================

IP="$REMOTE_ADDR"

# =========================
# DETECTAR NAVEGADOR (NO CONTAR)
# =========================

UA="$HTTP_USER_AGENT"

if echo "$UA" | grep -qiE "mozilla|chrome|safari"; then
    echo "Not exist"
    exit
fi

# =========================
# OBTENER USUARIO
# =========================

read INPUT
USER=$(echo "$INPUT" | grep -oP '"user"\s*:\s*"\K[^"]+')

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
    echo "Not exist"
    exit
fi

# =========================
# LIMPIAR SESIONES (5 min)
# =========================

awk -v now="$NOW" '$3 > now {print}' $SESS > $SESS.tmp && mv $SESS.tmp $SESS

# =========================
# CONTAR ACTIVOS
# =========================

ACTIVE=$(grep "^$USER|" $SESS | wc -l)

# =========================
# SI YA EXISTE ESA IP → RENOVAR
# =========================

EXIST=$(grep "^$USER|$IP|" $SESS)

if [ -n "$EXIST" ]; then
    EXP_TIME=$((NOW + 300))
    sed -i "s|^$USER|$IP|.*|$USER|$IP|$EXP_TIME|" $SESS
    echo "$EXP"
    exit
fi

# =========================
# VALIDAR LIMITE
# =========================

if [ "$ACTIVE" -ge "$LIMIT" ]; then
    echo "Not exist"
    exit
fi

# =========================
# AGREGAR SESIÓN
# =========================

EXP_TIME=$((NOW + 300))
echo "$USER|$IP|$EXP_TIME" >> $SESS

# RESPUESTA FINAL (SOLO FECHA)
echo "$EXP"

