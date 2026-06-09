# TFG: Entropy as a Service (QeeaS) con ESP32-C6 y Zephyr RTOS

Este proyecto implementa una arquitectura de Edge Computing Criptográfico. Utiliza una ESP32-C6 para extraer entropía pura del ruido térmico del hardware (TRNG) y prepararla para su fusión con números aleatorios cuánticos (QRNG) en una red distribuida.

## 🛠️ Requisitos Previos en la Máquina Host

El proyecto está contenerizado para garantizar que cualquier persona pueda compilar el firmware sin lidiar con dependencias de C o Zephyr. Solo necesitas:

1. **Docker Desktop:** Instalado y ejecutándose en segundo plano.
2. **Visual Studio Code:** Con la extensión oficial **Dev Containers** (de Microsoft) instalada.
3. **Conexión a Internet:** Para la primera descarga automatizada de la imagen del entorno (Toolchain de Zephyr).

---

## 🚀 Cómo Levantar el Proyecto (Paso a Paso)

Sigue este orden exacto para iniciar el entorno, enlazar el hardware y compilar el sistema operativo:

### 1. Preparación del hardware (Solo usuarios de Windows)
Si estás ejecutando este proyecto desde Windows, necesitas crear un túnel para que el contenedor Linux (Docker) pueda hablar físicamente con el puerto USB donde está conectada la ESP32.
* Conecta la ESP32-C6 por USB.
* Ejecuta el script `conectar_usb_windows.bat` haciendo doble clic sobre él.

### 2. Arrancar el Entorno de Desarrollo
* Abre Visual Studio Code en la carpeta raíz del proyecto (`TFG_QeeaS`).
* VS Code detectará la configuración y mostrará una notificación en la esquina inferior derecha: *"Reopen in Container"*. Haz clic en ella.
* *Nota: Si no sale la notificación, pulsa `F1`, escribe `Dev Containers: Reopen in Container` y pulsa Enter.*

### 3. Configuración de Credenciales Seguras (Wi-Fi)
Por motivos de ciberseguridad, las contraseñas no están en el código fuente. Antes de compilar, debes crear un archivo de superposición (Overlay):
* En la raíz del proyecto, crea un archivo llamado **exactamente** `secrets.conf`.
* Añade tus credenciales de red (manteniendo las comillas):

```text
CONFIG_WIFI_MI_SSID="Tu_Red_WIFI"
CONFIG_WIFI_MI_PASSWORD="Tu_Contraseña"
```

* *(Este archivo está protegido por `.gitignore` y nunca se subirá al repositorio).*

### 4. Compilación y Ejecución
Abre la terminal integrada de VS Code (que ahora estará ejecutando un Linux interno) y lanza el script de automatización. El sistema compilará el código C, lo inyectará en la ESP32 y abrirá el puerto serie automáticamente.

---

## ⚙️ Modos de Ejecución (Flags del Script)

El proyecto cuenta con dos perfiles de compilación gestionados por el preprocesador de C, adaptables según las necesidades de la prueba:

### 🔹 Modo Debug (Red y Texto)

```bash
bash main/entropy.sh
```

* **Uso:** Desarrollo y diagnóstico.
* **Comportamiento:** Compila la pila de red asíncrona, conecta al Wi-Fi especificado en el `secrets.conf` y emite logs legibles por consola sobre la extracción del TRNG.

### 🔹 Modo Producción (Pruebas NIST / Binario Crudo)

```bash
bash main/entropy.sh --nist
```

* **Uso:** Certificación criptográfica.
* **Comportamiento:** Borra físicamente todo el texto (logs) del firmware mediante Kconfig, silencia la consola y escupe datos binarios crudos a la máxima velocidad del procesador (`k_yield`) para realizar análisis matemáticos (ej. Test Chi-Cuadrado y Entropía de Shannon mediante un script paralelo en Python).