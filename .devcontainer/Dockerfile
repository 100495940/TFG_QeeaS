# Usamos la imágen oficial de Zehpyr conn el SDK y Python
FROM zephyrprojectrtos/zephyr-build:latest

# Usuario root necesario para gestionar permisos de hardware (USB/serial)
USER root

# Actualizar herramientas
RUN apt-get update && apt-get install -y \
    ent \
    minicom \
    python3-pip \
    && rm -rff /var/lib/apt/lists/*

# Indicar directorio de trabajo donde se ejecuta el proyecto
WORKDIR /workspaces/tfg-queeas