#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Generador de certificados TLS para QeeaS / Zenoh
#
# Este script crea una CA local y un certificado de servidor
# para el router Zenoh. También genera las configuraciones
# necesarias para lanzar zenohd y el cliente Rust con TLS.
#
# Uso:
#   ZENOH_HOST_IP=192.168.1.XXX bash scripts/generate_tls_certs.sh
#
# Si cambias de IP, regenera los certificados:
#   FORCE_TLS_CERTS=1 ZENOH_HOST_IP=192.168.1.XXX bash scripts/generate_tls_certs.sh
# ============================================================

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CERTS_DIR="$PROJECT_ROOT/certs"
CA_DIR="$CERTS_DIR/ca"
ROUTER_DIR="$CERTS_DIR/router"
CONFIG_DIR="$PROJECT_ROOT/config/zenoh"

ZENOH_HOST_IP="${ZENOH_HOST_IP:-}"
ZENOH_TLS_PORT="${ZENOH_TLS_PORT:-7447}"
FORCE_TLS_CERTS="${FORCE_TLS_CERTS:-0}"

CA_KEY="$CA_DIR/ca.key"
CA_CERT="$CA_DIR/ca.crt"

ROUTER_KEY="$ROUTER_DIR/router.key"
ROUTER_CSR="$ROUTER_DIR/router.csr"
ROUTER_CERT="$ROUTER_DIR/router.crt"
ROUTER_CNF="$ROUTER_DIR/router.cnf"

ZENOH_ROUTER_CONFIG="$CONFIG_DIR/zenohd_tls.json5"
RUST_CLIENT_CONFIG="$CONFIG_DIR/rust_client_tls.json5"

if [ -z "$ZENOH_HOST_IP" ]; then
    echo "[ERROR] Debes indicar la IP del host donde corre zenohd."
    echo
    echo "Ejemplo:"
    echo "  ZENOH_HOST_IP=192.168.1.45 bash scripts/generate_tls_certs.sh"
    exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
    echo "[ERROR] openssl no está instalado."
    echo "Instálalo con:"
    echo "  apt-get update && apt-get install -y openssl"
    exit 1
fi

mkdir -p "$CA_DIR" "$ROUTER_DIR" "$CONFIG_DIR"

echo "============================================================"
echo " GENERADOR TLS - QeeaS / Zenoh"
echo "============================================================"
echo "Proyecto       : $PROJECT_ROOT"
echo "IP Zenoh       : $ZENOH_HOST_IP"
echo "Puerto TLS     : $ZENOH_TLS_PORT"
echo "Certificados   : $CERTS_DIR"
echo "Config Zenoh   : $CONFIG_DIR"
echo "Force          : $FORCE_TLS_CERTS"
echo "============================================================"

if [ "$FORCE_TLS_CERTS" = "1" ]; then
    echo "[TLS] FORCE_TLS_CERTS=1, eliminando certificados/config previos..."
    rm -f "$CA_KEY" "$CA_CERT" "$CA_DIR/ca.srl"
    rm -f "$ROUTER_KEY" "$ROUTER_CSR" "$ROUTER_CERT" "$ROUTER_CNF"
    rm -f "$ZENOH_ROUTER_CONFIG" "$RUST_CLIENT_CONFIG"
fi

# ------------------------------------------------------------
# 1. Crear CA local
# ------------------------------------------------------------

if [ ! -f "$CA_KEY" ] || [ ! -f "$CA_CERT" ]; then
    echo "[TLS] Creando CA local..."

    openssl genrsa -out "$CA_KEY" 4096

    openssl req -x509 \
        -new \
        -nodes \
        -key "$CA_KEY" \
        -sha256 \
        -days 3650 \
        -out "$CA_CERT" \
        -subj "/CN=QeeaS Local CA"

    chmod 600 "$CA_KEY"
    chmod 644 "$CA_CERT"

    echo "[TLS] CA creada:"
    echo "      $CA_CERT"
else
    echo "[TLS] CA ya existente, no se regenera:"
    echo "      $CA_CERT"
fi

# ------------------------------------------------------------
# 2. Crear certificado del router Zenoh
# ------------------------------------------------------------

if [ ! -f "$ROUTER_KEY" ] || [ ! -f "$ROUTER_CERT" ]; then
    echo "[TLS] Creando certificado del router Zenoh..."

    openssl genrsa -out "$ROUTER_KEY" 2048
    chmod 600 "$ROUTER_KEY"

    cat > "$ROUTER_CNF" <<EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = req_ext

[dn]
CN = qeeas-zenoh-router

[req_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
DNS.2 = qeeas-zenoh-router
IP.1 = 127.0.0.1
IP.2 = ${ZENOH_HOST_IP}
EOF

    openssl req \
        -new \
        -key "$ROUTER_KEY" \
        -out "$ROUTER_CSR" \
        -config "$ROUTER_CNF"

    openssl x509 \
        -req \
        -in "$ROUTER_CSR" \
        -CA "$CA_CERT" \
        -CAkey "$CA_KEY" \
        -CAcreateserial \
        -out "$ROUTER_CERT" \
        -days 3650 \
        -sha256 \
        -extensions req_ext \
        -extfile "$ROUTER_CNF"

    chmod 644 "$ROUTER_CERT"

    echo "[TLS] Certificado del router creado:"
    echo "      $ROUTER_CERT"
else
    echo "[TLS] Certificado del router ya existente, no se regenera:"
    echo "      $ROUTER_CERT"
fi

# ------------------------------------------------------------
# 3. Comprobar Subject Alternative Name
# ------------------------------------------------------------

echo
echo "[TLS] Comprobando SAN del certificado del router..."
openssl x509 -in "$ROUTER_CERT" -noout -text | grep -A2 "Subject Alternative Name" || {
    echo "[WARN] No se ha podido comprobar el Subject Alternative Name."
}

# ------------------------------------------------------------
# 4. Crear configuración de zenohd con TLS
# ------------------------------------------------------------

echo
echo "[TLS] Generando config de zenohd TLS..."

cat > "$ZENOH_ROUTER_CONFIG" <<EOF
{
  mode: "router",

  listen: {
    endpoints: [
      "tls/0.0.0.0:${ZENOH_TLS_PORT}"
    ]
  },

  transport: {
    link: {
      tls: {
        listen_private_key: "$ROUTER_KEY",
        listen_certificate: "$ROUTER_CERT"
      }
    }
  }
}
EOF

echo "[TLS] Config zenohd:"
echo "      $ZENOH_ROUTER_CONFIG"

# ------------------------------------------------------------
# 5. Crear configuración TLS del cliente Rust
# ------------------------------------------------------------

echo
echo "[TLS] Generando config TLS para cliente Rust..."

cat > "$RUST_CLIENT_CONFIG" <<EOF
{
  mode: "client",

  connect: {
    endpoints: [
      "tls/127.0.0.1:${ZENOH_TLS_PORT}"
    ]
  },

  transport: {
    link: {
      tls: {
        root_ca_certificate: "$CA_CERT"
      }
    }
  }
}
EOF

echo "[TLS] Config cliente Rust:"
echo "      $RUST_CLIENT_CONFIG"

# ------------------------------------------------------------
# 6. Resumen final
# ------------------------------------------------------------

echo
echo "============================================================"
echo "[OK] Certificados y configuraciones TLS generados"
echo "============================================================"
echo "CA publica:"
echo "  $CA_CERT"
echo
echo "Clave privada CA:"
echo "  $CA_KEY"
echo
echo "Certificado router:"
echo "  $ROUTER_CERT"
echo
echo "Clave privada router:"
echo "  $ROUTER_KEY"
echo
echo "Config zenohd:"
echo "  $ZENOH_ROUTER_CONFIG"
echo
echo "Config Rust:"
echo "  $RUST_CLIENT_CONFIG"
echo
echo "Para lanzar zenohd con TLS:"
echo "  zenohd --config $ZENOH_ROUTER_CONFIG"
echo
echo "Para lanzar Rust con TLS:"
echo "  ZENOH_CONFIG=$RUST_CLIENT_CONFIG cargo run --release"
echo "============================================================"