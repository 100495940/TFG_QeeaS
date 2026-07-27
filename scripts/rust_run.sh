#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

RUST_PROFILE="${RUST_PROFILE:-debug}"
BIN_NAME="${BIN_NAME:-qeeas_server}"

export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/cargo-target/qeeas_server}"
export RUST_BACKTRACE="${RUST_BACKTRACE:-1}"

if [ "$RUST_PROFILE" = "release" ]; then
    BINARY="$CARGO_TARGET_DIR/release/$BIN_NAME"
else
    BINARY="$CARGO_TARGET_DIR/debug/$BIN_NAME"
fi

echo "[RUST-RUN] Perfil: $RUST_PROFILE"
echo "[RUST-RUN] Binario: $BINARY"

if [ ! -x "$BINARY" ]; then
    echo "[RUST-RUN][ERROR] No existe el binario o no es ejecutable:"
    echo "$BINARY"
    echo "[RUST-RUN][ERROR] Ejecuta primero:"
    echo "bash scripts/rust_build.sh"
    exit 1
fi

echo "[RUST-RUN] Lanzando servidor QeeaS..."
exec "$BINARY"