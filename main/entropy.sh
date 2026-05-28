#!/bin/bash
echo "============================================="
echo "   TFG: Extractor de Entropia ESP32-C6       "
echo "============================================="

# Compilar
echo "[1/2] Limpiando caché antigua y compilando el firmware"
rm -rf build/
west build -p always -b esp32c6_devkitc/esp32c6/hpcore

if [ $? -ne 0 ]; then
    echo "Error la compilación ha fallado"
    exit 1
fi

echo "[2/2] Flasheando código sobre la ESP32-C6"
west flash --esp-device /dev/ttyUSB0

if [ $? -eq 0 ]; then
    echo "============================================="
    echo " EXITO: El firmware esta corriendo sobre la placa"
    echo "============================================="
else
    echo "Error: No se pudo grabar. Asegurate de haber pasado el USB con usbipd."
fi