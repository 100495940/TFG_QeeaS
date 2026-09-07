# TFG: Quantum Entropy as a Service (QeeaS) con ESP32-C6, Zephyr RTOS, Rust y Zenoh

Este proyecto implementa una arquitectura de **entropía híbrida para sistemas embebidos**, combinando una fuente local de aleatoriedad generada en una **ESP32-C6** con una fuente externa de entropía recibida a través de red.

La solución integra:

* **TRNG local** generado en la ESP32-C6 mediante el subsistema de entropía de Zephyr.
* **QRNG externo** obtenido mediante una API QEaaS compatible con un dispositivo ID Quantique Quantis USB.
* **Servidor Rust** encargado de obtener, publicar y monitorizar la entropía externa.
* **Zenoh/zenoh-pico** como middleware de comunicación entre el servidor y la placa.
* **Zephyr RTOS** como sistema operativo embebido.
* **TLS** para proteger las comunicaciones Zenoh.
* **Pool local de entropía a nivel de aplicación**, mantenido dentro de la ESP32-C6.
* **Acondicionamiento criptográfico mediante BLAKE2s**, con modo legacy como baseline o fallback.
* **Modo legacy y XOR directo** como baselines experimentales.
* **Prometheus y Grafana** para observabilidad del sistema.
* **Captura binaria y análisis estadístico** de las fuentes y salidas generadas.

El objetivo principal es que la combinación y acondicionamiento de la entropía tenga lugar **dentro del microcontrolador**, evitando que el TRNG local salga de la placa. El servidor Rust suministra bloques externos de entropía, pero la mezcla final se realiza localmente en la ESP32-C6.

---

## Arquitectura general

El flujo principal del sistema es:

```text
Quantis USB
        |
        |
        v
API QEaaS / fuente externa :6065
        |
        | HTTP
        v
Servidor Rust
        |
        | publica bloques externos en qeeas/qrng/chunk
        | Zenoh / TLS
        v
Router Zenoh: zenohd :7447
        |
        | Zenoh-Pico / TLS
        v
ESP32-C6 + Zephyr 
        |
        | genera TRNG local
        | recibe QRNG externo
        | actualiza pool local de entropía
        | BLAKE2s / modo legacy (rotaciones y difusión de bits)
        | extrae salida final acondicionada
        v
Entropía híbrida final
```

La ESP32-C6 no se conecta directamente a la API QEaaS. El servidor Rust actúa como orquestador intermedio: obtiene bloques de entropía externa, los publica en Zenoh y recibe los estados y salidas experimentales que devuelve la placa.

El diseño sigue una evolución incremental:

```text
MVP inicial:
    E_final = TRNG XOR QRNG

Versión actual basada en estado:
    pool_n = Mix(pool_{n-1}, TRNG_n, QRNG_n, counter)
    output_n = Extract(pool_n)
```

La operación XOR directa se conserva como **baseline experimental**, pero la salida principal se obtiene desde un **pool local persistente**, con mezcla/acondicionamiento mediante BLAKE2s cuando está activado.

---

## Fuentes de entropía

### TRNG local

La ESP32-C6 genera entropía local utilizando su fuente hardware de aleatoriedad.

Esta fuente se utiliza:

- Para inicializar el pool.
- Durante cada actualización del pool.
- Para refrescar el estado después de las extracciones.

### QRNG externo

La fuente QRNG se obtiene mediante la API QEaaS.

Se puede utilizar un dispositivo Quantis si se encuentra conectado por USB:

```text
ID Quantique Quantis USB
VID:PID 0aba:0102
```

El dispositivo USB se accede mediante:

```text
Quantis USB
    ↓
libusb
    ↓
libQuantis
    ↓
QEaaS
```

A diferencia de una tarjeta Quantis PCIe, el modelo USB **no utiliza `/dev/qrandom0`**.

La API permite configurar:

```text
--source usb
--device-number 0
--extract on|off
--xor-os on|off
--fallback on|off
```

Para experimentos controlados se recomienda desactivar el fallback para evitar sustituir silenciosamente el QRNG por el RNG del sistema.

También puede activarse:

```text
--xor-os on
```

Para combinar mediante XOR la salida del Quantis con aleatoriedad proporcionada por el sistema operativo.

---

## Pool local de entropía

La ESP32-C6 mantiene un estado interno persistente durante cada ejecución (no entre reinicios):

```text
pool_state[32]
```

El pool se inicializa utilizando TRNG local y se actualiza cada vez que se recibe un nuevo bloque QRNG.

La interfaz principal está formada por:

```text
entropy_pool_mix()
entropy_pool_extract()
```

### Modo BLAKE2s

La configuración principal utiliza BLAKE2s:

```text
pool_n =
BLAKE2s(
    MIX_TAG
    || pool_(n-1)
    || QRNG_n
    || TRNG_n
    || counter
)
```

La salida se deriva sin exponer directamente el estado interno:

```text
output_n =
BLAKE2s(
    EXTRACT_TAG
    || pool_n
    || counter
)
```

Tras cada extracción, el estado se refresca incorporando nuevo TRNG local.

### Modo legacy

Se conserva la primera implementación del pool basada en:

- XOR.
- Rotaciones.
- Contador.
- Difusión entre bytes.

Este modo se utiliza como **baseline experimental**.

La selección se realiza mediante macros de compilación:

```c
ENTROPY_POOL_USE_BLAKE2S
ENTROPY_POOL_EXTRACT_USE_BLAKE2S
ENTROPY_POOL_ALLOW_LEGACY_FALLBACK
```

Por ejemplo, para utilizar completamente el modo legacy modificar la siguiente variable en el archivo CMakeLists.txt:

```text
ENTROPY_POOL_EXTRACT_USE_BLAKE2S=0
```

---

## Topics Zenoh utilizados

### Entrada de entropía externa

```text
qeeas/qrng/chunk
```

El servidor Rust publica en este topic bloques de 40 bytes con 32 bytes de entropía externa y 8 bytes de identificado de bloque. La ESP32-C6 está suscrita a este topic mediante zenoh-pico.

### Estado de la ESP32-C6

```text
qeeas/esp32/status
```

La ESP32-C6 publica mensajes de estado enriquecidos, por ejemplo:

```text
FUSION_OK mode=blake2s counter=12 qrng_len=32 trng_len=32 out_len=32 qrng_head=... trng_head=... out_head=...
```

Estos mensajes permiten comprobar:

* Modo activo de mezcla: `blake2s`, `legacy` o fallback.
* Contador interno de mezclas.
* Tamaño de los bloques recibidos y extraídos.
* Muestras cortas en hexadecimal para depuración.

### Topics de observabilidad experimental

Al ser un prototipo experimental, la ESP32-C6 publica flujos binarios separados para su posterior análisis:

```text
qeeas/esp32/entropy/source/trng
qeeas/esp32/entropy/source/qrng
qeeas/esp32/entropy/final/xor
qeeas/esp32/entropy/final/active
```

Estos topics permiten capturar por separado:

* TRNG local generado por la ESP32-C6.
* QRNG del QEaaS realmente recibido por la placa.
* Salida baseline `QRNG XOR TRNG`.
* Salida final del pool activo (BLAKE2s/legacy).

La publicación de estas fuentes se utiliza únicamente para validación experimental. En un despliegue de producción, estos topics deberían desactivarse para no exponer material de entropía.

### ACK ESP32-C6

La ESP32-C6 devuelve el identificador de secuencia del bloque procesado junto 
con los tiempos internos de procesamiento de cada operación. El servidor Rust 
utiliza estos ACK para calcular métricas extremo a extremo sin necesidad de 
sincronizar los relojes de PC y microcontrolador.

```text
qeeas/esp32/entropy/ack
```

---

## Comunicaciones y puertos

La arquitectura separa la LAN física, las redes Docker y las comunicaciones internas del DevContainer.

| Puerto | Servicio | Uso |
|---:|---|---|
| `3240/TCP` | usbipd | USB Windows ↔ WSL |
| `6065/TCP` | QEaaS | Rust ↔ API QEaaS |
| `7447/TCP` | Zenoh | ESP32/Rust ↔ zenohd |
| `9091/TCP` | Exporter Rust | Prometheus → Rust |
| `9090/TCP` | Prometheus | API e interfaz |
| `3000/TCP` | Grafana | Visualización |

### Rust → zenohd

Rust y `zenohd` se ejecutan dentro del mismo DevContainer, por lo que Rust puede utilizar:

```text
127.0.0.1:7447
```

### ESP32 → zenohd

La ESP32 utiliza la dirección Wi-Fi de la máquina host:

```text
tcp/IP_HOST:7447
tls/IP_HOST:7447
```

El puerto `7447` del DevContainer se publica hacia el host.

### Rust → QEaaS

La dirección de la API se configura mediante:

```text
QEAAS_API_URL
```

permitiendo utilizar tanto una API local como una instancia remota.

---

## Seguridad TLS

Las comunicaciones Zenoh pueden ejecutarse en modo plain o TLS.

Para TLS se utiliza:

- Una CA propia.
- Certificado del router Zenoh.
- Clave privada del router.
- SAN con las direcciones necesarias.
- Certificado de CA incluido en el firmware de la ESP32.

El flujo protegido es:

```text
Rust
   │
   │ TLS
   ▼
zenohd
   │
   │ TLS
   ▼
ESP32-C6
```

La configuración Rust se selecciona dinámicamente mediante:

```text
ZENOH_CONFIG
```

La integración de zenoh-pico utiliza Mbed TLS dentro de Zephyr y contiene las adaptaciones necesarias para las versiones actuales utilizadas por el proyecto.

---

## Observabilidad

El servidor Rust expone métricas Prometheus en:

```text
0.0.0.0:9091/metrics
```

Prometheus realiza scraping periódico y Grafana permite visualizar los resultados.

Entre las métricas monitorizadas se incluyen:

- Peticiones y errores QEaaS.
- Latencia de obtención QRNG.
- Bloques Zenoh publicados.
- Bytes y throughput.
- Duración de publicación.
- ACK recibidos.
- RTT extremo a extremo.
- Jitter.
- Timeouts.
- Bloques sin confirmar.
- Tiempo de generación TRNG.
- Tiempo de XOR.
- Tiempo de obtención de la salida final activa.

La red Docker utilizada para observabilidad es:

```text
qeeas-observability
```

El DevContainer utiliza el alias:

```text
qeeas-dev
```

por lo que Prometheus puede acceder al exporter mediante:

```text
qeeas-dev:9091
```

sin depender de IPs internas Docker.

Prometheus y Grafana utilizan volúmenes persistentes para conservar series temporales, configuración y dashboards.

Levantar ambos contenedores con docker compose up -d de manera manual sobre el directorio /observability de la raíz del proyecto.

---

## Despliegue del sistema

El proyecto está preparado para ejecutarse dentro de un **DevContainer reproducible**.

### Requisitos del host

- Windows con WSL2.
- Docker Desktop.
- Docker cli instalado dentro del DevContainer.
- Visual Studio Code.
- Extensión Dev Containers.
- `usbipd-win`.
- ESP32-C6.
- Quantis USB para los experimentos QRNG reales.

### 1. Conectar el hardware

La ESP32-C6 y Quantis se detectan inicialmente desde Windows.

```powershell
usbipd list
```

Los dispositivos se adjuntan a WSL mediante `usbipd`.

Una vez conectados, WSL expone:

```text
ESP32-C6  → /dev/ttyUSB*
Quantis   → /dev/bus/usb
```

Para esto ejecutar el script conectar_usb_windows.bat.

### 2. Abrir el DevContainer

El DevContainer contiene:

- Zephyr;
- SDK/toolchain;
- Rust;
- Zenoh;
- zenoh-pico;
- herramientas de compilación;
- scripts auxiliares.

El workspace se monta en:

```text
/workspaces/TFG_QeeaS
```

### 3. Levantar QEaaS

La API QRNG se ejecuta en un contenedor independiente:

```text
qrng-api
```

Para utilizar Quantis USB se configura:

```text
QRNG_SOURCE=usb
QRNG_DOCKER_DEVICE=/dev/bus/usb:/dev/bus/usb
```

La API queda disponible en:

```text
:6065
```

La respuesta permite comprobar la fuente realmente utilizada:

```json
{
  "source": "Quantis USB library",
  "fallback": false,
  "xor_os": false
}
```

### 4. Levantar observabilidad

Prometheus y Grafana se ejecutan mediante Docker.

Servicios:

```text
Prometheus → localhost:9090
Grafana    → localhost:3000
```

Los tres componentes principales de observabilidad comparten:

```text
qeeas-observability
```

```text
DevContainer
     │
     │ :9091
     ▼
Prometheus
     │
     ▼
Grafana
```

### 5. Ejecutar proyecto

Desde el DevContainer:

```bash
bash main/entropy.sh
```

El script principal automatiza:

1. Preparación y comprobación del entorno.
2. Compilación del firmware Zephyr.
3. Compilación del servidor Rust.
4. Arranque de `zenohd`.
5. Arranque del servidor Rust.
6. Flasheo de la ESP32-C6.
7. Ejecución del experimento.
8. Captura de datos cuando está habilitada.
9. Cierre ordenado de procesos ante finalización o error.

Los procesos Rust y `zenohd` se gestionan mediante PID para facilitar su terminación segura.

Hay ciertos procesos que el script no puede automatizar y hay que realizar para el correcto funcionamiento del sistema: 
1. Rellenar el archivo secrets.conf con la dirección IP de la máquina y las credencial Wi-Fi de la red a la que se van a conectar. Dicho archivo no se puede compartir al repositorio pero existe una plantilla llamada secrets_template.conf en la raíz del proyecto.
2. Conectar hardware (ESP32-C6 y/o Quantis USB) a la máquina por USB.
3. Ejecutar conectar_usb_windows.bat para conectar el hardware a WSL y Doker.
4. Elegir modo TCP o TLS en el endpoint CONFIG_ZENOH_ENDPOINT="tcp/IP_DEL_HOST:7447" del archivo secrets.conf
5. Obtener el siguiente valor del archivo secrets.conf: CONFIG_QEAAS_TLS_CA_BASE64="", ejecutando el siguiente comando con la ubicación del certificado (certs/ca/ca.crt): base64 -w 0 certs/ca/ca.crt
6. Levantar contenedores Prometheus y Grafana y crear red Docker "qeeas-observability" si no está creada, con los tres contenedores (DevContainer)

---

## Servidor Rust

El servidor se encuentra en:

```text
queeas_server/
```

Sus principales responsabilidades son:

### Obtención de QRNG

Obtiene entropía externa mediante QEaaS.

La URL puede seleccionarse con:

```text
QEAAS_API_URL
```

### Publicación Zenoh

Publica bloques QRNG en:

```text
qeeas/qrng/chunk
```

### Recepción de ACK

Mantiene un mapa de bloques pendientes asociado a su instante de publicación.

Cuando recibe un ACK calcula:

```text
RTT = instante_ACK - instante_publicación
```

sin sincronización de relojes entre Rust y la ESP32.

### Observabilidad

Expone las métricas Prometheus del sistema en:

```text
:9091/metrics
```

### Identificación experimental

Cada ejecución puede etiquetarse utilizando:

```text
ENTROPY_EXPERIMENT
```

normalmente mediante un timestamp o identificador del experimento.

---

## Captura y análisis estadístico

Al ser un prototipo experimental se pueden almacenar los flujos binarios correspondientes a:

- TRNG.
- QRNG.
- XOR baseline.
- salida final del pool.

Las capturas permiten aplicar análisis propios y herramientas externas.

Entre las métricas disponibles se encuentran:

- Entropía de Shannon.
- Min-entropía empírica.
- Chi-cuadrado.
- Balance de bits.
- Monobit.
- Runs.
- Autocorrelación.
- Bloques repetidos.
- Compresibilidad.
- Histogramas.
- Análisis por ventanas.

---

## Validación con randlab

La validación puede complementarse utilizando `randlab`.

Preparación:

```bash
bash scripts/bootstrap_randlab.sh
source external/randlab/.venv/bin/activate
```

Ejemplo:

```bash
randlab run \
  --input data/captures/blake2s/entropy_final_active.bin \
  --format raw \
  --profile quick \
  --suite ais31-p1-t0 \
  --suite ais31-p1-t1-t5 \
  --suite ais31-p2 \
  --suite ent \
  --suite practrand \
  --suite entropy-iid \
  --suite entropy-non-iid \
  --suite entropy-restart \
  --out data/randlab/blake2s_final_quick
```

Los perfiles `quick` deben interpretarse como pruebas rápidas de validación. Una evaluación normativa completa requiere capturas mayores y configuraciones específicas de cada batería.

---

## Estructura principal

```text
TFG_QeeaS/
│
├── main/
│   ├── main.c
│   ├── wifi.c
│   ├── wifi.h
│   ├── entropy.c
│   ├── entropy.h
│   ├── entropy_pool.c
│   ├── entropy_pool.h
│   ├── blake2s_min.c
│   ├── blake2s_min.h
│   ├── zenoh_client.c
│   ├── zenoh_client.h
│   └── entropy.sh
│
├── queeas_server/
│   ├── Cargo.toml
│   ├── Cargo.lock
│   └── src/
│       ├── main.rs
│       └── observability.rs
│
├── scripts/
│
├── observability/
│   ├── prometheus/
│   ├── grafana/
│   └── docker-compose.yml
│
├── data/
│   ├── captures/
│   ├── reports/
│   └── randlab/
│
├── lib/
│   └── zenoh-pico/
│
├── .devcontainer/
│   ├── devcontainer.json
│   ├── Dockerfile
│   └── setup.sh
│
├── config/
│   └── zenoh/
│
├── prj.conf
├── Kconfig
├── CMakeLists.txt
├── Cargo.lock
├── rust-toolchain.toml
└── secrets.conf
```

---

## Reproducibilidad

El proyecto fija o registra las versiones de sus componentes principales mediante:

```text
Cargo.lock
rust-toolchain.toml
zenoh_pico.commit
qeaas_server.commit
requirements_entropy.txt
```

El objetivo es poder reconstruir un entorno equivalente aunque evolucionen las dependencias externas.

---

## Archivos no versionados

No deben subirse a Git:

```gitignore
# Credenciales
secrets.conf

# Builds
build/
target/
**/target/

# Logs
*.log
qeeas_logs/

# Temporales
*.tmp
```

Los certificados privados y claves TLS tampoco deben almacenarse en el repositorio público.

---

## Estado final del proyecto

Actualmente QeeaS permite:

- Generar TRNG local en ESP32-C6.
- Obtener QRNG real desde Quantis USB.
- Utilizar `/dev/urandom` como segunda fuente opcional en QEaaS.
- Ejecutar QEaaS dentro de Docker.
- Publicar bloques QRNG mediante Zenoh.
- Proteger Zenoh mediante TLS.
- Recibir QRNG mediante zenoh-pico.
- Mantener un pool local persistente a nivel de ejecución.
- Acondicionar el pool mediante BLAKE2s.
- Utilizar legacy y XOR como baselines.
- Devolver ACK asociados a cada bloque.
- Medir RTT, jitter y tiempos internos.
- Exponer métricas Prometheus.
- Visualizar experimentos en Grafana.
- Capturar flujos binarios.
- Realizar análisis estadísticas propio.
- Ejecutar validaciones adicionales mediante la herramienta randlab.
- Automatizar compilación, despliegue, flasheo, ejecución y cierre.

---

## Limitaciones

QeeaS es un **prototipo experimental** y no debe interpretarse como un generador certificado.

Entre sus principales limitaciones:

- El pool se implementa a nivel de aplicación y no dentro del subsistema interno de entropía de Zephyr.
- La implementación BLAKE2s es específica del proyecto y debe considerarse dentro del alcance experimental del TFG.
- Los análisis estadísticos no constituyen por sí solos una demostración de seguridad criptográfica.
- La publicación de fuentes de entropía debe mantenerse desactivada fuera de los experimentos.

---

## Posibles líneas futuras

- Integrar QRNG externo directamente en mecanismos internos de entropía de Zephyr.
- Estudiar mecanismos formales de estimación y contabilización de entropía.
- Estudiar mecanismos adicionales de autenticación y gestión de credenciales.
- Explorar arquitecturas con múltiples proveedores y consumidores QEaaS.
- Estudiar extensiones criptográficas post-cuánticas para la protección de comunicaciones.