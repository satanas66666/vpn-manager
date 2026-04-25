#!/bin/bash

echo "Content-type: text/plain"
echo ""

DB="/opt/vpnmanager/usuarios.db"

read INPUT
TOKEN=$(echo "$INPUT" | grep -oP '"user"\s*:\s*"\K[^"]+')

LINE=$(grep "^$TOKEN|" "$DB")

[ -z "$LINE" ] && echo "Not exist" && exit

USER=$(echo "$LINE" | cut -d'|' -f1)
EXP=$(echo "$LINE" | cut -d'|' -f2)
USED=$(echo "$LINE" | cut -d'|' -f3)
LIMIT=$(echo "$LINE" | cut -d'|' -f4)

HOY=$(date +%d%m%Y)

if [ "$EXP" -lt "$HOY" ]; then
echo "Not exist"
exit
fi

if [ "$USED" -ge "$LIMIT" ]; then
echo "Limit reached"
exit
fi

NEW=$((USED+1))
sed -i "s/^$USER|.*/$USER|$EXP|$NEW|$LIMIT/" $DB

echo "$EXP"

