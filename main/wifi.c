#include <zephyr/kernel.h>
#include <zephyr/net/net_if.h>
#include <zephyr/net/wifi_mgmt.h>
#include <zephyr/net/net_event.h>
#include <zephyr/logging/log.h>

LOG_MODULE_REGISTER(wifi_tfg, LOG_LEVEL_INF);

// Semáforos
static K_SEM_DEFINE(wifi_conectado, 0, 1);
static K_SEM_DEFINE(ipv4_obtenida, 0, 1);

// Estructuras para escuchar los eventos de la red
static struct net_mgmt_event_callback wifi_cb;
static struct net_mgmt_event_callback ipv4_cb;

// Función que salta cuando reciba las alarmas
static void gestor_eventos_red(struct net_mgmt_event_callback *cb, 
    uint64_t mgmt_event, 
    struct net_if *iface) {
    if (mgmt_event == NET_EVENT_WIFI_CONNECT_RESULT) {
        const struct wifi_status *status = (const struct wifi_status *)cb->info;
        if (status->status == 0) {
            LOG_INF("Conexión Wi-Fi exitosa. Esperando dirección IP");
            k_sem_give(&wifi_conectado);
        } else {
            LOG_ERR("Fallo al conectarse al Wi-Fi. Código de error: %d", status->status);

        }    
    } else if (mgmt_event == NET_EVENT_IPV4_ADDR_ADD) {
        LOG_INF("Dirección IPv4 asignada correctamente por el router.");
        k_sem_give(&ipv4_obtenida);
    }
}

// Función principal que se llama desde main
void conectar_wifi(void) {
    // Busar la tarjeta de red principal de la placa
    struct net_if *iface = net_if_get_default();

    if (!iface) {
        LOG_ERR("Error: No se ha detectado la antena Wi-Fi física.");
        return;
    }

    LOG_INF("Iniciando módulo Wi-Fi.");

    // Alarma para avisar cuando la placa se conecte a la red inalámbrica
    net_mgmt_init_event_callback(&wifi_cb, gestor_eventos_red, NET_EVENT_WIFI_CONNECT_RESULT);
    net_mgmt_add_event_callback(&wifi_cb);

    // Alarma para avisar cuando la placa reciba una dirección IP válida por el router
    net_mgmt_init_event_callback(&ipv4_cb, gestor_eventos_red, NET_EVENT_IPV4_ADDR_ADD);
    net_mgmt_add_event_callback(&ipv4_cb);

    // Estructura con los datos de la red Wi-Fi
    struct wifi_connect_req_params wifi_params = {0};
    wifi_params.ssid = CONFIG_WIFI_MI_SSID;
    wifi_params.ssid_length = strlen(CONFIG_WIFI_MI_SSID);
    wifi_params.psk = CONFIG_WIFI_MI_PASSWORD;
    wifi_params.psk_length = strlen(CONFIG_WIFI_MI_PASSWORD);
    wifi_params.security = WIFI_SECURITY_TYPE_PSK;
    wifi_params.channel = WIFI_CHANNEL_ANY;

    LOG_INF("Intentando conectar a la red: %s", CONFIG_WIFI_MI_SSID);

    // Petición de conexión Wi-Fi (asíncronamente)
    if (net_mgmt(NET_REQUEST_WIFI_CONNECT, iface, &wifi_params, sizeof(struct wifi_connect_req_params))) {
        LOG_ERR("La petición de conexión fue rechazada por el sistema.");
        return;
    }

    LOG_INF("Negociando con el router.");
    k_sem_take(&wifi_conectado, K_FOREVER);
    k_sem_take(&ipv4_obtenida, K_FOREVER);

    LOG_INF("ESP32-C6 conectada a internet y lista para Zenoh.");
}