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
# LIMPIAR
# =========================
systemctl stop $SERVICIO 2>/dev/null
systemctl disable $SERVICIO 2>/dev/null
pkill -f "php -S" 2>/dev/null

# =========================
# CREAR DIRECTORIOS
# =========================
mkdir -p $RUTA
mkdir -p /etc/SSHPlus/blocked
mkdir -p /etc/SSHPlus/limits

# =========================
# CREAR API
# =========================
cat > $RUTA/api.php <<EOF
<?php

if (\$_SERVER['REQUEST_METHOD'] !== 'POST') {
    echo "API ONLINE ✅";
    exit;
}

\$TOKEN = "$TOKEN";

\$data = json_decode(file_get_contents("php://input"), true);

if (!\$data) {
    http_response_code(400);
    exit("JSON inválido");
}

if (!isset(\$data['token']) || \$data['token'] !== \$TOKEN) {
    http_response_code(403);
    exit("No autorizado");
}

\$user  = preg_replace('/[^a-zA-Z0-9]/', '', \$data['user'] ?? '');
\$pass  = \$data['pass'] ?? '';
\$dias  = intval(\$data['dias'] ?? 0);
\$accion = \$data['accion'] ?? '';
\$fecha = \$data['fecha'] ?? '';

function run(\$cmd){
    return shell_exec("sudo \$cmd 2>&1");
}

if (in_array(\$accion, ["crear","eliminar","bloquear","desbloquear","editar","reset"]) && empty(\$user)) {
    exit("Usuario inválido");
}

switch ($accion) {

    case "crear":

        // Crear usuario si no existe
        run("id $user || useradd -M -s /bin/false $user");

        // Password global
        run("echo " . escapeshellarg($user . ":" . $pass) . " | chpasswd");

        // Expiración consistente
        if ($dias > 0) {
            run("chage -E $(date -d '+$dias days' +%Y-%m-%d) $user");
        }

        // Limite sincronizado
        if (!file_exists("/etc/SSHPlus/limits")) {
            mkdir("/etc/SSHPlus/limits", 0777, true);
        }
        file_put_contents("/etc/SSHPlus/limits/$user", 3);

    break;


    case "eliminar":

        // Matar sesiones SIEMPRE
        run("pkill -KILL -u $user");
        run("killall -u $user");

        // Eliminar usuario
        run("userdel -f $user");

        // Limpiar TODO
        @unlink("/etc/SSHPlus/limits/$user");
        @unlink("/etc/SSHPlus/blocked/$user");
        @unlink("/etc/SSHPlus/abuse/$user");

    break;


    case "bloquear":

        // Bloqueo fuerte real
        run("usermod -L $user");
        run("usermod -s /usr/sbin/nologin $user");

        // Matar sesiones activas
        run("pkill -KILL -u $user");
        run("killall -u $user");

        // Marcar bloqueado
        if (!file_exists("/etc/SSHPlus/blocked")) {
            mkdir("/etc/SSHPlus/blocked", 0777, true);
        }
        file_put_contents("/etc/SSHPlus/blocked/$user", "blocked");

    break;


    case "desbloquear":

        // Restaurar acceso real
        run("usermod -U $user");
        run("usermod -s /bin/bash $user");

        // Limpiar bloqueos
        @unlink("/etc/SSHPlus/blocked/$user");
        @unlink("/etc/SSHPlus/abuse/$user");

    break;


    case "editar":

        // Actualizar expiración por días
        if ($dias > 0) {
            run("chage -E $(date -d '+$dias days' +%Y-%m-%d) $user");
        }

        // O por fecha directa
        if (!empty($fecha)) {
            run("chage -E $fecha $user");
        }

    break;


    case "reset":

        // Reset password
        run("echo " . escapeshellarg($user . ":" . $pass) . " | chpasswd");

        // Opcional: matar sesiones para forzar reconexión
        run("pkill -KILL -u $user");

    break;


    case "limpiar_expirados":

        $users = explode("\n", trim(shell_exec("awk -F: '$3>=1000 {print $1}' /etc/passwd")));

        foreach ($users as $u) {

            if (empty($u)) continue;

            $expire = trim(shell_exec("chage -l $u | grep 'Account expires' | cut -d: -f2"));

            if ($expire == "never" || empty($expire)) continue;

            $exp_date = strtotime($expire);
            $today = time();

            if ($today >= $exp_date) {

                run("pkill -KILL -u $u");
                run("killall -u $u");
                run("userdel -f $u");

                @unlink("/etc/SSHPlus/limits/$u");
                @unlink("/etc/SSHPlus/blocked/$u");
                @unlink("/etc/SSHPlus/abuse/$u");
            }
        }

        echo "cleaned";

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
# SUDO SIN PASSWORD
# =========================
if ! grep -q "www-data ALL=(ALL) NOPASSWD: ALL" /etc/sudoers; then
    echo "www-data ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
fi

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


