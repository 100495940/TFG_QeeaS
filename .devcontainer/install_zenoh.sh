#!/usr/bin/env bash

set -euo pipefail

ZENOH_VERSION="1.9.0"
ZENOH_INSTALL_DIR="/opt/zenoh"
ZENOH_BIN="/usr/local/bin/zenohd"

echo "[ZENOH] Verificando instalación de zenohd..."

if command -v zenohd >/dev/null 2>&1; then
    echo "[ZENOH] zenohd ya está instalado: $(zenohd --version 2>/dev/null || true)"
    exit 0
fi

ARCH="$(uname -m)"

case "$ARCH" in
    x86_64)
        ZENOH_TARGET="x86_64-unknown-linux-gnu"
        ;;
    aarch64|arm64)
        ZENOH_TARGET="aarch64-unknown-linux-gnu"
        ;;
    *)
        echo "[ZENOH][ERROR] Arquitectura no soportada automáticamente: $ARCH"
        exit 1
        ;;
esac

ZENOH_ZIP="zenoh-${ZENOH_VERSION}-${ZENOH_TARGET}-standalone.zip"
ZENOH_URL="https://download.eclipse.org/zenoh/zenoh/${ZENOH_VERSION}/${ZENOH_ZIP}"

echo "[ZENOH] Instalando dependencias base..."
apt-get update
apt-get install -y curl unzip ca-certificates
rm -rf /var/lib/apt/lists/*

echo "[ZENOH] Descargando Zenoh standalone:"
echo "[ZENOH] $ZENOH_URL"

mkdir -p "$ZENOH_INSTALL_DIR"
cd /tmp

curl -L "$ZENOH_URL" -o "$ZENOH_ZIP"

echo "[ZENOH] Descomprimiendo..."
unzip -o "$ZENOH_ZIP" -d "$ZENOH_INSTALL_DIR"

echo "[ZENOH] Buscando binario zenohd..."
FOUND_ZENOHD="$(find "$ZENOH_INSTALL_DIR" -type f -name zenohd | head -n 1)"

if [ -z "$FOUND_ZENOHD" ]; then
    echo "[ZENOH][ERROR] No se encontró el binario zenohd tras descomprimir."
    find "$ZENOH_INSTALL_DIR" -maxdepth 3 -type f
    exit 1
fi

chmod +x "$FOUND_ZENOHD"
ln -sf "$FOUND_ZENOHD" "$ZENOH_BIN"

echo "[ZENOH] Instalación completada:"
zenohd --version || true