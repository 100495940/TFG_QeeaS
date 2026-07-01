#define ZENOH_ZEPHYR 1
#include <stdint.h>
#include <stdio.h>
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include <zenoh-pico.h>
#include "entropy.h"

#define QRNG_TOPIC "qeeas/qrng/chunk"
#define STATUS_TOPIC "qeeas/esp32/status"
#define BLOCK_SIZE 32

LOG_MODULE_REGISTER(zenoh_client, LOG_LEVEL_INF);

static z_owned_session_t session;
static z_owned_publisher_t status_publisher;
static z_owned_subscriber_t qrng_subscriber;

// Función que se ejecuta cuando recibe mensaje en el topico de entropía
static void recepcion_qrng_callback(z_loaned_sample_t *sample, void *arg) {
    ARG_UNUSED(arg);

    const z_loaned_bytes_t *payload = z_sample_payload(sample);
    size_t payload_len = z_bytes_len(payload);

    // Validar que el servidor envía exactamente 32 bytes de entropía cuántica
    if (payload_len != BLOCK_SIZE) {
        LOG_ERR("Bloque QRNG ignorado: Tamaño incorrecto: (%zu bytes)", payload_len);
        return;
    }

    uint8_t qrng_buffer[BLOCK_SIZE];
    uint8_t trng_buffer[BLOCK_SIZE];
    uint8_t final_entropy_buffer[BLOCK_SIZE];

    // Recibir entropía cuántica del servidor
    z_bytes_reader_t reader = z_bytes_get_reader(payload);
    size_t read_bytes = z_bytes_reader_read(&reader, qrng_buffer, BLOCK_SIZE);

    if (read_bytes != BLOCK_SIZE) {
        LOG_ERR("Error al leer el bloque QRNG: (%zu bytes leídos)", read_bytes);
        return;
    }

    LOG_INF("Bloque QRNG recibido correctamente (%zu bytes)", read_bytes);

    // Extraer entropía local del TRNG de la placa
    get_trng_bytes(trng_buffer, BLOCK_SIZE);

    // Fusión criptográfica ambos bloques de entropía usando XOR
    for (size_t i = 0; i < BLOCK_SIZE; i++) {
        final_entropy_buffer[i] = qrng_buffer[i] ^ trng_buffer[i];
    }

    LOG_INF("Fusión completada. TRNG y QRNG combinados.");

    // Publicar el bloque de status
    char status_msg[64];
    snprintf(status_msg, sizeof(status_msg), "Fusión OK - Pool de entropía local listo");

    z_owned_bytes_t pub_payload;
    if (z_bytes_copy_from_str(&pub_payload, status_msg) < 0) {
        LOG_ERR("Error al crear el payload de estado");
        return;
    }
    
    if (z_publisher_put(z_loan(status_publisher), z_move(pub_payload), NULL) < 0) {
        LOG_ERR("Error al publicar el estado por Zenoh");
        return;
    }

    LOG_INF("Estado publicado correctamente en %s: %s ", STATUS_TOPIC, status_msg);
}

// Hilo principal de Zenoh
void zenoh_client_thread(void) {
    LOG_INF("Iniciando Zenoh-Pico en el ESP32-C6");

    z_owned_config_t config;
    if (z_config_default(&config) < 0) {
        LOG_ERR("Error al crear la configuración por defecto de Zenoh-Pico");
        return;
    }
    LOG_INF("Abriendo sesión de red");

    if (zp_config_insert(z_config_loan_mut(&config), Z_CONFIG_MODE_KEY, Z_CONFIG_MODE_CLIENT) < 0) {
        LOG_ERR("Error configurando Zenoh en modo cliente");
        return;
    }

    if (zp_config_insert(z_config_loan_mut(&config), Z_CONFIG_CONNECT_KEY, CONFIG_ZENOH_ENDPOINT) < 0) {
        LOG_ERR("Error configurando endpoint Zenoh");
        return;
    }

    if (z_open(&session, z_move(config), NULL) < 0) {
        LOG_ERR("Fallo al abrir la sesión de Zenoh-Pico. ¿Está el servidor Rust encendido?");
        return;
    }

    // Crear el publicador para enviar el estado al servidor Rust
    z_view_keyexpr_t key_pub;
    if (z_view_keyexpr_from_str(&key_pub, STATUS_TOPIC) < 0) {
        LOG_ERR("Error al crear el keyexpr para el publicador de estado");
        return;
    }

    if (z_declare_publisher(z_loan(session), &status_publisher, z_loan(key_pub), NULL) < 0) {
        LOG_ERR("Error al declarar el publicador de estado");
        return;
    }

    // Crear el suscriptor para recibir los bloques de entropía del servidor
    z_owned_closure_sample_t callback;
    if (z_closure_sample(&callback, recepcion_qrng_callback, NULL, NULL) < 0) {
        LOG_ERR("Error al crear el callback para el suscriptor de QRNG");
        return;
    }

    z_view_keyexpr_t key_sub;
    if (z_view_keyexpr_from_str(&key_sub, QRNG_TOPIC) <0) {
        LOG_ERR("Error al crear el keyexpr para el suscriptor de QRNG");
        return;
    }

    if (z_declare_subscriber(z_loan(session), &qrng_subscriber, z_loan(key_sub), z_move(callback), NULL) < 0) {
        LOG_ERR("Error al suscribirse al tópico del QRNG");
        return;
    }

    LOG_INF("Cliente Zenoh-Pico activo. Escuchando en %s y publicando en %s", QRNG_TOPIC, STATUS_TOPIC);

    while(1) {
        k_msleep(100);
    }
}