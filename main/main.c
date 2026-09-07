#include "entropy.h"
#include "wifi.h"
#include "zenoh_client.h"

void main(void) {
    // Conectar a Internet
    conectar_wifi();
    
    // Configurar el modo del subsistema radio del microcontrolador
    set_radio_entropy(true);

    // Bucle principal en caso de ejecutar el modo --nist
    //while(1) {
    //    send_trng_data_ask();
    //}

    // Iniciar ecosistema Zenoh
    zenoh_client_thread();
}