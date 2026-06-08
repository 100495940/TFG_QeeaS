# Este script servirá para leer datos binarios pueros del puerto serie
# y guardar los datos del TRNG en un archivo .bin para tests del NIST

import numpy as np
import math
import matplotlib.pyplot as plt
import os
import serial
import time

# Puerto COM de la ESP32-C6
PORT = '/dev/ttyUSB0'
# Velocidad de la comunicación que usa la placa
BAUD = 115200
BYTES_TO_COLLECT = 1024 * 1024      # 1MB

def shannonEntropy(probabilities):
    return -np.sum([p * math.log2(p) for p in probabilities if p > 0])

def minEntropy(probabilities):
    return -math.log2(np.max(probabilities))

def chiSquareEntropy(byte_array):
    counts = np.bincount(byte_array, minlength=256)
    expected = len(byte_array)/256

    return np.sum((counts-expected)**2/expected)

destination_folder = 'data'
if not os.path.exists(destination_folder):
    os.makedirs(destination_folder)

bin_path = os.path.join(destination_folder, 'trng_data_radio_on.bin')
png_path = os.path.join(destination_folder, 'grafico_entropia.png')
report_path = os.path.join(destination_folder, 'reporte_matematico.txt')

data_buffer = bytearray()
kb_pasados = 0
last_heartbeat = time.time()

try:
    # Abrir el puerto al que está conectado la placa
    with serial.Serial(PORT, BAUD, timeout=1) as ser:
        # Limpiar buffer
        ser.reset_input_buffer()
        print(f"Conectado a {PORT}. Capturando {BYTES_TO_COLLECT} bytes de entropía pura.")

        while len(data_buffer) < BYTES_TO_COLLECT:
            bytes_to_read = BYTES_TO_COLLECT - len(data_buffer)
            chunk_to_read = ser.read(min(4096, bytes_to_read))
            if chunk_to_read:
                data_buffer.extend(chunk_to_read)

                actual_time = time.time()
                if actual_time - last_heartbeat >= 2:
                    first_byte = chunk_to_read[0]
                    print(f"[DEBUG] Entraron {len(chunk_to_read)} bytes. Muestra: 0x{first_byte:02X}")
                    last_heartbeat = actual_time

            kb_actuales = len(data_buffer) // 1024

            if kb_actuales - kb_pasados >= 64:
                print(f"    -> Progreso: {kb_actuales} KB / 1024 KB capturados...")
                kb_pasados = kb_actuales

    with open(bin_path, 'wb') as f:
        f.write(data_buffer)
    print(f"\n[*] EXITO: Archivo binario guardado en {bin_path}")

    print("\n[*] Aplicando fórmulas matemáticas para analizar la entropía generada...")

    byte_array = np.frombuffer(data_buffer, dtype=np.uint8)

    counts = np.bincount(byte_array, minlength=256)
    probabilities = counts/len(byte_array)
    expected = len(byte_array)/256

    shannon_entropy = shannonEntropy(probabilities)
    min_entropy = minEntropy(probabilities)
    chi_square_entropy = chiSquareEntropy(byte_array)

    with open(report_path, 'w') as f:
        f.write("==================================================\n")
        f.write(" REPORTE MATEMATICO DE ENTROPIA (Línea Base TRNG) \n")
        f.write("==================================================\n\n")
        f.write(f"Muestras analizadas : {len(byte_array)} bytes (1 MB)\n")
        f.write(f"Entropía de Shannon : {shannon_entropy:.6f} bits/byte (Ideal: 8.0)\n")
        f.write(f"Min-Entropía (NIST) : {min_entropy:.6f} bits/byte\n")
        f.write(f"Test Chi-Cuadrado   : {chi_square_entropy:.2f}\n")
        f.write("==================================================\n")
           
    print("\n[*] Captura completada. Generando radiografía de la entropía...")

    # Generar gráfico
    plt.figure(figsize=(10, 6))

    plt.hist(byte_array, bins=256, range=(0, 256), color='teal', alpha=0.8, edgecolor='black')
    plt.axhline(y=expected, color='red', linestyle='--', linewidth=1.5, label='Distribución Ideal')
    
    plt.title('Prueba de entropía: Distribución de Bytes (ESP32-C6 TRNG)', fontsize=14)
    plt.xlabel('Valor del Byte (0 - 255)', fontsize=12)
    plt.ylabel('Frecuencia de aparición', fontsize=12)
    plt.legend()
    plt.grid(axis='y', alpha=0.3)
    plt.savefig(png_path, dpi=300, bbox_inches='tight')

    print(f"[*] EXITO: Gráfico guardado en {png_path}.")
    print("[*] Búscalo en la barra lateral izquierda de VS Code y hazle doble clic.")

except serial.SerialException:
    print("[ERROR CRÍTICO] No se puede acceder al puerto USB.")
    print("Asegúrate de tener la placa conectada y el puerto libre.")

except KeyboardInterrupt:
    print("\n[*] Captura cancelada por el usuario.")