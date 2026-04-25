#!/bin/bash

export TZ="America/Mexico_City"
DB="/opt/vpnmanager/usuarios.db"

HOY=$(date +%d%m%Y)

while IFS="|" read user exp
do
if [ "$exp" -lt "$HOY" ]; then
userdel -r $user 2>/dev/null
sed -i "/^$user|/d" $DB
fi
done < $DB

