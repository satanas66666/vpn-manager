#!/bin/bash

export TZ="America/Mexico_City"
DB="/opt/vpnmanager/usuarios.db"
HOY=$(date +%d%m%Y)

while IFS="|" read u e
do
if [ "$e" -lt "$HOY" ]; then
userdel -r $u 2>/dev/null
sed -i "/^$u|/d" $DB
fi
done < $DB

