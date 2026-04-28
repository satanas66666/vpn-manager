#!/bin/bash

echo "🔥 Instalando API VPS PRO..."

# =========================
# CONFIG
# =========================
RUTA="/etc/chido"
PUERTO="8888"
SERVICIO="api-vps"
TOKEN="ULTRA_SECRET_TOKEN"

# =========================
# LIMPIAR SERVICIOS ANTERIORES
# =========================
systemctl stop $SERVICIO 2>/dev/null
systemctl disable $SERVICIO 2>/dev/null
pkill -f "php -S" 2>/dev/null

# =========================
# CREAR DIRECTORIO
# =========================
mkdir -p $RUTA

# =========================
# CREAR API
# =========================
cat > $RUTA/api.php <<'EOF'
<?php

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    echo "API ONLINE ✅";
    exit;
}

$TOKEN = "ULTRA_SECRET_TOKEN";

$data = json_decode(file_get_contents("php://input"), true);

if (!$data) {
    http_response_code(400);
    exit("JSON inválido");
}

if (!isset($data['token']) || $data['token'] !== $TOKEN) {
    http_response_code(403);
    exit("No autorizado");
}

$user  = preg_replace('/[^a-zA-Z0-9]/', '', $data['user'] ?? '');
$pass  = $data['pass'] ?? '';
$dias  = intval($data['dias'] ?? 0);
$accion = $data['accion'] ?? '';
$fecha = $data['fecha'] ?? '';

function run($cmd){
    return shell_exec($cmd . " 2>/dev/null");
}

if (in_array($accion, ["crear","eliminar","bloquear","desbloquear","editar","reset"]) && empty($user)) {
    exit("Usuario inválido");
}

switch ($accion) {

    case "crear":
        run("id $user || useradd -M -s /bin/false $user");
        run("echo " . escapeshellarg($user . ":" . $pass) . " | chpasswd");
        run("chage -E $(date -d '+$dias days' +%Y-%m-%d) $user");
    break;

    case "eliminar":
        run("pkill -u $user");
        run("killall -u $user");
        run("userdel -f $user");
    break;

    case "bloquear":
        run("usermod -L $user");
        run("usermod -s /usr/sbin/nologin $user");
        run("pkill -KILL -u $user");
    break;

    case "desbloquear":
        run("usermod -U $user");
        run("usermod -s /bin/bash $user");
    break;

    case "editar":
        if ($dias > 0) {
            run("chage -E $(date -d '+$dias days' +%Y-%m-%d) $user");
        }
        if (!empty($fecha)) {
            run("chage -E $fecha $user");
        }
    break;

    case "reset":
        run("echo " . escapeshellarg($user . ":" . $pass) . " | chpasswd");
    break;

    default:
        exit("Acción inválida");
}

echo "OK";
EOF

# =========================
# ROUTER
# =========================
cat > $RUTA/router.php <<'EOF'
<?php
$uri = urldecode(parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH));

if ($uri === '/api.php') {
    require __DIR__ . '/api.php';
    return;
}

return false;
EOF

# =========================
# PERMISOS
# =========================
chmod -R 755 $RUTA

# =========================
# CREAR SERVICIO
# =========================
cat > /etc/systemd/system/$SERVICIO.service <<EOF
[Unit]
Description=API VPS PRO
After=network.target

[Service]
ExecStart=/usr/bin/php -S 0.0.0.0:$PUERTO $RUTA/router.php
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
EOF

# =========================
# ACTIVAR
# =========================
systemctl daemon-reload
systemctl enable $SERVICIO
systemctl restart $SERVICIO

# =========================
# FIREWALL
# =========================
ufw allow $PUERTO 2>/dev/null

echo ""
echo "✅ API VPS PRO INSTALADA"
echo "🌐 http://IP_VPS:$PUERTO/api.php"
echo ""
echo "👉 Prueba:"
echo "curl http://127.0.0.1:$PUERTO/api.php"
