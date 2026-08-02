#include "blake2s_min.h"

#include <errno.h>
#include <string.h>

// Constantes defnidas por la especificación de BLAKE2s
// Usadas para inicializar el estado interno y para la permutación de mensajes
static const uint32_t blake2s_iv[8] = {
    0x6A09E667U, 0xBB67AE85U, 0x3C6EF372U, 0xA54FF53AU,
    0x510E527FU, 0x9B05688CU, 0x1F83D9ABU, 0x5BE0CD19U
};

// Tabla que define el orden de mezcla de las palabras del mensaje en cada ronda de compresión
// BLAKE2s utiliza 10 rondas de compresión, y cada ronda tiene un patrón específico de mezcla
// en el que se usa una permutación distinta de los 16 bloques internos de mensaje
static const uint8_t blake2s_sigma[10][16] = {
    { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9,10,11,12,13,14,15 },
    {14,10, 4, 8, 9,15,13, 6, 1,12, 0, 2,11, 7, 5, 3 },
    {11, 8,12, 0, 5, 2,15,13,10,14, 3, 6, 7, 1, 9, 4 },
    { 7, 9, 3, 1,13,12,11,14, 2, 6, 5,10, 4, 0,15, 8 },
    { 9, 0, 5, 7, 2, 4,10,15,14, 1,11,12, 6, 8, 3,13 },
    { 2,12, 6,10, 0,11, 8, 3, 4,13, 7, 5,15,14, 1, 9 },
    {12, 5, 1,15,14,13, 4,10, 0, 7, 6, 3, 9, 2, 8,11 },
    {13,11, 7,14,12, 1, 3, 9, 5, 0,15, 4, 8, 6, 2,10 },
    { 6,15,14, 9,11, 3, 0, 8,12, 2,13, 7, 1, 4,10, 5 },
    {10, 2, 8, 4, 7, 6, 1, 5,15,11, 9,14, 3,12,13, 0 }
};

static uint32_t rotr32(uint32_t value, unsigned int shift) {
    // Función auxiliar para rotar una palabra de 32 bits a la derecha
    return (value >> shift) | (value << (32U - shift));
}

static uint32_t load32_le(const uint8_t *src) {
    // Función auxiliar para convertir 4 bytes en una palabra de 32 bits usando little-endian
    return ((uint32_t)src[0]) |
           ((uint32_t)src[1] << 8) |
           ((uint32_t)src[2] << 16) |
           ((uint32_t)src[3] << 24);
}

static void store32_le(uint8_t *dst, uint32_t value) {
    // Función auxiliar para convertir una palabra de 32 bits en 4 bytes usando little-endian
    dst[0] = (uint8_t)(value);
    dst[1] = (uint8_t)(value >> 8);
    dst[2] = (uint8_t)(value >> 16);
    dst[3] = (uint8_t)(value >> 24);
}

static void blake2s_increment_counter(qeeas_blake2s_ctx *ctx, uint32_t inc) {
    // Función para contar el número de bytes procesados
    ctx->t[0] += inc;

    if (ctx->t[0] < inc) {
        ctx->t[1]++;
    }
}

// Macro para implementar la función de mezcla básica de BLAKE2S
// Mezcla usando sumas modulares, XOR y rotaciones (operaciones ARX)
#define BLAKE2S_G(r, i, a, b, c, d)                                      \
    do {                                                                 \
        a = a + b + m[blake2s_sigma[r][2U * i + 0U]];                    \
        d = rotr32(d ^ a, 16);                                           \
        c = c + d;                                                       \
        b = rotr32(b ^ c, 12);                                           \
        a = a + b + m[blake2s_sigma[r][2U * i + 1U]];                    \
        d = rotr32(d ^ a, 8);                                            \
        c = c + d;                                                       \
        b = rotr32(b ^ c, 7);                                            \
    } while (0)

static void blake2s_compress(qeeas_blake2s_ctx *ctx, const uint8_t block[64]) {
    // Convertir bloque de 64 bytes en 16 palabras de 32 bits
    uint32_t m[16];
    uint32_t v[16];

    for (size_t i = 0; i < 16; i++) {
        m[i] = load32_le(block + i * 4U);
    }

    // Construir vector de trabajo con el estado interno y las constantes de inicialización
    for (size_t i = 0; i < 8; i++) {
        v[i] = ctx->h[i];
        v[i + 8U] = blake2s_iv[i];
    }

    // Introducir contadores y flags en el vector de trabajo
    v[12] ^= ctx->t[0];
    v[13] ^= ctx->t[1];
    v[14] ^= ctx->f[0];
    v[15] ^= ctx->f[1];

    // 10 rondas de compresión de BLAKE2S
    for (size_t r = 0; r < 10; r++) {
        // Cada ronda aplica la función G a 8 pares de palabras
        // 4 mezclas por columnas
        BLAKE2S_G(r, 0, v[0], v[4], v[8],  v[12]);
        BLAKE2S_G(r, 1, v[1], v[5], v[9],  v[13]);
        BLAKE2S_G(r, 2, v[2], v[6], v[10], v[14]);
        BLAKE2S_G(r, 3, v[3], v[7], v[11], v[15]);

        // 4 mezclas por diagonales
        BLAKE2S_G(r, 4, v[0], v[5], v[10], v[15]);
        BLAKE2S_G(r, 5, v[1], v[6], v[11], v[12]);
        BLAKE2S_G(r, 6, v[2], v[7], v[8],  v[13]);
        BLAKE2S_G(r, 7, v[3], v[4], v[9],  v[14]);
    }

    // Actualizar el estado interno con el resultado de la compresión
    for (size_t i = 0; i < 8; i++) {
        ctx->h[i] ^= v[i] ^ v[i + 8U];
    }
}

#undef BLAKE2S_G

int qeeas_blake2s_init(qeeas_blake2s_ctx *ctx, size_t outlen) {
    // Función para inicializar un nuevo hash
    if (ctx == NULL || outlen == 0 || outlen > QEEAS_BLAKE2S_OUT_SIZE) {
        return -EINVAL;
    }

    memset(ctx, 0, sizeof(*ctx));

    // Inicializar el estado interno con las constantes de BLAKE2S
    for (size_t i = 0; i < 8; i++) {
        ctx->h[i] = blake2s_iv[i];
    }

    /*
     * Parameter block for unkeyed BLAKE2s:
     * digest_length = outlen
     * key_length    = 0
     * fanout        = 1
     * depth         = 1
     */
    // BLAKE2S en modo secuencial normal, sin tree hashing y sin clave
    ctx->h[0] ^= 0x01010000U ^ (uint32_t)outlen;

    ctx->outlen = outlen;

    return 0;
}

int qeeas_blake2s_update(qeeas_blake2s_ctx *ctx,
                         const void *input,
                         size_t input_len) {
    // Función para añadir datos al hash
    const uint8_t *in = (const uint8_t *)input;

    if (ctx == NULL) {
        return -EINVAL;
    }

    if (input_len == 0) {
        return 0;
    }

    if (in == NULL) {
        return -EINVAL;
    }

    // Número de bytes que actualmente están en el buffer temporal
    size_t left = ctx->buflen;
    // Número de bytes que faltan para completar un bloque de 64 bytes
    size_t fill = QEEAS_BLAKE2S_BLOCK_SIZE - left;

    if (input_len > fill) {
        memcpy(ctx->buf + left, in, fill);
        ctx->buflen = 0;

        blake2s_increment_counter(ctx, QEEAS_BLAKE2S_BLOCK_SIZE);
        blake2s_compress(ctx, ctx->buf);

        in += fill;
        input_len -= fill;

        while (input_len > QEEAS_BLAKE2S_BLOCK_SIZE) {
            blake2s_increment_counter(ctx, QEEAS_BLAKE2S_BLOCK_SIZE);
            blake2s_compress(ctx, in);

            in += QEEAS_BLAKE2S_BLOCK_SIZE;
            input_len -= QEEAS_BLAKE2S_BLOCK_SIZE;
        }
    }

    memcpy(ctx->buf + ctx->buflen, in, input_len);
    ctx->buflen += input_len;

    return 0;
}

int qeeas_blake2s_final(qeeas_blake2s_ctx *ctx,
                        uint8_t *out,
                        size_t outlen) {
    // Función para finalizar el hash y generar la salida
    uint8_t buffer[QEEAS_BLAKE2S_OUT_SIZE];

    if (ctx == NULL || out == NULL) {
        return -EINVAL;
    }

    if (outlen != ctx->outlen || outlen > QEEAS_BLAKE2S_OUT_SIZE) {
        return -EINVAL;
    }

    blake2s_increment_counter(ctx, (uint32_t)ctx->buflen);

    // Indicamos que este es el último bloque a procesar
    ctx->f[0] = 0xFFFFFFFFU;

    memset(ctx->buf + ctx->buflen, 0, QEEAS_BLAKE2S_BLOCK_SIZE - ctx->buflen);

    blake2s_compress(ctx, ctx->buf);

    for (size_t i = 0; i < 8; i++) {
        store32_le(buffer + i * 4U, ctx->h[i]);
    }

    memcpy(out, buffer, outlen);

    memset(buffer, 0, sizeof(buffer));
    memset(ctx, 0, sizeof(*ctx));

    return 0;
}

int qeeas_blake2s_hash(uint8_t *out,
                       size_t outlen,
                       const void *input,
                       size_t input_len) {
    // Función auxiliar para comprobar funcionamiento
    qeeas_blake2s_ctx ctx;
    int ret;

    ret = qeeas_blake2s_init(&ctx, outlen);
    if (ret < 0) {
        return ret;
    }

    ret = qeeas_blake2s_update(&ctx, input, input_len);
    if (ret < 0) {
        return ret;
    }

    return qeeas_blake2s_final(&ctx, out, outlen);
}