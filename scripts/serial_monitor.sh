# Archivo para ver en directo que está realizando
# nuestra placa ESP32-C6 con el monitor nativo de python

#!/bin/bash

echo "============================================="
echo "   MONITOR SERIE TFG (ESP32-C6)              "
echo "   Puerto: /dev/ttyUSB0 a 115200 baudios     "
echo "   Para SALIR del monitor pulsa:  Ctrl + ]   "
echo "============================================="
echo ""

# Comprobar si la placa está conectada antes de abrir
if [ ! -e /dev/ttyUSB0 ]; then
    echo "[ERROR] No se detecta la placa en /dev/ttyUSB0."
    echo "Asegurate de haber ejecutado el lanzador de Windows."
    exit 1
fi

# Iniciar el monitor nativo de Python
python3 -m serial.tools.miniterm /dev/ttyUSB0 115200