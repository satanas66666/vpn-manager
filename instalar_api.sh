#!/usr/bin/env bash
set -Eeuo pipefail

# =====================================================================
# API VPS PRO / CheckUser - UNIVERSAL UBUNTU + DEBIAN
# Compatibilidad practica:
#   - Ubuntu 14.04+ (incluye 16/18/20/22/24 y posteriores)
#   - Debian 7+ (incluye 8/9/10/11/12/13 y posteriores)
# Requisito tecnico: PHP CLI >= 5.4 (php -S existe desde PHP 5.4).
#
# Conserva:
#   RUTA     /etc/chido
#   PUERTO   8888/TCP
#   SERVICIO api-vps
#   TOKEN    ULTRA_SECRET_TOKEN
#   API      /api.php -> GET = pong / POST = acciones CheckUser
#
# El instalador detecta systemd o SysV/Upstart, PHP moderno o php5-cli,
# ss/netstat, UFW/firewalld y valida que el 8888 realmente responda.
# =====================================================================

RUTA="/etc/chido"
PUERTO="8888"
SERVICIO="api-vps"
TOKEN="ULTRA_SECRET_TOKEN"
PIDFILE="/var/run/${SERVICIO}.pid"
LOGFILE="/var/log/${SERVICIO}.log"

GOLD='\033[1;33m'
GREEN='\033[1;32m'
RED='\033[1;31m'
CYAN='\033[1;36m'
RESET='\033[0m'
BAR='=×=×=×=×=×=×=×=×=×=×=×=×=×=×=×=×=×=×=×=×=×=×=×=×=×=×=×=×=×='

msg() { echo -e "$*"; }
fail() { msg "${RED}ERROR:${RESET} $*"; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    fail "Ejecuta como root: sudo bash $0"
fi

# ---------------------------------------------------------------------
# Detectar distro/version incluso en sistemas sin /etc/os-release.
# ---------------------------------------------------------------------
DISTRO="unknown"
VERSION_ID="unknown"
PRETTY_NAME="Linux"

if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    DISTRO="${ID:-unknown}"
    VERSION_ID="${VERSION_ID:-unknown}"
    PRETTY_NAME="${PRETTY_NAME:-$DISTRO $VERSION_ID}"
elif have lsb_release; then
    DISTRO="$(lsb_release -si 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)"
    VERSION_ID="$(lsb_release -sr 2>/dev/null || true)"
    PRETTY_NAME="$(lsb_release -ds 2>/dev/null | tr -d '"' || true)"
elif [[ -r /etc/debian_version ]]; then
    DISTRO="debian"
    VERSION_ID="$(cat /etc/debian_version 2>/dev/null || echo unknown)"
    PRETTY_NAME="Debian ${VERSION_ID}"
fi

case "$DISTRO" in
    ubuntu|debian|linuxmint|raspbian) : ;;
    *)
        if [[ -r /etc/debian_version ]]; then
            msg "${GOLD}Aviso:${RESET} distro derivada de Debian detectada (${PRETTY_NAME}); se intentara modo compatible APT."
        else
            fail "Este instalador esta diseñado para Ubuntu/Debian y derivados con APT. Detectado: ${PRETTY_NAME}"
        fi
        ;;
esac

have apt-get || fail "No se encontro apt-get."

msg "${GOLD}${BAR}${RESET}"
msg "${GOLD}       API VPS PRO - UBUNTU / DEBIAN UNIVERSAL${RESET}"
msg "${GOLD}${BAR}${RESET}"
msg "Sistema  : ${PRETTY_NAME}"
msg "Puerto   : ${PUERTO}/TCP"
msg "Servicio : ${SERVICIO}"

# ---------------------------------------------------------------------
# APT robusto: primero usa repos actuales. No reescribe sources.list
# automaticamente: hacerlo en sistemas EOL puede romper repos privados.
# ---------------------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
APT_UPDATED=0
apt_update_once() {
    if [[ "$APT_UPDATED" -eq 0 ]]; then
        if apt-get update -y; then
            APT_UPDATED=1
        else
            msg "${GOLD}Aviso:${RESET} apt-get update fallo. Si es una distro EOL, revisa sus repositorios archivados."
            return 1
        fi
    fi
    return 0
}

apt_try_install() {
    local pkg="$1"
    apt-get install -y --no-install-recommends "$pkg" >/dev/null 2>&1
}

msg "${CYAN}[1/8] Detectando/instalando dependencias...${RESET}"

# Herramientas basicas. Instalamos solo lo que falte.
if ! have curl; then apt_update_once || true; apt_try_install curl || fail "No se pudo instalar curl."; fi
if ! have pkill; then apt_update_once || true; apt_try_install procps || true; fi
if ! have killall; then apt_update_once || true; apt_try_install psmisc || true; fi
if ! have ss && ! have netstat; then
    apt_update_once || true
    apt_try_install iproute2 || apt_try_install iproute || apt_try_install net-tools || true
fi
if ! have netstat; then apt_try_install net-tools || true; fi
if [[ ! -e /etc/ssl/certs/ca-certificates.crt ]]; then apt_try_install ca-certificates || true; fi

# PHP: en distros modernas es php-cli; en las antiguas php5-cli.
PHP_BIN="$(command -v php 2>/dev/null || true)"
if [[ -z "$PHP_BIN" ]]; then
    apt_update_once || true
    apt_try_install php-cli || apt_try_install php5-cli || true
    PHP_BIN="$(command -v php 2>/dev/null || true)"
fi
[[ -n "$PHP_BIN" && -x "$PHP_BIN" ]] || fail "No se pudo instalar/detectar PHP CLI (php-cli/php5-cli)."

PHP_VERSION="$($PHP_BIN -r 'echo PHP_VERSION;' 2>/dev/null || echo unknown)"
PHP_OK="$($PHP_BIN -r 'echo version_compare(PHP_VERSION,"5.4.0",">=") ? "1" : "0";' 2>/dev/null || echo 0)"
[[ "$PHP_OK" == "1" ]] || fail "PHP ${PHP_VERSION} es demasiado antiguo. Se requiere PHP >= 5.4 para el servidor embebido php -S."
msg "${GREEN}PHP detectado:${RESET} ${PHP_VERSION} (${PHP_BIN})"

# Firewall helpers son opcionales. No activamos un firewall que estaba apagado.
if ! have ufw && [[ "$DISTRO" == "ubuntu" ]]; then
    apt_try_install ufw || true
fi

# ---------------------------------------------------------------------
# Detectar init system.
# ---------------------------------------------------------------------
INIT_MODE="sysv"
if have systemctl && [[ -d /run/systemd/system ]]; then
    INIT_MODE="systemd"
fi
msg "Init     : ${INIT_MODE}"

service_stop() {
    if [[ "$INIT_MODE" == "systemd" ]]; then
        systemctl stop "$SERVICIO" 2>/dev/null || true
        systemctl disable "$SERVICIO" 2>/dev/null || true
    else
        if [[ -x "/etc/init.d/${SERVICIO}" ]]; then
            service "$SERVICIO" stop 2>/dev/null || "/etc/init.d/${SERVICIO}" stop 2>/dev/null || true
            update-rc.d -f "$SERVICIO" remove >/dev/null 2>&1 || true
        fi
        if [[ -f "$PIDFILE" ]]; then
            local oldpid
            oldpid="$(cat "$PIDFILE" 2>/dev/null || true)"
            [[ -z "$oldpid" ]] || kill "$oldpid" 2>/dev/null || true
            rm -f "$PIDFILE"
        fi
    fi
}

service_start() {
    if [[ "$INIT_MODE" == "systemd" ]]; then
        systemctl daemon-reload
        systemctl enable "$SERVICIO" >/dev/null
        systemctl restart "$SERVICIO"
    else
        update-rc.d "$SERVICIO" defaults >/dev/null 2>&1 || true
        service "$SERVICIO" restart 2>/dev/null || "/etc/init.d/${SERVICIO}" restart
    fi
}

service_active() {
    if [[ "$INIT_MODE" == "systemd" ]]; then
        systemctl is-active --quiet "$SERVICIO"
    else
        if [[ -f "$PIDFILE" ]]; then
            local pid
            pid="$(cat "$PIDFILE" 2>/dev/null || true)"
            [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
        else
            return 1
        fi
    fi
}

port_listening() {
    if have ss; then
        ss -lnt 2>/dev/null | grep -Eq "(^|[.:])${PUERTO}[[:space:]]"
    elif have netstat; then
        netstat -lnt 2>/dev/null | grep -Eq "(^|[.:])${PUERTO}[[:space:]]"
    else
        return 1
    fi
}

port_details() {
    if have ss; then
        ss -lntp 2>/dev/null | grep -E "(^|[.:])${PUERTO}([[:space:]]|$)" || true
    elif have netstat; then
        netstat -lntp 2>/dev/null | grep -E "(^|[.:])${PUERTO}([[:space:]]|$)" || true
    fi
}

# ---------------------------------------------------------------------
# Limpiar solo la API anterior y comprobar colisiones en 8888.
# ---------------------------------------------------------------------
msg "${CYAN}[2/8] Preparando instalacion...${RESET}"
service_stop
rm -f "/etc/systemd/system/${SERVICIO}.service" 2>/dev/null || true
rm -f "/lib/systemd/system/${SERVICIO}.service" 2>/dev/null || true
rm -f "/etc/init.d/${SERVICIO}" 2>/dev/null || true

# Esperar un momento a que el socket anterior cierre.
sleep 1
if port_listening; then
    msg "${RED}El puerto ${PUERTO} ya esta ocupado por otro proceso.${RESET}"
    port_details
    fail "Libera TCP ${PUERTO} antes de instalar la API. No se mato ningun servicio ajeno automaticamente."
fi

mkdir -p "$RUTA" /etc/SSHPlus/blocked /etc/SSHPlus/limits /etc/SSHPlus/abuse
chmod 755 "$RUTA"

# ---------------------------------------------------------------------
# API PHP compatible con PHP 5.4+ (sin ?? ni sintaxis moderna obligatoria).
# ---------------------------------------------------------------------
msg "${CYAN}[3/8] Escribiendo API compatible...${RESET}"
cat > "$RUTA/api.php" <<'PHPAPI'
<?php
error_reporting(E_ALL);
ini_set('display_errors', '1');

function set_code($code) {
    if (function_exists('http_response_code')) {
        http_response_code($code);
    } else {
        $texts = array(200=>'OK', 400=>'Bad Request', 403=>'Forbidden', 404=>'Not Found');
        $text = isset($texts[$code]) ? $texts[$code] : 'Status';
        header('HTTP/1.1 ' . $code . ' ' . $text);
    }
}

function safe_equals($known, $user) {
    $known = (string)$known;
    $user = (string)$user;
    if (function_exists('hash_equals')) {
        return hash_equals($known, $user);
    }
    if (strlen($known) !== strlen($user)) return false;
    $result = 0;
    $len = strlen($known);
    for ($i = 0; $i < $len; $i++) {
        $result |= ord($known[$i]) ^ ord($user[$i]);
    }
    return $result === 0;
}

function run_cmd($cmd) {
    return shell_exec($cmd . ' 2>&1');
}

// GET/HEAD = health check del Monitor VPS.
if (!isset($_SERVER['REQUEST_METHOD']) || $_SERVER['REQUEST_METHOD'] !== 'POST') {
    set_code(200);
    header('Content-Type: text/plain; charset=UTF-8');
    echo 'pong';
    exit;
}

$TOKEN = 'ULTRA_SECRET_TOKEN';
$raw = file_get_contents('php://input');
$data = json_decode($raw, true);

if (!is_array($data)) {
    set_code(400);
    exit('JSON inválido');
}

if (!isset($data['token']) || !safe_equals($TOKEN, $data['token'])) {
    set_code(403);
    exit('No autorizado');
}

$user   = preg_replace('/[^a-zA-Z0-9]/', '', isset($data['user']) ? $data['user'] : '');
$pass   = isset($data['pass']) ? $data['pass'] : '';
$dias   = isset($data['dias']) ? intval($data['dias']) : 0;
$accion = isset($data['accion']) ? $data['accion'] : '';
$fecha  = isset($data['fecha']) ? $data['fecha'] : '';
$limite = isset($data['limite']) ? intval($data['limite']) : 0;

$requires_user = array('crear','eliminar','bloquear','desbloquear','editar','reset');
if (in_array($accion, $requires_user, true) && $user === '') {
    set_code(400);
    exit('Usuario inválido');
}

switch ($accion) {
    case 'crear':
        run_cmd('id ' . escapeshellarg($user) . ' || useradd -M -s /bin/false ' . escapeshellarg($user));
        if ($pass !== '') {
            run_cmd('echo ' . escapeshellarg($user . ':' . $pass) . ' | chpasswd');
        }
        if ($fecha !== '') {
            run_cmd('chage -E ' . escapeshellarg($fecha) . ' ' . escapeshellarg($user));
        } elseif ($dias > 0) {
            $exp = date('Y-m-d', strtotime('+' . $dias . ' days'));
            run_cmd('chage -E ' . escapeshellarg($exp) . ' ' . escapeshellarg($user));
        }
        if ($limite > 0) {
            if (!is_dir('/etc/SSHPlus/limits')) @mkdir('/etc/SSHPlus/limits', 0755, true);
            file_put_contents('/etc/SSHPlus/limits/' . $user, (string)$limite);
        }
        break;

    case 'eliminar':
        run_cmd('pkill -KILL -u ' . escapeshellarg($user));
        run_cmd('killall -u ' . escapeshellarg($user));
        run_cmd('userdel -f ' . escapeshellarg($user));
        @unlink('/etc/SSHPlus/limits/' . $user);
        @unlink('/etc/SSHPlus/blocked/' . $user);
        @unlink('/etc/SSHPlus/abuse/' . $user);
        break;

    case 'bloquear':
        run_cmd('usermod -L ' . escapeshellarg($user));
        run_cmd('usermod -s /bin/false ' . escapeshellarg($user));
        run_cmd('pkill -KILL -u ' . escapeshellarg($user));
        file_put_contents('/etc/SSHPlus/blocked/' . $user, 'blocked');
        break;

    case 'desbloquear':
        run_cmd('usermod -U ' . escapeshellarg($user));
        run_cmd('usermod -s /bin/bash ' . escapeshellarg($user));
        @unlink('/etc/SSHPlus/blocked/' . $user);
        break;

    case 'editar':
        if ($dias > 0) {
            $raw_exp = run_cmd('LC_ALL=C chage -l ' . escapeshellarg($user) . " | grep 'Account expires'");
            $fecha_actual = '';
            if ($raw_exp) {
                $parts = explode(':', $raw_exp, 2);
                $fecha_actual = isset($parts[1]) ? trim($parts[1]) : '';
            }
            if ($fecha_actual === '' || strtolower($fecha_actual) === 'never') {
                $base = time();
            } else {
                $base = strtotime($fecha_actual);
                if ($base === false || $base < time()) $base = time();
            }
            $nueva = strtotime('+' . $dias . ' days', $base);
            run_cmd('chage -E ' . escapeshellarg(date('Y-m-d', $nueva)) . ' ' . escapeshellarg($user));
        }
        if ($fecha !== '') {
            run_cmd('chage -E ' . escapeshellarg($fecha) . ' ' . escapeshellarg($user));
        }
        break;

    case 'reset':
        if ($pass !== '') {
            run_cmd('echo ' . escapeshellarg($user . ':' . $pass) . ' | chpasswd');
        }
        break;

    case 'limpiar_expirados':
        $list = shell_exec("awk -F: '$3>=1000 {print $1}' /etc/passwd");
        $users = explode("\n", trim((string)$list));
        foreach ($users as $u) {
            $u = preg_replace('/[^a-zA-Z0-9]/', '', $u);
            if ($u === '') continue;
            if (file_exists('/etc/SSHPlus/blocked/' . $u)) continue;

            $expire_raw = shell_exec('LC_ALL=C chage -l ' . escapeshellarg($u) . " 2>/dev/null | grep 'Account expires'");
            $expire = '';
            if ($expire_raw) {
                $parts = explode(':', $expire_raw, 2);
                $expire = isset($parts[1]) ? trim($parts[1]) : '';
            }
            if ($expire === '' || strtolower($expire) === 'never') continue;
            $exp_date = strtotime($expire);
            if (!$exp_date) continue;

            if (time() >= $exp_date) {
                run_cmd('pkill -KILL -u ' . escapeshellarg($u));
                run_cmd('killall -u ' . escapeshellarg($u));
                run_cmd('userdel -f ' . escapeshellarg($u));
                @unlink('/etc/SSHPlus/limits/' . $u);
                @unlink('/etc/SSHPlus/blocked/' . $u);
                @unlink('/etc/SSHPlus/abuse/' . $u);
            }
        }
        echo 'cleaned';
        exit;

    default:
        set_code(400);
        exit('Acción inválida');
}

echo 'OK';
PHPAPI

cat > "$RUTA/router.php" <<'PHPROUTER'
<?php
$path = '/';
if (isset($_SERVER['REQUEST_URI'])) {
    $parsed = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
    if ($parsed !== false && $parsed !== null) $path = urldecode($parsed);
}
if ($path === '/api.php' || $path === '/') {
    require dirname(__FILE__) . '/api.php';
    return true;
}
if (function_exists('http_response_code')) http_response_code(404);
else header('HTTP/1.1 404 Not Found');
echo 'not found';
return true;
PHPROUTER

chmod 644 "$RUTA/api.php" "$RUTA/router.php"
"$PHP_BIN" -l "$RUTA/api.php" >/dev/null || fail "api.php tiene error de sintaxis."
"$PHP_BIN" -l "$RUTA/router.php" >/dev/null || fail "router.php tiene error de sintaxis."

# ---------------------------------------------------------------------
# Crear arranque automatico para systemd o SysV/Upstart.
# ---------------------------------------------------------------------
msg "${CYAN}[4/8] Configurando arranque automatico...${RESET}"
if [[ "$INIT_MODE" == "systemd" ]]; then
    cat > "/etc/systemd/system/${SERVICIO}.service" <<EOF_SYSTEMD
[Unit]
Description=API VPS PRO CheckUser
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${RUTA}
ExecStart=${PHP_BIN} -S 0.0.0.0:${PUERTO} ${RUTA}/router.php
Restart=always
RestartSec=2
TimeoutStopSec=10
KillSignal=SIGTERM

[Install]
WantedBy=multi-user.target
EOF_SYSTEMD
else
    cat > "/etc/init.d/${SERVICIO}" <<EOF_SYSV
#!/bin/sh
### BEGIN INIT INFO
# Provides:          ${SERVICIO}
# Required-Start:    \$remote_fs \$network
# Required-Stop:     \$remote_fs \$network
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: API VPS PRO CheckUser
### END INIT INFO

NAME="${SERVICIO}"
PHP_BIN="${PHP_BIN}"
RUTA="${RUTA}"
PUERTO="${PUERTO}"
PIDFILE="${PIDFILE}"
LOGFILE="${LOGFILE}"

is_running() {
    [ -f "\$PIDFILE" ] || return 1
    PID=\$(cat "\$PIDFILE" 2>/dev/null)
    [ -n "\$PID" ] && kill -0 "\$PID" 2>/dev/null
}

start_api() {
    if is_running; then return 0; fi
    cd "\$RUTA" || exit 1
    if command -v start-stop-daemon >/dev/null 2>&1; then
        start-stop-daemon --start --background --make-pidfile --pidfile "\$PIDFILE" \
            --chdir "\$RUTA" --exec "\$PHP_BIN" -- -S 0.0.0.0:"\$PUERTO" "\$RUTA/router.php" >>"\$LOGFILE" 2>&1
    else
        nohup "\$PHP_BIN" -S 0.0.0.0:"\$PUERTO" "\$RUTA/router.php" >>"\$LOGFILE" 2>&1 &
        echo \$! > "\$PIDFILE"
    fi
}

stop_api() {
    if ! is_running; then rm -f "\$PIDFILE"; return 0; fi
    PID=\$(cat "\$PIDFILE")
    kill "\$PID" 2>/dev/null || true
    i=0
    while kill -0 "\$PID" 2>/dev/null && [ \$i -lt 10 ]; do sleep 1; i=\$((i+1)); done
    kill -9 "\$PID" 2>/dev/null || true
    rm -f "\$PIDFILE"
}

case "\$1" in
    start) start_api ;;
    stop) stop_api ;;
    restart|force-reload) stop_api; sleep 1; start_api ;;
    status) if is_running; then echo "\$NAME running"; exit 0; else echo "\$NAME stopped"; exit 3; fi ;;
    *) echo "Usage: \$0 {start|stop|restart|status}"; exit 1 ;;
esac
exit 0
EOF_SYSV
    chmod 755 "/etc/init.d/${SERVICIO}"
fi

service_start

# ---------------------------------------------------------------------
# Firewall local: abre solo si detectamos un firewall activo/conocido.
# Nunca activamos UFW/firewalld por sorpresa.
# ---------------------------------------------------------------------
msg "${CYAN}[5/8] Revisando firewall local...${RESET}"
FIREWALL_NOTE="sin firewall local activo detectado"
if have ufw && ufw status 2>/dev/null | grep -qi '^Status: active'; then
    ufw allow "${PUERTO}/tcp" >/dev/null 2>&1 || true
    FIREWALL_NOTE="UFW activo: regla ${PUERTO}/tcp aplicada"
elif have firewall-cmd && firewall-cmd --state >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port="${PUERTO}/tcp" >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
    FIREWALL_NOTE="firewalld activo: regla ${PUERTO}/tcp aplicada"
elif have ufw; then
    # UFW inactivo: preparamos la regla, pero no lo activamos.
    ufw allow "${PUERTO}/tcp" >/dev/null 2>&1 || true
    FIREWALL_NOTE="UFW inactivo: regla preparada; UFW no fue activado"
fi
msg "Firewall : ${FIREWALL_NOTE}"

# ---------------------------------------------------------------------
# Verificacion real local.
# ---------------------------------------------------------------------
msg "${CYAN}[6/8] Verificando servicio, socket y HTTP...${RESET}"
OK=0
COUNT=0
while [[ "$COUNT" -lt 20 ]]; do
    if service_active && port_listening; then
        REPLY="$(curl -fsS --max-time 3 "http://127.0.0.1:${PUERTO}/api.php" 2>/dev/null || true)"
        if [[ "$REPLY" == "pong" ]]; then
            OK=1
            break
        fi
    fi
    COUNT=$((COUNT + 1))
    sleep 1
done

if [[ "$OK" -ne 1 ]]; then
    msg "${RED}La API no paso la validacion local.${RESET}"
    echo
    if [[ "$INIT_MODE" == "systemd" ]]; then
        systemctl --no-pager --full status "$SERVICIO" 2>/dev/null || true
        journalctl -u "$SERVICIO" -n 80 --no-pager 2>/dev/null || true
    else
        service "$SERVICIO" status 2>/dev/null || true
        tail -n 80 "$LOGFILE" 2>/dev/null || true
    fi
    echo
    port_details
    exit 1
fi

# ---------------------------------------------------------------------
# Prueba de persistencia del arranque (sin reiniciar la VPS): confirma
# que el servicio esta habilitado en el sistema de init correspondiente.
# ---------------------------------------------------------------------
msg "${CYAN}[7/8] Verificando auto-arranque...${RESET}"
AUTOSTART="desconocido"
if [[ "$INIT_MODE" == "systemd" ]]; then
    if systemctl is-enabled "$SERVICIO" >/dev/null 2>&1; then AUTOSTART="habilitado (systemd)"; fi
else
    if ls /etc/rc2.d/S*"${SERVICIO}" /etc/rc3.d/S*"${SERVICIO}" /etc/rc4.d/S*"${SERVICIO}" /etc/rc5.d/S*"${SERVICIO}" >/dev/null 2>&1; then
        AUTOSTART="habilitado (SysV/Upstart)"
    fi
fi

# ---------------------------------------------------------------------
# Resumen.
# ---------------------------------------------------------------------
msg "${CYAN}[8/8] Instalacion validada.${RESET}"
IP_PUBLICA=""
IP_PUBLICA="$(curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)"
if [[ -z "$IP_PUBLICA" ]]; then
    IP_PUBLICA="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
fi

msg "${GOLD}${BAR}${RESET}"
msg "${GREEN}API VPS PRO INSTALADA Y ACTIVA${RESET}"
msg "Sistema   : ${PRETTY_NAME}"
msg "PHP       : ${PHP_VERSION}"
msg "Init      : ${INIT_MODE}"
msg "Autostart : ${AUTOSTART}"
msg "Servicio  : ${SERVICIO}"
msg "Escucha   : 0.0.0.0:${PUERTO}/TCP"
msg "Local     : http://127.0.0.1:${PUERTO}/api.php -> pong"
if [[ -n "$IP_PUBLICA" ]]; then
    msg "Panel     : http://${IP_PUBLICA}:${PUERTO}/api.php"
fi
msg "Firewall  : ${FIREWALL_NOTE}"
msg "${GOLD}${BAR}${RESET}"

echo
port_details

echo
msg "${CYAN}Diagnostico rapido:${RESET}"
if [[ "$INIT_MODE" == "systemd" ]]; then
    echo "systemctl status ${SERVICIO} --no-pager"
    echo "journalctl -u ${SERVICIO} -n 100 --no-pager"
else
    echo "service ${SERVICIO} status"
    echo "tail -n 100 ${LOGFILE}"
fi
echo "curl -v http://127.0.0.1:${PUERTO}/api.php"
if have ss; then echo "ss -lntp | grep :${PUERTO}"; else echo "netstat -lntp | grep :${PUERTO}"; fi

echo
msg "${GOLD}IMPORTANTE:${RESET} si localmente responde 'pong' pero el panel marca Offline,"
msg "revisa el firewall externo/security group del proveedor y permite TCP ${PUERTO}."
