#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include "zenoh-pico.h"

#define QRNG_TOPIC "qeeas/qrng/chunk"
#define STATUS_TOPIC "qeeas/esp32/status"
#define BLOCK_SIZE 32

LOG_MODULE_REGISTER(zenoh_client, LOG_LEVEL_INF);

static z_owned_session_t session;
static z_owned_publisher_t status_publisher;

// Función que se ejecuta cuando recibe mensaje en el topico de entropía
static void recepcion_qrng_callback(const z_sample_t *sample, void *arg) {
    if (sample->payload.len != BLOCK_SIZE) {
        LOG_ERR("Bloque QRNG ignorado: Tamaño incorrecto: (%d bytes)", sample->payload.len);
        return;
    }

    uint8_t qrng_buffer[BLOCK_SIZE];
    uint8_t trng_buffer[BLOCK_SIZE];
    uint8_t final_entropy_buffer[BLOCK_SIZE];

    // Recibir entropía cuántica del servidor
    memcpy(qrng_buffer, sample->payload.start, BLOCK_SIZE);

    // Extraer entropía local del TRNG de la placa
    get_trng_bytes(trng_buffer, BLOCK_SIZE);

    // Fusión criptográfica ambos bloques de entropía usando XOR
    for (int i = 0; i < BLOCK_SIZE; i++) {
        final_entropy_buffer[i] = qrng_buffer[i] ^ trng_buffer[i];
    }

    LOG_INF("Fusión completada. TRNG y QRNG combinados.");

    // Publicar el bloque de status
    char status_msg[64];
    snprintf(status_msg, sizeof(status_msg), "Fusión OK - Pool de entropía local listo");

    z_publisher_put_options_t options = z_publisher_put_options_default();
    z_publisher_put(z_loan(status_publisher), (const uint8_t *)status_msg, strlen(status_msg), &options);
}

// Hilo principal de Zenoh
void zenoh_client_thread(void) {
    LOG_INF("Iiniciando Zenoh-Pico en el ESP32-C6");

    z_owned_config_t config = z_config_default();
    LOG_INF("Abriendo sesión de red");

    if (z_open(&session, z_move(config), NULL) < 0) {
        LOG_ERR("Fallo al abrir la sesión de Zenoh-Pico. ¿Está el servidor Rust encendido?");
        return;
    }

    // Crear el publicador para enviar el estado al servidor Rust
    if (z_declare_publisher(z_loan(session), &status_publisher, z_keyexpr(STATUS_TOPIC), NULL) < 0) {
        LOG_ERR("Error al declarar el publicador de estado");
        return;
    }

    // Crear el suscriptor para recibir los bloques de entropía del servidor
    z_owned_closure_sample_t callback;
    z_closure_sample(&callback, recepcion_qrng_callback, ,NULL, NULL);

    z_owned_subscriber_t subscriber;
    if (z_declare_subscriber(z_loan(session), &subscriber, z_keyexpr(QRNG_TOPIC), z_move(callback), NULL) < 0) {
        LOG_ERR("Error al suscribirse al tópico del QRNG");
        return;
    }

    LOG_INF("Cliente Zenoh-Pico activo. Escuchando en %s y publicando en %s", QRNG_TOPIC, STATUS_TOPIC);

    while(1) {
        k_msleep(100);
    }
}