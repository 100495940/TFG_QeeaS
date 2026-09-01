#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="$PROJECT_ROOT/queeas_server"

export PATH="$HOME/.cargo/bin:$PATH"

MIN_RUST="1.88.0"
CARGO_JOBS="${CARGO_JOBS:-2}"
RUST_PROFILE="${RUST_PROFILE:-debug}"
BIN_NAME="${BIN_NAME:-qeeas_server}"

# Sacar target/ del repo montado desde Windows
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/cargo-target/qeeas_server}"

mkdir -p "$CARGO_TARGET_DIR"

cd "$PROJECT_DIR"

CURRENT_RUST="$(rustc --version | awk '{print $2}')"
CURRENT_CARGO="$(cargo --version | awk '{print $2}')"

echo "[RUST-BUILD] Proyecto: $PROJECT_DIR"
echo "[RUST-BUILD] Rust actual: $CURRENT_RUST"
echo "[RUST-BUILD] Rust actual: $CURRENT_CARGO"
echo "[RUST-BUILD] Rust mínimo: $MIN_RUST"
echo "[RUST-BUILD] Perfil: $RUST_PROFILE"
echo "[RUST-BUILD] Jobs: $CARGO_JOBS"
echo "[RUST-BUILD] Target dir: $CARGO_TARGET_DIR"
echo "[RUST-BUILD] Binario: $BIN_NAME"

if [ "$RUST_PROFILE" = "release" ]; then
    echo "[RUST-BUILD] Compilando en modo release..."
    cargo build --locked --release --bin "$BIN_NAME" -j "$CARGO_JOBS"
    BINARY="$CARGO_TARGET_DIR/release/$BIN_NAME"
else
    echo "[RUST-BUILD] Compilando en modo debug..."
    cargo build --locked --bin "$BIN_NAME" -j "$CARGO_JOBS"
    BINARY="$CARGO_TARGET_DIR/debug/$BIN_NAME"
fi

echo "[RUST-BUILD] Compilación finalizada."
echo "[RUST-BUILD] Binario generado en:"
echo "$BINARY"