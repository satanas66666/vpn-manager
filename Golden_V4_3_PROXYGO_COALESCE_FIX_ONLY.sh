#!/usr/bin/env bash
# V4.3 stable -> ProxyGo coalesced SSH-ident fix ONLY
# No cambia HAProxy, Xray, SSL, Path, UUID, usuarios, puertos ni AUTO-TUNE.
set -Eeuo pipefail

[[ "$(id -u)" -eq 0 ]] || { echo "ERROR: ejecuta como root."; exit 1; }

BIN="/usr/local/bin/proxygo"
SRC_DIR="/opt/newgolden-proxygo"
SRC="$SRC_DIR/main.go"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="/var/backups/proxygo-v43-coalesce-$STAMP"
TMPBIN="/tmp/proxygo-v43-coalesce.$$"

cleanup() { rm -f "$TMPBIN"; }
trap cleanup EXIT

command -v go >/dev/null 2>&1 || { echo "ERROR: falta Go."; exit 1; }
[[ -x "$BIN" ]] || { echo "ERROR: no existe $BIN"; exit 1; }

mkdir -p "$BACKUP_DIR" "$SRC_DIR"
cp -a "$BIN" "$BACKUP_DIR/proxygo"
[[ -f "$SRC" ]] && cp -a "$SRC" "$BACKUP_DIR/main.go" || true

cat > "$SRC" <<'EOF'
package main

import (
	"bytes"
	"flag"
	"fmt"
	"io"
	"net"
	"time"
)

func sshIdentOffset(b []byte) int {
	best := -1
	for _, marker := range [][]byte{[]byte("SSH-2.0-"), []byte("SSH-1.99-")} {
		if i := bytes.Index(b, marker); i >= 0 && (best < 0 || i < best) {
			best = i
		}
	}
	return best
}

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

	// Golden original: respuesta 101.
	_, _ = client.Write([]byte("HTTP/1.1 101 Connection Established\r\n\r\n"))

	// Golden original: un solo Read(1024) para descartar la inyección inicial.
	// FIX mínimo: si HAProxy agrupó también la identificación SSH del cliente
	// dentro de ESTE MISMO Read, se conserva desde "SSH-2.0-" / "SSH-1.99-"
	// en vez de perderla. Todo lo demás mantiene la semántica Golden.
	client.SetReadDeadline(time.Now().Add(3 * time.Second))
	buffer := make([]byte, 1024)
	n, _ := client.Read(buffer)
	client.SetReadDeadline(time.Time{})

	var earlySSH []byte
	if n > 0 {
		if i := sshIdentOffset(buffer[:n]); i >= 0 {
			earlySSH = append(earlySSH, buffer[i:n]...)
		}
	}

	// Golden original: respuesta 200.
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

	// ÚNICO cambio funcional: reinyecta la identificación SSH que el Read
	// inicial habría descartado si llegó coalescida con el payload.
	if len(earlySSH) > 0 {
		if _, err := server.Write(earlySSH); err != nil {
			return
		}
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

gofmt -w "$SRC"
go build -ldflags='-s -w' -o "$TMPBIN" "$SRC"
"$TMPBIN" -h >/dev/null 2>&1

install -m 0755 "$TMPBIN" "$BIN"

mapfile -t units < <(
  systemctl list-unit-files --type=service --no-legend 2>/dev/null |
  awk '{print $1}' |
  grep -E '^proxygo_(shared80|[0-9]+)\.service$' || true
)

if ((${#units[@]} == 0)); then
  units=(proxygo_shared80.service)
fi

failed=0
for u in "${units[@]}"; do
  if systemctl cat "$u" >/dev/null 2>&1; then
    systemctl restart "$u" || failed=1
  fi
done

if (( failed != 0 )) || ! systemctl is-active --quiet proxygo_shared80.service; then
  echo "ERROR: ProxyGo no reinició. Restaurando binario anterior..."
  install -m 0755 "$BACKUP_DIR/proxygo" "$BIN"
  for u in "${units[@]}"; do
    systemctl restart "$u" >/dev/null 2>&1 || true
  done
  exit 1
fi

echo "[PASS] ProxyGo coalesced SSH-ident fix aplicado."
echo "[PASS] HAProxy/Xray/SSL/Path/UUID/usuarios/puertos/AUTO-TUNE: SIN CAMBIOS."
echo "[BACKUP] $BACKUP_DIR"
echo
echo "SHA-256 ProxyGo nuevo:"
sha256sum "$BIN"
echo
echo "Servicios ProxyGo:"
systemctl --no-pager --full status proxygo_shared80.service 2>/dev/null | sed -n '1,8p' || true
