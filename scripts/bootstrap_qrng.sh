#!/usr/bin/env bash

# Script utilizado para clonar el repo de la API QRNG en caso de
# que este aún no exista. Si este ya existe, lo reutiliza y hace
# checkout al commit especificado en el archivo qrng_server.commit.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

QEAAS_REPO_URL="https://github.com/qursa-uc3m/qeaas-server.git"
QEAAS_DIR="${QEAAS_DIR:-/qeeas_deps/qrng_server}"
QEAAS_COMMIT_FILE="${QEAAS_COMMIT_FILE:-$PROJECT_ROOT/qrng_server.commit}"

echo "[QEAAS-BOOTSTRAP] Preparando servidor QEaaS..."
echo "[QEAAS-BOOTSTRAP] Directorio esperado: $QEAAS_DIR"
echo "[QEAAS-BOOTSTRAP] Archivo commit: $QEAAS_COMMIT_FILE"

if [ ! -f "$QEAAS_COMMIT_FILE" ]; then
    echo "[QEAAS-BOOTSTRAP][ERROR] No existe el archivo de commit fijo:"
    echo "[QEAAS-BOOTSTRAP][ERROR] $QEAAS_COMMIT_FILE"
    echo "[QEAAS-BOOTSTRAP][ERROR] Crea este archivo con:"
    echo "[QEAAS-BOOTSTRAP][ERROR] git -C qrng_server rev-parse HEAD > qrng_server.commit"
    exit 1
fi

QEAAS_COMMIT="$(tr -d '[:space:]' < "$QEAAS_COMMIT_FILE")"

if [ -z "$QEAAS_COMMIT" ]; then
    echo "[QEAAS-BOOTSTRAP][ERROR] El archivo $QEAAS_COMMIT_FILE está vacío."
    exit 1
fi

echo "[QEAAS-BOOTSTRAP] Commit esperado: $QEAAS_COMMIT"

mkdir -p "$(dirname "$QEAAS_DIR")"

REPO_OK=false

if [ ! -d "$QEAAS_DIR/.git" ]; then
    if git -C "$QEAAS_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        REPO_OK=true
    else
        echo "[QEAAS-BOOTSTRAP][WARN] Existe $QEAAS_DIR, pero no parece un repo Git válido."
    fi
fi

if [ "$REPO_OK" != "true" ]; then
    echo "[QEAAS-BOOTSTRAP] Clonando QEaaS desde cero..."

    rm -rf "$QEAAS_DIR"
    git clone "$QEAAS_REPO_URL" "$QEAAS_DIR"
fi

echo "[QEAAS-BOOTSTRAP] Sincronizando repo QEaaS con origin..."
if ! git -C "$QEAAS_DIR" fetch --tags origin; then
    echo "[QEAAS-BOOTSTRAP][WARN] Fetch falló. Re-clonando QEaaS..."

    rm -rf "$QEAAS_DIR"
    git clone "$QEAAS_REPO_URL" "$QEAAS_DIR"
    git -C "$QEAAS_DIR" fetch --tags origin
fi

echo "[QEAAS-BOOTSTRAP] Haciendo checkout al commit fijado..."
git -C "$QEAAS_DIR" checkout --detach "$QEAAS_COMMIT"
git -C "$QEAAS_DIR" reset --hard "$QEAAS_COMMIT"

echo "[QEAAS-BOOTSTRAP] Inicializando submódulos internos de QEaaS..."
git -C "$QEAAS_DIR" submodule update --init --recursive

echo "[QEAAS-BOOTSTRAP] QEaaS preparado correctamente."
echo "[QEAAS-BOOTSTRAP] Commit actual:"
git -C "$QEAAS_DIR" rev-parse HEAD