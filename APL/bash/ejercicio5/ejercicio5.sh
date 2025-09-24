#!/bin/bash
#
# ================================== Encabezado ==============================
# Nombre del script: ejercicio5.sh
# Numero de ejercicio: 2

# ============================================================================

# -------------------------- Integrantes del grupo ---------------------------
#
# Nombre/s	        |	Apellido/s	    |	DNI

# Karina	        | Familia Cruz		| 42.838.266 
# Luciano Dario     | Gomez		        | 41.572.055 
# Micaela Valeria	| Puca			    | 39.913.189
# Franco Damian		| Sabes			    | 38.168.884
# Florencia		    | Salvatierra		| 38.465.901 

#------------------------------------------------------------------------------

mostrar_ayuda() {
    echo "Uso: $0 -n <nombre_pais> -t <ttl>"
    echo
    echo "Opciones:"
    echo "  -n, --nombre     Nombre del país o países a buscar (separados por comas)"
    echo "  -t, --ttl        Tiempo en segundos que se guardarán los resultados en caché"
    echo "  -h, --help       Muestra esta ayuda"
    echo
    echo "Ejemplo:"
    echo "  $0 --nombre Chile,Argentina --ttl 60"
    exit 0
}

# Variables
NOMBRE=""
TTL=""
CACHE_DIR="./cache"

# Parsear argumentos
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -n|--nombre)
            NOMBRE="$2"
            shift 2
            ;;
        -t|--ttl)
            TTL="$2"
            shift 2
            ;;
        -h|--help)
            mostrar_ayuda
            ;;
        *)
            echo "Opción desconocida: $1"
            mostrar_ayuda
            ;;
    esac
done

# Validar parámetros obligatorios
if [[ -z "$NOMBRE" || -z "$TTL" ]]; then
    echo "Error: Los parámetros -n (nombre) y -t (ttl) son obligatorios."
    echo
    mostrar_ayuda
fi

# Crear directorio de caché si no existe
mkdir -p "$CACHE_DIR"

IFS=',' read -ra PAISES <<< "$NOMBRE"
for PAIS in "${PAISES[@]}"; do
    PAIS_TRIM=$(echo "$PAIS" | xargs)  # Quitar espacios
    CACHE_FILE="$CACHE_DIR/${PAIS_TRIM// /_}.cache"

    if [[ -f "$CACHE_FILE" ]]; then
        TTL_CACHE=$(grep "^# TTL:" "$CACHE_FILE" | cut -d':' -f2 | xargs)
        TIMESTAMP_CACHE=$(grep "^# TIMESTAMP:" "$CACHE_FILE" | cut -d':' -f2 | xargs)
        CURRENT_TIME=$(date +%s)

        if [[ -n "$TTL_CACHE" && -n "$TIMESTAMP_CACHE" && $((CURRENT_TIME)) -lt $((TIMESTAMP_CACHE + TTL_CACHE)) ]]; then
            # Mostrar solo líneas que no sean encabezado
            grep -v "^# " "$CACHE_FILE"
            echo
            continue
        fi
    fi

    RESPONSE=$(curl -s "https://restcountries.com/v3.1/name/${PAIS_TRIM}")

    if echo "$RESPONSE" | grep -q "\"name\""; then
        NAME=$(echo "$RESPONSE" | grep -oP '"common":\s*"\K[^"]+' | head -1)
        CAPITAL=$(echo "$RESPONSE" | grep -oP '"capital":\s*\[\s*"\K[^"]+' | head -1)
        REGION=$(echo "$RESPONSE" | grep -oP '"region":\s*"\K[^"]+' | head -1)
        POPULATION=$(echo "$RESPONSE" | grep -oP '"population":\s*\K[0-9]+' | head -1)
        CURRENCY_NAME=$(echo "$RESPONSE" | grep -oP '"name":\s*"\K[^"]+' | head -1)
        CURRENCY_CODE=$(echo "$RESPONSE" | grep -oP '"currencies":\s*{[^}]*' | grep -oP '"\K[A-Z]{3}(?=":)')

        OUTPUT="País: $NAME
Capital: ${CAPITAL:-N/A}
Región: ${REGION:-N/A}
Población: ${POPULATION:-N/A}
Moneda: ${CURRENCY_NAME:-N/A} (${CURRENCY_CODE:-N/A})"

        echo "$OUTPUT"

        # Guardar en caché con encabezado TTL y timestamp
        {
            echo "# TTL: $TTL"
            echo "# TIMESTAMP: $(date +%s)"
            echo "$OUTPUT"
        } > "$CACHE_FILE"
    else
        echo "No se encontró información para '$PAIS_TRIM'."
        {
            echo "# TTL: $TTL"
            echo "# TIMESTAMP: $(date +%s)"
            echo "No se encontró información para '$PAIS_TRIM'."
        } > "$CACHE_FILE"
    fi

    echo
done
