#ifndef ENTROPY_POOL_H
#define ENTROPY_POOL_H

#include <stddef.h>
#include <stdint.h>

#define ENTROPY_POOL_SIZE 32

void entropy_pool_init(void);

int entropy_pool_mix(const uint8_t *qrng,
                     size_t qrng_len,
                     const uint8_t *trng,
                     size_t trng_len);

int entropy_pool_extract(uint8_t *out, size_t out_len);

uint64_t entropy_pool_get_mix_counter(void);

#endif