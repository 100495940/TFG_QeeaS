// Firmware para extraer los datos de la placa ESP32-C6
// Vamos a capturar bloques de aleatoriedad de la placa
// y a enviarlos en formato binario puro por el puerto serie

#include <stdio.h>
#include "esp_random.h"
#include "esp_wifi.h"
#include "nvs_flash.h"

// Función para activar la radio de la placa como
// fuente de entropía
void set_radio_entropy(bool enable) {
    if(enable){
        printf("Modo de entropía: RADIO ON");
        // Inicializamos almacenamiento no volátil para el Wi-Fi
        nvs_flash_init();
        // Inicializamos pila de red
        esp_netif_init();
        // Creamos sistemas que gestione eventos
        esp_event_loop_create_default();
        // Estructura con la configuración inicial del Wi-Fi
        wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
        esp_wifi_init(&cfg);
        // Activamos la radio para utilizar el ruido electromagnético
        // para alimentar el hardware del generador aleatorio
        esp_wifi_start();
    } else {
        printf("Modo de entropía: RADIO OFF");
        // Apagamos la radio, dejando al generador sin su fuente
        // principal de entropía
        esp_wifi_stop();
    }
}

void send_trng_data_ask(void) {
    // Creamos buffer  de 512 bytes
    uint8_t rand_buffer[512];

    // Encendemos la radio
    set_radio_entropy(true);

    while(1) {
        // Llenamos el buffer con toda la aleatoriedad disponible
        esp_fill_random(rand_buffer, sizeof(rand_buffer));
        fwrite(rand_buffer, 1, sizeof(rand_buffer), stdout);
        // Delay de 10 milisegundos
        vTaskDelay(pdMS_TO_TICKS(10));
    }
}