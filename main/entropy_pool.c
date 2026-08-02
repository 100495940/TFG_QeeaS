#include "entropy.h"
#include "entropy_pool.h"

#ifndef ENTROPY_POOL_USE_BLAKE2S
#define ENTROPY_POOL_USE_BLAKE2S 1
#endif

#ifndef ENTROPY_POOL_EXTRACT_USE_BLAKE2S
#define ENTROPY_POOL_EXTRACT_USE_BLAKE2S ENTROPY_POOL_USE_BLAKE2S
#endif

#ifndef ENTROPY_POOL_ALLOW_LEGACY_FALLBACK
#define ENTROPY_POOL_ALLOW_LEGACY_FALLBACK 1
#endif

#if ENTROPY_POOL_USE_BLAKE2S || ENTROPY_POOL_EXTRACT_USE_BLAKE2S
#include "blake2s_min.h"
#endif

#include <errno.h>
#include <stdbool.h>
#include <string.h>

#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>

LOG_MODULE_REGISTER(entropy_pool, LOG_LEVEL_INF);

static uint8_t pool_state[ENTROPY_POOL_SIZE];
static uint64_t mix_counter;
static bool pool_initialized;
static const char *last_mix_mode = "uninitialized";

K_MUTEX_DEFINE(pool_mutex);

#if ENTROPY_POOL_USE_BLAKE2S || ENTROPY_POOL_EXTRACT_USE_BLAKE2S

static const uint8_t MIX_TAG[] = "QEEAS_POOL_MIX_V1";
static const uint8_t EXTRACT_TAG[] = "QEEAS_POOL_EXTRACT_V1";
static const uint8_t REFRESH_TAG[] = "QEEAS_POOL_REFRESH_V1";

static void store64_le(uint8_t out[8], uint64_t value) {
    out[0] = (uint8_t)(value);
    out[1] = (uint8_t)(value >> 8);
    out[2] = (uint8_t)(value >> 16);
    out[3] = (uint8_t)(value >> 24);
    out[4] = (uint8_t)(value >> 32);
    out[5] = (uint8_t)(value >> 40);
    out[6] = (uint8_t)(value >> 48);
    out[7] = (uint8_t)(value >> 56);
}

static int blake2s_pool_update(const uint8_t *tag,
                               size_t tag_len,
                               const uint8_t *input_a,
                               size_t input_a_len,
                               const uint8_t *input_b,
                               size_t input_b_len,
                               const uint8_t *input_c,
                               size_t input_c_len,
                               const uint8_t counter_le[8],
                               uint8_t out[ENTROPY_POOL_SIZE]) {
    qeeas_blake2s_ctx ctx;
    int ret;

    ret = qeeas_blake2s_init(&ctx, ENTROPY_POOL_SIZE);
    if (ret < 0) {
        return ret;
    }

    ret = qeeas_blake2s_update(&ctx, tag, tag_len);
    if (ret < 0) {
        return ret;
    }

    if (input_a != NULL && input_a_len > 0) {
        ret = qeeas_blake2s_update(&ctx, input_a, input_a_len);
        if (ret < 0) {
            return ret;
        }
    }

    if (input_b != NULL && input_b_len > 0) {
        ret = qeeas_blake2s_update(&ctx, input_b, input_b_len);
        if (ret < 0) {
            return ret;
        }
    }

    if (input_c != NULL && input_c_len > 0) {
        ret = qeeas_blake2s_update(&ctx, input_c, input_c_len);
        if (ret < 0) {
            return ret;
        }
    }

    ret = qeeas_blake2s_update(&ctx, counter_le, 8);
    if (ret < 0) {
        return ret;
    }

    return qeeas_blake2s_final(&ctx, out, ENTROPY_POOL_SIZE);
}

#endif

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
    last_mix_mode = "initialized";

    k_mutex_unlock(&pool_mutex);

    LOG_INF("Pool de entropía inicializado con TRNG local (%d bytes)",
            ENTROPY_POOL_SIZE);
}

static int entropy_pool_mix_legacy(const uint8_t *qrng,
                     size_t qrng_len,
                     const uint8_t *trng,
                     size_t trng_len) {
    // Función para mezclar entropía externa (QRNG) y local (TRNG) en el pool
    uint8_t mixed_state[ENTROPY_POOL_SIZE];

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

        mixed_state[i] = rotl8((uint8_t)(a ^ b ^ c), 3U);
    }

    memcpy(pool_state, mixed_state, ENTROPY_POOL_SIZE);

    return 0;
}

#if ENTROPY_POOL_USE_BLAKE2S

static int entropy_pool_mix_blake2s(const uint8_t *qrng,
                                    size_t qrng_len,
                                    const uint8_t *trng,
                                    size_t trng_len) {
    uint8_t new_state[ENTROPY_POOL_SIZE];
    uint8_t counter_le[8];
    int ret;

    /*
     * Mezcla principal basada en BLAKE2s:
     *
     * pool_state_nuevo = BLAKE2s(
     *     MIX_TAG
     *     || pool_state_anterior
     *     || QRNG
     *     || TRNG
     *     || mix_counter
     * )
     */

    store64_le(counter_le, mix_counter);

    ret = blake2s_pool_update(MIX_TAG,
                              sizeof(MIX_TAG) - 1U,
                              pool_state,
                              ENTROPY_POOL_SIZE,
                              qrng,
                              qrng_len,
                              trng,
                              trng_len,
                              counter_le,
                              new_state);

    if (ret < 0) {
        return ret;
    }

    memcpy(pool_state, new_state, ENTROPY_POOL_SIZE);

    return 0;
}

#endif

int entropy_pool_mix(const uint8_t *qrng,
                     size_t qrng_len,
                     const uint8_t *trng,
                     size_t trng_len) {
    int ret;
    const char *mix_mode;

    if (qrng == NULL || trng == NULL || qrng_len == 0 || trng_len == 0) {
        LOG_ERR("No se puede mezclar entropía: entrada inválida");
        return -EINVAL;
    }

    if (!pool_initialized) {
        entropy_pool_init();
    }

    k_mutex_lock(&pool_mutex, K_FOREVER);

#if ENTROPY_POOL_USE_BLAKE2S
    ret = entropy_pool_mix_blake2s(qrng, qrng_len, trng, trng_len);

    if (ret < 0) {
#if ENTROPY_POOL_ALLOW_LEGACY_FALLBACK
        LOG_WRN("Fallo en mezcla BLAKE2s (%d). Usando mezcla legacy como fallback.",
                ret);

        ret = entropy_pool_mix_legacy(qrng, qrng_len, trng, trng_len);
        mix_mode = "legacy-fallback";
#else
        mix_mode = "blake2s-error";
#endif
    } else {
        mix_mode = "blake2s";
    }
#else
    ret = entropy_pool_mix_legacy(qrng, qrng_len, trng, trng_len);
    mix_mode = "legacy";
#endif

    if (ret == 0) {
        mix_counter++;
        last_mix_mode = mix_mode;
    }

    k_mutex_unlock(&pool_mutex);

    if (ret < 0) {
        LOG_ERR("No se pudo actualizar el pool de entropía. Modo=%s. Error=%d",
                mix_mode,
                ret);
        return ret;
    }

    LOG_INF("Pool actualizado correctamente. Modo=%s. Mezclas realizadas: %llu",
            mix_mode,
            (unsigned long long)mix_counter);

    return 0;
}

static int entropy_pool_extract_legacy(uint8_t *out, size_t out_len) {
    // Función para extraer entropía del pool local de manera legacy
    uint8_t refresh[ENTROPY_POOL_SIZE];

    memcpy(out, pool_state, out_len);

    /*
     * Después de extraer, refrescamos el estado con TRNG local.
     * Así evitamos que dos extracciones consecutivas sin nueva entrada externa
     * devuelvan exactamente el mismo estado.
     */
    get_trng_bytes(refresh, ENTROPY_POOL_SIZE);

    for (size_t i = 0; i < ENTROPY_POOL_SIZE; i++) {
        pool_state[i] ^= rotl8(refresh[i], (unsigned int)((i + 1U) % 8U));
    }

    return 0;
}

#if ENTROPY_POOL_EXTRACT_USE_BLAKE2S

static int entropy_pool_extract_blake2s(uint8_t *out, size_t out_len) {
    uint8_t derived_output[ENTROPY_POOL_SIZE];
    uint8_t refreshed_state[ENTROPY_POOL_SIZE];
    uint8_t refresh_trng[ENTROPY_POOL_SIZE];
    uint8_t counter_le[8];
    int ret;

    /*
     * No exponemos directamente pool_state como salida.
     *
     * salida = BLAKE2s(
     *     EXTRACT_TAG
     *     || pool_state
     *     || mix_counter
     * )
     */

    store64_le(counter_le, mix_counter);

    ret = blake2s_pool_update(EXTRACT_TAG,
                              sizeof(EXTRACT_TAG) - 1U,
                              pool_state,
                              ENTROPY_POOL_SIZE,
                              NULL,
                              0,
                              NULL,
                              0,
                              counter_le,
                              derived_output);

    if (ret < 0) {
        return ret;
    }

    memcpy(out, derived_output, out_len);

    /*
     * Refresco tras extracción:
     *
     * pool_state_refrescado = BLAKE2s(
     *     REFRESH_TAG
     *     || pool_state
     *     || TRNG_refresh
     *     || mix_counter
     * )
     */

    get_trng_bytes(refresh_trng, ENTROPY_POOL_SIZE);

    ret = blake2s_pool_update(REFRESH_TAG,
                              sizeof(REFRESH_TAG) - 1U,
                              pool_state,
                              ENTROPY_POOL_SIZE,
                              refresh_trng,
                              ENTROPY_POOL_SIZE,
                              NULL,
                              0,
                              counter_le,
                              refreshed_state);

    if (ret < 0) {
        return ret;
    }

    memcpy(pool_state, refreshed_state, ENTROPY_POOL_SIZE);

    return 0;
}

#endif

int entropy_pool_extract(uint8_t *out, size_t out_len) {
    int ret;
    const char *extract_mode;

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

#if ENTROPY_POOL_EXTRACT_USE_BLAKE2S
    ret = entropy_pool_extract_blake2s(out, out_len);

    if (ret < 0) {
#if ENTROPY_POOL_ALLOW_LEGACY_FALLBACK
        LOG_WRN("Fallo en extracción BLAKE2s (%d). Usando extracción legacy como fallback.",
                ret);

        ret = entropy_pool_extract_legacy(out, out_len);
        extract_mode = "legacy-fallback";
#else
        extract_mode = "blake2s-error";
#endif
    } else {
        extract_mode = "blake2s";
    }
#else
    ret = entropy_pool_extract_legacy(out, out_len);
    extract_mode = "legacy";
#endif

    k_mutex_unlock(&pool_mutex);

    if (ret < 0) {
        LOG_ERR("No se pudo extraer entropía del pool. Modo=%s. Error=%d",
                extract_mode,
                ret);
        return ret;
    }

    LOG_INF("Entropía extraída desde el pool local. Modo=%s. Bytes=%zu",
            extract_mode,
            out_len);

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

const char *entropy_pool_get_last_mix_mode(void) {
    const char *value;

    k_mutex_lock(&pool_mutex, K_FOREVER);
    value = last_mix_mode;
    k_mutex_unlock(&pool_mutex);

    return value;
}