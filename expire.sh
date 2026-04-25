#!/bin/bash

DB="/opt/vpnmanager/usuarios.db"
TMP="/opt/vpnmanager/tmp.db"

> $TMP

HOY=$(date +%d%m%Y)

while IFS="|" read user exp used limit; do
if [ "$exp" -ge "$HOY" ]; then
echo "$user|$exp|0|$limit" >> $TMP
fi
done < $DB

mv $TMP $DB

