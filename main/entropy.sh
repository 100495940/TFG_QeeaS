#!/bin/bash
echo "============================================="
echo "   TFG: Extractor de Entropia ESP32-C6       "
echo "============================================="

# Detectar modo de ejecución mediante argumentos
MODO_NIST=false
EXTRA_ARGS=""
NOMBRE_MODO="DEBUG (Texto legible)"

if [ "$1" == "--nist" ]; then
    MODO_NIST=true
    EXTRA_ARGS="-- -DCONFIG_ENTROPY_RAW_MODE=y"
    NOMBRE_MODO="NIST (Binario crudo a alta velocidad)"
fi

echo "[INFO] Configuración seleccionada: $NOMBRE_MODO"
echo ""

# Compilar
BLOBS_DIR="/workspaces/zephyrproject/modules/hal/espressif/zephyr/blobs"
echo "[1/4] Verificando dependencias de hardware Wi-Fi"
if [ ! -d "$BLOBS_DIR" ]; then
    west blobs fetch hal_espressif > /dev/null 2>&1
fi

echo "[2/4] Limpiando caché antigua y compilando el firmware"
rm -rf build/
west build -p always -b esp32c6_devkitc/esp32c6/hpcore $EXTRA_ARGS
#west build -p auto -b esp32c6_devkitc/esp32c6/hpcore $EXTRA_ARGS

if [ $? -ne 0 ]; then
    echo "Error la compilación ha fallado"
    exit 1
fi

echo "[3/4] Flasheando código sobre la ESP32-C6"
west flash --esp-device /dev/ttyUSB0

if [ $? -eq 0 ]; then
    echo "============================================="
    echo " EXITO: El firmware esta corriendo sobre la placa"
    echo "============================================="
else
    echo "Error: No se pudo grabar. Asegurate de haber pasado el USB con usbipd."
fi

# Análisis entropía
echo ""
echo "[4/4] Firmware ejecutándose. Escuchando el puerto USB..."
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