#!/bin/bash

set -euo pipefail

echo "============================================="
echo "   TFG: Extractor de Entropia ESP32-C6       "
echo "============================================="

# Detectar modo de ejecución mediante argumentos
MODO_NIST=false
EXTRA_ARGS="-DZP_PLATFORM=zephyr"
NOMBRE_MODO="DEBUG (Red Zenoh y Texto legible)"

RUST_SERVER_PID=""
ZENOH_ROUTER_PID=""

ZENOH_PICO_VERSION="1.9.0"

QEEAS_LOG_DIR="/tmp/qeeas_logs"
QRNG_LOG_DIR="/tmp/qrng_logs"
mkdir -p "$QEEAS_LOG_DIR"
mkdir -p "$QRNG_LOG_DIR"

cleanup() {
    echo ""
    echo "[INFO] Cerrando entorno de forma segura..."

    if [ -n "$RUST_SERVER_PID" ]; then
        echo "[INFO] Deteniendo servidor Rust PID=$RUST_SERVER_PID..."
        kill "$RUST_SERVER_PID" 2>/dev/null || true
        wait "$RUST_SERVER_PID" 2>/dev/null || true
    fi

    if [ -n "$ZENOH_ROUTER_PID" ]; then
        echo "[INFO] Deteniendo router Zenoh PID=$ZENOH_ROUTER_PID..."
        kill "$ZENOH_ROUTER_PID" 2>/dev/null || true
        wait "$ZENOH_ROUTER_PID" 2>/dev/null || true
    fi

    echo "============================================="
    echo "    Entorno cerrado de forma segura          "
    echo "============================================="
}

trap cleanup EXIT INT TERM

# Limpiar entorno previo de Zenoh y Rust
bash scripts/zenoh_cleanup.sh

# Detectar modo de ejecución mediante argumentos
if [ "${1:-}" == "--nist" ]; then
    MODO_NIST=true
    EXTRA_ARGS="$EXTRA_ARGS -DCONFIG_ENTROPY_RAW_MODE=y"
    NOMBRE_MODO="NIST (Binario crudo a alta velocidad)"
fi

if [ -f "secrets.conf" ]; then
    EXTRA_ARGS="$EXTRA_ARGS -DOVERLAY_CONFIG=secrets.conf"
fi

echo "[INFO] Configuración seleccionada: $NOMBRE_MODO"
echo ""

# Levantar servidor de números cuánticos
echo "[0/6] Iniciando servidor de números cuánticos (QRNG)..."
rm -f /tmp/qeaas_api_url
if ! bash scripts/quant_lab.sh > "$QRNG_LOG_DIR/qrng_server.log" 2>&1; then
    echo "[ERROR] No se pudo iniciar el servidor QEaaS/QRNG."
    echo "[ERROR] Últimos logs:"
    tail -120 "$QRNG_LOG_DIR/qrng_server.log" || true
    exit 1
fi

QEAAS_API_URL="$(cat /tmp/qeaas_api_url)"
export QEAAS_API_URL

echo "[INFO] QEaaS disponible para Rust en: $QEAAS_API_URL"

# Compilar
BLOBS_DIR="/workspaces/zephyrproject/modules/hal/espressif/zephyr/blobs"

echo "[1/6] Verificando dependencias de hardware Wi-Fi y Zenoh-Pico"
#west blobs fetch hal_espressif
# Comprobar blobs de Espressif para el Wi-Fi
if [ ! -d "$BLOBS_DIR" ]; then
    echo "[INFO] Blobs de Espressif no encontrados. Descargando..."
    west blobs fetch hal_espressif > /dev/null 2>&1
else
    echo "[INFO] Blobs de Espressif ya disponibles."
fi

# Comprobar instalación de Zenoh-Pico
if [ ! -d "lib/zenoh-pico" ]; then
    echo "[INFO] Zenoh-Pico no detectado en 'lib/'. Clonando repositorio oficial..."
    mkdir -p lib
    git clone https://github.com/eclipse-zenoh/zenoh-pico.git lib/zenoh-pico
    echo "[INFO] Zenoh-Pico instalado con éxito."
else
    echo "[INFO] Zenoh-Pico ya instalado localmente. Saltando descarga."
fi

echo "[INFO] Fijando Zenoh-Pico a la versión $ZENOH_PICO_VERSION..."
cd lib/zenoh-pico
git fetch --tags

if git rev-parse "$ZENOH_PICO_VERSION" >/dev/null 2>&1; then
    git checkout "$ZENOH_PICO_VERSION"
elif git rev-parse "v$ZENOH_PICO_VERSION" >/dev/null 2>&1; then
    git checkout "v$ZENOH_PICO_VERSION"
else
    echo "[ERROR] No se encontró tag de Zenoh-Pico para versión $ZENOH_PICO_VERSION"
    echo "[ERROR] Tags disponibles similares:"
    git tag -l | grep "$ZENOH_PICO_VERSION" || true
    exit 1
fi

cd /workspaces/TFG_QeeaS
echo "[INFO] Zenoh-Pico fijado correctamente."

echo "[INFO] Aplicando parche de compatibilidad Zenoh-Pico / Zephyr..."

python3 - <<'PY'
from pathlib import Path

ZENOH_PICO_DIR = Path("/workspaces/TFG_QeeaS/lib/zenoh-pico")

replacement = """#if __has_include(<zephyr/version.h>)
#include <zephyr/version.h>
#else
#include <version.h>
#endif"""

patched_files = []

for path in ZENOH_PICO_DIR.rglob("*"):
    if path.suffix not in [".c", ".h"]:
        continue

    text = path.read_text(errors="ignore")

    if "#include <version.h>" in text:
        text = text.replace("#include <version.h>", replacement)
        path.write_text(text)
        patched_files.append(str(path))

if patched_files:
    print("[OK] Archivos parcheados:")
    for file in patched_files:
        print(" -", file)
else:
    print("[INFO] No había includes <version.h> pendientes de parchear.")
PY

echo "[2/6] Limpiando caché antigua y compilando el firmware"

rm -rf build/
west build -p always -b esp32c6_devkitc/esp32c6/hpcore . -- $EXTRA_ARGS
#west build -p auto -b esp32c6_devkitc/esp32c6/hpcore . -- $EXTRA_ARGS

if [ $? -ne 0 ]; then
    echo "Error la compilación ha fallado"
    exit 1
fi

if [ "$MODO_NIST" = false ]; then
    echo "[3/6] Levantando router Zenoh zenoh en segundo plano..."

    if ! command -v zenohd >/dev/null 2>&1; then
        echo "[ERROR] Zenohd no se encuentra instalado dentro del devcontainer"
        echo "[ERROR] Instálalo en el Dockerfile o en .devcontainer/setup.sh"
        exit 1
    fi

    zenohd --cfg='listen/endpoints:["tcp/0.0.0.0:7447"]' > "$QEEAS_LOG_DIR/zenoh_router.log" 2>&1 &
    ZENOH_ROUTER_PID=$!
    echo "[INFO] Router Zenoh zenohd iniciado con PID: $ZENOH_ROUTER_PID"
    echo "[INFO] Puedes revisar los logs del router en: $QEEAS_LOG_DIR/zenoh_router.log"

    sleep 2

    if ss -ltn | grep -q ":7447"; then
        echo "[INFO] Router Zenoh escuchando en el puerto 7447"
    else
        echo "[ERROR] Router Zenoh no está escuchando en el puerto 7447"
        echo "[ERROR] Revisa los logs en: $QEEAS_LOG_DIR/zenoh_router.log"
        exit 1
    fi

    echo "[4/6] Lanzando servidor Rust de Zenoh en segundo plano..."
    RUST_PROFILE="${RUST_PROFILE:-debug}"
    QEEAS_BUILD_RUST="${QEEAS_BUILD_RUST:-1}"

    if [ "$QEEAS_BUILD_RUST" = "1" ]; then
        echo "[INFO] Compilando servidor Rust antes de lanzarlo..."
        echo "[INFO] Log de compilación Rust: $QEEAS_LOG_DIR/rust_build.log"

        if ! bash scripts/rust_build.sh > "$QEEAS_LOG_DIR/rust_build.log" 2>&1; then
            echo "[ERROR] Falló la compilación del servidor Rust."
            echo "[ERROR] Últimas líneas del log:"
            tail -80 "$QEEAS_LOG_DIR/rust_build.log"
            exit 1
        fi
    else
        echo "[INFO] Saltando compilación Rust porque QEEAS_BUILD_RUST=0"
    fi

    echo "[INFO] Lanzando servidor Rust ya compilado..."
    bash scripts/rust_run.sh > "$QEEAS_LOG_DIR/rust_server.log" 2>&1 &

    RUST_SERVER_PID=$!

    echo "[INFO] Servidor Rust iniciado con PID: $RUST_SERVER_PID"
    echo "[INFO] Log del servidor Rust: $QEEAS_LOG_DIR/rust_server.log"

    echo "[INFO] Esperando a que el servidor Rust abra sesión Zenoh..."

    RUST_READY=false

    for i in {1..60}; do
        if ! kill -0 "$RUST_SERVER_PID" 2>/dev/null; then
            echo "[ERROR] El servidor Rust ha terminado antes de estar listo."
            echo "[ERROR] Últimas líneas del log:"
            tail -80 "$QEEAS_LOG_DIR/rust_server.log"
            exit 1
        fi

        if grep -q "Sesión de Zenoh abierta\|Publicando QRNG" "$QEEAS_LOG_DIR/rust_server.log"; then
            RUST_READY=true
            echo "[INFO] Servidor Rust conectado correctamente a Zenoh."
            break
        fi

        sleep 1
    done

    if [ "$RUST_READY" != "true" ]; then
        echo "[ERROR] Timeout esperando al servidor Rust."
        echo "[ERROR] Últimas líneas del log:"
        tail -80 "$QEEAS_LOG_DIR/rust_server.log"
        exit 1
    fi
else
    echo "[INFO] Modo NIST activado. No se lanzará el servidor Rust ni el router Zenoh."
fi

echo "[5/6] Flasheando código sobre la ESP32-C6"
west flash --esp-device /dev/ttyUSB0

if [ $? -eq 0 ]; then
    echo "============================================="
    echo " EXITO: El firmware esta corriendo sobre la placa"
    echo "============================================="
else
    echo "[ERROR] No se pudo grabar. Asegurate de haber pasado el USB con usbipd."
fi

# Análisis entropía
echo ""
echo "[6/6] Firmware ejecutándose. Escuchando el puerto USB..."
sleep 2

if [ "$MODO_NIST" = true ]; then
    echo "[INFO] Iniciando captura del Megabyte binario con Python..."

    python3 scripts/entropy.py

    if [ $? -eq 0 ]; then
        echo "============================================="
        echo " EXITO: Proceso completo. Revisa el grafico!"
        echo "============================================="
    else
        echo "[ERROR] Fallo al analizar los datos con Python."
    fi

else
    echo "[INFO] Entrando en modo Monitor Serie automáticamente."
    echo "[INFO] Para salir del monitor pulsa: Ctrl + X"
    echo "---------------------------------------------"
    # Añadir argumento --exit-char 24 para poder salir del monitor
    python3 -m serial.tools.miniterm --exit-char 24 /dev/ttyUSB0 115200
fi