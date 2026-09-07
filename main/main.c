#include "entropy.h"
#include "wifi.h"
#include "zenoh_client.h"

void main(void) {
    // Conectar a Internet
    conectar_wifi();
    
    // Configurar el modo de la entropía
    set_radio_entropy(true);

    // Bucle principal
    //while(1) {
        //send_trng_data_ask();
    //}

    // Iniciar ecosistema Zenoh
    zenoh_client_thread();
}