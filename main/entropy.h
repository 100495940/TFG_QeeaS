#ifndef ENTROPY_H
#define ENTROPY_H

#include <stdbool.h>

void set_radio_entropy(bool enable);
void send_trng_data_ask(void);

#endif