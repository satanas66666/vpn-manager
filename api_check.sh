#!/bin/bash

export TZ="America/Mexico_City"

DB="/opt/vpnmanager/usuarios.db"

read INPUT

TOKEN=$(echo "$INPUT" | grep -oP '"user"\s*:\s*"\K[^"]+')

[[ ! "$TOKEN" =~ ^[a-zA-Z0-9]+$ ]] && echo "Not exist" && exit

LINE=$(grep "^$TOKEN|" "$DB")

[ -z "$LINE" ] && echo "Not exist" && exit

EXP=$(echo "$LINE" | cut -d '|' -f2)
HOY=$(date +%d%m%Y)

if [ "$EXP" -lt "$HOY" ]; then
    echo "Not exist"
else
    echo "$EXP"
fi

