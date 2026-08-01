#include "entropy_pool.h"
#include "entropy.h"

#include <errno.h>
#include <stdbool.h>
#include <string.h>

#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>

LOG_MODULE_REGISTER(entropy_pool, LOG_LEVEL_INF);

static uint8_t pool_state[ENTROPY_POOL_SIZE];
static uint64_t mix_counter;
static bool pool_initialized;

K_MUTEX_DEFINE(pool_mutex);

static uint8_t rotl8(uint8_t value, unsigned int shift) {
    // Función auxiliar para rotar bits a la izquierda dentro de un byte
    shift &= 7U;

    if (shift == 0U) {
        return value;
    }

    return (uint8_t)((value << shift) | (value >> (8U - shift)));
}

void entropy_pool_init(void) {
    // Función para inicializar el pool de entropía local con entropía del TRNG de la placa
    k_mutex_lock(&pool_mutex, K_FOREVER);

    get_trng_bytes(pool_state, ENTROPY_POOL_SIZE);

    mix_counter = 0;
    pool_initialized = true;

    k_mutex_unlock(&pool_mutex);

    LOG_INF("Pool de entropía inicializado con TRNG local (%d bytes)",
            ENTROPY_POOL_SIZE);
}

int entropy_pool_mix(const uint8_t *qrng,
                     size_t qrng_len,
                     const uint8_t *trng,
                     size_t trng_len) {
    // Función para mezclar entropía externa (QRNG) y local (TRNG) en el pool
    if (qrng == NULL || trng == NULL || qrng_len == 0 || trng_len == 0) {
        LOG_ERR("No se puede mezclar entropía: entrada inválida");
        return -EINVAL;
    }

    if (!pool_initialized) {
        entropy_pool_init();
    }

    k_mutex_lock(&pool_mutex, K_FOREVER);

    /*
     * Primera versión funcional del pool:
     *
     * - Conserva un estado interno persistente.
     * - Introduce QRNG externo.
     * - Introduce TRNG local.
     * - Añade un contador de mezclas.
     *
     * Esta mezcla es provisional. Sirve para validar la arquitectura del pool.
     * En la siguiente mejora sustituiremos esta parte por una mezcla basada en
     * una primitiva criptográfica como BLAKE2s/hash.
     */
    for (size_t i = 0; i < ENTROPY_POOL_SIZE; i++) {
        uint8_t q = qrng[i % qrng_len];
        uint8_t t = trng[i % trng_len];
        uint8_t c = (uint8_t)((mix_counter >> ((i % 8U) * 8U)) & 0xFFU);

        pool_state[i] ^= rotl8(q, (unsigned int)(i % 8U));
        pool_state[i] ^= rotl8(t, (unsigned int)((i + 3U) % 8U));
        pool_state[i] ^= c;
    }

    /*
     * Difusión interna básica:
     * cada byte del pool pasa a depender de otros bytes del estado.
     *
     * Importante: esto no debe venderse como construcción criptográfica final.
     * Es una primera versión estructural del pool.
     */
    for (size_t i = 0; i < ENTROPY_POOL_SIZE; i++) {
        uint8_t a = pool_state[i];
        uint8_t b = pool_state[(i + 7U) % ENTROPY_POOL_SIZE];
        uint8_t c = pool_state[(i + 13U) % ENTROPY_POOL_SIZE];

        pool_state[i] = rotl8((uint8_t)(a ^ b ^ c), 3U);
    }

    mix_counter++;

    k_mutex_unlock(&pool_mutex);

    LOG_INF("Pool actualizado correctamente. Mezclas realizadas: %llu",
            (unsigned long long)mix_counter);

    return 0;
}

int entropy_pool_extract(uint8_t *out, size_t out_len) {
    // Función para extraer entropía del pool local
    if (out == NULL || out_len == 0) {
        LOG_ERR("No se puede extraer entropía: buffer inválido");
        return -EINVAL;
    }

    if (out_len > ENTROPY_POOL_SIZE) {
        LOG_ERR("Solicitud demasiado grande: %zu bytes. Máximo: %d",
                out_len,
                ENTROPY_POOL_SIZE);
        return -EINVAL;
    }

    if (!pool_initialized) {
        entropy_pool_init();
    }

    k_mutex_lock(&pool_mutex, K_FOREVER);

    memcpy(out, pool_state, out_len);

    /*
     * Después de extraer, refrescamos el estado con TRNG local.
     * Así evitamos que dos extracciones consecutivas sin nueva entrada externa
     * devuelvan exactamente el mismo estado.
     */
    uint8_t refresh[ENTROPY_POOL_SIZE];

    get_trng_bytes(refresh, ENTROPY_POOL_SIZE);

    for (size_t i = 0; i < ENTROPY_POOL_SIZE; i++) {
        pool_state[i] ^= rotl8(refresh[i], (unsigned int)((i + 1U) % 8U));
    }

    k_mutex_unlock(&pool_mutex);

    LOG_INF("Entropía extraída desde el pool local (%zu bytes)", out_len);

    return 0;
}

uint64_t entropy_pool_get_mix_counter(void) {
    // Función para obtener el número de veces que se ha actualizado el pool
    uint64_t value;

    k_mutex_lock(&pool_mutex, K_FOREVER);
    value = mix_counter;
    k_mutex_unlock(&pool_mutex);

    return value;
}