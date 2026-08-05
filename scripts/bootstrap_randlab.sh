#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

RANDLAB_DIR="${RANDLAB_DIR:-$PROJECT_ROOT/external/randlab}"
RANDLAB_REPO_URL="${RANDLAB_REPO_URL:-https://github.com/perlab-uc3m/randlab.git}"
RANDLAB_COMMIT_FILE="${RANDLAB_COMMIT_FILE:-$PROJECT_ROOT/randlab.commit}"
RANDLAB_VENV_DIR="${RANDLAB_VENV_DIR:-$RANDLAB_DIR/.venv}"

echo "[RANDLAB-BOOTSTRAP] Preparando randlab..."
echo "[RANDLAB-BOOTSTRAP] Directorio esperado: $RANDLAB_DIR"

if [ ! -f "$RANDLAB_COMMIT_FILE" ]; then
    echo "[RANDLAB-BOOTSTRAP][ERROR] No existe el archivo de commit fijado:"
    echo "  $RANDLAB_COMMIT_FILE"
    exit 1
fi

RANDLAB_COMMIT="$(tr -d '[:space:]' < "$RANDLAB_COMMIT_FILE")"

if [ -z "$RANDLAB_COMMIT" ]; then
    echo "[RANDLAB-BOOTSTRAP][ERROR] El archivo $RANDLAB_COMMIT_FILE está vacío."
    exit 1
fi

echo "[RANDLAB-BOOTSTRAP] Commit esperado: $RANDLAB_COMMIT"

mkdir -p "$(dirname "$RANDLAB_DIR")"

if [ ! -d "$RANDLAB_DIR/.git" ]; then
    echo "[RANDLAB-BOOTSTRAP] Repositorio no encontrado. Clonando..."
    git clone "$RANDLAB_REPO_URL" "$RANDLAB_DIR"
else
    echo "[RANDLAB-BOOTSTRAP] Repositorio ya presente. Reutilizando."
fi

cd "$RANDLAB_DIR"

echo "[RANDLAB-BOOTSTRAP] Sincronizando repo..."
git fetch --all --tags

if git rev-parse "$RANDLAB_COMMIT" >/dev/null 2>&1; then
    git checkout "$RANDLAB_COMMIT"
else
    echo "[RANDLAB-BOOTSTRAP][ERROR] No se encuentra el commit fijado:"
    echo "  $RANDLAB_COMMIT"
    exit 1
fi

echo "[RANDLAB-BOOTSTRAP] Commit actual:"
git rev-parse HEAD

if [ ! -d "$RANDLAB_VENV_DIR" ]; then
    echo "[RANDLAB-BOOTSTRAP] Creando entorno virtual Python..."
    python3 -m venv "$RANDLAB_VENV_DIR"
else
    echo "[RANDLAB-BOOTSTRAP] Entorno virtual ya existente."
fi

# shellcheck disable=SC1090
source "$RANDLAB_VENV_DIR/bin/activate"

echo "[RANDLAB-BOOTSTRAP] Actualizando pip..."
python -m pip install --upgrade pip

echo "[RANDLAB-BOOTSTRAP] Instalando randlab en editable..."
python -m pip install -e .[dev]

echo "[RANDLAB-BOOTSTRAP] Instalando/verificando dependencias nativas..."
randlab deps install --install-system || true

echo "[RANDLAB-BOOTSTRAP] Comprobando instalación..."
randlab check || true

echo "[RANDLAB-BOOTSTRAP] randlab preparado correctamente."