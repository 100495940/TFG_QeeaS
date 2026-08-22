#define ZENOH_ZEPHYR 1
#include <errno.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include <zephyr/net/socket.h>
#include <zenoh-pico.h>
#include "entropy.h"
#include "entropy_pool.h"

#define QRNG_TOPIC "qeeas/qrng/chunk"
#define STATUS_TOPIC "qeeas/esp32/status"
#define ENTROPY_SOURCE_TRNG_TOPIC   "qeeas/esp32/entropy/source/trng"
#define ENTROPY_SOURCE_QRNG_TOPIC   "qeeas/esp32/entropy/source/qrng"
#define ENTROPY_FINAL_ACTIVE_TOPIC  "qeeas/esp32/entropy/final/active"
#define ENTROPY_FINAL_XOR_TOPIC     "qeeas/esp32/entropy/final/xor"
#define BLOCK_SIZE 32

LOG_MODULE_REGISTER(zenoh_client, LOG_LEVEL_INF);

static z_owned_session_t session;
static z_owned_publisher_t status_publisher;
static z_owned_subscriber_t qrng_subscriber;

// Función para crear el status enriquecido
static int crear_status_fusion(char *status_msg,
                               size_t status_msg_len,
                               const uint8_t *qrng_buffer,
                               const uint8_t *trng_buffer,
                               const uint8_t *final_entropy_buffer) {
    int written;

    if (status_msg == NULL ||
        qrng_buffer == NULL ||
        trng_buffer == NULL ||
        final_entropy_buffer == NULL ||
        status_msg_len == 0) {
        return -EINVAL;
    }

    written = snprintf(status_msg,
                       status_msg_len,
                       "FUSION_OK "
                       "mode=%s "
                       "counter=%llu "
                       "qrng_len=%d "
                       "trng_len=%d "
                       "out_len=%d "
                       "qrng_head=%02x%02x%02x%02x "
                       "trng_head=%02x%02x%02x%02x "
                       "out_head=%02x%02x%02x%02x",
                       entropy_pool_get_last_mix_mode(),
                       (unsigned long long)entropy_pool_get_mix_counter(),
                       BLOCK_SIZE,
                       BLOCK_SIZE,
                       BLOCK_SIZE,
                       qrng_buffer[0], qrng_buffer[1],
                       qrng_buffer[2], qrng_buffer[3],
                       trng_buffer[0], trng_buffer[1],
                       trng_buffer[2], trng_buffer[3],
                       final_entropy_buffer[0], final_entropy_buffer[1],
                       final_entropy_buffer[2], final_entropy_buffer[3]);

    if (written < 0) {
        return -EINVAL;
    }

    if ((size_t)written >= status_msg_len) {
        LOG_WRN("Status de fusion truncado. written=%d buffer=%zu",
                written,
                status_msg_len);
    }

    return 0;
}

// Función para publicar bloques de bytes puros para su posterior análisis en el servidor Rust
static int publicar_bytes_zenoh(const z_loaned_session_t *session,
                                const char *topic,
                                const uint8_t *buffer,
                                size_t buffer_len) {
    z_view_keyexpr_t key_pub;
    z_owned_publisher_t publisher;
    z_owned_bytes_t payload;
    int ret;

    if (session == NULL || topic == NULL || buffer == NULL || buffer_len == 0) {
        LOG_ERR("No se puede publicar payload binario: argumentos invalidos");
        return -EINVAL;
    }

    // Crear el publicador para enviar el bloque de bytes al servidor Rust
    ret = z_view_keyexpr_from_str(&key_pub, topic);
    if (ret < 0) {
        LOG_ERR("Keyexpr invalido para topic %s: %d", topic, ret);
        return ret;
    }

    ret = z_declare_publisher(session,
                          &publisher,
                          z_loan(key_pub),
                          NULL);
    if (ret < 0) {
        LOG_ERR("No se pudo declarar publisher binario para %s: %d",
                topic,
                ret);
        return ret;
    }

    ret = z_bytes_copy_from_buf(&payload, buffer, buffer_len);
    if (ret < 0) {
        LOG_ERR("No se pudo crear payload binario para %s: %d",
                topic,
                ret);
        z_drop(z_move(publisher));
        return ret;
    }

    ret = z_publisher_put(z_loan(publisher), z_move(payload), NULL);

    z_drop(z_move(publisher));

    if (ret < 0) {
        LOG_ERR("Error publicando payload binario en %s: %d",
                topic,
                ret);
        return ret;
    }

    LOG_INF("Payload binario publicado en %s (%zu bytes)", topic, buffer_len);

    return 0;
}

// Función que se ejecuta cuando recibe mensaje en el tópico de entropía
static void recepcion_qrng_callback(z_loaned_sample_t *sample, void *arg) {
    LOG_INF("CALLBACK QRNG INVOCADO");

    ARG_UNUSED(arg);

    const z_loaned_bytes_t *payload = z_sample_payload(sample);
    size_t payload_len = z_bytes_len(payload);

    // Validar que el servidor envía exactamente 32 bytes de entropía cuántica
    if (payload_len != BLOCK_SIZE) {
        LOG_ERR("Bloque QRNG ignorado: Tamaño incorrecto: (%zu bytes)", payload_len);
        return;
    }

    // Crear los distintos buffers de entropía
    uint8_t qrng_buffer[BLOCK_SIZE];
    uint8_t trng_buffer[BLOCK_SIZE];
    uint8_t final_entropy_buffer[BLOCK_SIZE];
    uint8_t xor_entropy_buffer[BLOCK_SIZE];

    // Recibir entropía cuántica del servidor en el buffer del qrng
    z_bytes_reader_t reader = z_bytes_get_reader(payload);
    size_t read_bytes = z_bytes_reader_read(&reader, qrng_buffer, BLOCK_SIZE);

    if (read_bytes != BLOCK_SIZE) {
        LOG_ERR("Error al leer el bloque QRNG: (%zu bytes leídos)", read_bytes);
        return;
    }

    LOG_INF("Bloque QRNG recibido correctamente (%zu bytes). qrng: %02x%02x%02x%02x", 
        read_bytes, qrng_buffer[0], qrng_buffer[1], qrng_buffer[2], qrng_buffer[3]);

    // Extraer entropía local del TRNG de la placa
    get_trng_bytes(trng_buffer, BLOCK_SIZE);
    LOG_INF("Bloque TRNG recibido correctamente. trng: %02x%02x%02x%02x", 
        trng_buffer[0], qrng_buffer[1], trng_buffer[2], trng_buffer[3]);

    if (entropy_pool_mix(qrng_buffer, BLOCK_SIZE, trng_buffer, BLOCK_SIZE) < 0) {
        LOG_ERR("Error actualizando el pool local de entropía");
        return;
    }

    LOG_INF("Fusión completada. TRNG y QRNG combinados.");

    if (entropy_pool_extract(final_entropy_buffer, BLOCK_SIZE) < 0) {
        LOG_ERR("Error extrayendo entropía desde el pool local");
        return;
    }

    LOG_INF("Entropía extraída desde el pool local.");
    LOG_INF("Pool mode: %s, mix_counter: %llu, output: %02x%02x%02x%02x",
            entropy_pool_get_last_mix_mode(),
            (unsigned long long)entropy_pool_get_mix_counter(),
            final_entropy_buffer[0], final_entropy_buffer[1],
            final_entropy_buffer[2], final_entropy_buffer[3]);

    // Fusión criptográfica experimental usando XOR
    for (size_t i = 0; i < BLOCK_SIZE; i++) {
        xor_entropy_buffer[i] = qrng_buffer[i] ^ trng_buffer[i];
    }

    // Publicar el bloque de status
    char status_msg[256];
    snprintf(status_msg, 
            sizeof(status_msg), 
            "Fusión OK - Pool local de entropía actualizado. Modo: %s. "
            "Contador de mezclas: %llu, qrng: %02x%02x%02x%02x out: %02x%02x%02x%02x",
            entropy_pool_get_last_mix_mode(),
            (unsigned long long)entropy_pool_get_mix_counter(),
            qrng_buffer[0], qrng_buffer[1], qrng_buffer[2], qrng_buffer[3],
            final_entropy_buffer[0], final_entropy_buffer[1],
            final_entropy_buffer[2], final_entropy_buffer[3]);

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

    if (publicar_bytes_zenoh(z_loan(session),
                            ENTROPY_SOURCE_QRNG_TOPIC,
                            qrng_buffer,
                            BLOCK_SIZE) < 0) {
        LOG_WRN("No se pudo publicar QRNG en topic de observabilidad");
    }

    if (publicar_bytes_zenoh(z_loan(session),
                            ENTROPY_SOURCE_TRNG_TOPIC,
                            trng_buffer,
                            BLOCK_SIZE) < 0) {
        LOG_WRN("No se pudo publicar TRNG en topic de observabilidad");
    }

    if (publicar_bytes_zenoh(z_loan(session),
                            ENTROPY_FINAL_XOR_TOPIC,
                            xor_entropy_buffer,
                            BLOCK_SIZE) < 0) {
        LOG_WRN("No se pudo publicar baseline XOR en topic de observabilidad");
    }

    if (publicar_bytes_zenoh(z_loan(session),
                            ENTROPY_FINAL_ACTIVE_TOPIC,
                            final_entropy_buffer,
                            BLOCK_SIZE) < 0) {
        LOG_WRN("No se pudo publicar salida final activa en topic de observabilidad");
    }

}

// Función para parsear la dirección IP de la máquina local sacada de secrets.conf
static int parse_zenoh_tcp_endpoint(const char *endpoint, 
                                    char *ip_buffer, 
                                    size_t ip_buffer_size, 
                                    uint16_t *port) {
    const char *prefix = "tcp/";
    const char *ip_start;
    const char *port_start;
    size_t ip_len;
    char port_buffer[8];
    unsigned long parsed_port;

    if (endpoint == NULL || ip_buffer == NULL || port == NULL) {
        return -EINVAL;
    }

    if (strncmp(endpoint, prefix, strlen(prefix)) != 0) {
        LOG_ERR("TCP test: endpoint no soportado: %s", endpoint);
        LOG_ERR("TCP test: se esperaba formato tcp/IP:PUERTO");
        return -EINVAL;
    }

    ip_start = endpoint + strlen(prefix);
    port_start = strrchr(ip_start, ':');

    if (port_start == NULL) {
        LOG_ERR("TCP test: endpoint sin puerto: %s", endpoint);
        return -EINVAL;
    }

    ip_len = (size_t)(port_start - ip_start);

    if (ip_len == 0 || ip_len >= ip_buffer_size) {
        LOG_ERR("TCP test: IP inválida o demasiado larga");
        return -EINVAL;
    }

    memcpy(ip_buffer, ip_start, ip_len);
    ip_buffer[ip_len] = '\0';

    port_start++;

    if (strlen(port_start) == 0 || strlen(port_start) >= sizeof(port_buffer)) {
        LOG_ERR("TCP test: puerto inválido");
        return -EINVAL;
    }

    strcpy(port_buffer, port_start);

    parsed_port = strtoul(port_buffer, NULL, 10);

    if (parsed_port == 0 || parsed_port > 65535) {
        LOG_ERR("TCP test: puerto fuera de rango: %lu", parsed_port);
        return -EINVAL;
    }

    *port = (uint16_t)parsed_port;

    return 0;
}

// Función para comprobar la conexión TCP con el host del router Zenoh
static int probar_conexion_tcp_host(void) {
    int sock;
    struct sockaddr_in server_addr;
    char ip[32];
    uint16_t port;
    int ret;

    ret = parse_zenoh_tcp_endpoint(CONFIG_ZENOH_ENDPOINT, ip, sizeof(ip), &port);
    if (ret < 0) {
        LOG_ERR("TCP test: no se pudo interpretar CONFIG_ZENOH_ENDPOINT");
        return ret;
    }

    LOG_INF("TCP test: endpoint parseado correctamente: IP=%s PUERTO=%u", ip, port);

    sock = zsock_socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (sock < 0) {
        LOG_ERR("TCP test: no se pudo crear socket. errno=%d", errno);
        return -1;
    }

    memset(&server_addr, 0, sizeof(server_addr));
    server_addr.sin_family = AF_INET;
    server_addr.sin_port = htons(port);

    if (zsock_inet_pton(AF_INET, ip, &server_addr.sin_addr) != 1) {
        LOG_ERR("TCP test: IP inválida");
        close(sock);
        return -1;
    }

    LOG_INF("TCP test: intentando conectar a %s:%u", ip, port);

    if (zsock_connect(sock, (struct sockaddr *)&server_addr, sizeof(server_addr)) < 0) {
        LOG_ERR("TCP test: connect falló. errno=%d", errno);
        close(sock);
        return -1;
    }

    LOG_INF("TCP test: conexión TCP OK con %s:%u", ip, port);

    zsock_close(sock);
    return 0;
}

// Función auxiliar para ver si el endpoint a usar es TLS o TCP
static bool endpoint_usa_tls(const char *endpoint) {
    return endpoint != NULL && strncmp(endpoint, "tls/", 4) == 0;
}

// Hilo principal de Zenoh
void zenoh_client_thread(void) {
    LOG_INF("Iniciando Zenoh-Pico en el ESP32-C6");

    // Inicializar el pool de entropía local al arrancar Zenoh
    entropy_pool_init();

    z_owned_config_t config;
    if (z_config_default(&config) < 0) {
        LOG_ERR("Error al crear la configuración por defecto de Zenoh-Pico");
        return;
    }
    LOG_INF("Abriendo sesión de red");
    LOG_INF("Endpoint Zenoh configurado: %s", CONFIG_ZENOH_ENDPOINT);

    if (!endpoint_usa_tls(CONFIG_ZENOH_ENDPOINT)) {
        probar_conexion_tcp_host();
    } else {
        LOG_INF("Endpoint TLS detectado; se omite prueba TCP auxiliar previa");
    }

    if (zp_config_insert(z_config_loan_mut(&config), Z_CONFIG_MODE_KEY, Z_CONFIG_MODE_CLIENT) < 0) {
        LOG_ERR("Error configurando Zenoh en modo cliente");
        return;
    }

    if (zp_config_insert(z_config_loan_mut(&config), Z_CONFIG_CONNECT_KEY, CONFIG_ZENOH_ENDPOINT) < 0) {
        LOG_ERR("Error configurando endpoint Zenoh");
        return;
    }

    // Configuración TLS para zenoh-pico
    // La ESP32 necesita conocer la CA que firma el certificado del router Zenoh
    if (endpoint_usa_tls(CONFIG_ZENOH_ENDPOINT)) {
        LOG_INF("Endpoint Zenoh TLS detectado");

        if (strlen(CONFIG_QEAAS_TLS_CA_BASE64) == 0) {
            LOG_ERR("CONFIG_QEAAS_TLS_CA_BASE64 está vacío");
            LOG_ERR("No se puede validar el certificado TLS del router Zenoh");
            return;
        }

        LOG_INF("Longitud CA TLS Base64: %zu",
                strlen(CONFIG_QEAAS_TLS_CA_BASE64));

        if (zp_config_insert(z_config_loan_mut(&config),
                            Z_CONFIG_TLS_ROOT_CA_CERTIFICATE_BASE64_KEY,
                            CONFIG_QEAAS_TLS_CA_BASE64) < 0) {
            LOG_ERR("Error configurando la CA TLS en Base64 para Zenoh-Pico");
            return;
        }

        LOG_INF("CA TLS configurada correctamente para validar el router Zenoh");
    }

    z_result_t open_result = z_open(&session, z_move(config), NULL);
    if (open_result < 0) {
        LOG_ERR("Fallo al abrir la sesión de Zenoh-Pico: %d. No se pudo conectar al router Zenoh en %s", open_result, CONFIG_ZENOH_ENDPOINT);
        return;
    }

    LOG_INF("Sesión Zenoh-Pico abierta correctamente");

    LOG_INF("Arrancando tareas internas de Zenoh-Pico");

    // Mantener activo procesamiento de mensajes
    int ret_read = zp_start_read_task(z_loan_mut(session), NULL);
    if (ret_read < 0) {
        LOG_ERR("No se pudo iniciar read task de Zenoh-Pico: %d", ret_read);
        return;
    }

    // Enviar keepalive al router zenohd cuando sea necesario
    int ret_lease = zp_start_lease_task(z_loan_mut(session), NULL);
    if (ret_lease < 0) {
        LOG_ERR("No se pudo iniciar lease task de Zenoh-Pico: %d", ret_lease);
        return;
    }

    LOG_INF("Read task y lease task iniciadas correctamente");

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

    uint32_t counter = 0;

    while(1) {
        LOG_INF("ESP32 viva. Esperando QRNG... contador=%u", counter++);
        k_sleep(K_SECONDS(10));
    }
}