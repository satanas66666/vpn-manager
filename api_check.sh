#!/bin/bash

echo "Content-type: text/plain"
echo ""

export TZ="America/Mexico_City"

DB="/opt/vpnmanager/usuarios.db"
BLOCK="/opt/vpnmanager/bloqueados.db"

mkdir -p /opt/vpnmanager
touch $DB $BLOCK

# Evitar GET
if [ "$REQUEST_METHOD" = "GET" ]; then
    echo "OK - Use POST"
    exit
fi

# Leer JSON
read INPUT

# Extraer usuario
TOKEN=$(echo "$INPUT" | grep -oP '"user"\s*:\s*"\K[^"]+')

# Validación básica
if [[ ! "$TOKEN" =~ ^[a-zA-Z0-9]+$ ]]; then
    echo "Not exist"
    exit
fi

# 🔴 BLOQUEADO
if grep -q "^$TOKEN$" "$BLOCK"; then
    echo "Not exist"
    exit
fi

# Buscar usuario
LINE=$(grep "^$TOKEN|" "$DB")

if [ -z "$LINE" ]; then
    echo "Not exist"
    exit
fi

# Extraer datos
EXP=$(echo "$LINE" | cut -d '|' -f2)
LIMIT=$(echo "$LINE" | cut -d '|' -f3)

HOY=$(date +%d%m%Y)

# 🔴 EXPIRADO
if [ "$EXP" -lt "$HOY" ]; then
    echo "Not exist"
    exit
fi

# 🔥 LIMITADOR REAL (por IP)
IP=$(echo $REMOTE_ADDR)

SESSION_FILE="/opt/vpnmanager/sessions_$TOKEN.db"

touch $SESSION_FILE

# limpiar IP duplicada
grep -v "^$IP$" $SESSION_FILE > tmp && mv tmp $SESSION_FILE

# agregar IP
echo "$IP" >> $SESSION_FILE

# contar IP únicas
COUNT=$(sort -u $SESSION_FILE | wc -l)

# validar límite
if [ "$COUNT" -gt "$LIMIT" ]; then
    echo "$TOKEN" >> $BLOCK
    echo "Not exist"
    exit
fi

# ✅ OK (tu app recibe fecha como siempre)
echo "$EXP"

