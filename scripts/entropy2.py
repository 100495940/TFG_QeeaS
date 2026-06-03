# Este script servirá para leer el puerto serie
# y guardar los datos del TRNG en un archivo .bin

import matplotlib.pyplot as plt
import os
import serial
import time

destination_folder = 'data'
if not os.path.exists(destination_folder):
    os.makedirs(destination_folder)

path = os.path.join(destination_folder, 'grafico_entropia.png')

# Puerto COM de la ESP32-C6
PORT = '/dev/ttyUSB0'
# Velocidad de la comunicación que usa la placa
BAUD = 921600
FILENAME = "trng_data_radio_on.bin"
#BYTES_TO_COLLECT = 1024 * 1024      # 1MB
MUESTRAS = 500
data = []

try:
    # Abrir el puerto al que está conectado la placa
    with serial.Serial(PORT, BAUD, timeout=1) as ser:
        # Limpiar buffer
        ser.reset_input_buffer()
        print(f"Conectado a {PORT}. Capturando {MUESTRAS} muestras.")

        while len(data) < MUESTRAS:
            # Leer una linea, decodificarla, quitar espacios y guardarla
            line = ser.readline().decode('utf-8', errors='ignore').strip()

            if line and line.lstrip('-').isdigit():
                data.append(int(line))

                # Imprimir progreso cada 1000 muestras
                if len(data) % 1000 == 0:
                    print(f"-> {len(data)} muestras capturadas...")

    print("\n[*] Captura completada. Generando radiografía de la entropía...")

    # Generar gráfico
    plt.figure(figsize=(10, 6))

    plt.hist(data, bins=50, color='teal', alpha=0.8, edgecolor='black')
    plt.title('Prueba de entropía: Distribución de valores generados por ESP32-C6', fontsize=14)
    plt.xlabel('Valor del número aletorio', fontsize=12)
    plt.ylaberl('Frecuencia de aparición', fontsize=12)
    plt.grid(axis='y', alpha=0.3)

    plt.savefig(path, dpi=300, bbox_inches='tight')

    print(f"[*] EXITO: Gráfico guardado en {path}.")
    print("[*] Búscalo en la barra lateral izquierda de VS Code y hazle doble clic.")

except serial.SerialException:
    print("[ERROR CRÍTICO] No se puede acceder al puerto USB.")
    print("Asegúrate de tener la placa conectada y el puerto libre.")

except KeyboardInterrupt:
    print("\n[*] Captura cancelada por el usuario.")