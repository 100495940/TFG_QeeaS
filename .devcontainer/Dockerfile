# Usamr imágen oficial de Zehpyr con SDK y Python
FROM zephyrprojectrtos/zephyr-build:latest

# Usuario root necesario para gestionar permisos de hardware USB/serial
USER root

# Instalar herramientas base + dependencias para Zenoh
RUN apt-get update && apt-get install -y \
    ent \
    minicom \
    python3-pip \
    curl \
    gnupg \
    ca-certificates \
    iproute2 \
    netcat-openbsd \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Indicar directorio de trabajo donde se ejecuta el proyecto
WORKDIR /workspaces/TFG-QueeaS