#!/usr/bin/env bash

# Script utilizado para clonar el repo de los drivers de QUANTIS en caso de
# que este aún no exista. Si este ya existe, lo reutiliza y hace
# checkout al commit especificado en el archivo quantis_drivers_server.commit.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

QUANTIS_DRIVERS_REPO_URL="https://github.com/qursa-uc3m/quantis-qrng-tls-pq-bench"
QUANTIS_DRIVERS_DIR="${QUANTIS_DRIVERS_DIR:-/quantis_drivers_deps/quantis_drivers}"
QUANTIS_DRIVERS_COMMIT_FILE="${QUANTIS_DRIVERS_COMMIT_FILE:-$PROJECT_ROOT/quantis_drivers.commit}"

echo "[QUANTIS_DRIVERS-BOOTSTRAP] Preparando drivers de QUANTIS..."
echo "[QUANTIS_DRIVERS-BOOTSTRAP] Directorio esperado: $QUANTIS_DRIVERS_DIR"
echo "[QUANTIS_DRIVERS-BOOTSTRAP] Archivo commit: $QUANTIS_DRIVERS_COMMIT_FILE"

if [ ! -f "$QUANTIS_DRIVERS_COMMIT_FILE" ]; then
    echo "[QUANTIS_DRIVERS-BOOTSTRAP][ERROR] No existe el archivo de commit fijo:"
    echo "[QUANTIS_DRIVERS-BOOTSTRAP][ERROR] $QUANTIS_DRIVERS_COMMIT_FILE"
    echo "[QUANTIS_DRIVERS-BOOTSTRAP][ERROR] Crea este archivo con:"
    echo "[QUANTIS_DRIVERS-BOOTSTRAP][ERROR] git -C quantis_drivers rev-parse HEAD > quantis_drivers.commit"
    exit 1
fi

QUANTIS_DRIVERS_COMMIT="$(tr -d '[:space:]' < "$QUANTIS_DRIVERS_COMMIT_FILE")"

if [ -z "$QUANTIS_DRIVERS_COMMIT" ]; then
    echo "[QUANTIS_DRIVERS-BOOTSTRAP][ERROR] El archivo $QUANTIS_DRIVERS_COMMIT_FILE está vacío."
    exit 1
fi

echo "[QUANTIS_DRIVERS-BOOTSTRAP] Commit esperado: $QUANTIS_DRIVERS_COMMIT"

mkdir -p "$(dirname "$QUANTIS_DRIVERS_DIR")"

REPO_OK=false

if [ ! -d "$QUANTIS_DRIVERS_DIR/.git" ]; then
    if git -C "$QUANTIS_DRIVERS_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        REPO_OK=true
    else
        echo "[QUANTIS_DRIVERS-BOOTSTRAP][WARN] Existe $QUANTIS_DRIVERS_DIR, pero no parece un repo Git válido."
    fi
fi

if [ "$REPO_OK" != "true" ]; then
    echo "[QUANTIS_DRIVERS-BOOTSTRAP] Clonando drivers de QUANTIS desde cero..."

    rm -rf "$QUANTIS_DRIVERS_DIR"
    git clone "$QUANTIS_DRIVERS_REPO_URL" "$QUANTIS_DRIVERS_DIR"
fi

echo "[QUANTIS_DRIVERS-BOOTSTRAP] Sincronizando repo de drivers QUANTIS con origin..."
if ! git -C "$QUANTIS_DRIVERS_DIR" fetch --tags origin; then
    echo "[QUANTIS_DRIVERS-BOOTSTRAP][WARN] Fetch falló. Re-clonando drivers de QUANTIS..."

    rm -rf "$QUANTIS_DRIVERS_DIR"
    git clone "$QUANTIS_DRIVERS_REPO_URL" "$QUANTIS_DRIVERS_DIR"
    git -C "$QUANTIS_DRIVERS_DIR" fetch --tags origin
fi

echo "[QUANTIS_DRIVERS-BOOTSTRAP] Haciendo checkout al commit fijado..."
git -C "$QUANTIS_DRIVERS_DIR" checkout --detach "$QUANTIS_DRIVERS_COMMIT"
git -C "$QUANTIS_DRIVERS_DIR" reset --hard "$QUANTIS_DRIVERS_COMMIT"

echo "[QUANTIS_DRIVERS-BOOTSTRAP] QEaaS preparado correctamente."
echo "[QUANTIS_DRIVERS-BOOTSTRAP] Commit actual:"
git -C "$QUANTIS_DRIVERS_DIR" rev-parse HEAD