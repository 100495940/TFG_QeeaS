// Firmware para extraer los datos de la placa ESP32-C6
// Vamos a capturar bloques de aleatoriedad de la placa
// y a enviarlos en formato binario puro por el puerto serie
// Capaz de cambiar dinámicamente entre modo Debug (Texto) 
// y NIST (binario) para el análisis matemático.

#include "entropy.h"
#include <stdio.h>
#include <zephyr/kernel.h>
#include <zephyr/device.h>
#include <zephyr/drivers/entropy.h>
#include <zephyr/pm/device.h>
#include <zephyr/drivers/uart.h>

// Función para activar la radio de la placa como
// fuente de entropía
void set_radio_entropy(bool enable) {
#ifndef CONFIG_ENTROPY_RAW_MODE
    if(enable){
        printk("Modo de entropía: RADIO ON.\n");
    } else {
        printk("Modo de entropía: RADIO OFF.\n");
    }
#endif
}

// Función para extrar entropía bajo demanda
void get_trng_bytes(uint8_t *buffer, size_t length) {
    const struct device *entropy_dev = DEVICE_DT_GET(DT_CHOSEN(zephyr_entropy));
    if (!device_is_ready(entropy_dev)) {
        return;
    }

    entropy_get_entropy(entropy_dev, buffer, length);
}

// Función para modo nist
void send_trng_data_ask(void) {
    // Crear buffer  de 512 bytes
    uint8_t rand_buffer[512];

    // Pedir al RTOS el driver del generador de entropía
    const struct device *entropy_dev = DEVICE_DT_GET(DT_CHOSEN(zephyr_entropy));
    const struct device *uart_dev = DEVICE_DT_GET(DT_CHOSEN(zephyr_console));

    if (!device_is_ready(entropy_dev) || !device_is_ready(uart_dev)) {
#ifndef CONFIG_ENTROPY_RAW_MODE
        printk("Error: El hardware de entropía del ESP32-C6 no está listo.\n");
#endif
        return;
    }

    // Encender la radio
    set_radio_entropy(true);

    while(1) {
        // Extraer entropía del hardware usando la API de Zephyr
        int ret = entropy_get_entropy(entropy_dev, rand_buffer, sizeof(rand_buffer));

        if (ret == 0) {
#ifdef CONFIG_ENTROPY_RAW_MODE
            for (int i = 0; i < sizeof(rand_buffer); i++) {
                uart_poll_out(uart_dev, rand_buffer[i]);
            }
            k_yield();
#else
            //fwrite(rand_buffer, 1, sizeof(rand_buffer), stdout);
            //fflush(stdout);
            printk("[TRNG] Bloque extraido. Primer byte: 0x%02X\n", rand_buffer[0]);
        

        // Pausar el scheduler de Zephyr
        k_msleep(1000);      
#endif
        }
    }
}