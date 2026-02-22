# Indicamos a ESP-IDF qué archivos compilar dentro
# de la carpeta main

# Registrar archivo main.c como el código fuente principal
idf_component_register(SRCS "main.c" "entropy.c"
                INCLUDE_DIRS ".")