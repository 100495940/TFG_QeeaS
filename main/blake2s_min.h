#ifndef QEEAS_BLAKE2S_MIN_H
#define QEEAS_BLAKE2S_MIN_H

#include <stddef.h>
#include <stdint.h>

#define QEEAS_BLAKE2S_BLOCK_SIZE 64
#define QEEAS_BLAKE2S_OUT_SIZE   32

typedef struct {
    uint32_t h[8];      // Estado interno principal de BLAKE2S
    uint32_t t[2];      // Contado de bytes procesados
    uint32_t f[2];      // Flags internos
    uint8_t buf[QEEAS_BLAKE2S_BLOCK_SIZE];      // Buffer temporal de 64 bytes
    size_t buflen;      // Número de bytes actualmente en el buffer
    size_t outlen;      // Número de bytes de salida deseados
} qeeas_blake2s_ctx;

// Inicializar una operación BLAKE2S
int qeeas_blake2s_init(qeeas_blake2s_ctx *ctx, size_t outlen);

// Añadir datos a la operación BLAKE2S
int qeeas_blake2s_update(qeeas_blake2s_ctx *ctx,
                         const void *input,
                         size_t input_len);

// Finalizar hash y generar salida
int qeeas_blake2s_final(qeeas_blake2s_ctx *ctx,
                        uint8_t *out,
                        size_t outlen);

int qeeas_blake2s_hash(uint8_t *out,
                       size_t outlen,
                       const void *input,
                       size_t input_len);

#endif