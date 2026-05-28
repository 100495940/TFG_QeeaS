# Indicamos a ZEPHYR qué archivos compilar dentro
# de la carpeta main

# Versión mínima de CMake
cmake_minimum_required(VERSION 3.20.0)

# Buscar el sistema operativo ZEPHYR en las carpetas de Docker
find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})

# Nombrar proyecto
project(tfg_entropy)

# Enlazar archivos a compilar con la app
target_sources(app PRIVATE main/main.c main/entropy.c)