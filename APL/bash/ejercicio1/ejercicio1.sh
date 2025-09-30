#!/bin/bash
#
# ================================== Encabezado ==============================
# Nombre del script: ejercicio1.sh
# Numero de ejercicio: 1

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

# Función para mostrar ayuda
mostrar_ayuda() {
    echo "Uso: $0"
    echo ""
    echo "[OPCIONES]"
    echo "  -h, --help          Muestra esta ayuda."
    echo "  -d, --directorio    Ruta del directorio con los archivos de encuestas."
    echo "  -a, --archivo       Ruta completa del archivo JSON de salida (excluyente con -p)."
    echo "  -p, --pantalla      Muestra la salida por pantalla (excluyente con -a)."
}

# Validación de parámetros
DIRECTORIO=""
ARCHIVO_DE_SALIDA=""
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
        # Verifica si hay un argumento después de -d
            if [[ -z "$2" || "$2" == -* ]]; then
                echo "Error: se requiere la ruta del directorio después de $1" >&2
                exit 1
            fi
            DIRECTORIO="$2"
            shift 2
            ;;
        -a|--archivo)
        # Verifica si hay un argumento después de -a
            FLAG_ARCHIVO=1
            if [[ -z "$2" || "$2" == -* ]]; then
                echo "Error: se requiere la ruta del archivo JSON después de $1" >&2
                exit 1
            fi
            ARCHIVO_DE_SALIDA="$2"
            shift 2
            ;;
        -p|--pantalla)
            FLAG_PANTALLA=1
            shift
            ;;
        *)
            echo "Error: parámetro desconocido o argumento faltante: $1" >&2
            mostrar_ayuda
            exit 1
            ;;
    esac
done

# -----------------------------
# Validaciones de parámetros
# -----------------------------
if [[ -z "$DIRECTORIO" ]]; then
    echo "Error: debe especificar un directorio con -d" >&2
    exit 1
fi

if [[ ! -d "$DIRECTORIO" ]]; then
    echo "Error: El directorio '$DIRECTORIO' no existe o no es un directorio válido." >&2
    exit 1
fi

# Exclusión de -a y -p
if [[ $FLAG_ARCHIVO -eq 1 && $FLAG_PANTALLA -eq 1 ]]; then
    echo "Error: no puede usar -a y -p juntos." >&2
    exit 1
fi

# Debe especificar al menos -a o -p
if [[ $FLAG_ARCHIVO -eq 0 && $FLAG_PANTALLA -eq 0 ]]; then
    echo "Error: debe especificar -a (archivo) o -p (pantalla) para la salida." >&2
    exit 1
fi

if [[ $FLAG_ARCHIVO -eq 1 ]]; then
    MODO="archivo"
    # Validar que el directorio de salida exista
    if [[ ! -d "$ARCHIVO_DE_SALIDA" ]]; then
        echo "Error: El directorio de salida '$ARCHIVO_DE_SALIDA' no existe o no es un directorio válido." >&2
        exit 1
    fi
elif [[ $FLAG_PANTALLA -eq 1 ]]; then
    MODO="pantalla"
fi

# Buscar archivos de encuestas (*.txt) en el directorio.
# Con `nullglob` evitamos que el array contenga "*.txt" si no hay coincidencias.
shopt -s nullglob
archivos=("$DIRECTORIO"/*.txt)
shopt -u nullglob

# Validar que existan archivos.
if [[ ${#archivos[@]} -eq 0 ]]; then
    echo "Error: No se encontraron archivos (*.txt) en '$DIRECTORIO'." >&2
    exit 1
fi

# -----------------------------
# Procesamiento
# -----------------------------
declare -A tiempos     # Suma de tiempos de respuesta
declare -A notas       # Suma de notas de satisfacción
declare -A conteos     # Conteo de encuestas
declare -A dias        # Lista de días únicos

# Recorrer todos los archivos .txt en el directorio.
# Para ser más estricto, usaremos solo *.txt
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

# -----------------------------
# Construir JSON
# -----------------------------
json="{"
primera_fecha=1 # Bandera para saber si estamos en la primera fecha

# Ordenar los días cronológicamente (las fechas en formato YYYY-MM-DD se ordenan correctamente con sort)
dias_ordenados=($(printf '%s\n' "${!dias[@]}" | sort))

# Recorrer los días únicos ordenados
for dia in "${dias_ordenados[@]}"; do
    # 1. Agregar coma entre fechas (si no es la primera)
    if [[ $primera_fecha -eq 0 ]]; then
        json+=","
    fi
    # Inicio del bloque de fecha
    json+="\"$dia\": {"
    primera_fecha=0
    primera_canal=1 # Bandera para saber si es el primer canal para esta fecha

    # Recorrer todas las claves (dia_canal)
    for key in "${!conteos[@]}"; do
        d="${key%%_*}"
        canal="${key#*_}"

        if [[ "$d" == "$dia" ]]; then
            # Cálculo de promedios con 2 decimales
            avg_tiempo=$(echo "scale=2; ${tiempos[$key]} / ${conteos[$key]}" | bc -l)
            avg_nota=$(echo "scale=2; ${notas[$key]} / ${conteos[$key]}" | bc -l)

            # 2. Agregar coma entre canales (si no es el primero)
            if [[ $primera_canal -eq 0 ]]; then
                json+=","
            fi

            # Agregar el objeto del canal
            json+="\"$canal\": {\"tiempo_respuesta_promedio\": $avg_tiempo, \"nota_satisfaccion_promedio\": $avg_nota}"
            primera_canal=0
        fi
    done
    # Cierre del bloque de fecha
    json+="}"
done
# Cierre del bloque principal
json+="}"

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
    # Crear archivo con nombre fijo resultado.json en el directorio especificado
    # Normalizar la ruta para evitar dobles barras
    directorio_salida=$(echo "$ARCHIVO_DE_SALIDA" | sed 's|/$||')
    archivo_salida="$directorio_salida/resultado.json"
    echo "$json" > "$archivo_salida"
    echo "Análisis completado. Resultados guardados en: $archivo_salida"
fi

exit 0