// Firmware para extraer los datos de la placa ESP32-C6
// Vamos a capturar bloques de aleatoriedad de la placa
// y a enviarlos en formato binario puro por el puerto serie

#include "entropy.h"
#include <stdio.h>
#include <zephyr/kernel.h>
#include <zephyr/device.h>
#include <zephyr/drivers/entropy.h>
#include <zephyr/pm/device.h>

// Función para activar la radio de la placa como
// fuente de entropía
void set_radio_entropy(bool enable) {
    if(enable){
        printk("Modo de entropía: RADIO ON.\n");
    } else {
        printk("Modo de entropía: RADIO OFF.\n");
    }
}

void send_trng_data_ask(void) {
    // Crear buffer  de 512 bytes
    uint8_t rand_buffer[512];

    // Pedir al RTOS el driver del generador de entropía
    const struct device *entropy_dev = DEVICE_DT_GET(DT_CHOSEN(zephyr_entropy));

    if (!device_is_ready(entropy_dev)) {
        printk("Error: El hardware de entropía del ESP32-C6 no está listo.\n");
        return;
    }

    // Encender la radio
    set_radio_entropy(true);

    while(1) {
        // Extraer entropía del hardware usando la API de Zephyr
        int ret = entropy_get_entropy(entropy_dev, rand_buffer, sizeof(rand_buffer));

        if (ret == 0) {
            //fwrite(rand_buffer, 1, sizeof(rand_buffer), stdout);
            //fflush(stdout);
            printk("[TRNG] Bloque extraido. Primer byte: 0x%02X\n", rand_buffer[0]);
        }

        // Pausar el scheduler de Zephyr
        k_msleep(1000);
    }
}