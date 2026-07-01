# Indicamos a ZEPHYR qué archivos compilar dentro
# de la carpeta main

# Versión mínima de CMake
cmake_minimum_required(VERSION 3.20.0)

# Buscar el sistema operativo ZEPHYR en las carpetas de Docker
find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})

# Nombrar proyecto
project(tfg_entropy)

# Enlazar archivos a compilar con la app
target_sources(app PRIVATE 
    main/main.c 
    main/entropy.c
    main/wifi.c
    main/zenoh_client.c
)

# Configuración de zenoh-pico

# Añadir carpeta include globalmente para todo el proyecto
zephyr_include_directories(lib/zenoh-pico/include)

# Declarar cuál es nuestro sistema operativo a zenoh forzando caché global
set(ZP_PLATFORM zephyr CACHE STRING "Forzar la plataforma Zehpyr para Zenoh" FORCE)

# Recompilar el código fuente de la librería con CMake
add_subdirectory(lib/zenoh-pico)

# Inyectar cabeceras del sistema Zephyr dentro de Zenoh
target_link_libraries(zenohpico PRIVATE zephyr-interface)

# Enlazar el motor de red con mi app
target_link_libraries(app PRIVATE zenohpico)