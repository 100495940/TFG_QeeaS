# Indicamos a ZEPHYR qué archivos compilar dentro
# de la carpeta main

# Versión mínima de CMake
cmake_minimum_required(VERSION 3.20.0)

set(ZENOH_ZEPHYR ON CACHE BOOL "" FORCE)
add_compile_definitions(ZENOH_ZEPHYR=1)

set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(PICO_STATIC ON CACHE BOOL "" FORCE)
set(PICO_SHARED OFF CACHE BOOL "" FORCE)

set(BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(PACKAGING OFF CACHE BOOL "" FORCE)

# Tamaños reducidos para microcontrolador
set(BATCH_UNICAST_SIZE 8192 CACHE STRING "" FORCE)
set(BATCH_MULTICAST_SIZE 8192 CACHE STRING "" FORCE)
set(FRAG_MAX_SIZE 16384 CACHE STRING "" FORCE)

# Logs internos de zenoh-pico
set(ZENOH_LOG "" CACHE STRING "" FORCE)

# Funcionalidades de zenoh-pico que vamos a usar
set(Z_FEATURE_PUBLICATION 1 CACHE STRING "" FORCE)
set(Z_FEATURE_SUBSCRIPTION 1 CACHE STRING "" FORCE)
set(Z_FEATURE_QUERY 0 CACHE STRING "" FORCE)
set(Z_FEATURE_QUERYABLE 0 CACHE STRING "" FORCE)

set(Z_FEATURE_MULTI_THREAD 1 CACHE STRING "" FORCE)

# Transporte usado: TCP cliente contra router/servidor
set(Z_FEATURE_LINK_TCP 1 CACHE STRING "" FORCE)
set(Z_FEATURE_LINK_UDP_UNICAST 0 CACHE STRING "" FORCE)
set(Z_FEATURE_LINK_UDP_MULTICAST 0 CACHE STRING "" FORCE)
set(Z_FEATURE_SCOUTING 0 CACHE STRING "" FORCE)

set(Z_FEATURE_UNICAST_TRANSPORT 1 CACHE STRING "" FORCE)
set(Z_FEATURE_MULTICAST_TRANSPORT 0 CACHE STRING "" FORCE)

# Desactivar lo que no se necesita al principio
set(Z_FEATURE_LINK_SERIAL 0 CACHE STRING "" FORCE)
set(Z_FEATURE_LINK_WS 0 CACHE STRING "" FORCE)
set(Z_FEATURE_LINK_TLS 0 CACHE STRING "" FORCE)

# Evitar posibles problemas con opciones de socket en Zephyr
set(Z_FEATURE_TCP_NODELAY 0 CACHE BOOL "" FORCE)

set(Z_FEATURE_INTEREST 0 CACHE BOOL "" FORCE)
set(Z_FEATURE_LIVELINESS 0 CACHE BOOL "" FORCE)
set(Z_FEATURE_MATCHING 0 CACHE BOOL "" FORCE)
set(Z_FEATURE_CONNECTIVITY 0 CACHE BOOL "" FORCE)
set(Z_FEATURE_ADMIN_SPACE 0 CACHE BOOL "" FORCE)

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

# Añadir zenoh-pico como una librería completa
add_subdirectory(
    lib/zenoh-pico
    ${CMAKE_CURRENT_BINARY_DIR}/zenoh-pico
)

# Parche: añadir SOLO fuentes de sistema compatibles con Zephyr

target_sources(zenohpico_static PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/lib/zenoh-pico/src/system/common/platform.c
    ${CMAKE_CURRENT_SOURCE_DIR}/lib/zenoh-pico/src/system/zephyr/system.c
    ${CMAKE_CURRENT_SOURCE_DIR}/lib/zenoh-pico/src/system/zephyr/network.c
)

target_compile_definitions(zenohpico_static PUBLIC ZENOH_ZEPHYR=1)

# Forzar dependencia
target_link_libraries(zenohpico_static PUBLIC zephyr_interface)

# Enlazar aplicación con zenoh-pico
target_link_libraries(app PRIVATE zenohpico_static)