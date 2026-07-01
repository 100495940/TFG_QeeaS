#!/usr/bin/env bash

set -euo pipefail

echo "[INFO] Limpiando procesos antiguos de Zenoh/QeeaS..."

pkill -x zenohd 2>/dev/null || true
pkill -f "qeeas_server" 2>/dev/null || true
pkill -f "target/release/qeeas_server" 2>/dev/null || true

sleep 1

echo "[INFO] Limpieza inicial completada."