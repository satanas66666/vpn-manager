#!/bin/bash

DB="/opt/vpnmanager/usuarios.db"
TMP="/opt/vpnmanager/tmp.db"

> $TMP

hoy=$(date +"%d%m%Y")

while IFS="|" read user fecha
do
if [ "$fecha" -ge "$hoy" ]; then
echo "$user|$fecha" >> $TMP
fi
done < $DB

mv $TMP $DB

