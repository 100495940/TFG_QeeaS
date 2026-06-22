#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="$PROJECT_ROOT/queeas_server"
echo "$PROJECT_DIR"

MIN_RUST="1.88.0"
CURRENT_RUST="$(rustc --version | awk '{print $2}')"

cd "$PROJECT_DIR"

echo "Versión actual de Rust: $CURRENT_RUST"
echo "Versión mínima requerida de Rust: $MIN_RUST"

if [ "$(printf '%s\n' "$MIN_RUST" "$CURRENT_RUST" | sort -V | head -n1)" != "$MIN_RUST" ]; then
    echo "Versión de Rust demasiado antigua"
    echo "Actualizando a última versión disponible de Rust"
    rustup default stable
    rustup update stable

    echo "Recargando entorno Rust"
    source "$HOME/.cargo/env"

    CURRENT_RUST="$(rustc --version | awk '{print $2}')"
    echo "Nueva versión de Rust: $CURRENT_RUST"

    cargo clean || true
fi

echo "Compilando servidor QeeaS"
cargo build --release

echo "Lanzando servidor Qeeas"
exec "$PROJECT_DIR/../queeas_server/target/release/qeeas_server"
