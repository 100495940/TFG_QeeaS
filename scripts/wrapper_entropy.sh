#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

EXPERIMENT="${ENTROPY_EXPERIMENT:-blake2s}"
TARGET_BYTES="${CAPTURE_TARGET_BYTES:-1048576}"
CAPTURE_ROOT="${CAPTURE_ROOT:-$PROJECT_ROOT/data/captures}"
CAPTURE_DIR="$CAPTURE_ROOT/$EXPERIMENT"
WATCH_FILE="${CAPTURE_WATCH_FILE:-$CAPTURE_DIR/entropy_final_active.bin}"
POLL_INTERVAL="${CAPTURE_POLL_INTERVAL:-1}"
BAR_WIDTH="${CAPTURE_BAR_WIDTH:-40}"
LOG_FILE="$CAPTURE_DIR/entropy_capture_run.log"

if ! [[ "$TARGET_BYTES" =~ ^[0-9]+$ ]]; then
    echo "[ERROR] CAPTURE_TARGET_BYTES debe ser un numero entero."
    exit 1
fi

mkdir -p "$CAPTURE_DIR"

if [ "${CAPTURE_CLEAN:-0}" = "1" ]; then
    echo "[CAPTURE] Limpiando capturas previas en $CAPTURE_DIR"
    rm -f "$CAPTURE_DIR"/*.bin
    rm -f "$LOG_FILE"
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

draw_progress() {
    local current="$1"
    local target="$2"
    local rate="$3"
    local eta="$4"

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

    filled_bar="$(printf "%${filled}s" "" | tr ' ' '#')"
    empty_bar="$(printf "%${empty}s" "" | tr ' ' '-')"

    printf "\r[%-${BAR_WIDTH}s] %3d.%02d%%  %s/%s  rate=%s/s  eta=%s" \
        "${filled_bar}${empty_bar}" \
        "$percent_int" \
        "$percent_dec" \
        "$(human_bytes "$current")" \
        "$(human_bytes "$target")" \
        "$(human_bytes "$rate")" \
        "$(format_time "$eta")"
}

RUNNER_PID=""

cleanup_runner() {
    echo

    if [ -n "${TAIL_PID:-}" ] && kill -0 "$TAIL_PID" 2>/dev/null; then
        kill "$TAIL_PID" 2>/dev/null || true
    fi

    if [ -n "${RUNNER_PID:-}" ] && kill -0 "$RUNNER_PID" 2>/dev/null; then
        echo "[CAPTURE] Deteniendo entropy.sh..."

        kill -INT "-$RUNNER_PID" 2>/dev/null || kill -INT "$RUNNER_PID" 2>/dev/null || true
        sleep 3

        if kill -0 "$RUNNER_PID" 2>/dev/null; then
            kill -TERM "-$RUNNER_PID" 2>/dev/null || kill -TERM "$RUNNER_PID" 2>/dev/null || true
            sleep 2
        fi

        if kill -0 "$RUNNER_PID" 2>/dev/null; then
            kill -KILL "-$RUNNER_PID" 2>/dev/null || kill -KILL "$RUNNER_PID" 2>/dev/null || true
        fi
    fi

    if [ -x "$PROJECT_ROOT/scripts/zenoh_cleanup.sh" ]; then
        bash "$PROJECT_ROOT/scripts/zenoh_cleanup.sh" >/dev/null 2>&1 || true
    fi
}

trap cleanup_runner INT TERM

echo "============================================================"
echo " CAPTURA CONTROLADA DE ENTROPIA - QeeaS"
echo "============================================================"
echo "Experimento : $EXPERIMENT"
echo "Target      : $(human_bytes "$TARGET_BYTES") ($TARGET_BYTES bytes)"
echo "Directorio  : $CAPTURE_DIR"
echo "Watch file  : $WATCH_FILE"
echo "Log         : $LOG_FILE"
echo "============================================================"

export ENTROPY_EXPERIMENT="$EXPERIMENT"

echo "[CAPTURE] Lanzando main/entropy.sh..."

: > "$LOG_FILE"

tail -n +1 -f "$LOG_FILE" &
TAIL_PID="$!"

setsid bash "$PROJECT_ROOT/main/entropy.sh" > "$LOG_FILE" 2>&1 &
RUNNER_PID="$!"

echo "[CAPTURE] PID principal: $RUNNER_PID"
echo "[CAPTURE] Esperando a que empiece a crecer el archivo..."
echo

START_TS="$(date +%s)"
START_BYTES="$(file_size "$WATCH_FILE")"

while kill -0 "$RUNNER_PID" 2>/dev/null; do
    CURRENT_BYTES="$(file_size "$WATCH_FILE")"
    NOW_TS="$(date +%s)"
    ELAPSED=$((NOW_TS - START_TS))

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

    draw_progress "$CURRENT_BYTES" "$TARGET_BYTES" "$RATE" "$ETA"

    if [ "$CURRENT_BYTES" -ge "$TARGET_BYTES" ]; then
        echo
        echo "[CAPTURE] Target alcanzado."
        cleanup_runner
        break
    fi

    sleep "$POLL_INTERVAL"
done

wait "$RUNNER_PID" 2>/dev/null || true

echo
echo "============================================================"
echo "[CAPTURE] Captura finalizada"
echo "============================================================"
echo "Directorio: $CAPTURE_DIR"
echo

ls -lh "$CAPTURE_DIR" || true

echo
echo "[CAPTURE] Tamaños exactos:"
for file in "$CAPTURE_DIR"/*.bin; do
    if [ -f "$file" ]; then
        printf "  %-45s %12s bytes\n" "$(basename "$file")" "$(stat -c "%s" "$file")"
    fi
done

echo "============================================================"