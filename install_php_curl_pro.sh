#!/bin/bash
set -e

echo "======================================"
echo "🔧 CONFIGURANDO PHP + CURL (MODO PRO)"
echo "======================================"

export DEBIAN_FRONTEND=noninteractive

# =========================
# ACTUALIZAR SISTEMA
# =========================
echo "📦 Actualizando repositorios..."
apt update -y

# =========================
# INSTALAR BASE
# =========================
echo "📦 Instalando paquetes base..."
apt install -y curl wget unzip software-properties-common

# =========================
# VERIFICAR PHP
# =========================
if ! command -v php >/dev/null 2>&1; then
    echo "⚙️ PHP no encontrado, instalando..."
    apt install -y php php-cli php-common
fi

# =========================
# DETECTAR VERSION PHP
# =========================
PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;" 2>/dev/null)

if [ -z "$PHP_VERSION" ]; then
    echo "❌ No se pudo detectar PHP"
    exit 1
fi

echo "📌 PHP detectado: $PHP_VERSION"

# =========================
# INSTALAR CURL SEGÚN VERSION
# =========================
echo "⚙️ Instalando php$PHP_VERSION-curl..."

if ! apt install -y php$PHP_VERSION-curl; then
    echo "⚠️ Instalación específica falló, usando fallback..."
    apt install -y php-curl
fi

# =========================
# HABILITAR MODULO
# =========================
echo "🔌 Habilitando módulo curl..."
phpenmod curl 2>/dev/null || true

# =========================
# REINICIAR SERVICIOS
# =========================
echo "🔄 Reiniciando servicios..."

systemctl restart php$PHP_VERSION-fpm 2>/dev/null || true
systemctl restart apache2 2>/dev/null || true
systemctl restart nginx 2>/dev/null || true
systemctl restart api-vps 2>/dev/null || true

# =========================
# VERIFICACION REAL
# =========================
echo "🔍 Verificando módulo CURL..."

if php -m | grep -q curl; then
    echo "✅ CURL activo en módulos PHP"
else
    echo "❌ CURL no aparece en módulos"
fi

# =========================
# TEST FUNCION REAL
# =========================
echo "🧪 Test de función curl_init():"

RESULT=$(php -r "echo function_exists('curl_init') ? 'OK' : 'FAIL';")

if [ "$RESULT" = "OK" ]; then
    echo "✅ curl_init() FUNCIONANDO"
else
    echo "❌ curl_init() FALLANDO"

    echo "⚠️ Intentando solución avanzada..."

    apt purge -y php*curl || true
    apt install -y php-curl
    phpenmod curl || true

    systemctl restart php$PHP_VERSION-fpm 2>/dev/null || true

    RESULT2=$(php -r "echo function_exists('curl_init') ? 'OK' : 'FAIL';")

    if [ "$RESULT2" = "OK" ]; then
        echo "✅ CURL RECUPERADO"
    else
        echo "💥 ERROR CRÍTICO: CURL NO FUNCIONA"
        echo "👉 Revisar múltiples versiones de PHP"
    fi
fi

# =========================
# INFO FINAL
# =========================
echo "======================================"
echo "📊 INFORMACIÓN FINAL"
echo "======================================"

php -v
echo ""
php --ini
echo ""

echo "🚀 CONFIGURACIÓN TERMINADA"
