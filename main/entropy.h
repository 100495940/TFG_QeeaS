#ifndef ENTROPY_H
#define ENTROPY_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

void set_radio_entropy(bool enable);
void get_trng_bytes(uint8_t *buffer, size_t length);
void send_trng_data_ask(void);

#endif