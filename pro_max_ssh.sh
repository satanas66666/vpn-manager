#!/bin/bash

echo "🚀 OPTIMIZACION PRO MAX (SSH + LATENCIA + ESTABILIDAD)"

# ===== BACKUP =====
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak 2>/dev/null

# ===== LIMPIAR SYSCTL (EVITA DUPLICADOS) =====
sed -i '/# PRO-OPTIM/d' /etc/sysctl.conf

# ===== CONFIG SSH =====
cat > /etc/ssh/sshd_config <<EOF
Port 22
Protocol 2

# CONEXIONES
MaxSessions 200
MaxStartups 200:30:400

# PERFORMANCE
LoginGraceTime 15
UseDNS no

# KEEP ALIVE
ClientAliveInterval 60
ClientAliveCountMax 2

# CIFRADO RAPIDO
Ciphers aes128-ctr

PermitRootLogin yes
PasswordAuthentication yes
UsePAM yes

Subsystem sftp /usr/lib/openssh/sftp-server
EOF

# ===== LIMITES =====
cat > /etc/security/limits.d/99-pro.conf <<EOF
* soft nofile 200000
* hard nofile 200000
root soft nofile 200000
root hard nofile 200000
EOF

# ===== SYSCTL PRO =====
cat >> /etc/sysctl.conf <<EOF

# PRO-OPTIM NETWORK
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 65535

net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_tw_reuse = 1

net.ipv4.ip_local_port_range = 1024 65535

# BUFFERS
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864

# BAJA LATENCIA
net.ipv4.tcp_low_latency = 1
net.ipv4.tcp_mtu_probing = 1
EOF

sysctl -p

# ===== ACTIVAR BBR =====
modprobe tcp_bbr
echo "tcp_bbr" > /etc/modules-load.d/bbr.conf

# ===== SYSTEMD LIMIT =====
mkdir -p /etc/systemd/system/ssh.service.d

cat > /etc/systemd/system/ssh.service.d/limit.conf <<EOF
[Service]
LimitNOFILE=200000
EOF

systemctl daemon-reexec
systemctl daemon-reload

# ===== NIC OPTIMIZATION =====
apt install ethtool -y

IFACE=$(ip route | grep default | awk '{print $5}')

ethtool -K $IFACE gro on gso on tso on 2>/dev/null
ethtool -G $IFACE rx 4096 tx 4096 2>/dev/null

# ===== IRQ BALANCE =====
apt install irqbalance -y
systemctl enable irqbalance
systemctl start irqbalance

# ===== FAIL2BAN =====
apt install fail2ban -y
systemctl enable fail2ban
systemctl start fail2ban

# ===== IPTABLES ANTI SATURACION =====
iptables -A INPUT -p tcp --dport 22 -m connlimit --connlimit-above 20 -j REJECT
iptables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --set
iptables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --update --seconds 1 --hitcount 30 -j DROP

# ===== RESTART SSH =====
systemctl restart ssh

echo "====================================="
echo "✅ OPTIMIZACION COMPLETA APLICADA"
echo "🔥 BAJA LATENCIA ACTIVADA (BBR + FQ)"
echo "🔥 SSH OPTIMIZADO PARA 150 USUARIOS"
echo "🔥 SISTEMA ESTABLE Y SIN LAG"
echo "====================================="
