#!/usr/bin/env bash
# V4.3 frozen -> LATENCY ONLY patch
# ONLY: HAProxy TCP keepalive + inspect-delay 443/80. No other service/config is changed.
set -Eeuo pipefail

CFG=/etc/haproxy/haproxy.cfg
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="/etc/haproxy/haproxy.cfg.pre-latency-$STAMP"
TMP=$(mktemp)
cleanup(){ rm -f "$TMP"; }
trap cleanup EXIT

[[ $(id -u) -eq 0 ]] || { echo 'ERROR: ejecuta como root.'; exit 1; }
command -v haproxy >/dev/null 2>&1 || { echo 'ERROR: HAProxy no está instalado.'; exit 1; }
[[ -s "$CFG" ]] || { echo "ERROR: no existe $CFG"; exit 1; }

grep -q '^frontend shared_ssl_v2ray_443$' "$CFG" || { echo 'ERROR: no encontré frontend V4.3 shared_ssl_v2ray_443.'; exit 1; }
grep -q '^frontend shared_proxygo_v2ray_80$' "$CFG" || { echo 'ERROR: no encontré frontend V4.3 shared_proxygo_v2ray_80.'; exit 1; }

cp -a "$CFG" "$BACKUP"
cp -a "$CFG" "$TMP"

python3 - "$TMP" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
s=p.read_text()
# Add tcpka only inside defaults if missing.
if '    option tcpka\n' not in s:
    marker='    option tcplog\n'
    if marker not in s:
        raise SystemExit('No se encontró option tcplog')
    s=s.replace(marker, marker+'    option tcpka\n', 1)

# Change delay only inside the exact frozen frontends.
def replace_frontend(text, frontend, old, new):
    start=text.find('frontend '+frontend+'\n')
    if start < 0:
        raise SystemExit('No se encontró '+frontend)
    nxt=text.find('\nfrontend ', start+1)
    if nxt < 0:
        nxt=len(text)
    block=text[start:nxt]
    if old not in block:
        # Idempotent: accept if already patched.
        if new in block:
            return text
        raise SystemExit(f'No se encontró {old.strip()} en {frontend}')
    block=block.replace(old,new,1)
    return text[:start]+block+text[nxt:]

s=replace_frontend(s,'shared_ssl_v2ray_443','    tcp-request inspect-delay 3s\n','    tcp-request inspect-delay 400ms\n')
s=replace_frontend(s,'shared_proxygo_v2ray_80','    tcp-request inspect-delay 500ms\n','    tcp-request inspect-delay 200ms\n')
p.write_text(s)
PY

haproxy -c -f "$TMP" >/tmp/haproxy-latency-check.log 2>&1 || {
  echo 'ERROR: HAProxy rechazó el parche. No se cambió la configuración activa.'
  cat /tmp/haproxy-latency-check.log
  exit 1
}

install -m 0644 "$TMP" "$CFG"
if ! systemctl restart haproxy; then
  echo 'ERROR: falló restart. Restaurando V4.3...'
  cp -a "$BACKUP" "$CFG"
  systemctl restart haproxy || true
  exit 1
fi

if ! systemctl is-active --quiet haproxy; then
  echo 'ERROR: HAProxy no quedó activo. Restaurando V4.3...'
  cp -a "$BACKUP" "$CFG"
  systemctl restart haproxy || true
  exit 1
fi

echo '[PASS] Parche LATENCY ONLY aplicado.'
echo '[PASS] V2Ray/ProxyGo/Xray/SSL/usuarios/Path/UUID/binarios NO fueron modificados.'
echo '[PASS] 443 inspect-delay: 400ms'
echo '[PASS] 80  inspect-delay: 200ms'
echo '[PASS] HAProxy TCP keepalive: ON'
echo "[BACKUP] $BACKUP"
echo
echo 'Configuración efectiva:'
grep -n -E 'option tcpka|frontend shared_ssl_v2ray_443|frontend shared_proxygo_v2ray_80|inspect-delay' "$CFG"
