<?php

$FORMATO = "dmY";

// Leer input
$raw = file_get_contents("php://input");
$update = json_decode($raw, true);

// Validar
if (empty($update) || !isset($update['user'])) {
    echo "00000000";
    exit;
}

$usuario_raw = $update['user'];

// Seguridad
if (!preg_match('/^[a-zA-Z0-9._-]+$/', $usuario_raw)) {
    echo "00000000";
    exit;
}

$usuario = escapeshellarg($usuario_raw);

// Cache (reduce carga brutal)
$cacheFile = "/tmp/chido_user_" . md5($usuario_raw);

if (file_exists($cacheFile) && (time() - filemtime($cacheFile)) < 10) {
    echo file_get_contents($cacheFile);
    exit;
}

// Obtener expiración
$cmd = "sudo chage -l $usuario 2>/dev/null | grep 'Account expires'";
$out = shell_exec($cmd);

if (!empty($out)) {

    $fecha = explode(':', $out);

    if (isset($fecha[1])) {

        $rawDate = trim($fecha[1]);

        if (strtolower($rawDate) === "never") {
            file_put_contents($cacheFile, "00000000");
            echo "00000000";
            exit;
        }

        $date = date_create($rawDate);

        if ($date !== false) {
            $result = date_format($date, $FORMATO);
            file_put_contents($cacheFile, $result);
            echo $result;
            exit;
        }
    }
}

// fallback
echo "00000000";
exit();
?>

