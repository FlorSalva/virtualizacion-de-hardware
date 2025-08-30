#!/bin/bash

mostrar_ayuda() {
    echo "Uso: $0 [OPCIONES]"
    echo ""
    echo "Opciones:"
    echo "  -h, --help          Muestra esta ayuda."
    echo "  -d, --directorio    Ruta del directorio con los archivos de encuestas."
    echo "  -a, --archivo       Ruta completa del archivo JSON de salida (excluyente con -p)."
    echo "  -p, --pantalla      Muestra la salida por pantalla (excluyente con -a)."
}

DIRECTORIO=""
SALIDA=""

FLAG_ARCHIVO=0
FLAG_PANTALLA=0
MODO=""

# Procesar parámetros
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            mostrar_ayuda
            exit 0
            ;;
        -d|--directorio)
            DIRECTORIO="$2"
            shift 2
            ;;
        -a|--archivo)
            FLAG_ARCHIVO=1
            SALIDA="$2"
            shift 2
            ;;
        -p|--pantalla)
            FLAG_PANTALLA=1
            shift
            ;;
        *)
            echo "Error: parámetro desconocido: $1"
            mostrar_ayuda
            exit 1
            ;;
    esac
done

# -----------------------------
# Validaciones de parámetros
# -----------------------------
if [[ -z "$DIRECTORIO" ]]; then
    echo "Error: debe especificar un directorio con -d"
    exit 1
fi

# No pueden estar los dos
if [[ $FLAG_ARCHIVO -eq 1 && $FLAG_PANTALLA -eq 1 ]]; then
    echo "Error: no puede usar -a y -p juntos."
    exit 1
fi

# Si se usa -a debe tener argumento válido
if [[ $FLAG_ARCHIVO -eq 1 ]]; then
    if [[ -z "$SALIDA" || "$SALIDA" == -* ]]; then
        echo "Error: debe especificar un archivo de salida después de -a"
        exit 1
    fi
    if [[ -d "$SALIDA" ]]; then
        echo "Error: '$SALIDA' es un directorio, debe ser un archivo JSON"
        exit 1
    fi
    MODO="archivo"
elif [[ $FLAG_PANTALLA -eq 1 ]]; then
    MODO="pantalla"
else
    echo "Error: debe especificar -a (archivo) o -p (pantalla)"
    exit 1
fi

# -----------------------------
# Procesamiento
# -----------------------------
declare -A tiempos
declare -A notas
declare -A conteos
declare -A dias

for file in "$DIRECTORIO"/*.txt; do
    while IFS="|" read -r id fecha canal tiempo nota; do
        [[ -z "$id" ]] && continue   # salta líneas vacías
        dia=$(echo "$fecha" | cut -d' ' -f1)
        key="${dia}_${canal}"

        tiempos[$key]=$(echo "${tiempos[$key]:-0} + $tiempo" | bc -l)
        notas[$key]=$(echo "${notas[$key]:-0} + $nota" | bc -l)
        conteos[$key]=$(( ${conteos[$key]:-0} + 1 ))
        dias["$dia"]=1
    done < "$file"
done

# Construir JSON
json="{"
for dia in "${!dias[@]}"; do
    json+="\"$dia\": {"
    for key in "${!conteos[@]}"; do
        d="${key%%_*}"
        canal="${key#*_}"
        if [[ "$d" == "$dia" ]]; then
            avg_tiempo=$(echo "scale=2; ${tiempos[$key]} / ${conteos[$key]}" | bc -l)
            avg_nota=$(echo "scale=2; ${notas[$key]} / ${conteos[$key]}" | bc -l)
            json+="\"$canal\": {\"tiempo_respuesta_promedio\": $avg_tiempo, \"nota_satisfaccion_promedio\": $avg_nota},"
        fi
    done
    json="${json%,}" # saca coma extra
    json+="},"
done
json="${json%,}}"  # cerrar último bloque

# Formato bonito si existe jq
if command -v jq >/dev/null; then
    json=$(echo "$json" | jq .)
fi

# -----------------------------
# Salida final
# -----------------------------
if [[ "$MODO" == "pantalla" ]]; then
    echo "$json"
else
    echo "$json" > "$SALIDA"
fi
