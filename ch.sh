#!/bin/bash

clear

ZIP_URL="https://raw.githubusercontent.com/satanas66666/vpn-manager/main/chido.zip"
CARPETA_ETC="/etc/chido"
TMP_DIR="/tmp/chido_install"

apt-get update -y > /dev/null
apt-get install -y unzip curl php > /dev/null

rm -rf $TMP_DIR
mkdir -p $TMP_DIR
cd $TMP_DIR

echo "Descargando archivos..."
curl -L $ZIP_URL -o chido.zip

if [ ! -f chido.zip ]; then
    echo "Error al descargar"
    exit 1
fi

unzip -q chido.zip -d extract

echo "Buscando estructura correcta..."

BASE_DIR=""

for dir in $(find extract -type d); do
    if [ -f "$dir/index.php" ] && [ -d "$dir/chidito1" ]; then
        BASE_DIR="$dir"
        break
    fi
done

if [ -z "$BASE_DIR" ]; then
    echo "Error: estructura inválida"
    exit 1
fi

echo "Estructura detectada en: $BASE_DIR"

# BACKUP
if [ -d "$CARPETA_ETC" ]; then
    mv "$CARPETA_ETC" "${CARPETA_ETC}_backup_$(date +%s)"
fi

mkdir -p "$CARPETA_ETC"

cp -r "$BASE_DIR"/* "$CARPETA_ETC"

# VALIDACIÓN
if [ ! -f "$CARPETA_ETC/index.php" ]; then
    echo "Error final: falta index.php"
    exit 1
fi

if [ ! -d "$CARPETA_ETC/chidito1" ]; then
    echo "Error final: falta chidito1"
    exit 1
fi

# =========================
# 🔥 ROUTER (checkUser + admin)
# =========================
cat > $CARPETA_ETC/router.php <<'EOF'
<?php

$uri = urldecode(parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH));

if ($uri === '/checkUser' || $uri === '/checkUser/') {
    require __DIR__ . '/chidito1/index.php';
    return;
}

if ($uri === '/admin' || $uri === '/admin/') {
    require __DIR__ . '/admin.php';
    return;
}

$file = __DIR__ . $uri;
if ($uri !== '/' && file_exists($file) && !is_dir($file)) {
    return false;
}

require __DIR__ . '/index.php';
EOF

# =========================
# 🔥 PANEL ADMIN
# =========================
cat > $CARPETA_ETC/admin.php <<'EOF'
<?php

$PASS = "admin123";

if (!isset($_GET['key']) || $_GET['key'] !== $PASS) {
    die("Acceso denegado");
}

$users = explode("\n", trim(shell_exec("cut -d: -f1 /etc/passwd")));

function getExpire($user) {
    $out = shell_exec("chage -l $user 2>/dev/null | grep 'Account expires'");
    if (!$out) return "N/A";
    $f = explode(':', $out);
    return trim($f[1]);
}

if (isset($_POST['newuser'])) {
    $u = $_POST['user'];
    $p = $_POST['pass'];
    $d = $_POST['days'];

    shell_exec("useradd -M -s /bin/false $u");
    shell_exec("echo '$u:$p' | chpasswd");
    shell_exec("chage -E $(date -d '+$d days' +%Y-%m-%d) $u");
}

if (isset($_GET['del'])) {
    $u = $_GET['del'];
    shell_exec("userdel $u");
}

?>
<!DOCTYPE html>
<html>
<head>
<title>Panel Admin</title>
<style>
body{background:#0f172a;color:white;font-family:sans-serif}
table{width:100%}
td,th{padding:8px}
input{padding:5px}
button{padding:6px}
</style>
</head>
<body>

<h2>Panel VPN</h2>

<form method="post">
<input name="user" placeholder="usuario">
<input name="pass" placeholder="pass">
<input name="days" placeholder="dias">
<button name="newuser">Crear</button>
</form>

<table border="1">
<tr><th>User</th><th>Expira</th><th>Acción</th></tr>

<?php
foreach ($users as $u) {
    if (strlen($u) < 3) continue;
    echo "<tr>
    <td>$u</td>
    <td>".getExpire($u)."</td>
    <td><a href='?key=$PASS&del=$u'>Eliminar</a></td>
    </tr>";
}
?>

</table>

</body>
</html>
EOF

# =========================
# PUERTOS
# =========================
echo ""
read -p "Puerto checkUser: " PUERTO_CHECK
read -p "Puerto online: " PUERTO_ONLINE

if ! [[ "$PUERTO_CHECK" =~ ^[0-9]+$ ]] || ! [[ "$PUERTO_ONLINE" =~ ^[0-9]+$ ]]; then
    echo "Puertos inválidos"
    exit 1
fi

# =========================
# SERVICIOS
# =========================
cat > /etc/systemd/system/chido-check.service <<EOF
[Unit]
Description=Chido API (checkUser + admin)
After=network.target

[Service]
ExecStart=/usr/bin/php -S 0.0.0.0:$PUERTO_CHECK -t $CARPETA_ETC $CARPETA_ETC/router.php
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/chido-online.service <<EOF
[Unit]
Description=Chido Online Users
After=network.target

[Service]
ExecStart=/usr/bin/php -S 0.0.0.0:$PUERTO_ONLINE -t $CARPETA_ETC
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl daemon-reload

systemctl enable chido-check
systemctl enable chido-online

systemctl restart chido-check
systemctl restart chido-online

rm -rf $TMP_DIR

IP=$(hostname -I | awk '{print $1}')

clear
echo "======================================="
echo " INSTALADO CORRECTAMENTE 🚀"
echo "======================================="
echo ""
echo "CheckUser:"
echo "http://$IP:$PUERTO_CHECK/checkUser"
echo ""
echo "Panel Admin:"
echo "http://$IP:$PUERTO_CHECK/admin?key=admin123"
echo ""
echo "Online Users:"
echo "http://$IP:$PUERTO_ONLINE"
echo ""
echo "======================================="
