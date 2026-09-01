#!/usr/bin/env bash
set -Eeuo pipefail

# ==========================================================
# API VPS PRO - Ubuntu 24.04 FIX
# Mantiene compatibilidad con el api.php original del panel.
# Corrige: PHP ausente, servicio que falla silenciosamente,
# puerto 8888 sin verificacion y arranque tras reinicio.
# ==========================================================

RUTA="/etc/chido"
PUERTO="8888"
SERVICIO="api-vps"
TOKEN="ULTRA_SECRET_TOKEN"

GOLD='\033[1;33m'
GREEN='\033[1;32m'
RED='\033[1;31m'
CYAN='\033[1;36m'
RESET='\033[0m'
BAR='=×=×=×=×=×=×=×=×=×=×=×=×=×=×=×=×=×=×=×=×=×=×=×=×=×=×=×=×=×='

msg() { echo -e "$*"; }
fail() { msg "${RED}ERROR:${RESET} $*"; exit 1; }

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  fail "Ejecuta este instalador como root: sudo bash $0"
fi

msg "${GOLD}${BAR}${RESET}"
msg "${GOLD}       API VPS PRO - UBUNTU 24.04 FIX${RESET}"
msg "${GOLD}${BAR}${RESET}"

# ----------------------------------------------------------
# 1) Dependencias reales necesarias en Ubuntu 24.04
# ----------------------------------------------------------
msg "${CYAN}[1/7] Instalando dependencias...${RESET}"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y php-cli curl ca-certificates procps psmisc iproute2 ufw

PHP_BIN="$(command -v php || true)"
[[ -n "$PHP_BIN" && -x "$PHP_BIN" ]] || fail "php-cli no quedo instalado."
msg "${GREEN}PHP detectado:${RESET} $($PHP_BIN -r 'echo PHP_VERSION;' 2>/dev/null) ($PHP_BIN)"

# ----------------------------------------------------------
# 2) Limpiar SOLO el servicio anterior de esta API
# ----------------------------------------------------------
msg "${CYAN}[2/7] Limpiando instalacion anterior de la API...${RESET}"
systemctl stop "$SERVICIO" 2>/dev/null || true
systemctl disable "$SERVICIO" 2>/dev/null || true
rm -f "/etc/systemd/system/${SERVICIO}.service"

mkdir -p "$RUTA" /etc/SSHPlus/blocked /etc/SSHPlus/limits /etc/SSHPlus/abuse
chmod 755 "$RUTA"

# ----------------------------------------------------------
# 3) API compatible con el panel actual
# ----------------------------------------------------------
msg "${CYAN}[3/7] Escribiendo api.php...${RESET}"
cat > "$RUTA/api.php" <<'PHPAPI'
<?php

error_reporting(E_ALL);
ini_set('display_errors', 1);

// El monitor del panel usa GET para comprobar que la VPS esta viva.
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(200);
    header('Content-Type: text/plain; charset=UTF-8');
    echo "pong";
    exit;
}

$TOKEN = "ULTRA_SECRET_TOKEN";
$data = json_decode(file_get_contents("php://input"), true);

if (!$data) {
    http_response_code(400);
    exit("JSON inválido");
}

if (!isset($data['token']) || !hash_equals($TOKEN, (string)$data['token'])) {
    http_response_code(403);
    exit("No autorizado");
}

$user   = preg_replace('/[^a-zA-Z0-9]/', '', $data['user'] ?? '');
$pass   = $data['pass'] ?? '';
$dias   = intval($data['dias'] ?? 0);
$accion = $data['accion'] ?? '';
$fecha  = $data['fecha'] ?? '';
$limite = intval($data['limite'] ?? 0);

// El servicio systemd corre como root; no dependemos de sudo.
function run($cmd) {
    return shell_exec($cmd . " 2>&1");
}

if (in_array($accion, ["crear","eliminar","bloquear","desbloquear","editar","reset"], true) && empty($user)) {
    exit("Usuario inválido");
}

switch ($accion) {
    case "crear":
        run("id " . escapeshellarg($user) . " || useradd -M -s /bin/false " . escapeshellarg($user));

        if (!empty($pass)) {
            run("echo " . escapeshellarg($user . ":" . $pass) . " | chpasswd");
        }

        if (!empty($fecha)) {
            run("chage -E " . escapeshellarg($fecha) . " " . escapeshellarg($user));
        } elseif ($dias > 0) {
            $exp = date("Y-m-d", strtotime("+$dias days"));
            run("chage -E " . escapeshellarg($exp) . " " . escapeshellarg($user));
        }

        if ($limite > 0) {
            @mkdir('/etc/SSHPlus/limits', 0755, true);
            file_put_contents('/etc/SSHPlus/limits/' . $user, (string)$limite);
        }
        break;

    case "eliminar":
        run("pkill -KILL -u " . escapeshellarg($user));
        run("killall -u " . escapeshellarg($user));
        run("userdel -f " . escapeshellarg($user));
        @unlink("/etc/SSHPlus/limits/$user");
        @unlink("/etc/SSHPlus/blocked/$user");
        @unlink("/etc/SSHPlus/abuse/$user");
        break;

    case "bloquear":
        run("usermod -L " . escapeshellarg($user));
        run("usermod -s /bin/false " . escapeshellarg($user));
        run("pkill -KILL -u " . escapeshellarg($user));
        file_put_contents("/etc/SSHPlus/blocked/$user", "blocked");
        break;

    case "desbloquear":
        run("usermod -U " . escapeshellarg($user));
        run("usermod -s /bin/bash " . escapeshellarg($user));
        @unlink("/etc/SSHPlus/blocked/$user");
        break;

    case "editar":
        if ($dias > 0) {
            $raw = run("LC_ALL=C chage -l " . escapeshellarg($user) . " | grep 'Account expires'");
            $fecha_actual = "";
            if ($raw) {
                $parts = explode(":", $raw, 2);
                $fecha_actual = trim($parts[1] ?? '');
            }

            if ($fecha_actual === "" || strtolower($fecha_actual) === "never") {
                $base = time();
            } else {
                $base = strtotime($fecha_actual);
                if ($base === false || $base < time()) $base = time();
            }

            $nueva_fecha = strtotime("+$dias days", $base);
            $formato = date("Y-m-d", $nueva_fecha);
            run("chage -E " . escapeshellarg($formato) . " " . escapeshellarg($user));
        }

        if (!empty($fecha)) {
            run("chage -E " . escapeshellarg($fecha) . " " . escapeshellarg($user));
        }
        break;

    case "reset":
        if (!empty($pass)) {
            run("echo " . escapeshellarg($user . ":" . $pass) . " | chpasswd");
        }
        break;

    case "limpiar_expirados":
        $users = explode("\n", trim(shell_exec("awk -F: '$3>=1000 {print $1}' /etc/passwd")));

        foreach ($users as $u) {
            $u = preg_replace('/[^a-zA-Z0-9]/', '', $u);
            if (empty($u)) continue;
            if (file_exists("/etc/SSHPlus/blocked/$u")) continue;

            $expire_raw = shell_exec("LC_ALL=C chage -l " . escapeshellarg($u) . " 2>/dev/null | grep 'Account expires'");
            $expire = "";
            if ($expire_raw) {
                $parts = explode(":", $expire_raw, 2);
                $expire = trim($parts[1] ?? '');
            }

            if ($expire === "" || strtolower($expire) === "never") continue;
            $exp_date = strtotime($expire);
            if (!$exp_date) continue;

            if (time() >= $exp_date) {
                run("pkill -KILL -u " . escapeshellarg($u));
                run("killall -u " . escapeshellarg($u));
                run("userdel -f " . escapeshellarg($u));
                @unlink("/etc/SSHPlus/limits/$u");
                @unlink("/etc/SSHPlus/blocked/$u");
                @unlink("/etc/SSHPlus/abuse/$u");
            }
        }

        echo "cleaned";
        break;

    default:
        http_response_code(400);
        exit("Acción inválida");
}

echo "OK";
PHPAPI

cat > "$RUTA/router.php" <<'PHPROUTER'
<?php
$uri = urldecode(parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH));

if ($uri === '/api.php' || $uri === '/') {
    require __DIR__ . '/api.php';
    return true;
}

http_response_code(404);
echo "not found";
return true;
PHPROUTER

chmod 644 "$RUTA/api.php" "$RUTA/router.php"

"$PHP_BIN" -l "$RUTA/api.php" >/dev/null || fail "api.php tiene error de sintaxis PHP."
"$PHP_BIN" -l "$RUTA/router.php" >/dev/null || fail "router.php tiene error de sintaxis PHP."

# ----------------------------------------------------------
# 4) Servicio systemd robusto y auto-start
# ----------------------------------------------------------
msg "${CYAN}[4/7] Creando servicio systemd...${RESET}"
cat > "/etc/systemd/system/${SERVICIO}.service" <<EOF_SERVICE
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
EOF_SERVICE

systemctl daemon-reload
systemctl enable "$SERVICIO"
systemctl restart "$SERVICIO"

# ----------------------------------------------------------
# 5) Firewall local - sin activar UFW a la fuerza
# ----------------------------------------------------------
msg "${CYAN}[5/7] Configurando puerto TCP ${PUERTO}...${RESET}"
if command -v ufw >/dev/null 2>&1; then
    ufw allow "${PUERTO}/tcp" >/dev/null || true
    if ufw status 2>/dev/null | grep -qi '^Status: active'; then
        msg "${GREEN}UFW activo:${RESET} regla ${PUERTO}/tcp aplicada."
    else
        msg "${GREEN}UFW esta inactivo:${RESET} no bloquea el puerto localmente; la regla quedo preparada."
    fi
fi

# ----------------------------------------------------------
# 6) Verificacion real: proceso + socket + HTTP local
# ----------------------------------------------------------
msg "${CYAN}[6/7] Verificando servicio y puerto...${RESET}"
OK=0
for _ in $(seq 1 15); do
    if systemctl is-active --quiet "$SERVICIO" \
       && ss -lnt 2>/dev/null | grep -Eq "[:.]${PUERTO}[[:space:]]" \
       && [[ "$(curl -fsS --max-time 2 "http://127.0.0.1:${PUERTO}/api.php" 2>/dev/null || true)" == "pong" ]]; then
        OK=1
        break
    fi
    sleep 1
done

if [[ "$OK" -ne 1 ]]; then
    msg "${RED}La API no paso la prueba local.${RESET}"
    echo
    systemctl --no-pager --full status "$SERVICIO" || true
    echo
    journalctl -u "$SERVICIO" -n 80 --no-pager || true
    echo
    ss -lntp | grep -E ":${PUERTO}([[:space:]]|$)" || true
    exit 1
fi

# ----------------------------------------------------------
# 7) Resumen y prueba externa
# ----------------------------------------------------------
msg "${CYAN}[7/7] Instalacion validada.${RESET}"
IP_PUBLICA="$(curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)"
[[ -z "$IP_PUBLICA" ]] && IP_PUBLICA="$(hostname -I 2>/dev/null | awk '{print $1}')"

msg "${GOLD}${BAR}${RESET}"
msg "${GREEN}API VPS PRO INSTALADA Y ACTIVA${RESET}"
msg "Servicio : ${SERVICIO}"
msg "PHP      : $($PHP_BIN -r 'echo PHP_VERSION;' 2>/dev/null)"
msg "Escucha  : 0.0.0.0:${PUERTO}/TCP"
msg "Local    : http://127.0.0.1:${PUERTO}/api.php  -> pong"
if [[ -n "$IP_PUBLICA" ]]; then
    msg "Panel    : http://${IP_PUBLICA}:${PUERTO}/api.php"
fi
msg "${GOLD}${BAR}${RESET}"

echo
ss -lntp | grep -E ":${PUERTO}([[:space:]]|$)" || true

echo
msg "${CYAN}Comandos de diagnostico:${RESET}"
echo "systemctl status ${SERVICIO} --no-pager"
echo "journalctl -u ${SERVICIO} -n 100 --no-pager"
echo "curl -v http://127.0.0.1:${PUERTO}/api.php"
echo "ss -lntp | grep :${PUERTO}"
echo
msg "${GOLD}IMPORTANTE:${RESET} si la prueba local responde 'pong' pero el panel sigue Offline,"
msg "abre TCP ${PUERTO} en cualquier firewall externo/security group del proveedor de la VPS."
