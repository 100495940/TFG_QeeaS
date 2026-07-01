#ifndef ZENOH_CLIENT_H
#define ZENOH_CLIENT_H

#include <stdbool.h>
#include "zenoh-pico.h"

void recepcion_qrng_callback(const _z_sample_t *sample, void *arg);
void zenoh_client_thread(void);

#endif