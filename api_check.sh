#!/bin/bash

echo "Content-type: text/plain"
echo ""

export TZ="America/Mexico_City"
DB="/opt/vpnmanager/usuarios.db"

# evitar error navegador
if [ "$REQUEST_METHOD" = "GET" ]; then
    echo "OK - Use POST"
    exit
fi

read INPUT

TOKEN=$(echo "$INPUT" | grep -oP '"user"\s*:\s*"\K[^"]+')

[[ -z "$TOKEN" ]] && echo "Not exist" && exit

LINE=$(grep "^$TOKEN|" "$DB")

[ -z "$LINE" ] && echo "Not exist" && exit

EXP=$(echo "$LINE" | cut -d '|' -f2)
HOY=$(date +%d%m%Y)

if [ "$EXP" -lt "$HOY" ]; then
    echo "Not exist"
else
    echo "$EXP"
fi

