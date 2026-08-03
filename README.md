# TFG: Quantum Entropy as a Service (QeeaS) con ESP32-C6, Zephyr RTOS, Rust y Zenoh

Este proyecto implementa una arquitectura de **entropía híbrida para sistemas embebidos**, combinando una fuente local de aleatoriedad generada en una **ESP32-C6** con una fuente externa de entropía recibida a través de red.

La solución integra:

* **TRNG local** generado en la ESP32-C6 mediante el subsistema de entropía de Zephyr.
* **Fuente externa QEaaS/QRNG**, obtenida por un servidor Rust y distribuida mediante Zenoh.
* **Zenoh/zenoh-pico** como middleware de comunicación entre el servidor y la placa.
* **Zephyr RTOS** como sistema operativo embebido.
* **Pool local de entropía a nivel de aplicación**, mantenido dentro de la ESP32-C6.
* **Acondicionamiento criptográfico mediante BLAKE2s**, con modo legacy como baseline o fallback.
* **Captura binaria y análisis estadístico** de las fuentes y salidas generadas.

El objetivo principal es que la combinación y acondicionamiento de la entropía tenga lugar **dentro del microcontrolador**, evitando que el TRNG local salga de la placa. El servidor Rust suministra bloques externos de entropía, pero la mezcla final se realiza localmente en la ESP32-C6.

---

## Arquitectura general

El flujo principal del sistema es:

```text
API QEaaS / fuente externa
        |
        v
Servidor Rust
        |
        | publica bloques externos en qeeas/qrng/chunk
        v
Router Zenoh: zenohd
        |
        v
ESP32-C6 + Zephyr + zenoh-pico
        |
        | genera TRNG local
        | recibe QRNG/QEaaS externo
        | actualiza pool local de entropía
        | extrae salida final acondicionada
        v
Entropía híbrida final
```

La ESP32-C6 no se conecta directamente a la API QEaaS. El servidor Rust actúa como orquestador intermedio: obtiene bloques de entropía externa, los publica en Zenoh y recibe los estados y salidas experimentales que devuelve la placa.

El diseño sigue una evolución incremental:

```text
MVP inicial:
    E_final = TRNG XOR QRNG

Versión actual:
    pool_n = Mix(pool_{n-1}, TRNG_n, QRNG_n, counter)
    output_n = Extract(pool_n)
```

La operación XOR directa se conserva como **baseline experimental**, pero la salida principal se obtiene desde un **pool local persistente**, con mezcla/acondicionamiento mediante BLAKE2s cuando está activado.

---

## Topics Zenoh utilizados

### Entrada de entropía externa

```text
qeeas/qrng/chunk
```

El servidor Rust publica en este topic bloques de 32 bytes de entropía externa. La ESP32-C6 está suscrita a este topic mediante zenoh-pico.

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

En modo experimental, la ESP32-C6 publica flujos binarios separados para análisis posterior:

```text
qeeas/esp32/entropy/source/trng
qeeas/esp32/entropy/source/qrng
qeeas/esp32/entropy/final/xor
qeeas/esp32/entropy/final/active
```

Estos topics permiten capturar por separado:

* TRNG local generado por la ESP32-C6.
* QRNG/QEaaS realmente recibido por la placa.
* Salida baseline `QRNG XOR TRNG`.
* Salida final del pool activo.

La publicación de estas fuentes se utiliza únicamente para validación experimental. En un despliegue de producción, estos topics deberían desactivarse para no exponer material de entropía.

---

## Estructura principal del proyecto

```text
TFG_QeeaS/
│
├── main/
│   ├── main.c
│   ├── wifi.c
│   ├── entropy.c
│   ├── entropy_pool.c
│   ├── entropy_pool.h
│   ├── blake2s_min.c
│   ├── blake2s_min.h
│   ├── zenoh_client.c
│   └── entropy.sh
│
├── queeas_server/
│   ├── Cargo.toml
│   ├── Cargo.lock
│   └── src/
│       └── main.rs
│
├── scripts/
│   ├── rust.sh
│   ├── install_zenoh.sh
│   ├── zenoh_cleanup.sh
│   ├── analyze_entropy_capture.py
│   └── compare_entropy_experiments.py
│
├── data/
│   ├── captures/
│   │   ├── blake2s/
│   │   └── legacy/
│   └── reports/
│       ├── blake2s/
│       ├── legacy/
│       └── entropy_global_comparison.csv
│
├── lib/
│   └── zenoh-pico/
│
├── .devcontainer/
│   ├── devcontainer.json
│   ├── Dockerfile
│   └── setup.sh
│
├── prj.conf
├── Kconfig
├── CMakeLists.txt
├── requirements_entropy.txt
├── qeaas_server.commit
├── zenoh_pico.commit
└── secrets.conf
```

---

## Requisitos previos

El proyecto está preparado para ejecutarse dentro de un **Dev Container**, reduciendo las instalaciones manuales necesarias en la máquina host.

Se necesita:

1. Docker Desktop.
2. Visual Studio Code.
3. Extensión Dev Containers.
4. Una placa ESP32-C6.
5. Conexión a Internet durante la primera creación del entorno.
6. Acceso USB desde WSL/Docker si se ejecuta desde Windows.

---

## Configuración segura

Las credenciales Wi-Fi y el endpoint Zenoh se definen en un archivo local no versionado:

```text
secrets.conf
```

Ejemplo:

```ini
CONFIG_WIFI_MI_SSID="Nombre_De_Tu_WiFi"
CONFIG_WIFI_MI_PASSWORD="Contraseña_De_Tu_WiFi"
CONFIG_ZENOH_ENDPOINT="tcp/IP_DEL_HOST:7447"
```

`CONFIG_ZENOH_ENDPOINT` debe apuntar a la IP local de la máquina host donde se ejecuta `zenohd`, no a `127.0.0.1`, ya que la ESP32-C6 se conecta desde la red Wi-Fi.

---

## Ejecución del sistema completo

Para compilar, levantar el entorno, ejecutar el servidor Rust, iniciar Zenoh, flashear la placa y abrir el monitor serie:

```bash
bash main/entropy.sh
```

Este script automatiza:

* Verificación de blobs de Espressif.
* Compilación del firmware Zephyr.
* Arranque del router `zenohd`.
* Ejecución del servidor Rust.
* Flasheo de la ESP32-C6.
* Monitorización serie.
* Cierre ordenado del entorno.

Flujo esperado:

```text
ESP32-C6 se conecta al Wi-Fi
ESP32-C6 obtiene IPv4
ESP32-C6 abre sesión Zenoh
Servidor Rust publica bloques QEaaS/QRNG
ESP32-C6 recibe QRNG externo
ESP32-C6 genera TRNG local
ESP32-C6 actualiza el pool local de entropía
ESP32-C6 extrae salida final
ESP32-C6 publica status enriquecido
Servidor Rust recibe status y capturas binarias
```

---

## Servidor Rust

El servidor Rust se encuentra en:

```text
queeas_server/
```

Actualmente cumple tres funciones:

### 1. Orquestador de entropía externa

Obtiene bloques externos de entropía desde la fuente configurada y los publica en:

```text
qeeas/qrng/chunk
```

El modo de fuente puede configurarse mediante variable de entorno:

```text
QRNG_SOURCE_MODE=auto|qeaas|simulated
```

* `qeaas`: usa la API QEaaS.
* `simulated`: genera bloques simulados para desarrollo.
* `auto`: intenta QEaaS y usa fallback simulado si falla.

### 2. Monitor de estado

Se suscribe a:

```text
qeeas/esp32/status
```

e imprime los estados enviados por la ESP32-C6.

### 3. Capturador experimental

Se suscribe a los topics binarios de observabilidad y guarda cada flujo en archivos `.bin`:

```text
data/captures/<experimento>/entropy_source_trng.bin
data/captures/<experimento>/entropy_source_qrng.bin
data/captures/<experimento>/entropy_final_xor.bin
data/captures/<experimento>/entropy_final_active.bin
```

La variable de entorno `ENTROPY_EXPERIMENT` permite separar capturas:

```bash
ENTROPY_EXPERIMENT=blake2s bash scripts/rust.sh
ENTROPY_EXPERIMENT=legacy bash scripts/rust.sh
```

---

## Pool local de entropía

La ESP32-C6 mantiene un pool local de 32 bytes a nivel de aplicación:

```text
pool_state[32]
```

Este pool se inicializa con TRNG local y se actualiza cada vez que se recibe un bloque externo.

La lógica se separa en dos fases:

```text
entropy_pool_mix()
    actualiza el estado interno con TRNG, QRNG y contador.

entropy_pool_extract()
    deriva una salida final sin exponer directamente el estado interno.
```

El proyecto contempla dos modos:

### Modo legacy

Mezcla basada en XOR, rotaciones y difusión interna. Se conserva como baseline y como comparación frente al modo criptográfico.

### Modo BLAKE2s

Mezcla/acondicionamiento mediante BLAKE2s:

```text
pool_n = BLAKE2s(MIX_TAG || pool_{n-1} || QRNG_n || TRNG_n || counter)
output_n = BLAKE2s(EXTRACT_TAG || pool_n || counter)
```

Este modo proporciona una construcción más defendible que la mezcla manual inicial, aunque sigue siendo una implementación a nivel de aplicación y no una integración completa dentro del subsistema interno de entropía de Zephyr.

---

## Análisis estadístico propio

Los archivos `.bin` capturados pueden analizarse mediante:

```bash
python3 scripts/analyze_entropy_capture.py \
  data/captures/blake2s \
  --experiment blake2s
```

o, si las capturas están dentro del servidor Rust:

```bash
python3 scripts/analyze_entropy_capture.py \
  queeas_server/data/captures/blake2s \
  --experiment blake2s
```

El script genera reportes en:

```text
data/reports/<experimento>/
```

Métricas calculadas:

* Entropía de Shannon.
* Min-entropía empírica.
* Chi-cuadrado y p-value.
* Balance de ceros y unos.
* Test monobit.
* Test de runs.
* Autocorrelación de bytes y bits.
* Bloques repetidos de 32 bytes.
* Mayor racha del mismo byte.
* Ratio de compresión zlib.
* Shannon por ventanas.
* Histogramas de bytes.
* CSV de frecuencias por byte.

Para comparar experimentos:

```bash
python3 scripts/compare_entropy_experiments.py \
  data/reports/blake2s/entropy_metrics_summary.csv \
  data/reports/legacy/entropy_metrics_summary.csv \
  --out data/reports/entropy_global_comparison.csv \
  --markdown data/reports/entropy_global_comparison.md
```

---

## Validación externa con randlab

Además de las métricas propias, el proyecto puede complementar la validación con `randlab`, una herramienta que centraliza varias baterías de evaluación de generadores aleatorios.

Ejemplo sobre la salida final BLAKE2s:

```bash
randlab run \
  --input data/captures/blake2s/entropy_final_active.bin \
  --format raw \
  --profile quick \
  --suite ent \
  --suite practrand \
  --suite entropy-iid \
  --suite entropy-non-iid \
  --suite testu01-rabbit \
  --out data/randlab/blake2s_final_quick
```

Ejemplo sobre el baseline XOR:

```bash
randlab run \
  --input data/captures/blake2s/entropy_final_xor.bin \
  --format raw \
  --profile quick \
  --suite ent \
  --suite practrand \
  --suite entropy-iid \
  --suite entropy-non-iid \
  --suite testu01-rabbit \
  --out data/randlab/xor_baseline_quick
```

Los perfiles `quick` deben interpretarse como pruebas de validación rápida o smoke tests. Para una evaluación normativa fuerte serían necesarios archivos de mayor tamaño y perfiles más exigentes.

---

## Reproducibilidad

Para evitar que cambios externos rompan el proyecto, se fijan versiones o commits de componentes críticos:

```text
qeaas_server.commit
zenoh_pico.commit
Cargo.lock
rust-toolchain.toml
west-freeze.yml
requirements_entropy.txt
```

Objetivo:

* Fijar el commit funcional de la API QEaaS.
* Fijar la versión funcional de zenoh-pico.
* Congelar dependencias Rust mediante `Cargo.lock`.
* Fijar dependencias Python para análisis.
* Documentar el estado del workspace Zephyr mediante manifiesto congelado.

---

## Archivos que no deben subirse a Git

```gitignore
# Credenciales
secrets.conf

# Builds Zephyr
build/

# Rust
target/
**/target/

# Logs
*.log
/tmp/
qeeas_logs/

# Capturas y reportes pesados
data/captures/
data/reports/
data/randlab/

# Archivos temporales
*.tmp
```

Los resultados experimentales pueden almacenarse externamente o añadirse solo de forma selectiva si son necesarios para la memoria.

---

## Estado actual del proyecto

Actualmente el sistema permite:

* Compilar firmware Zephyr para ESP32-C6.
* Conectar la ESP32-C6 a Wi-Fi.
* Ejecutar `zenohd` como router de mensajería.
* Ejecutar un servidor Rust como orquestador QEaaS/QRNG.
* Publicar bloques externos de 32 bytes en `qeeas/qrng/chunk`.
* Conectar la ESP32-C6 a Zenoh mediante zenoh-pico.
* Recibir bloques externos en la ESP32-C6.
* Generar TRNG local.
* Inicializar y actualizar un pool local de entropía.
* Extraer salida final desde el pool.
* Usar BLAKE2s como mecanismo principal de acondicionamiento.
* Conservar el modo legacy y el XOR inicial como baseline.
* Publicar estados enriquecidos desde la ESP32-C6.
* Capturar fuentes y salidas en archivos `.bin` desde Rust.
* Analizar los archivos capturados mediante scripts Python.
* Preparar las salidas para validación adicional con randlab.

---

## Limitaciones actuales

El proyecto es un prototipo experimental funcional, pero no debe interpretarse como un RNG certificado.

Limitaciones principales:

* El pool de entropía se implementa a nivel de aplicación, no dentro del subsistema interno de entropía de Zephyr.
* Las pruebas estadísticas detectan desviaciones empíricas, pero no prueban por sí solas seguridad criptográfica.
* Los topics de observabilidad exponen material de entropía y solo deben usarse en modo experimental.
* La seguridad del transporte Zenoh no está todavía reforzada con TLS/mTLS.
* No se ha implementado todavía una política completa de reconexión, reintentos y tolerancia a fallos.
* La validación normativa fuerte requiere capturas de mayor tamaño y baterías externas completas.

---

## Trabajo futuro

* Integrar el diseño con el fork de Zephyr basado en `entropy_add_entropy()`.
* Evaluar la inyección de QEaaS/QRNG en el pool interno de Zephyr.
* Añadir autenticación y cifrado del canal de comunicación.
* Mejorar reconexión y modos degradados ante caída de Wi-Fi, Zenoh o QEaaS.
* Automatizar capturas de tamaño objetivo.
* Ejecutar perfiles avanzados de randlab sobre capturas grandes.
* Explorar CoAPs/DTLS o mecanismos post-cuánticos como extensión futura.
* Estudiar integración con micro-ROS/rmw_zenoh_pico como línea avanzada.
