#!/bin/bash
set -euo pipefail

# Usamos submódulo fijado para usar commit concreto del repositorio de qeaas-server
# Así podemos garantizar una versión reproducible y estable de la app, así como 
# una especia de backup en caso de que el repositorio original desaparezca o cambie.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

QEAAS_DIR="${QEAAS_DIR:-/qeeas_deps/qrng_server}"
QEAAS_API_URLS="${QEAAS_API_URLS:-http://host.docker.internal:6065 http://127.0.0.1:6065}"
#QEAAS_API_URL="${QEAAS_API_URL:-http://127.0.0.1:6065}"

QEAAS_COMPOSE_OVERRIDE="/tmp/qeaas-qrng-api.override.yaml"
cat > "$QEAAS_COMPOSE_OVERRIDE" <<'EOF'
services:
  qrng-api:
    network_mode: bridge
    ports:
      - "6065:6065"
EOF

echo "[QRNG] Preparando dependencia QEaaS..."
bash "$PROJECT_ROOT/scripts/bootstrap_qrng.sh"

echo "[QRNG] Levantando servidor cuántico de números desde $QEAAS_DIR"
echo "[QRNG] API de números cuánticos escuchando en una de las siguientes URLs:"
echo "[QRNG] $QEAAS_API_URLS"
echo ""

if ! command -v docker >/dev/null 2>&1; then
    echo "[QRNG][ERROR] Docker CLI no está instalado dentro del devcontainer."
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo "[QRNG][ERROR] Docker CLI existe, pero no puede hablar con Docker Desktop."
    echo "[QRNG][ERROR] Revisa la configuración docker-outside-of-docker del devcontainer."
    exit 1
fi

if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD=(docker compose)
elif docker-compose version >/dev/null 2&1; then
    COMPOSE_CMD=(docker-compose)
else
    echo "[QRNG][ERROR] No se encontró docker compose ni docker-compose."
    echo "[QRNG][ERROR] Por favor, instale Docker y Docker Compose para continuar."
    exit 1
fi

cd "$QEAAS_DIR"

echo "[QRNG] Ejecutando setup-and-clean.sh de QEaaS..."

if ! bash ./setup-and-clean.sh; then
    echo "[QRNG][WARN] setup-and-clean.sh terminó con error."
    echo "[QRNG][WARN] Continuo porque puede deberse a contenedores inexistentes durante la limpieza."
fi
# Ejecutamos lo que ejecutaría setup-and-clean.sh pero con nuestro control de
# fallos para poder capturar errores y mostrar logs en caso de fallo.
# Si ejecutamos el comando directamente, se puede cortar todo el script
# si borramos un contenedor que no existe todavía por ejemplo.



# Levantar los servicios en modo detached para no bloquear la terminal
echo "[QRNG] Levantando contenedores QEaaS..."
"${COMPOSE_CMD[@]}" up --build -d qrng-api nginx-proxy
#"${COMPOSE_CMD[@]}" \
#    -f docker-compose.yaml \
#    -f "$QEAAS_COMPOSE_OVERRIDE" \
#    up --build -d qrng-api

echo "[QRNG] Esperando a que la API HTTP responda..."

API_READY=false

for i in {1..60}; do
    for candidate_url in $QEAAS_API_URLS; do
        echo "[QRNG] Probando $candidate_url/random_number/1"

        if docker run --network host --rm curlimages/curl:8.9.1 \
        curl --connect-timeout 2 --max-time 10 -fsS \
        $candidate_url/random_number/1 >/dev/null 2>&1; then
            QEAAS_API_URL="$candidate_url"
            API_READY=true
            echo "[QRNG] API QEaaS lista en $QEAAS_API_URL"
            break 2
        fi

    done

    if [ "$API_READY" = "true" ]; then
        break
    fi

    echo "[QRNG] API todavía no lista. Intento $i/60..."
    sleep 2
done

if [ "$API_READY" != "true" ]; then
    echo "[QRNG][ERROR] La API QEaaS no respondió en ninguna URL:"
    echo "[QRNG][ERROR] $QEAAS_API_URLS"
    echo "[QRNG][ERROR] Estado de contenedores:"
    "${COMPOSE_CMD[@]}" ps || true

    echo "[QRNG][ERROR] Últimos logs:"
    "${COMPOSE_CMD[@]}" logs --tail=80 || true

    exit 1
fi

DOCKER_GATEWAY_IP="$(ip route | awk '/default/ { print $3 }')"
echo "[QRNG] Docker gateway IP: $DOCKER_GATEWAY_IP"
echo "http://$DOCKER_GATEWAY_IP:6065/" > /tmp/qeaas_api_url

echo "[QRNG] API QEaaS lista."
echo "[QRNG] Prueba de respuesta:"
curl -v --connect-timeout 2 --max-time 10 \
  "http://$DOCKER_GATEWAY_IP:6065/random_number/1" || true
echo ""

cd ..