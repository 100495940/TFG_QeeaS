#!/bin/bash
echo "[INFO] Levantando servidor cuántico de números"
echo ""

if [ ! -d "qrng_server" ]; then
    echo "[INFO] Repositorio del servidor cuántico no encontrado. Clonando..."
    echo ""
    git clone https://github.com/qursa-uc3m/qeaas-server.git qrng_server
    cd qrng_server
    echo "[INFO] Inicializando submódulos criptográficos..."
    echo ""
    git submodule update --init --recursive
    echo "[INFO] Levantando entorno..."
    echo ""
    chmod +x setup-and-clean.sh
    bash setup-and-clean.sh
    cd ..
fi

echo "[INFO] Encendiendo contenedores en segundo plano..."
echo ""
cd qrng_server
# Levantar los servicios en modo detached para no bloquear la terminal
docker-compose up --build -d
cd ..
echo "[INFO] API de número cuánticos lista y escuchando en 127.0.0.1:4433"
echo ""
.