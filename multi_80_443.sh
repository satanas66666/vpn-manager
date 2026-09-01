#!/usr/bin/env bash
# ================================================================
# SSL + V2RAY/XRAY + PROXYGO 80/443 MANAGER - INDEPENDIENTE
# Target: Debian 11/12 (tambien suele funcionar en Debian 13)
# Public TCP/443 is owned by HAProxy.
#   - SSH-over-SSL: TLS -> HAProxy -> local OpenSSH :22
#   - V2Ray/Xray:   TLS -> HAProxy -> local Xray :10000
# HAProxy terminates TLS and classifies the decrypted first bytes:
#   SSH-... => SSH backend; anything else with a payload => Xray.
# This lets both services use the SAME public TCP/443.
# ================================================================

set -o pipefail
export DEBIAN_FRONTEND=noninteractive

C_RESET='\033[0m'
C_GOLD='\033[1;33m'
C_GREEN='\033[1;32m'
C_RED='\033[1;31m'
C_CYAN='\033[1;36m'
C_WHITE='\033[1;37m'
C_GRAY='\033[0;37m'

BASE_DIR='/etc/ssl-v2ray443-manager'
STATE_FILE="$BASE_DIR/state.env"
USERS_FILE="$BASE_DIR/xray-users.json"
BACKUP_DIR="$BASE_DIR/backups"
XRAY_CONFIG='/usr/local/etc/xray/config.json'
XRAY_BIN='/usr/local/bin/xray'
XRAY_PORT='10000'
HA_CERT_DIR='/etc/haproxy/certs'
HA_CERT="$HA_CERT_DIR/shared443.pem"
HA_CFG='/etc/haproxy/haproxy.cfg'
INFO_FILE='/root/SSL_V2RAY_PROXYGO_80_443_INFO.txt'
XRAY80_PORT='10080'
PROXYGO_BIN='/usr/local/bin/proxygo'
PROXYGO_SRC_DIR='/opt/newgolden-proxygo'
PROXYGO_DIR='/etc/proxygo'
PROXYGO_LOCAL_PORT='18080'

DOMAIN=''
EMAIL=''
CERT_MODE='self-signed'
XRAY_PROTOCOL='vless'
XRAY_TRANSPORT='websocket'
XRAY_PATH='/v2ray'
XRAY_GRPC_SERVICE='v2raygrpc'
XRAY_XHTTP_MODE='auto'

# Puerto 80 compartido: ProxyGo es el backend por defecto.
XRAY80_ENABLED='0'
XRAY80_PROTOCOL='vless'
XRAY80_TRANSPORT='websocket'
XRAY80_PATH='/v2ray80'
XRAY80_GRPC_SERVICE='v2ray80grpc'
XRAY80_XHTTP_MODE='auto'
PROXYGO_TARGET_PORT='22'
PROXYGO_BANNER='OK'

require_root() {
  if [[ $(id -u) -ne 0 ]]; then
    echo -e "${C_RED}ERROR:${C_RESET} ejecuta como root: sudo bash $0"
    exit 1
  fi
}

bar() {
  echo -e "${C_GOLD}=×=×=×=×=×=×=×=×=×=×=×=×=×=×=×=×=×=×=×=×=×=×=×=×=×=×=×=×=×=${C_RESET}"
}

pause() {
  echo
  read -r -p 'ENTER para continuar...' _
}

safe_clear() {
  command -v clear >/dev/null 2>&1 && clear || printf '\033c'
}

ensure_dirs() {
  mkdir -p "$BASE_DIR" "$BACKUP_DIR" "$HA_CERT_DIR" /usr/local/etc/xray
  if [[ ! -f "$USERS_FILE" ]]; then
    printf '[]\n' > "$USERS_FILE"
    chmod 600 "$USERS_FILE"
  fi
}

load_state() {
  ensure_dirs
  if [[ -f "$STATE_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$STATE_FILE"
  fi
}

save_state() {
  ensure_dirs
  cat > "$STATE_FILE" <<EOF
DOMAIN=$(printf '%q' "$DOMAIN")
EMAIL=$(printf '%q' "$EMAIL")
CERT_MODE=$(printf '%q' "$CERT_MODE")
XRAY_PROTOCOL=$(printf '%q' "$XRAY_PROTOCOL")
XRAY_TRANSPORT=$(printf '%q' "$XRAY_TRANSPORT")
XRAY_PATH=$(printf '%q' "$XRAY_PATH")
XRAY_GRPC_SERVICE=$(printf '%q' "$XRAY_GRPC_SERVICE")
XRAY_XHTTP_MODE=$(printf '%q' "$XRAY_XHTTP_MODE")
XRAY80_ENABLED=$(printf '%q' "$XRAY80_ENABLED")
XRAY80_PROTOCOL=$(printf '%q' "$XRAY80_PROTOCOL")
XRAY80_TRANSPORT=$(printf '%q' "$XRAY80_TRANSPORT")
XRAY80_PATH=$(printf '%q' "$XRAY80_PATH")
XRAY80_GRPC_SERVICE=$(printf '%q' "$XRAY80_GRPC_SERVICE")
XRAY80_XHTTP_MODE=$(printf '%q' "$XRAY80_XHTTP_MODE")
PROXYGO_TARGET_PORT=$(printf '%q' "$PROXYGO_TARGET_PORT")
PROXYGO_BANNER=$(printf '%q' "$PROXYGO_BANNER")
EOF
  chmod 600 "$STATE_FILE"
}

service_is_active() {
  systemctl is-active --quiet "$1" 2>/dev/null
}

onoff() {
  if service_is_active "$1"; then
    echo -e "${C_GREEN}ON${C_RESET}"
  else
    echo -e "${C_RED}OFF${C_RESET}"
  fi
}

public_ip() {
  local ip=''
  ip=$(curl -4fsS --max-time 4 https://api.ipify.org 2>/dev/null || true)
  [[ -n "$ip" ]] || ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  printf '%s' "$ip"
}

host_for_clients() {
  if [[ -n "$DOMAIN" ]]; then
    printf '%s' "$DOMAIN"
  else
    public_ip
  fi
}

backup_file_once() {
  local f="$1" tag="$2"
  [[ -f "$f" ]] || return 0
  if ! compgen -G "$BACKUP_DIR/${tag}-*.bak" >/dev/null; then
    cp -a "$f" "$BACKUP_DIR/${tag}-$(date +%Y%m%d-%H%M%S).bak"
  fi
}

install_base() {
  echo -e "${C_CYAN}Instalando dependencias base...${C_RESET}"
  apt-get update -y || return 1
  apt-get install -y ca-certificates curl openssl haproxy openssh-server jq uuid-runtime certbot iproute2 procps golang-go lsof || return 1
  systemctl enable ssh >/dev/null 2>&1 || systemctl enable sshd >/dev/null 2>&1 || true
  systemctl restart ssh >/dev/null 2>&1 || systemctl restart sshd >/dev/null 2>&1 || true
  echo -e "${C_GREEN}Dependencias listas.${C_RESET}"
}

make_self_signed() {
  local cn
  cn="${DOMAIN:-$(hostname -f 2>/dev/null || hostname)}"
  mkdir -p "$HA_CERT_DIR"
  openssl req -x509 -newkey rsa:2048 -nodes -days 825 \
    -keyout "$BASE_DIR/selfsigned.key" \
    -out "$BASE_DIR/selfsigned.crt" \
    -subj "/CN=${cn}" >/dev/null 2>&1 || return 1
  cat "$BASE_DIR/selfsigned.crt" "$BASE_DIR/selfsigned.key" > "$HA_CERT"
  chmod 600 "$HA_CERT"
  CERT_MODE='self-signed'
  save_state
}

configure_certificate() {
  install_base || return 1
  load_state
  safe_clear
  bar
  echo -e "${C_GOLD}        CERTIFICADO TLS PARA SSL + V2RAY 443${C_RESET}"
  bar
  echo 'Para produccion se recomienda un dominio apuntando a esta VPS.'
  echo 'Si lo dejas vacio se creara un certificado autofirmado.'
  echo
  read -r -p "Dominio [${DOMAIN:-ninguno}]: " in_domain
  if [[ -n "$in_domain" ]]; then
    DOMAIN="${in_domain,,}"
  fi
  if [[ -n "$DOMAIN" ]]; then
    read -r -p "Email Let's Encrypt [${EMAIL:-opcional}]: " in_email
    [[ -n "$in_email" ]] && EMAIL="$in_email"
  fi
  save_state

  if [[ -z "$DOMAIN" ]]; then
    make_self_signed || return 1
    echo -e "${C_GREEN}Certificado autofirmado creado.${C_RESET}"
    write_haproxy_config >/dev/null 2>&1 || true
    systemctl restart haproxy >/dev/null 2>&1 || true
    return 0
  fi

  echo "Solicitando Let's Encrypt para: $DOMAIN"
  mkdir -p "$HA_CERT_DIR"
  local args=(certonly --standalone --preferred-challenges http --non-interactive --agree-tos -d "$DOMAIN")
  if [[ -n "$EMAIL" ]]; then
    args+=(--email "$EMAIL")
  else
    args+=(--register-unsafely-without-email)
  fi

  # Only port 80 is needed for the HTTP challenge. Stop services that may own it.
  local stopped_haproxy=0
  if ss -lnt 2>/dev/null | awk '{print $4}' | grep -Eq '(^|:)80$'; then
    if service_is_active haproxy; then
      systemctl stop haproxy || true
      stopped_haproxy=1
    fi
  fi

  if certbot "${args[@]}"; then
    cat "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" \
        "/etc/letsencrypt/live/${DOMAIN}/privkey.pem" > "$HA_CERT"
    chmod 600 "$HA_CERT"
    CERT_MODE='letsencrypt'
    save_state
    mkdir -p /etc/letsencrypt/renewal-hooks/deploy
    cat > /etc/letsencrypt/renewal-hooks/deploy/ssl-v2ray443-haproxy.sh <<EOF
#!/usr/bin/env bash
set -e
cat "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" "/etc/letsencrypt/live/${DOMAIN}/privkey.pem" > "${HA_CERT}"
chmod 600 "${HA_CERT}"
systemctl reload haproxy
EOF
    chmod 700 /etc/letsencrypt/renewal-hooks/deploy/ssl-v2ray443-haproxy.sh
    echo -e "${C_GREEN}Let's Encrypt instalado.${C_RESET}"
  else
    echo -e "${C_RED}Let's Encrypt fallo. Se usara certificado autofirmado.${C_RESET}"
    make_self_signed || return 1
  fi

  [[ $stopped_haproxy -eq 1 ]] && systemctl start haproxy >/dev/null 2>&1 || true
  write_haproxy_config >/dev/null 2>&1 || true
  systemctl restart haproxy >/dev/null 2>&1 || true
}

write_haproxy_config() {
  ensure_dirs
  load_state
  [[ -s "$HA_CERT" ]] || make_self_signed || return 1
  backup_file_once "$HA_CFG" 'haproxy.cfg'

  local x80_acl=''
  local x80_backend=''
  if [[ "$XRAY80_ENABLED" == '1' ]]; then
    # Port 80 can only be safely multiplexed when Xray traffic is identifiable
    # as HTTP-like traffic (WS / HTTPUpgrade / XHTTP) or h2c (gRPC/XHTTP).
    x80_acl=$(cat <<EOF
    acl is_xray80_path req.payload(0,0) -m sub " ${XRAY80_PATH}"
    acl is_xray80_h2 req.payload(0,14) -m str "PRI * HTTP/2.0"
    tcp-request content accept if is_xray80_path
    tcp-request content accept if is_xray80_h2
    use_backend xray_80 if is_xray80_path
    use_backend xray_80 if is_xray80_h2
EOF
)
    x80_backend=$(cat <<EOF

backend xray_80
    mode tcp
    server xray80 127.0.0.1:${XRAY80_PORT} check
EOF
)
  fi

  cat > "$HA_CFG" <<EOF
global
    log /dev/log local0
    log /dev/log local1 notice
    daemon
    user haproxy
    group haproxy
    maxconn 4096
    ssl-default-bind-options no-sslv3 no-tlsv10 no-tlsv11
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners

defaults
    log global
    mode tcp
    option tcplog
    timeout connect 5s
    timeout client  2h
    timeout server  2h
    timeout tunnel  24h

# ---------------------------------------------------------------
# TCP/443 COMPARTIDO
# HAProxy termina TLS. SSH comienza con SSH- y va a OpenSSH.
# Todo otro payload va al perfil Xray 443.
# ---------------------------------------------------------------
frontend shared_ssl_v2ray_443
    bind *:443 ssl crt ${HA_CERT} alpn h2,http/1.1
    mode tcp
    tcp-request inspect-delay 3s
    acl enough_payload req.len ge 4
    acl is_ssh req.payload(0,4) -m str SSH-
    tcp-request content accept if enough_payload
    use_backend ssh_direct if is_ssh
    use_backend xray_selected if enough_payload !is_ssh
    default_backend ssh_direct

backend ssh_direct
    mode tcp
    server ssh1 127.0.0.1:22 check

backend xray_selected
    mode tcp
    server xray1 127.0.0.1:${XRAY_PORT} check

# ---------------------------------------------------------------
# TCP/80 COMPARTIDO
# ProxyGo NEW GOLDEN es el backend por defecto.
# Solo el path Xray configurado / h2c se desvia a Xray local.
# Esto preserva el comportamiento ProxyGo que ya funciona en Golden MX.
# ---------------------------------------------------------------
frontend shared_proxygo_v2ray_80
    bind *:80
    mode tcp
    tcp-request inspect-delay 500ms
${x80_acl}
    default_backend proxygo_80

backend proxygo_80
    mode tcp
    server proxygo1 127.0.0.1:${PROXYGO_LOCAL_PORT} check${x80_backend}
EOF

  if ! haproxy -c -f "$HA_CFG"; then
    echo -e "${C_RED}ERROR: la configuracion HAProxy no paso validacion.${C_RESET}"
    return 1
  fi
  systemctl enable haproxy >/dev/null 2>&1 || true
  systemctl restart haproxy || return 1
  return 0
}

install_haproxy_ssl() {
  install_base || return 1
  load_state
  if [[ ! -s "$HA_CERT" ]]; then
    echo 'Primero se preparara el certificado TLS.'
    configure_certificate || return 1
  fi
  write_haproxy_config || return 1
  echo -e "${C_GREEN}HAProxy SSL directo activo en el puerto publico 443.${C_RESET}"
  echo 'Backend SSH: 127.0.0.1:22'
}

install_xray_core() {
  install_base || return 1
  echo -e "${C_CYAN}Instalando/actualizando Xray-core desde el instalador oficial XTLS...${C_RESET}"
  curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh -o /tmp/xray-install-release.sh || return 1
  bash /tmp/xray-install-release.sh install || return 1
  if [[ ! -x "$XRAY_BIN" ]]; then
    echo -e "${C_RED}Xray no quedo instalado en $XRAY_BIN${C_RESET}"
    return 1
  fi
  systemctl enable xray >/dev/null 2>&1 || true
  echo -e "${C_GREEN}Xray-core instalado.${C_RESET}"
}

transport_name() {
  case "$XRAY_TRANSPORT" in
    websocket) echo 'WebSocket' ;;
    xhttp) echo 'XHTTP' ;;
    grpc) echo 'gRPC' ;;
    raw) echo 'RAW/TCP' ;;
    httpupgrade) echo 'HTTPUpgrade' ;;
    *) echo "$XRAY_TRANSPORT" ;;
  esac
}

profile_name() {
  echo "${XRAY_PROTOCOL^^} + $(transport_name) + TLS"
}

xray_settings_for_protocol() {
  local proto="$1" clients
  case "$proto" in
    vmess)
      clients=$(jq '[.[] | {id:.uuid, level:0, email:(.name + "@local")}]' "$USERS_FILE") || return 1
      jq -nc --argjson c "$clients" '{clients:$c}'
      ;;
    vless)
      clients=$(jq '[.[] | {id:.uuid, level:0, email:(.name + "@local")}]' "$USERS_FILE") || return 1
      jq -nc --argjson c "$clients" '{clients:$c,decryption:"none"}'
      ;;
    trojan)
      clients=$(jq '[.[] | {password:.password, level:0, email:(.name + "@local")}]' "$USERS_FILE") || return 1
      jq -nc --argjson c "$clients" '{clients:$c}'
      ;;
    *) return 1 ;;
  esac
}

xray_stream_for() {
  local transport="$1" path="$2" grpc="$3" xmode="$4"
  case "$transport" in
    websocket) jq -nc --arg p "$path" '{network:"ws",security:"none",wsSettings:{path:$p}}' ;;
    xhttp) jq -nc --arg p "$path" --arg m "$xmode" '{network:"xhttp",security:"none",xhttpSettings:{path:$p,mode:$m}}' ;;
    grpc) jq -nc --arg s "$grpc" '{network:"grpc",security:"none",grpcSettings:{serviceName:$s,multiMode:false}}' ;;
    raw) jq -nc '{network:"tcp",security:"none",tcpSettings:{header:{type:"none"}}}' ;;
    httpupgrade) jq -nc --arg p "$path" '{network:"httpupgrade",security:"none",httpupgradeSettings:{path:$p}}' ;;
    *) return 1 ;;
  esac
}

build_xray_config() {
  load_state
  [[ -x "$XRAY_BIN" ]] || { echo 'Xray no esta instalado.'; return 1; }
  [[ -f "$USERS_FILE" ]] || printf '[]
' > "$USERS_FILE"

  local set443 stream443 inbound443 inbounds tmp
  set443=$(xray_settings_for_protocol "$XRAY_PROTOCOL") || return 1
  stream443=$(xray_stream_for "$XRAY_TRANSPORT" "$XRAY_PATH" "$XRAY_GRPC_SERVICE" "$XRAY_XHTTP_MODE") || return 1
  inbound443=$(jq -nc --arg proto "$XRAY_PROTOCOL" --argjson settings "$set443" --argjson stream "$stream443" --argjson port "$XRAY_PORT" '{tag:"shared443-in",listen:"127.0.0.1",port:$port,protocol:$proto,settings:$settings,streamSettings:$stream}')
  inbounds=$(jq -nc --argjson a "$inbound443" '[$a]')

  if [[ "$XRAY80_ENABLED" == '1' ]]; then
    case "$XRAY80_TRANSPORT" in
      websocket|xhttp|grpc|httpupgrade) ;;
      *) echo 'Puerto 80 compartido solo admite WS/XHTTP/gRPC/HTTPUpgrade.'; return 1 ;;
    esac
    local set80 stream80 inbound80
    set80=$(xray_settings_for_protocol "$XRAY80_PROTOCOL") || return 1
    stream80=$(xray_stream_for "$XRAY80_TRANSPORT" "$XRAY80_PATH" "$XRAY80_GRPC_SERVICE" "$XRAY80_XHTTP_MODE") || return 1
    inbound80=$(jq -nc --arg proto "$XRAY80_PROTOCOL" --argjson settings "$set80" --argjson stream "$stream80" --argjson port "$XRAY80_PORT" '{tag:"shared80-in",listen:"127.0.0.1",port:$port,protocol:$proto,settings:$settings,streamSettings:$stream}')
    inbounds=$(jq -nc --argjson a "$inbounds" --argjson b "$inbound80" '$a + [$b]')
  fi

  tmp=$(mktemp)
  jq -n --argjson inbounds "$inbounds" '{log:{loglevel:"warning"},inbounds:$inbounds,outbounds:[{tag:"direct",protocol:"freedom",settings:{}},{tag:"blocked",protocol:"blackhole",settings:{}}]}' > "$tmp" || { rm -f "$tmp"; return 1; }

  backup_file_once "$XRAY_CONFIG" 'xray-config.json'
  install -m 644 "$tmp" "$XRAY_CONFIG"
  rm -f "$tmp"

  if ! "$XRAY_BIN" run -test -config "$XRAY_CONFIG" >/tmp/xray-test.log 2>&1; then
    if ! "$XRAY_BIN" -test -config "$XRAY_CONFIG" >/tmp/xray-test.log 2>&1; then
      echo -e "${C_RED}ERROR: Xray rechazo la configuracion.${C_RESET}"
      cat /tmp/xray-test.log
      return 1
    fi
  fi

  systemctl daemon-reload
  systemctl enable xray >/dev/null 2>&1 || true
  systemctl restart xray || return 1
  return 0
}

choose_xray_profile() {
  load_state
  safe_clear
  bar
  echo -e "${C_GOLD}     ELEGIR PROTOCOLO / TRANSPORTE V2RAY - PUERTO 443${C_RESET}"
  bar
  echo '[1] VMESS + WEBSOCKET + TLS'
  echo '[2] VLESS + WEBSOCKET + TLS'
  echo '[3] VLESS + XHTTP + TLS'
  echo '[4] VLESS + gRPC + TLS'
  echo '[5] VLESS + RAW/TCP + TLS'
  echo '[6] TROJAN + RAW/TCP + TLS'
  echo '[7] VMESS + RAW/TCP + TLS'
  echo '[8] VLESS + HTTPUPGRADE + TLS'
  echo '[0] VOLVER'
  bar
  read -r -p 'Seleccione: ' op
  case "$op" in
    1) XRAY_PROTOCOL='vmess'; XRAY_TRANSPORT='websocket' ;;
    2) XRAY_PROTOCOL='vless'; XRAY_TRANSPORT='websocket' ;;
    3) XRAY_PROTOCOL='vless'; XRAY_TRANSPORT='xhttp' ;;
    4) XRAY_PROTOCOL='vless'; XRAY_TRANSPORT='grpc' ;;
    5) XRAY_PROTOCOL='vless'; XRAY_TRANSPORT='raw' ;;
    6) XRAY_PROTOCOL='trojan'; XRAY_TRANSPORT='raw' ;;
    7) XRAY_PROTOCOL='vmess'; XRAY_TRANSPORT='raw' ;;
    8) XRAY_PROTOCOL='vless'; XRAY_TRANSPORT='httpupgrade' ;;
    0) return 0 ;;
    *) echo 'Opcion invalida.'; pause; return 0 ;;
  esac

  if [[ "$XRAY_TRANSPORT" == 'websocket' || "$XRAY_TRANSPORT" == 'xhttp' || "$XRAY_TRANSPORT" == 'httpupgrade' ]]; then
    read -r -p "Path [${XRAY_PATH}]: " p
    if [[ -n "$p" ]]; then XRAY_PATH="$p"; fi
    [[ "$XRAY_PATH" == /* ]] || XRAY_PATH="/$XRAY_PATH"
  fi
  if [[ "$XRAY_TRANSPORT" == 'grpc' ]]; then
    read -r -p "ServiceName gRPC [${XRAY_GRPC_SERVICE}]: " s
    [[ -n "$s" ]] && XRAY_GRPC_SERVICE="$s"
  fi
  if [[ "$XRAY_TRANSPORT" == 'xhttp' ]]; then
    echo 'Modo XHTTP recomendado: auto'
    read -r -p "Modo [${XRAY_XHTTP_MODE}]: " m
    [[ -n "$m" ]] && XRAY_XHTTP_MODE="$m"
  fi

  save_state
  if [[ -x "$XRAY_BIN" ]]; then
    if build_xray_config; then
      write_haproxy_config >/dev/null 2>&1 || true
      echo -e "${C_GREEN}Perfil aplicado: $(profile_name)${C_RESET}"
    fi
  else
    echo -e "${C_GOLD}Perfil guardado. Instala Xray-core para aplicarlo.${C_RESET}"
  fi
  pause
}

xray80_profile_name() {
  [[ "$XRAY80_ENABLED" == '1' ]] || { echo 'DESACTIVADO'; return; }
  local t
  case "$XRAY80_TRANSPORT" in
    websocket) t='WebSocket' ;;
    xhttp) t='XHTTP' ;;
    grpc) t='gRPC/h2c' ;;
    httpupgrade) t='HTTPUpgrade' ;;
    *) t="$XRAY80_TRANSPORT" ;;
  esac
  echo "${XRAY80_PROTOCOL^^} + ${t} (SIN TLS)"
}

choose_xray80_profile() {
  load_state
  safe_clear
  bar
  echo -e "${C_GOLD}      V2RAY/XRAY EN PUERTO 80 COMPARTIDO CON PROXYGO${C_RESET}"
  bar
  echo 'ProxyGo NEW GOLDEN sigue siendo el backend por defecto del puerto 80.'
  echo 'Xray se identifica por path HTTP o por HTTP/2 h2c.'
  echo 'RAW/TCP y Trojan RAW no se ofrecen aqui porque no se pueden distinguir'
  echo 'de ProxyGo de forma segura en el mismo TCP/80.'
  bar
  echo '[1] VMESS + WEBSOCKET'
  echo '[2] VLESS + WEBSOCKET'
  echo '[3] VLESS + XHTTP'
  echo '[4] VLESS + HTTPUPGRADE'
  echo '[5] VLESS + gRPC / h2c'
  echo '[6] DESACTIVAR XRAY EN 80 (ProxyGo queda solo)'
  echo '[0] VOLVER'
  bar
  read -r -p 'Seleccione: ' op
  case "$op" in
    1) XRAY80_ENABLED='1'; XRAY80_PROTOCOL='vmess'; XRAY80_TRANSPORT='websocket' ;;
    2) XRAY80_ENABLED='1'; XRAY80_PROTOCOL='vless'; XRAY80_TRANSPORT='websocket' ;;
    3) XRAY80_ENABLED='1'; XRAY80_PROTOCOL='vless'; XRAY80_TRANSPORT='xhttp' ;;
    4) XRAY80_ENABLED='1'; XRAY80_PROTOCOL='vless'; XRAY80_TRANSPORT='httpupgrade' ;;
    5) XRAY80_ENABLED='1'; XRAY80_PROTOCOL='vless'; XRAY80_TRANSPORT='grpc' ;;
    6) XRAY80_ENABLED='0'; save_state; [[ -x "$XRAY_BIN" ]] && build_xray_config >/dev/null 2>&1 || true; write_haproxy_config >/dev/null 2>&1 || true; echo 'Xray 80 desactivado; ProxyGo sigue en 80.'; pause; return 0 ;;
    0) return 0 ;;
    *) echo 'Opcion invalida.'; pause; return 0 ;;
  esac

  if [[ "$XRAY80_TRANSPORT" == 'websocket' || "$XRAY80_TRANSPORT" == 'xhttp' || "$XRAY80_TRANSPORT" == 'httpupgrade' ]]; then
    read -r -p "Path exclusivo Xray80 [${XRAY80_PATH}]: " p
    [[ -n "$p" ]] && XRAY80_PATH="$p"
    [[ "$XRAY80_PATH" == /* ]] || XRAY80_PATH="/$XRAY80_PATH"
  fi
  if [[ "$XRAY80_TRANSPORT" == 'grpc' ]]; then
    read -r -p "ServiceName gRPC [${XRAY80_GRPC_SERVICE}]: " s
    [[ -n "$s" ]] && XRAY80_GRPC_SERVICE="$s"
  fi
  if [[ "$XRAY80_TRANSPORT" == 'xhttp' ]]; then
    read -r -p "Modo XHTTP [${XRAY80_XHTTP_MODE}]: " m
    [[ -n "$m" ]] && XRAY80_XHTTP_MODE="$m"
  fi
  save_state
  [[ -x "$XRAY_BIN" ]] && build_xray_config || true
  write_haproxy_config || true
  echo -e "${C_GREEN}Perfil 80 aplicado: $(xray80_profile_name)${C_RESET}"
  pause
}

valid_username() {
  [[ "$1" =~ ^[A-Za-z0-9._-]{1,32}$ ]]
}

create_xray_user() {
  load_state
  ensure_dirs
  read -r -p 'Nombre del usuario V2RAY: ' name
  if ! valid_username "$name"; then
    echo 'Nombre invalido. Usa letras, numeros, punto, guion o guion bajo.'
    pause
    return 0
  fi
  if jq -e --arg n "$name" '.[] | select(.name==$n)' "$USERS_FILE" >/dev/null; then
    echo 'Ese usuario ya existe.'
    pause
    return 0
  fi
  local uuid password tmp
  if [[ -x "$XRAY_BIN" ]]; then
    uuid=$($XRAY_BIN uuid 2>/dev/null | head -n1)
  else
    uuid=$(uuidgen | tr 'A-F' 'a-f')
  fi
  password=$(openssl rand -hex 16)
  tmp=$(mktemp)
  jq --arg n "$name" --arg u "$uuid" --arg p "$password" '. + [{name:$n,uuid:$u,password:$p}]' "$USERS_FILE" > "$tmp" || { rm -f "$tmp"; return 1; }
  install -m 600 "$tmp" "$USERS_FILE"
  rm -f "$tmp"
  echo -e "${C_GREEN}Usuario creado: $name${C_RESET}"
  [[ -x "$XRAY_BIN" ]] && build_xray_config || true
  show_one_xray_user "$name"
  pause
}

delete_xray_user() {
  ensure_dirs
  local name tmp
  read -r -p 'Usuario V2RAY a eliminar: ' name
  if ! jq -e --arg n "$name" '.[] | select(.name==$n)' "$USERS_FILE" >/dev/null; then
    echo 'No existe.'
    pause
    return 0
  fi
  tmp=$(mktemp)
  jq --arg n "$name" '[.[] | select(.name!=$n)]' "$USERS_FILE" > "$tmp" || { rm -f "$tmp"; return 1; }
  install -m 600 "$tmp" "$USERS_FILE"
  rm -f "$tmp"
  [[ -x "$XRAY_BIN" ]] && build_xray_config || true
  echo -e "${C_GREEN}Usuario eliminado.${C_RESET}"
  pause
}

uri_encode() {
  jq -nr --arg v "$1" '$v|@uri'
}

show_one_xray_user() {
  load_state
  local name="$1" row uuid pass host label p_enc s_enc name_enc net vmjson link
  row=$(jq -c --arg n "$name" '.[] | select(.name==$n)' "$USERS_FILE" | head -n1)
  [[ -n "$row" ]] || return 1
  uuid=$(jq -r '.uuid' <<<"$row")
  pass=$(jq -r '.password' <<<"$row")
  host=$(host_for_clients)
  label="${name}-443"
  name_enc=$(uri_encode "$label")
  p_enc=$(uri_encode "$XRAY_PATH")
  s_enc=$(uri_encode "$XRAY_GRPC_SERVICE")

  bar
  echo -e "${C_WHITE}USUARIO:${C_RESET} $name"
  echo "Perfil : $(profile_name)"
  echo "Host   : $host"
  echo 'Puerto : 443'
  [[ -n "$DOMAIN" ]] && echo "SNI    : $DOMAIN"
  [[ "$CERT_MODE" == 'self-signed' ]] && echo -e "${C_GOLD}TLS inseguro/allowInsecure: ACTIVAR en el cliente${C_RESET}"

  case "$XRAY_PROTOCOL" in
    vless)
      case "$XRAY_TRANSPORT" in
        websocket)
          link="vless://${uuid}@${host}:443?encryption=none&security=tls&sni=$(uri_encode "$DOMAIN")&type=ws&host=$(uri_encode "$DOMAIN")&path=${p_enc}#${name_enc}"
          ;;
        xhttp)
          link="vless://${uuid}@${host}:443?encryption=none&security=tls&sni=$(uri_encode "$DOMAIN")&type=xhttp&path=${p_enc}&mode=$(uri_encode "$XRAY_XHTTP_MODE")#${name_enc}"
          ;;
        grpc)
          link="vless://${uuid}@${host}:443?encryption=none&security=tls&sni=$(uri_encode "$DOMAIN")&type=grpc&serviceName=${s_enc}#${name_enc}"
          ;;
        raw)
          link="vless://${uuid}@${host}:443?encryption=none&security=tls&sni=$(uri_encode "$DOMAIN")&type=tcp#${name_enc}"
          ;;
        httpupgrade)
          link="vless://${uuid}@${host}:443?encryption=none&security=tls&sni=$(uri_encode "$DOMAIN")&type=httpupgrade&host=$(uri_encode "$DOMAIN")&path=${p_enc}#${name_enc}"
          ;;
      esac
      echo "UUID   : $uuid"
      ;;
    vmess)
      case "$XRAY_TRANSPORT" in
        websocket) net='ws' ;;
        grpc) net='grpc' ;;
        raw) net='tcp' ;;
        xhttp) net='xhttp' ;;
        httpupgrade) net='httpupgrade' ;;
        *) net='tcp' ;;
      esac
      vmjson=$(jq -nc \
        --arg v '2' --arg ps "$label" --arg add "$host" --arg port '443' --arg id "$uuid" \
        --arg aid '0' --arg scy 'auto' --arg net "$net" --arg type 'none' \
        --arg host "$DOMAIN" --arg path "$XRAY_PATH" --arg tls 'tls' --arg sni "$DOMAIN" \
        --arg serviceName "$XRAY_GRPC_SERVICE" \
        '{v:$v,ps:$ps,add:$add,port:$port,id:$id,aid:$aid,scy:$scy,net:$net,type:$type,host:$host,path:(if $net=="grpc" then $serviceName else $path end),tls:$tls,sni:$sni}')
      link="vmess://$(printf '%s' "$vmjson" | base64 -w0)"
      echo "UUID   : $uuid"
      ;;
    trojan)
      link="trojan://${pass}@${host}:443?security=tls&sni=$(uri_encode "$DOMAIN")&type=tcp#${name_enc}"
      echo "Password: $pass"
      ;;
  esac

  case "$XRAY_TRANSPORT" in
    websocket|httpupgrade) echo "Path   : $XRAY_PATH" ;;
    xhttp) echo "Path   : $XRAY_PATH"; echo "XHTTP  : $XRAY_XHTTP_MODE" ;;
    grpc) echo "gRPC   : $XRAY_GRPC_SERVICE" ;;
  esac
  echo
  echo 'LINK:'
  echo "$link"
  bar
}

show_one_xray_user80() {
  load_state
  [[ "$XRAY80_ENABLED" == '1' ]] || return 0
  local name="$1" row uuid host label name_enc p_enc s_enc link vmjson net
  row=$(jq -c --arg n "$name" '.[] | select(.name==$n)' "$USERS_FILE" | head -n1)
  [[ -n "$row" ]] || return 1
  uuid=$(jq -r '.uuid' <<<"$row")
  host=$(host_for_clients)
  label="${name}-80"
  name_enc=$(uri_encode "$label")
  p_enc=$(uri_encode "$XRAY80_PATH")
  s_enc=$(uri_encode "$XRAY80_GRPC_SERVICE")
  echo
  echo -e "${C_GOLD}PUERTO 80 COMPARTIDO CON PROXYGO:${C_RESET}"
  echo "Perfil : $(xray80_profile_name)"
  echo "Host   : $host"
  echo 'Puerto : 80'
  echo 'TLS    : OFF'
  case "$XRAY80_PROTOCOL" in
    vless)
      case "$XRAY80_TRANSPORT" in
        websocket) link="vless://${uuid}@${host}:80?encryption=none&security=none&type=ws&host=$(uri_encode "$DOMAIN")&path=${p_enc}#${name_enc}" ;;
        xhttp) link="vless://${uuid}@${host}:80?encryption=none&security=none&type=xhttp&path=${p_enc}&mode=$(uri_encode "$XRAY80_XHTTP_MODE")#${name_enc}" ;;
        grpc) link="vless://${uuid}@${host}:80?encryption=none&security=none&type=grpc&serviceName=${s_enc}#${name_enc}" ;;
        httpupgrade) link="vless://${uuid}@${host}:80?encryption=none&security=none&type=httpupgrade&host=$(uri_encode "$DOMAIN")&path=${p_enc}#${name_enc}" ;;
      esac
      echo "UUID   : $uuid"
      ;;
    vmess)
      case "$XRAY80_TRANSPORT" in
        websocket) net='ws' ;;
        *) net="$XRAY80_TRANSPORT" ;;
      esac
      vmjson=$(jq -nc --arg v '2' --arg ps "$label" --arg add "$host" --arg port '80' --arg id "$uuid" --arg aid '0' --arg scy 'auto' --arg net "$net" --arg type 'none' --arg host "$DOMAIN" --arg path "$XRAY80_PATH" --arg tls '' '{v:$v,ps:$ps,add:$add,port:$port,id:$id,aid:$aid,scy:$scy,net:$net,type:$type,host:$host,path:$path,tls:$tls}')
      link="vmess://$(printf '%s' "$vmjson" | base64 -w0)"
      echo "UUID   : $uuid"
      ;;
  esac
  case "$XRAY80_TRANSPORT" in
    websocket|httpupgrade) echo "Path   : $XRAY80_PATH" ;;
    xhttp) echo "Path   : $XRAY80_PATH"; echo "XHTTP  : $XRAY80_XHTTP_MODE" ;;
    grpc) echo "gRPC   : $XRAY80_GRPC_SERVICE" ;;
  esac
  echo 'LINK 80:'
  echo "$link"
  bar
}

show_xray_users() {
  load_state
  ensure_dirs
  safe_clear
  bar
  echo -e "${C_GOLD}             USUARIOS + LINKS V2RAY/XRAY${C_RESET}"
  bar
  local count
  count=$(jq 'length' "$USERS_FILE")
  echo "Perfil actual: $(profile_name)"
  echo "Usuarios: $count"
  echo
  if [[ "$count" -eq 0 ]]; then
    echo 'No hay usuarios V2RAY creados.'
  else
    while IFS= read -r name; do
      show_one_xray_user "$name"
      show_one_xray_user80 "$name"
      echo
    done < <(jq -r '.[].name' "$USERS_FILE")
  fi
  write_info_file >/dev/null 2>&1 || true
  pause
}

create_ssh_user() {
  local user pass
  read -r -p 'Nuevo usuario SSH: ' user
  if ! [[ "$user" =~ ^[a-z_][a-z0-9_-]{0,30}$ ]]; then
    echo 'Nombre Linux invalido.'; pause; return 0
  fi
  if id "$user" >/dev/null 2>&1; then
    echo 'El usuario ya existe.'; pause; return 0
  fi
  read -r -s -p 'Password SSH: ' pass; echo
  [[ -n "$pass" ]] || { echo 'Password vacio no permitido.'; pause; return 0; }
  useradd -m -s /bin/bash "$user" || { pause; return 0; }
  printf '%s:%s\n' "$user" "$pass" | chpasswd
  echo -e "${C_GREEN}Usuario SSH creado.${C_RESET}"
  echo 'Conexion SSL: servidor/IP + puerto 443 + este usuario/password.'
  pause
}

delete_ssh_user() {
  local user
  read -r -p 'Usuario SSH a eliminar: ' user
  if [[ "$user" == 'root' ]]; then
    echo 'No se permite borrar root desde este manager.'; pause; return 0
  fi
  id "$user" >/dev/null 2>&1 || { echo 'No existe.'; pause; return 0; }
  userdel -r "$user" 2>/dev/null || userdel "$user"
  echo -e "${C_GREEN}Usuario SSH eliminado.${C_RESET}"
  pause
}

ssh_users_menu() {
  while true; do
    safe_clear
    bar
    echo -e "${C_GOLD}              USUARIOS SSH PARA SSL DIRECTO${C_RESET}"
    bar
    echo '[1] CREAR USUARIO SSH'
    echo '[2] ELIMINAR USUARIO SSH'
    echo '[3] MOSTRAR USUARIOS SSH'
    echo '[0] VOLVER'
    bar
    read -r -p 'Seleccione: ' op
    case "$op" in
      1) create_ssh_user ;;
      2) delete_ssh_user ;;
      3) awk -F: '$3>=1000 && $1!="nobody" {print $1}' /etc/passwd; pause ;;
      0) return 0 ;;
      *) echo 'Opcion invalida.'; sleep 1 ;;
    esac
  done
}

# =====================================================================
# PROXYGO NEW GOLDEN - MOTOR EXACTO DEL GOLDEN MX
# La logica del motor se conserva: 101 -> descarta payload inicial ->
# 200 <banner> -> tunel TCP al backend. Solo cambia el LISTEN del puerto 80:
# queda local 127.0.0.1:18080 para que HAProxy pueda compartir publicamente :80.
# =====================================================================
proxygo_compile_golden() {
  install_base || return 1
  mkdir -p "$PROXYGO_SRC_DIR" "$PROXYGO_DIR"
  cat > "$PROXYGO_SRC_DIR/main.go" <<'EOF'
package main

import (
	"flag"
	"fmt"
	"io"
	"net"
	"time"
)

func handle(client net.Conn, target string, banner string) {
	defer client.Close()

	if tcp, ok := client.(*net.TCPConn); ok {
		_ = tcp.SetNoDelay(true)
		_ = tcp.SetKeepAlive(true)
		_ = tcp.SetKeepAlivePeriod(60 * time.Second)
	}

	if banner == "" {
		banner = "OK"
	}

	// Primera respuesta fija
	_, _ = client.Write([]byte("HTTP/1.1 101 Connection Established\r\n\r\n"))

	// Leer y tirar payload inicial para que NO llegue al SSH
	client.SetReadDeadline(time.Now().Add(3 * time.Second))
	buffer := make([]byte, 1024)
	_, _ = client.Read(buffer)
	client.SetReadDeadline(time.Time{})

	// Aquí aparece el banner
	_, _ = client.Write([]byte(fmt.Sprintf("HTTP/1.1 200 %s\r\n\r\n", banner)))

	server, err := net.DialTimeout("tcp", target, 10*time.Second)
	if err != nil {
		return
	}
	defer server.Close()

	if tcp, ok := server.(*net.TCPConn); ok {
		_ = tcp.SetNoDelay(true)
		_ = tcp.SetKeepAlive(true)
		_ = tcp.SetKeepAlivePeriod(60 * time.Second)
	}

	done := make(chan struct{}, 2)

	go func() {
		_, _ = io.Copy(server, client)
		done <- struct{}{}
	}()

	go func() {
		_, _ = io.Copy(client, server)
		done <- struct{}{}
	}()

	<-done
}

func main() {
	listen := flag.String("listen", "0.0.0.0:80", "listen address")
	target := flag.String("target", "127.0.0.1:22", "target address")
	banner := flag.String("banner", "OK", "banner en respuesta 200")
	flag.Parse()

	ln, err := net.Listen("tcp", *listen)
	if err != nil {
		panic(err)
	}

	fmt.Println("ProxyGo ONLINE", *listen, "->", *target, "BANNER:", *banner)

	for {
		conn, err := ln.Accept()
		if err != nil {
			continue
		}
		go handle(conn, *target, *banner)
	}
}
EOF
  (cd "$PROXYGO_SRC_DIR" && go build -ldflags='-s -w' -o "$PROXYGO_BIN" main.go) || return 1
  chmod 755 "$PROXYGO_BIN"
  "$PROXYGO_BIN" -h >/dev/null 2>&1 || return 1
  sha256sum "$PROXYGO_BIN" > "$PROXYGO_DIR/.binary.sha256"
  printf 'NEW-GOLDEN exact-engine %s\n' "$(date '+%F %T')" > "$PROXYGO_DIR/.golden-installed"
}

proxygo_write_shared80_service() {
  load_state
  [[ -x "$PROXYGO_BIN" ]] || proxygo_compile_golden || return 1
  cat > /etc/systemd/system/proxygo_shared80.service <<EOF
[Unit]
Description=ProxyGo NEW GOLDEN shared public 80 backend
After=network-online.target ssh.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=${PROXYGO_BIN} -listen 127.0.0.1:${PROXYGO_LOCAL_PORT} -target 127.0.0.1:${PROXYGO_TARGET_PORT} -banner "${PROXYGO_BANNER}"
Restart=always
RestartSec=1
LimitNOFILE=262144
KillSignal=SIGTERM
TimeoutStartSec=15
TimeoutStopSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now proxygo_shared80.service >/dev/null 2>&1 || return 1
  write_haproxy_config >/dev/null 2>&1 || true
}

proxygo_write_extra_service() {
  local pub="$1" target="$2" banner="$3"
  [[ "$pub" =~ ^[0-9]+$ && "$pub" -ge 1 && "$pub" -le 65535 ]] || return 1
  [[ "$target" =~ ^[0-9]+$ && "$target" -ge 1 && "$target" -le 65535 ]] || return 1
  [[ "$pub" != '80' && "$pub" != '443' ]] || { echo '80 y 443 estan reservados para HAProxy compartido.'; return 1; }
  cat > "/etc/systemd/system/proxygo_${pub}.service" <<EOF
[Unit]
Description=ProxyGo NEW GOLDEN ${pub} to ${target}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${PROXYGO_BIN} -listen 0.0.0.0:${pub} -target 127.0.0.1:${target} -banner "${banner}"
Restart=always
RestartSec=1
LimitNOFILE=262144
KillSignal=SIGTERM
TimeoutStartSec=15
TimeoutStopSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now "proxygo_${pub}.service"
}

proxygo_extra_add() {
  [[ -x "$PROXYGO_BIN" ]] || { echo 'Primero instala ProxyGo.'; pause; return; }
  local target pub banner
  read -r -p 'Puerto local destino [22]: ' target; target="${target:-22}"
  ss -lnt 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)${target}$" || { echo 'Ese puerto local no esta escuchando.'; pause; return; }
  read -r -p 'Puerto publico ProxyGo dedicado: ' pub
  ss -lnt 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)${pub}$" && { echo 'Ese puerto ya esta en uso.'; pause; return; }
  read -r -p 'Banner [OK]: ' banner; banner="${banner:-OK}"
  if proxygo_write_extra_service "$pub" "$target" "$banner"; then echo 'Puerto ProxyGo agregado.'; else echo 'No se pudo agregar.'; fi
  pause
}

proxygo_extra_close() {
  local ports pub
  ports=$(find /etc/systemd/system -maxdepth 1 -type f -name 'proxygo_[0-9]*.service' -printf '%f\n' 2>/dev/null | sed -n 's/^proxygo_\([0-9][0-9]*\)\.service$/\1/p' | sort -n)
  [[ -n "$ports" ]] || { echo 'No hay puertos ProxyGo dedicados.'; pause; return; }
  echo "$ports" | sed 's/^/ - /'
  read -r -p 'Puerto a cerrar: ' pub
  echo "$ports" | grep -wxq "$pub" || { echo 'No pertenece a ProxyGo.'; pause; return; }
  systemctl disable --now "proxygo_${pub}.service" >/dev/null 2>&1 || true
  rm -f "/etc/systemd/system/proxygo_${pub}.service"
  systemctl daemon-reload
  echo "Puerto ${pub} cerrado."
  pause
}

proxygo_restart_all() {
  local u
  for u in proxygo_shared80.service /etc/systemd/system/proxygo_[0-9]*.service; do
    [[ "$u" == /* ]] && u=$(basename "$u")
    systemctl cat "$u" >/dev/null 2>&1 || continue
    systemctl restart "$u" >/dev/null 2>&1 || true
  done
}

proxygo_uninstall() {
  read -r -p 'Escribe SI para desinstalar ProxyGo: ' ok
  [[ "$ok" == 'SI' ]] || return
  local f
  systemctl disable --now proxygo_shared80.service >/dev/null 2>&1 || true
  for f in /etc/systemd/system/proxygo_[0-9]*.service; do
    [[ -e "$f" ]] || continue
    systemctl disable --now "$(basename "$f")" >/dev/null 2>&1 || true
  done
  rm -f /etc/systemd/system/proxygo_shared80.service /etc/systemd/system/proxygo_[0-9]*.service
  pkill -x proxygo >/dev/null 2>&1 || true
  rm -f "$PROXYGO_BIN"
  rm -rf "$PROXYGO_SRC_DIR" "$PROXYGO_DIR"
  systemctl daemon-reload
  write_haproxy_config >/dev/null 2>&1 || true
  echo 'ProxyGo eliminado; Xray/SSL permanecen.'
  pause
}

proxygo_menu() {
  while true; do
    load_state
    safe_clear
    bar
    echo -e "${C_GOLD}              PROXYGO - NEW GOLDEN (MOTOR GOLDEN MX)${C_RESET}"
    bar
    if [[ -x "$PROXYGO_BIN" ]]; then echo -e " CORE        : ${C_GREEN}INSTALADO${C_RESET}"; else echo -e " CORE        : ${C_RED}NO INSTALADO${C_RESET}"; fi
    printf ' SHARED 80   : '; onoff proxygo_shared80.service
    echo " BACKEND     : 127.0.0.1:${PROXYGO_TARGET_PORT}"
    echo " BANNER      : ${PROXYGO_BANNER}"
    echo ' PUBLICO 80  : HAProxy -> ProxyGo local 18080 (default)'
    bar
    echo '[1] INSTALAR / REPARAR PROXYGO GOLDEN'
    echo '[2] ACTIVAR / REPARAR PROXYGO EN 80 COMPARTIDO'
    echo '[3] CAMBIAR BACKEND LOCAL DEL PROXYGO 80'
    echo '[4] CAMBIAR BANNER DEL PROXYGO 80'
    echo '[5] AGREGAR PUERTO PROXYGO DEDICADO'
    echo '[6] CERRAR PUERTO PROXYGO DEDICADO'
    echo '[7] REINICIAR PROXYGO'
    echo '[8] DESINSTALAR PROXYGO'
    echo '[0] VOLVER'
    bar
    read -r -p 'Seleccione: ' op
    case "$op" in
      1) proxygo_compile_golden && proxygo_write_shared80_service; pause ;;
      2) proxygo_write_shared80_service; pause ;;
      3) read -r -p "Puerto local destino [${PROXYGO_TARGET_PORT}]: " p; [[ -n "$p" ]] && PROXYGO_TARGET_PORT="$p"; save_state; proxygo_write_shared80_service; pause ;;
      4) read -r -p "Banner [${PROXYGO_BANNER}]: " b; [[ -n "$b" ]] && PROXYGO_BANNER="$b"; save_state; proxygo_write_shared80_service; pause ;;
      5) proxygo_extra_add ;;
      6) proxygo_extra_close ;;
      7) proxygo_restart_all; echo 'ProxyGo reiniciado.'; pause ;;
      8) proxygo_uninstall ;;
      0) return ;;
      *) echo 'Opcion invalida.'; sleep 1 ;;
    esac
  done
}

status_general() {
  load_state
  safe_clear
  bar
  echo -e "${C_GOLD}     ESTADO SSL + XRAY + PROXYGO 80/443 - INDEPENDIENTE${C_RESET}"
  bar
  printf 'HAProxy      : '; onoff haproxy
  printf 'OpenSSH      : '; if service_is_active ssh || service_is_active sshd; then echo -e "${C_GREEN}ON${C_RESET}"; else echo -e "${C_RED}OFF${C_RESET}"; fi
  printf 'Xray         : '; onoff xray
  printf 'ProxyGo 80   : '; onoff proxygo_shared80.service
  echo "Xray 443     : $(profile_name)"
  echo "Xray 80      : $(xray80_profile_name)"
  echo "Certificado  : $CERT_MODE"
  echo "Dominio      : ${DOMAIN:-SIN DOMINIO}"
  echo "IP publica   : $(public_ip)"
  echo 'Publicos     : TCP/443 SSL+Xray | TCP/80 ProxyGo+Xray HTTP-like'
  echo "Locales      : SSH:22 XR443:${XRAY_PORT} XR80:${XRAY80_PORT} PG80:${PROXYGO_LOCAL_PORT}"
  echo "Usuarios XR  : $(jq 'length' "$USERS_FILE" 2>/dev/null || echo 0)"
  bar
  ss -lntp 2>/dev/null | grep -E '(:22|:80|:443|:10000|:10080|:18080)([[:space:]]|$)' || echo 'No se detectaron los puertos esperados.'
  bar
  pause
}

diagnostics() {
  load_state
  safe_clear
  bar
  echo -e "${C_GOLD}                    DIAGNOSTICO${C_RESET}"
  bar
  echo '[HAProxy config]'
  if command -v haproxy >/dev/null 2>&1 && [[ -f "$HA_CFG" ]]; then
    haproxy -c -f "$HA_CFG" || true
  else
    echo 'HAProxy no instalado/configurado.'
  fi
  echo
  echo '[Xray config]'
  if [[ -x "$XRAY_BIN" && -f "$XRAY_CONFIG" ]]; then
    "$XRAY_BIN" run -test -config "$XRAY_CONFIG" 2>&1 || "$XRAY_BIN" -test -config "$XRAY_CONFIG" 2>&1 || true
  else
    echo 'Xray no instalado/configurado.'
  fi
  echo
  echo '[Servicios]'
  systemctl --no-pager --full status haproxy xray ssh proxygo_shared80 2>/dev/null | sed -n '1,100p' || true
  echo
  echo '[Ultimos logs HAProxy/Xray]'
  journalctl -u haproxy -u xray -u proxygo_shared80 -n 50 --no-pager 2>/dev/null || true
  pause
}

restart_services() {
  systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
  systemctl restart xray 2>/dev/null || true
  proxygo_restart_all
  systemctl restart haproxy 2>/dev/null || true
  echo -e "${C_GREEN}Servicios reiniciados.${C_RESET}"
  pause
}

renew_certificate() {
  load_state
  if [[ "$CERT_MODE" != 'letsencrypt' || -z "$DOMAIN" ]]; then
    echo 'No hay certificado Lets Encrypt activo. Usa CONFIGURAR CERTIFICADO.'
    pause
    return 0
  fi
  certbot renew --force-renewal || true
  if [[ -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]]; then
    cat "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" "/etc/letsencrypt/live/${DOMAIN}/privkey.pem" > "$HA_CERT"
    chmod 600 "$HA_CERT"
    systemctl reload haproxy || true
  fi
  pause
}

optimize_100_clients() {
  cat > /etc/sysctl.d/99-ssl-xray-proxygo-manager.conf <<'EOF'
# Perfil conservador para VPS pequeña (~100 clientes, no necesariamente 100 saturando 1Gbps).
fs.file-max = 524288
net.core.somaxconn = 8192
net.core.netdev_max_backlog = 16384
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_fin_timeout = 20
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_tw_reuse = 1
EOF
  if modprobe tcp_bbr >/dev/null 2>&1 && sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -qw bbr; then
    cat >> /etc/sysctl.d/99-ssl-xray-proxygo-manager.conf <<'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
  fi
  sysctl --system >/dev/null 2>&1 || true
  mkdir -p /etc/systemd/system/haproxy.service.d /etc/systemd/system/xray.service.d
  cat > /etc/systemd/system/haproxy.service.d/99-shared-manager.conf <<'EOF'
[Unit]
After=network-online.target
Wants=network-online.target
[Service]
Restart=always
RestartSec=1
LimitNOFILE=262144
EOF
  cat > /etc/systemd/system/xray.service.d/99-shared-manager.conf <<'EOF'
[Unit]
After=network-online.target
Wants=network-online.target
[Service]
Restart=always
RestartSec=1
LimitNOFILE=262144
EOF
  systemctl daemon-reload
  enable_boot_fast
  echo -e "${C_GREEN}Perfil conservador ~100 clientes aplicado.${C_RESET}"
  echo 'El limite real seguira dependiendo de CPU, cifrado y fair-share/ancho de banda del VPS.'
  [[ "${1:-}" == '--no-pause' ]] || pause
}

enable_boot_fast() {
  systemctl enable ssh >/dev/null 2>&1 || systemctl enable sshd >/dev/null 2>&1 || true
  systemctl enable haproxy >/dev/null 2>&1 || true
  [[ -f /etc/systemd/system/xray.service || -f /lib/systemd/system/xray.service ]] && systemctl enable xray >/dev/null 2>&1 || true
  [[ -f /etc/systemd/system/proxygo_shared80.service ]] && systemctl enable proxygo_shared80 >/dev/null 2>&1 || true
  local f
  for f in /etc/systemd/system/proxygo_[0-9]*.service; do [[ -e "$f" ]] && systemctl enable "$(basename "$f")" >/dev/null 2>&1 || true; done
  systemctl daemon-reload
  systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
  [[ -f /etc/systemd/system/xray.service || -f /lib/systemd/system/xray.service ]] && systemctl restart xray >/dev/null 2>&1 || true
  [[ -f /etc/systemd/system/proxygo_shared80.service ]] && systemctl restart proxygo_shared80 >/dev/null 2>&1 || true
  systemctl restart haproxy >/dev/null 2>&1 || true
}

boot_test() {
  enable_boot_fast
  safe_clear
  bar
  echo -e "${C_GOLD}             AUTO-BOOT / PUERTOS DESPUES DE REINICIO${C_RESET}"
  bar
  systemctl is-enabled haproxy 2>/dev/null || true
  systemctl is-enabled xray 2>/dev/null || true
  systemctl is-enabled proxygo_shared80 2>/dev/null || true
  echo
  ss -lntp 2>/dev/null | grep -E '(:80|:443|:10000|:10080|:18080)([[:space:]]|$)' || true
  bar
  echo 'Los servicios usan systemd enable + Restart=always/RestartSec=1.'
  pause
}

write_info_file() {
  load_state
  ensure_dirs
  local host
  host=$(host_for_clients)
  {
    echo 'SSL + V2RAY/XRAY 443 MANAGER'
    echo '================================'
    echo "Host/IP      : $host"
    echo 'Puertos publicos: 443 TCP (SSL+Xray) / 80 TCP (ProxyGo+Xray HTTP-like)'
    echo "Certificado  : $CERT_MODE"
    echo "Dominio/SNI  : ${DOMAIN:-SIN DOMINIO}"
    echo
    echo 'SSL DIRECTO / SSH'
    echo '-----------------'
    echo "Servidor : $host"
    echo 'Puerto   : 443'
    echo 'Backend  : OpenSSH local :22'
    echo
    echo 'PROXYGO NEW GOLDEN'
    echo '------------------'
    echo 'Publico  : 80 (a traves de HAProxy)'
    echo "Local    : 127.0.0.1:${PROXYGO_LOCAL_PORT}"
    echo "Destino  : 127.0.0.1:${PROXYGO_TARGET_PORT}"
    echo "Banner   : ${PROXYGO_BANNER}"
    echo
    echo 'V2RAY/XRAY'
    echo '-----------'
    echo "Perfil   : $(profile_name)"
    echo "Local    : 127.0.0.1:${XRAY_PORT}"
    case "$XRAY_TRANSPORT" in
      websocket|httpupgrade) echo "Path     : $XRAY_PATH" ;;
      xhttp) echo "Path     : $XRAY_PATH"; echo "Mode     : $XRAY_XHTTP_MODE" ;;
      grpc) echo "Service  : $XRAY_GRPC_SERVICE" ;;
    esac
    echo
    echo 'Usuarios V2Ray:'
    jq -r '.[] | "- " + .name + " UUID=" + .uuid + " PASS=" + .password' "$USERS_FILE" 2>/dev/null || true
  } > "$INFO_FILE"
  chmod 600 "$INFO_FILE"
}

install_everything() {
  load_state
  install_base || { pause; return 0; }
  if [[ ! -s "$HA_CERT" ]]; then configure_certificate || { pause; return 0; }; fi
  install_xray_core || { pause; return 0; }
  if [[ $(jq 'length' "$USERS_FILE" 2>/dev/null || echo 0) -eq 0 ]]; then
    local uuid pass
    uuid=$($XRAY_BIN uuid 2>/dev/null | head -n1); [[ -n "$uuid" ]] || uuid=$(uuidgen | tr 'A-F' 'a-f')
    pass=$(openssl rand -hex 16)
    jq -n --arg u "$uuid" --arg p "$pass" '[{name:"cliente1",uuid:$u,password:$p}]' > "$USERS_FILE"
    chmod 600 "$USERS_FILE"
  fi
  proxygo_compile_golden || { pause; return 0; }
  proxygo_write_shared80_service || { pause; return 0; }
  build_xray_config || { pause; return 0; }
  write_haproxy_config || { pause; return 0; }
  optimize_100_clients --no-pause >/dev/null 2>&1 || true
  enable_boot_fast
  write_info_file
  echo -e "${C_GREEN}INSTALACION BASE COMPLETA: 443 + 80 COMPARTIDOS.${C_RESET}"
  echo '443: SSL directo + Xray | 80: ProxyGo NEW GOLDEN + Xray HTTP-like opcional'
  pause
}

uninstall_xray_only() {
  read -r -p 'Escribe SI para desinstalar SOLO Xray: ' ok
  [[ "$ok" == 'SI' ]] || return 0
  if [[ -f /tmp/xray-install-release.sh ]]; then
    bash /tmp/xray-install-release.sh remove --purge || true
  else
    curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh -o /tmp/xray-install-release.sh && bash /tmp/xray-install-release.sh remove --purge || true
  fi
  rm -f "$XRAY_CONFIG"
  echo 'Xray eliminado. HAProxy SSL/SSH queda intacto.'
  pause
}

uninstall_all() {
  read -r -p 'PELIGRO: escribe BORRAR para quitar HAProxy/Xray y este manager: ' ok
  [[ "$ok" == 'BORRAR' ]] || return 0
  systemctl disable --now xray 2>/dev/null || true
  systemctl disable --now haproxy 2>/dev/null || true
  if [[ -f /tmp/xray-install-release.sh ]]; then
    bash /tmp/xray-install-release.sh remove --purge || true
  fi
  # Restore earliest backups when available.
  local hbak xbak
  hbak=$(find "$BACKUP_DIR" -maxdepth 1 -name 'haproxy.cfg-*.bak' | sort | head -n1)
  xbak=$(find "$BACKUP_DIR" -maxdepth 1 -name 'xray-config.json-*.bak' | sort | head -n1)
  [[ -n "$hbak" ]] && cp -a "$hbak" "$HA_CFG"
  [[ -n "$xbak" ]] && cp -a "$xbak" "$XRAY_CONFIG"
  rm -f /etc/sysctl.d/99-ssl-v2ray443-manager.conf /etc/sysctl.d/99-ssl-xray-proxygo-manager.conf
  rm -rf /etc/systemd/system/haproxy.service.d /etc/systemd/system/xray.service.d
  rm -f /etc/letsencrypt/renewal-hooks/deploy/ssl-v2ray443-haproxy.sh
  systemctl daemon-reload
  echo 'Desinstalacion terminada. Los usuarios Linux/SSH no fueron borrados.'
  pause
}

main_menu() {
  while true; do
    load_state
    safe_clear
    bar
    echo -e "${C_GOLD} SSL + V2RAY/XRAY + PROXYGO [ 80/443 SHARED MANAGER ]${C_RESET}"
    bar
    printf ' HAPROXY     : '; if service_is_active haproxy; then echo -e "${C_GREEN}ACTIVO${C_RESET}"; else echo -e "${C_RED}INACTIVO${C_RESET}"; fi
    printf ' XRAY        : '; if service_is_active xray; then echo -e "${C_GREEN}ACTIVO${C_RESET}"; else echo -e "${C_RED}INACTIVO${C_RESET}"; fi
    printf ' PROXYGO 80  : '; if service_is_active proxygo_shared80; then echo -e "${C_GREEN}ACTIVO${C_RESET}"; else echo -e "${C_RED}INACTIVO${C_RESET}"; fi
    echo " XRAY 443    : $(profile_name)"
    echo " XRAY 80     : $(xray80_profile_name)"
    echo ' PUBLICOS    : TCP 443 + TCP 80 COMPARTIDOS'
    bar
    echo '[1]  INSTALAR / PREPARAR TODO'
    echo '[2]  HAPROXY SSL DIRECTO + SHARING 443/80'
    echo '[3]  CONFIGURAR / RENOVAR CERTIFICADO TLS'
    echo '[4]  PROXYGO NEW GOLDEN (IGUAL MOTOR GOLDEN MX)'
    echo '[5]  INSTALAR / ACTUALIZAR XRAY-CORE'
    echo '[6]  ELEGIR V2RAY/XRAY PARA PUERTO 443'
    echo '[7]  ELEGIR V2RAY/XRAY PARA PUERTO 80 COMPARTIDO'
    echo '[8]  CREAR USUARIO V2RAY'
    echo '[9]  ELIMINAR USUARIO V2RAY'
    echo '[10] MOSTRAR USUARIOS + LINKS V2RAY 443'
    echo '[11] USUARIOS SSH PARA SSL DIRECTO'
    echo '[12] ESTADO GENERAL / PUERTOS'
    echo '[13] DIAGNOSTICO'
    echo '[14] REINICIAR SERVICIOS'
    echo '[15] OPTIMIZAR VPS ~100 CLIENTES'
    echo '[16] AUTO-BOOT / LEVANTAR PUERTOS AL REINICIAR'
    echo '[17] DESINSTALAR SOLO XRAY'
    echo '[18] DESINSTALAR TODO EL MANAGER'
    echo '[0]  SALIR'
    bar
    read -r -p 'Seleccione una Opcion: ' op
    case "$op" in
      1) install_everything ;;
      2) install_haproxy_ssl; write_haproxy_config; pause ;;
      3) configure_certificate; pause ;;
      4) proxygo_menu ;;
      5) install_xray_core; build_xray_config >/dev/null 2>&1 || true; enable_boot_fast; pause ;;
      6) choose_xray_profile ;;
      7) choose_xray80_profile ;;
      8) create_xray_user ;;
      9) delete_xray_user ;;
      10) show_xray_users ;;
      11) ssh_users_menu ;;
      12) status_general ;;
      13) diagnostics ;;
      14) restart_services ;;
      15) optimize_100_clients ;;
      16) boot_test ;;
      17) uninstall_xray_only ;;
      18) uninstall_all ;;
      0) safe_clear; exit 0 ;;
      *) echo 'Opcion invalida.'; sleep 1 ;;
    esac
  done
}

require_root
ensure_dirs
load_state
main_menu
