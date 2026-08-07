#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Monitor de captura de entropia para QeeaS / ESP32-C6
#
# Este script NO lanza entropy.sh.
# Solo observa el crecimiento de los archivos .bin capturados
# por Rust y avisa cuando entropy_final_active.bin alcanza
# el numero de bytes objetivo.
#
# Uso:
#   ENTROPY_EXPERIMENT=blake2s \
#   CAPTURE_TARGET_BYTES=1048576 \
#   bash scripts/watch_entropy_capture.sh
# ============================================================

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

EXPERIMENT="${ENTROPY_EXPERIMENT:-default}"
TARGET_BYTES="${CAPTURE_TARGET_BYTES:-1048576}"
CAPTURE_ROOT="${CAPTURE_ROOT:-$PROJECT_ROOT/data/captures}"
CAPTURE_DIR="$CAPTURE_ROOT/$EXPERIMENT"
WATCH_FILE="${CAPTURE_WATCH_FILE:-$CAPTURE_DIR/entropy_final_active.bin}"

POLL_INTERVAL="${CAPTURE_POLL_INTERVAL:-1}"
BAR_WIDTH="${CAPTURE_BAR_WIDTH:-40}"
STALL_SECONDS="${CAPTURE_STALL_SECONDS:-30}"

# Si stdout es una terminal real, usamos barra dinamica en una sola linea.
# Si stdout esta redirigido a un log, imprimimos una linea cada LOG_EVERY segundos.
if [ -t 1 ]; then
    DYNAMIC_OUTPUT=1
else
    DYNAMIC_OUTPUT=0
fi

LOG_EVERY="${CAPTURE_LOG_EVERY:-10}"

if ! [[ "$TARGET_BYTES" =~ ^[0-9]+$ ]]; then
    echo "[ERROR] CAPTURE_TARGET_BYTES debe ser un numero entero."
    exit 1
fi

if ! [[ "$POLL_INTERVAL" =~ ^[0-9]+$ ]]; then
    echo "[ERROR] CAPTURE_POLL_INTERVAL debe ser un numero entero."
    exit 1
fi

if ! [[ "$STALL_SECONDS" =~ ^[0-9]+$ ]]; then
    echo "[ERROR] CAPTURE_STALL_SECONDS debe ser un numero entero."
    exit 1
fi

human_bytes() {
    local bytes="$1"

    if command -v numfmt >/dev/null 2>&1; then
        numfmt --to=iec-i --suffix=B "$bytes"
    else
        echo "${bytes}B"
    fi
}

format_time() {
    local total="$1"
    local h=$((total / 3600))
    local m=$(((total % 3600) / 60))
    local s=$((total % 60))

    printf "%02d:%02d:%02d" "$h" "$m" "$s"
}

file_size() {
    local file="$1"

    if [ -f "$file" ]; then
        stat -c "%s" "$file"
    else
        echo 0
    fi
}

draw_progress_line() {
    local current="$1"
    local target="$2"
    local rate="$3"
    local eta="$4"
    local elapsed="$5"
    local stalled_for="$6"

    local percent_x100=0
    local percent_int=0
    local percent_dec=0
    local filled=0

    if [ "$target" -gt 0 ]; then
        percent_x100=$((current * 10000 / target))
        percent_int=$((percent_x100 / 100))
        percent_dec=$((percent_x100 % 100))
        filled=$((current * BAR_WIDTH / target))
    fi

    if [ "$filled" -gt "$BAR_WIDTH" ]; then
        filled="$BAR_WIDTH"
    fi

    local empty=$((BAR_WIDTH - filled))
    local filled_bar
    local empty_bar
    local status

    filled_bar="$(printf "%${filled}s" "" | tr ' ' '#')"
    empty_bar="$(printf "%${empty}s" "" | tr ' ' '-')"

    if [ "$stalled_for" -ge "$STALL_SECONDS" ]; then
        status="STALLED ${stalled_for}s"
    else
        status="OK"
    fi

    printf "[%-${BAR_WIDTH}s] %3d.%02d%%  %s/%s  rate=%s/s  eta=%s  elapsed=%s  status=%s" \
        "${filled_bar}${empty_bar}" \
        "$percent_int" \
        "$percent_dec" \
        "$(human_bytes "$current")" \
        "$(human_bytes "$target")" \
        "$(human_bytes "$rate")" \
        "$(format_time "$eta")" \
        "$(format_time "$elapsed")" \
        "$status"
}

print_dynamic_progress() {
    local current="$1"
    local target="$2"
    local rate="$3"
    local eta="$4"
    local elapsed="$5"
    local stalled_for="$6"

    # \r vuelve al inicio de la linea.
    # \033[2K limpia toda la linea actual.
    printf "\r\033[2K"
    draw_progress_line "$current" "$target" "$rate" "$eta" "$elapsed" "$stalled_for"
}

print_log_progress() {
    local current="$1"
    local target="$2"
    local rate="$3"
    local eta="$4"
    local elapsed="$5"
    local stalled_for="$6"

    draw_progress_line "$current" "$target" "$rate" "$eta" "$elapsed" "$stalled_for"
    printf "\n"
}

echo "============================================================"
echo " MONITOR DE CAPTURA DE ENTROPIA - QeeaS / ESP32-C6"
echo "============================================================"
echo "Experimento : $EXPERIMENT"
echo "Target      : $(human_bytes "$TARGET_BYTES") ($TARGET_BYTES bytes)"
echo "Directorio  : $CAPTURE_DIR"
echo "Watch file  : $WATCH_FILE"
echo "Intervalo   : ${POLL_INTERVAL}s"
echo "Stall warn  : ${STALL_SECONDS}s sin crecer"
echo "TTY         : $([ "$DYNAMIC_OUTPUT" -eq 1 ] && echo "si" || echo "no")"
echo "============================================================"

echo "[WATCH] Esperando a que exista el archivo..."
while [ ! -f "$WATCH_FILE" ]; do
    sleep "$POLL_INTERVAL"
done

START_TS="$(date +%s)"
START_BYTES="$(file_size "$WATCH_FILE")"

LAST_BYTES="$START_BYTES"
LAST_CHANGE_TS="$START_TS"
LAST_LOG_TS="$START_TS"

echo "[WATCH] Archivo detectado."
echo "[WATCH] Bytes iniciales: $START_BYTES"
echo

while true; do
    CURRENT_BYTES="$(file_size "$WATCH_FILE")"
    NOW_TS="$(date +%s)"
    ELAPSED=$((NOW_TS - START_TS))

    if [ "$CURRENT_BYTES" -ne "$LAST_BYTES" ]; then
        LAST_BYTES="$CURRENT_BYTES"
        LAST_CHANGE_TS="$NOW_TS"
    fi

    STALLED_FOR=$((NOW_TS - LAST_CHANGE_TS))

    if [ "$ELAPSED" -gt 0 ]; then
        DELTA=$((CURRENT_BYTES - START_BYTES))

        if [ "$DELTA" -lt 0 ]; then
            DELTA=0
        fi

        RATE=$((DELTA / ELAPSED))
    else
        RATE=0
    fi

    REMAINING=$((TARGET_BYTES - CURRENT_BYTES))

    if [ "$REMAINING" -lt 0 ]; then
        REMAINING=0
    fi

    if [ "$RATE" -gt 0 ]; then
        ETA=$((REMAINING / RATE))
    else
        ETA=0
    fi

    if [ "$DYNAMIC_OUTPUT" -eq 1 ]; then
        print_dynamic_progress "$CURRENT_BYTES" "$TARGET_BYTES" "$RATE" "$ETA" "$ELAPSED" "$STALLED_FOR"
    else
        if [ $((NOW_TS - LAST_LOG_TS)) -ge "$LOG_EVERY" ]; then
            print_log_progress "$CURRENT_BYTES" "$TARGET_BYTES" "$RATE" "$ETA" "$ELAPSED" "$STALLED_FOR"
            LAST_LOG_TS="$NOW_TS"
        fi
    fi

    if [ "$CURRENT_BYTES" -ge "$TARGET_BYTES" ]; then
        if [ "$DYNAMIC_OUTPUT" -eq 1 ]; then
            printf "\n"
        fi

        echo
        echo "============================================================"
        echo "[OK] Target de captura alcanzado"
        echo "============================================================"
        echo "Archivo     : $WATCH_FILE"
        echo "Bytes       : $CURRENT_BYTES"
        echo "Target      : $TARGET_BYTES"
        echo "Directorio  : $CAPTURE_DIR"
        echo "Tiempo      : $(format_time "$ELAPSED")"
        echo "Rate medio  : $(human_bytes "$RATE")/s"
        echo "============================================================"

        echo
        echo "[WATCH] Tamaños actuales de los .bin:"
        ls -lh "$CAPTURE_DIR"/*.bin 2>/dev/null || true

        echo
        echo "[WATCH] Tamaños exactos:"
        for file in "$CAPTURE_DIR"/*.bin; do
            if [ -f "$file" ]; then
                printf "  %-45s %12s bytes\n" "$(basename "$file")" "$(stat -c "%s" "$file")"
            fi
        done

        echo
        echo "[WATCH] Captura suficiente. Puedes parar entropy.sh con Ctrl + X en el monitor serie."
        echo "============================================================"
        break
    fi

    sleep "$POLL_INTERVAL"
done