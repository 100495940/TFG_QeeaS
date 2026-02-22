# Este script servirá para leer el puerto serie
# y guardar los datos del TRNG en un archivo .bin

import serial
import time

# Puerto COM de la ESP32-C6
PORT = 'COM3'
# Velocidad de la comunicación que usa la placa
BAUD = 115200
FILENAME = "trng_data_radio_off.bin"
BYTES_TO_COLLECT = 1024 * 1024      # 1MB

# Abrimos el puerto al que está conectado la placa
ser = serial.Serial(PORT, BAUD, timeout=1)
print(f"Conectado a {PORT}. Capturando {BYTES_TO_COLLECT} bytes.")

with open(FILENAME, "wb") as f:
    bytes_count = 0
    while bytes_count < BYTES_TO_COLLECT:
        # Comprobamos si hay datos nuevos esperando en el puerto USB
        if ser.in_waiting > 0:
            data = ser.read(ser.in_waiting)
            f.write(data)
            bytes_count += len(data)
            print(f"Progreso: {bytes_count/BYTES_TO_COLLECT*100:.2f}%", end='\r')

print(f"\nCaptura finalizada. Archivo guardado como : {FILENAME}")
# Cerramos la conexión del puerto
ser.close()