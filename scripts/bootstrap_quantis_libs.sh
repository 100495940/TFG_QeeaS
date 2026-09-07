#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

QUANTIS_LIB_REPO_URL="https://github.com/fj-blanco/qursa-software-installation.git"
QUANTIS_LIB_DIR="${QUANTIS_LIB_DIR:-/quantis_lib_deps/qursa-software-installation}"
QUANTIS_LIB_COMMIT_FILE="${QUANTIS_LIB_COMMIT_FILE:-$PROJECT_ROOT/quantis_libraries.commit}"

if [ ! -f "$QUANTIS_LIB_COMMIT_FILE" ]; then
    echo "[QUANTIS-LIB][ERROR] Falta $QUANTIS_LIB_COMMIT_FILE"
    exit 1
fi

COMMIT="$(tr -d '[:space:]' < "$QUANTIS_LIB_COMMIT_FILE")"

if [ ! -d "$QUANTIS_LIB_DIR/.git" ]; then

    rm -rf "$QUANTIS_LIB_DIR"

    git clone \
        --filter=blob:none \
        --no-checkout \
        "$QUANTIS_LIB_REPO_URL" \
        "$QUANTIS_LIB_DIR"

    git -C "$QUANTIS_LIB_DIR" sparse-checkout init --cone
    git -C "$QUANTIS_LIB_DIR" sparse-checkout set quantis-libraries
fi

git -C "$QUANTIS_LIB_DIR" fetch origin
git -C "$QUANTIS_LIB_DIR" checkout --detach "$COMMIT"
git -C "$QUANTIS_LIB_DIR" sparse-checkout set quantis-libraries

echo "[QUANTIS-LIB] Librerías disponibles en:"
echo "$QUANTIS_LIB_DIR/quantis-libraries"