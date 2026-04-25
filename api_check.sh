#!/bin/bash

# Cabecera obligatoria para Apache CGI
echo "Content-type: text/plain"
echo ""

export TZ="America/Mexico_City"

DB="/opt/vpnmanager/usuarios.db"

# Evitar error si abren en navegador
if [ "$REQUEST_METHOD" = "GET" ]; then
    echo "OK - Use POST"
    exit
fi

# Leer JSON
read INPUT

# Extraer token
TOKEN=$(echo "$INPUT" | grep -oP '"user"\s*:\s*"\K[^"]+')

# Validar token
if [[ ! "$TOKEN" =~ ^[a-zA-Z0-9]+$ ]]; then
    echo "Not exist"
    exit
fi

# Buscar usuario
LINE=$(grep "^$TOKEN|" "$DB")

if [ -z "$LINE" ]; then
    echo "Not exist"
    exit
fi

# Obtener fecha
EXP=$(echo "$LINE" | cut -d '|' -f2)
HOY=$(date +%d%m%Y)

# Validar expiración
if [ "$EXP" -lt "$HOY" ]; then
    echo "Not exist"
else
    echo "$EXP"
fi

