# Usar imágen oficial de Zehpyr con SDK y Python
FROM zephyrprojectrtos/zephyr-build:latest

# Usuario root necesario para gestionar permisos de hardware USB/serial
USER root

# Instalar herramientas base + dependencias para Zenoh
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    ent \
    gnupg \
    iproute2 \
    libmbedtls-dev \
    minicom \
    netcat-openbsd \
    pkg-config \
    python3-pip \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Indicar directorio de trabajo donde se ejecuta el proyecto
WORKDIR /workspaces/TFG-QueeaS