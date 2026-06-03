#include "entropy.h"

void main(void) {
    // Configurar el modo de la entropía
    set_radio_entropy(true);

    // Bucle principal
    while(1) {
        send_trng_data_ask();
    }
}