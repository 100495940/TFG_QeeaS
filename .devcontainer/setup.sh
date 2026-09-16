#!/usr/bin/env bash
# Este script se ejecutará automáticamente tras crear el contenedor

echo "=== Configurando dependencias de Python ==="
pip install -r requirements.txt

echo "=== Verificando instalación de Zenoh ==="
bash scripts/install_zenoh.sh

echo "=== Configurando el entorno de Zephyr automáticamente ==="

ZEPHYR_WORKSPACE="/workspaces/zephyrproject"
ZEPHYR_REPO="$ZEPHYR_WORKSPACE/zephyr"

ESPRESSIF_REPO="$ZEPHYR_WORKSPACE/modules/hal/espressif"

ZEPHYR_COMMIT_FILE="/workspaces/TFG_QeeaS/zephyr.commit"
ESPRESSIF_COMMIT_FILE="/workspaces/TFG_QeeaS/espressif.commit"

if [[ ! -f "$ZEPHYR_COMMIT_FILE" ]]; then
    echo "[ERROR] No existe $ZEPHYR_COMMIT_FILE"
    exit 1
fi

ZEPHYR_COMMIT="$(tr -d '[:space:]' < "$ZEPHYR_COMMIT_FILE")"

echo "Zephyr commit requerido: $ZEPHYR_COMMIT"

if [[ ! -f "$ESPRESSIF_COMMIT_FILE" ]]; then
    echo "[ERROR] No existe $ESPRESSIF_COMMIT_FILE"
    exit 1
fi

ESPRESSIF_COMMIT="$(tr -d '[:space:]' < "$ESPRESSIF_COMMIT_FILE")"

echo "Espressif commit requerido: $ESPRESSIF_COMMIT"

cd /workspaces

if [ ! -d "zephyrproject" ] ; then
    echo "Descargando Zephyr RTOS, módulos y drivers (esto puede llevar unos minutos)"
    west init zephyrproject
    cd zephyrproject
    west update
    west zephyr-export
    echo "Zephyr instalado con éxito"
    echo "Fijando repositorio de zephyr"
    git -C "$ZEPHYR_REPO" fetch --all --tags
    git -C "$ZEPHYR_REPO" checkout "$ZEPHYR_COMMIT"
    echo "Fijando repositorio de espressif"
    git -C "$ESPRESSIF_REPO" fetch --all --tags
    git -C "$ESPRESSIF_REPO" checkout "$ESPRESSIF_COMMIT"
else
    echo "Entorno de Zephyr ya configurado previamente"
fi