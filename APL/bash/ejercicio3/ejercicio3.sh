#!/bin/bash
#
# ================================== Encabezado ==============================
# Nombre del script: ejercicio3.sh
# Numero de ejercicio: 3

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
    echo "Uso: $0 [OPCIONES]"
    echo "Script para contar ocurrencias de eventos específicos en archivos de log."
    echo
    echo "Opciones:"
    echo "  -d, --directorio    Directorio donde se encuentran los archivos .log (obligatorio)"
    echo "  -p, --palabras      Lista de palabras clave a buscar, separadas por comas (obligatorio)"
    echo "  -h, --help          Muestra esta ayuda"
    echo
    echo "Ejemplo:"
    echo "  $0 -d /var/log -p \"USB,Invalid,Error\""
}

validar_directorio() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        echo "Error: El directorio '$dir' no existe o no es accesible."
        exit 1
    fi
}

validar_palabras() {
    local palabras="$1"
    if [[ -z "$palabras" || "$palabras" =~ ^[,[:space:]]*$ ]]; then
        echo "Error: La lista de palabras clave no puede estar vacía."
        exit 1
    fi
}

DIRECTORIO=""
PALABRAS=""

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
        -p|--palabras)
            PALABRAS="$2"
            shift 2
            ;;
        *)
            echo "Error: Parámetro desconocido: $1"
            mostrar_ayuda
            exit 1
            ;;
    esac
done

if [[ -z "$DIRECTORIO" || -z "$PALABRAS" ]]; then
    echo "Error: Los parámetros -d y -p son obligatorios."
    mostrar_ayuda
    exit 1
fi

validar_directorio "$DIRECTORIO"
validar_palabras "$PALABRAS"


find "$DIRECTORIO" -type f -name "*.log" -print0 | xargs -0 awk -v palabras="$PALABRAS" '
BEGIN {
    # Separar las palabras por comas y procesar cada una
    n = split(palabras, words, ",")
    for (i = 1; i <= n; i++) {
        # Eliminar espacios al inicio y final
        gsub(/^[ \t]+|[ \t]+$/, "", words[i])
        count[words[i]] = 0
    }
    IGNORECASE = 1  # Hacer la búsqueda case-insensitive
}
{
    # Para cada línea del archivo
    linea = $0
    for (i = 1; i <= n; i++) {
        palabra = words[i]
        # Buscar la palabra con límites de palabra
        pos = 1
        while (match(substr(linea, pos), "\\<" palabra "\\>")) {
            count[palabra]++
            pos += RSTART + RLENGTH - 1
        }
    }
}
END {
    # Imprimir la tabla de resultados
    print "+-----------------+------------+"
    printf "| %-15s | %-10s |\n", "PALABRA", "OCURRENCIAS"
    print "+-----------------+------------+"
    for (i = 1; i <= n; i++) {
        palabra = words[i]
        if (palabra != "") {
            printf "| %-15s | %10d |\n", palabra, count[palabra]
        }
    }
    print "+-----------------+------------+"
}'