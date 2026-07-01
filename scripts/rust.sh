#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="$PROJECT_ROOT/queeas_server"

export PATH="$HOME/.cargo/bin:$PATH"

MIN_RUST="1.88.0"

cd "$PROJECT_DIR"

CURRENT_RUST="$(rustc --version | awk '{print $2}')"

echo "[RUST] Proyecto: $PROJECT_DIR"
echo "[RUST] Versión actual de Rust: $CURRENT_RUST"
echo "[RUST] Versión mínima requerida: $MIN_RUST"

if [ "$(printf '%s\n' "$MIN_RUST" "$CURRENT_RUST" | sort -V | head -n1)" != "$MIN_RUST" ]; then
    echo "[RUST] Versión de Rust demasiado antigua"
    echo "[RUST] Actualizando a stable..."

    rustup default stable
    rustup update stable

    source "$HOME/.cargo/env"

    CURRENT_RUST="$(rustc --version | awk '{print $2}')"
    echo "[RUST] Nueva versión de Rust: $CURRENT_RUST"

    cargo clean || true
fi

echo "[RUST] Compilando servidor QeeaS"
cargo build --release

echo "[RUST] Lanzando servidor QeeaS"
exec "$PROJECT_DIR/target/release/qeeas_server"