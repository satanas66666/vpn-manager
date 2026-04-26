<?php

$ONLINE = "DIRECTO";

// Cache global
$cacheFile = "/tmp/chido_online";

if (file_exists($cacheFile) && (time() - filemtime($cacheFile)) < 5) {
    echo file_get_contents($cacheFile);
    exit;
}

// SSH optimizado
$ssh = intval(trim(shell_exec("pgrep -c sshd")));

// OpenVPN
$openvpn = 0;
if (is_readable('/etc/openvpn/openvpn-status.log')) {
    $openvpn = intval(trim(shell_exec("grep -c '10.8.0' /etc/openvpn/openvpn-status.log")));
}

// Dropbear
$dropbear = 0;
if (is_readable('/etc/default/dropbear')) {
    $dropbear = intval(trim(shell_exec("pgrep -c dropbear"))) - 1;
    if ($dropbear < 0) $dropbear = 0;
}

$total = $ssh + $openvpn + $dropbear;

// Guardar cache
file_put_contents($cacheFile, $total);

// Salida compatible
switch ($ONLINE) {

    case 'DIRECTO':
        echo $total;
        break;

    case 'JSON':
        echo json_encode([
            "onlines" => $total,
            "limite" => "2500"
        ]);
        break;

    default:
        echo $total;
        break;
}

exit();
?>
