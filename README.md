# TFG: Entropy as a Service (QeeaS) con ESP32-C6, Zephyr RTOS, Rust y Zenoh

Este proyecto implementa una arquitectura de **Edge Computing Criptográfico** para la generación y distribución de entropía híbrida. La solución combina:

* **TRNG local** generado dentro de una ESP32-C6 a partir del ruido térmico del hardware.
* **QRNG externo** recibido desde un servidor Rust.
* **Zenoh/zenoh-pico** como sistema de comunicación distribuida entre el servidor y la placa.
* **Zephyr RTOS** como sistema operativo embebido de la ESP32-C6.

El objetivo principal es que la fusión de entropía tenga lugar **dentro del microcontrolador**, evitando que el TRNG local salga de la placa.

La operación criptográfica central es:

```text
E_final = TRNG XOR QRNG
```

donde:

* `TRNG` se genera localmente en la ESP32-C6.
* `QRNG` se recibe desde la red mediante Zenoh.
* `E_final` se calcula dentro de la ESP32-C6.

---

## Arquitectura general

El flujo del sistema en modo red es el siguiente:

```text
Servidor Rust
    |
    | publica QRNG en qeeas/qrng/chunk
    v
Router Zenoh: zenohd
    ^
    | recibe estado desde qeeas/esp32/status
    |
ESP32-C6 + Zephyr + zenoh-pico
    |
    | genera TRNG local
    | recibe QRNG externo
    | calcula TRNG XOR QRNG
    v
Entropía híbrida local
```

La ESP32-C6 no se conecta directamente al servidor Rust. Tanto el servidor Rust como la ESP32-C6 se conectan al router Zenoh `zenohd`, que se encarga de enrutar los mensajes.

Actualmente, el servidor Rust publica bloques QRNG simulados para validar la arquitectura completa. En la versión final, esta fuente se sustituirá por una API QRNG proporcionada por el profesor, de forma que el servidor Rust actuará como orquestador entre dicha API cuántica y la red Zenoh.

---

## Estructura principal del proyecto

```text
TFG_QeeaS/
│
├── main/
│   ├── main.c
│   ├── wifi.c
│   ├── entropy.c
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
│   └── entropy.py
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
└── secrets.conf
```

---

## Requisitos previos en la máquina host

El proyecto está contenerizado mediante Dev Containers para evitar instalaciones manuales de Zephyr, toolchains de C o dependencias del sistema.

Solo se necesita:

1. **Docker Desktop** instalado y ejecutándose.
2. **Visual Studio Code**.
3. Extensión oficial **Dev Containers** de Microsoft.
4. Conexión a Internet durante la primera creación del contenedor.
5. Una placa **ESP32-C6** conectada por USB.

---

## Preparación del hardware en Windows

Si se ejecuta el proyecto desde Windows, es necesario exponer el puerto USB de la ESP32-C6 al entorno Linux usado por Docker/WSL.

Pasos:

1. Conectar la ESP32-C6 por USB.
2. Ejecutar el script:

```text
conectar_usb_windows.bat
```

3. Comprobar que dentro del devcontainer aparece el dispositivo:

```bash
ls /dev/ttyUSB*
```

En la mayoría de casos el dispositivo será:

```text
/dev/ttyUSB0
```

---

## Arrancar el entorno de desarrollo

1. Abrir Visual Studio Code en la carpeta raíz del proyecto.
2. Seleccionar:

```text
Dev Containers: Reopen in Container
```

3. Esperar a que se cree el contenedor.

Durante la creación del contenedor se automatiza:

* Instalación de dependencias Python.
* Preparación del entorno Zephyr.
* Verificación/instalación de Zenoh.
* Configuración de herramientas necesarias para compilar y flashear la ESP32-C6.

---

## Configuración segura de credenciales y endpoint

Por seguridad, las credenciales Wi-Fi y la dirección del endpoint Zenoh no se versionan en Git.

Antes de ejecutar el proyecto, crear en la raíz del repositorio un archivo llamado:

```text
secrets.conf
```

con este contenido:

```ini
CONFIG_WIFI_MI_SSID="Nombre_De_Tu_WiFi"
CONFIG_WIFI_MI_PASSWORD="Contraseña_De_Tu_WiFi"
CONFIG_ZENOH_ENDPOINT="tcp/IP_DEL_HOST:7447"
```

Ejemplo:

```ini
CONFIG_WIFI_MI_SSID="MiRedWiFi"
CONFIG_WIFI_MI_PASSWORD="MiContraseña"
CONFIG_ZENOH_ENDPOINT="tcp/192.168.1.130:7447"
```

`CONFIG_ZENOH_ENDPOINT` debe apuntar a la IP local de la máquina host donde se está ejecutando el devcontainer, no a `localhost` ni a `127.0.0.1`.

Este archivo está incluido en `.gitignore` y no debe subirse al repositorio.

---

## Modos de ejecución

El proyecto tiene dos modos principales.

---

### Modo Debug: red Zenoh y logs legibles

```bash
bash main/entropy.sh
```

Este modo:

* Compila el firmware Zephyr.
* Verifica los blobs binarios de Espressif necesarios para Wi-Fi.
* Verifica o instala `zenohd`.
* Levanta el router Zenoh.
* Lanza el servidor Rust.
* Flashea la ESP32-C6.
* Abre el monitor serie automáticamente.
* Permite ver logs legibles del proceso completo.

Flujo esperado:

```text
ESP32-C6 se conecta al Wi-Fi
ESP32-C6 obtiene IPv4
ESP32-C6 abre sesión Zenoh
Servidor Rust publica QRNG
ESP32-C6 recibe QRNG
ESP32-C6 genera TRNG local
ESP32-C6 calcula TRNG XOR QRNG
ESP32-C6 publica estado
Servidor Rust recibe estado
```

---

### Modo NIST: salida binaria cruda

```bash
bash main/entropy.sh --nist
```

Este modo está pensado para pruebas estadísticas de aleatoriedad.

En este modo:

* Se evita la salida de logs legibles.
* Se prioriza la emisión de datos binarios crudos.
* Se puede capturar una muestra para análisis posterior.
* El análisis puede realizarse con scripts Python, por ejemplo para:

  * Entropía de Shannon.
  * Chi-cuadrado.
  * Frecuencias de bytes.
  * Preparación de datos para baterías NIST.

---

## Servidor Rust

El servidor Rust se encuentra en:

```text
queeas_server/
```

Su función actual es:

* Conectarse al router Zenoh local.
* Publicar bloques QRNG en:

```text
qeeas/qrng/chunk
```

* Escuchar estados de la ESP32-C6 en:

```text
qeeas/esp32/status
```

En el estado actual del proyecto, el QRNG se simula dentro del propio servidor Rust para validar el flujo completo de comunicación y fusión de entropía.

En la versión final, esta parte se sustituirá por una llamada a una API QRNG proporcionada por el profesor. De esta forma, el servidor Rust descargará bloques de aleatoriedad cuántica desde dicha API y los publicará en la red Zenoh para que la ESP32-C6 los fusione localmente con su TRNG.

---

## Zenoh y zenoh-pico

El sistema usa dos componentes distintos:

### `zenohd`

Es el router Zenoh. Se ejecuta dentro del devcontainer y escucha en:

```text
tcp/0.0.0.0:7447
```

El puerto `7447` debe estar expuesto en el devcontainer para que la ESP32-C6 pueda conectarse desde la red Wi-Fi.

### `zenoh-pico`

Es la implementación ligera de Zenoh en C para dispositivos embebidos. Se compila junto con el firmware Zephyr y permite que la ESP32-C6:

* Abra una sesión Zenoh.
* Se suscriba a bloques QRNG.
* Publique mensajes de estado.
* Trabaje sobre TCP/IP usando la conexión Wi-Fi.

---

## Funcionamiento dentro del devcontainer

Como el servidor Rust y `zenohd` corren dentro del devcontainer, el servidor Rust se conecta a:

```text
tcp/127.0.0.1:7447
```

Sin embargo, la ESP32-C6 está fuera del contenedor. Por eso la placa debe conectarse a la IP local de la máquina host:

```text
tcp/IP_DEL_HOST:7447
```

Ejemplo:

```text
Rust dentro del devcontainer:
tcp/127.0.0.1:7447

ESP32-C6 desde la red Wi-Fi:
tcp/192.168.1.130:7447
```

---

## Archivos que no deben subirse a Git

El repositorio debe ignorar archivos generados, credenciales y builds locales.

Recomendado en `.gitignore`:

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

# Archivos temporales
*.tmp
```

---

## Archivos Rust que sí deben subirse a Git

Dentro de `queeas_server/`, sí deben subirse:

```text
Cargo.toml
Cargo.lock
src/main.rs
```

`Cargo.toml` define el proyecto y sus dependencias.

`Cargo.lock` fija las versiones exactas de las dependencias para que el servidor Rust sea reproducible en otra máquina.

No debe subirse:

```text
target/
```

porque contiene binarios y archivos intermedios generados por Cargo.

---

## Comprobaciones útiles

### Ver si la ESP32 aparece por USB

```bash
ls /dev/ttyUSB*
```

### Ver si `zenohd` está instalado

```bash
which zenohd
zenohd --version
```

### Ver si Zenoh escucha en el puerto 7447

```bash
ss -ltnp | grep 7447
```

Salida esperada:

```text
LISTEN ... 0.0.0.0:7447
```

### Ver logs del router Zenoh

```bash
cat /tmp/qeeas_logs/zenohd.log
```

### Ver logs del servidor Rust

```bash
cat /tmp/qeeas_logs/rust_server.log
```

---

## Problemas frecuentes

### La ESP32 no se conecta al Wi-Fi

Revisar:

```text
secrets.conf
```

y comprobar que el SSID y la contraseña son correctos.

---

### Error de blobs de Espressif

Si aparece un error similar a:

```text
Blob missing. Update with: west blobs fetch hal_espressif
```

ejecutar:

```bash
cd /workspaces/zephyrproject
west blobs fetch hal_espressif
cd /workspaces/TFG_QeeaS
```

El script principal está preparado para automatizar esta verificación antes de compilar.

---

### `zenohd` no escucha en el puerto 7447

Comprobar:

```bash
ss -ltnp | grep 7447
```

Si no aparece nada, revisar:

```bash
cat /tmp/qeeas_logs/zenohd.log
```

---

### La ESP32 no conecta con Zenoh

Comprobar:

1. Que la ESP32 está conectada al Wi-Fi.
2. Que tiene dirección IPv4.
3. Que `zenohd` está escuchando en `0.0.0.0:7447`.
4. Que el puerto `7447` está publicado en el devcontainer.
5. Que `CONFIG_ZENOH_ENDPOINT` en `secrets.conf` apunta a la IP local correcta del host.

---

## Ejecución resumida

Para ejecutar el sistema completo en modo debug:

```bash
bash main/entropy.sh
```

Para ejecutar el sistema en modo binario crudo para análisis estadístico:

```bash
bash main/entropy.sh --nist
```

---

## Estado actual del proyecto

Actualmente el sistema permite:

* Compilar firmware Zephyr para ESP32-C6.
* Conectar la ESP32-C6 a Wi-Fi.
* Ejecutar `zenohd` como router de mensajería.
* Ejecutar un servidor Rust como publicador QRNG simulado.
* Conectar la ESP32-C6 a Zenoh mediante zenoh-pico.
* Recibir bloques QRNG en la ESP32-C6.
* Generar TRNG local.
* Fusionar ambas fuentes mediante XOR dentro del microcontrolador.
* Publicar mensajes de estado desde la ESP32-C6 hacia el servidor Rust.

---

## Mejoras futuras

* Sustituir el QRNG simulado por una API QRNG real proporcionada por el profesor.
* Automatizar la detección de la IP local del host para generar automáticamente `CONFIG_ZENOH_ENDPOINT`.
* Implementar un pool local persistente de entropía híbrida.
* Añadir derivación criptográfica mediante hash o KDF.
* Añadir pruebas estadísticas completas sobre la entropía final.
* Evaluar TLS/mTLS o mecanismos de autenticación para Zenoh.
