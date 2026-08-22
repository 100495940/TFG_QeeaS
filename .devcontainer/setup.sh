#!/usr/bin/env bash
# Este script se ejecutará automáticamente tras crear el contenedor

echo "=== Configurando dependencias de Python ==="
pip install -r requirements.txt

echo "=== Verificando instalación de Zenoh ==="
bash scripts/install_zenoh.sh

echo "=== Configurando el entorno de Zephyr automáticamente ==="

cd /workspaces

if [ ! -d "zephyrproject" ] ; then
    echo "Descargando Zephyr RTOS, módulos y drivers (esto puede llevar unos minutos)"
    west init zephyrproject
    cd zephyrproject
    west update
    west zephyr-export
    echo "Zephyr instalado con éxito"
else
    echo "Entorno de Zephyr ya configurado previamente"
fi