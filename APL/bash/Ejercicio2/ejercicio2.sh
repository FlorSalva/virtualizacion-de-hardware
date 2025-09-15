#!/bin/bash
#
# ================================== Encabezado ==============================
# Nombre del script: ejercicio2.sh
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

# Función para mostrar ayuda
mostrar_ayuda() {
    echo "Uso: $0 -m <archivo_matriz> [-h | -c] [-s <separador>]"
    echo "  -m, --matriz      Archivo de matriz de adyacencia"
    echo "  -h, --hub         Analiza el hub de la red"
    echo "  -c, --camino      Calcula el camino más corto entre todas las estaciones"
    echo "  -s, --separador   Separador de columnas (por defecto: '|')"
    exit 1
}

# Validación de parámetros
MATRIZ=""
HUB=0
CAMINO=0
SEPARADOR="|"

# Procesar argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        -m|--matriz)
            MATRIZ="$2"
            shift 2
            ;;
        -h|--hub)
            HUB=1
            shift
            ;;
        -c|--camino)
            CAMINO=1
            shift
            ;;
        -s|--separador)
            SEPARADOR="$2"
            if [[ -z "$SEPARADOR" ]]; then
                echo "Debe indicar un separador válido."
                exit 1
            fi
            if [[ "$SEPARADOR" == "," || "$SEPARADOR" == "." ]]; then
                echo "El separador no puede ser coma ni punto porque se usan para decimales."
                exit 1
            fi
            shift 2
            ;;
        *)
            mostrar_ayuda
            ;;
    esac
done

if [[ -z "$MATRIZ" || ( $HUB -eq 1 && $CAMINO -eq 1 ) || ( $HUB -eq 0 && $CAMINO -eq 0 ) ]]; then
    mostrar_ayuda
fi

# Validar archivo
if [[ ! -f "$MATRIZ" ]]; then
    echo "Archivo de matriz no encontrado."
    exit 2
fi


# Leer matriz y validar cuadrada/simétrica/números
mapfile -t lineas < "$MATRIZ"

sep_encontrado=0
for linea in "${lineas[@]}"; do
    if [[ "$linea" == *"$SEPARADOR"* ]]; then
        sep_encontrado=1
        break
    fi
done
if [[ $sep_encontrado -eq 0 ]]; then
    echo "El separador '$SEPARADOR' no se encuentra en el archivo de entrada."
    exit 6
fi


N=${#lineas[@]}
declare -A matriz

for ((i=0; i<N; i++)); do
    IFS="$SEPARADOR" read -ra fila <<< "${lineas[i]}"
    if [[ ${#fila[@]} -ne $N ]]; then
        echo "La matriz no es cuadrada."
        exit 3
    fi
    for ((j=0; j<N; j++)); do
        valor="${fila[j]}"
        if ! [[ "$valor" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
            echo "Valor no numérico en la matriz."
            exit 4
        fi
        # Normalizar valor a punto decimal y quitar espacios
        valor_normalizado="${valor//,/\.}"
        valor_normalizado="${valor_normalizado// /}"
        matriz[$i,$j]="$valor_normalizado"
        # Validar simetría
        if [[ $i -gt $j ]]; then
            sim_val="${matriz[$j,$i]}"
            sim_val="${sim_val//,/\.}"
            sim_val="${sim_val// /}"
            if [[ "$sim_val" != "$valor_normalizado" ]]; then
                echo "La matriz no es simétrica. (Fila $((i+1)), Col $((j+1)))"
                exit 5
            fi
        fi
    done
done
                alt=$(echo "${dist[$u]} + $peso" | bc -l)
# Nombre del informe
dir="$(dirname "$MATRIZ")"
ruta_informe="$dir/informe_mapa_transporte.txt"

# Función para encontrar el hub
encontrar_hub() {
    max_conex=0
    hub_idx=0
    for ((i=0; i<N; i++)); do
        conexiones=0
        for ((j=0; j<N; j++)); do
            [[ $i -ne $j && "${matriz[$i,$j]}" != "0" ]] && ((conexiones++))
        done
        if ((conexiones > max_conex)); then
            max_conex=$conexiones
            hub_idx=$i
        fi
    done
    {
        echo "## Informe de análisis de red de transporte"
        echo "**Hub de la red:** Estación $((hub_idx+1)) ($max_conex conexiones)"
    } > "$ruta_informe"
    echo "Informe generado en: $ruta_informe"
}

# Algoritmo de Dijkstra para todos los pares
dijkstra() {
    declare -a dist
    declare -a prev
    declare -a visit

    start=0   # Estación 1 (índice 0)
    end=$((N-1))  # Última estación

    # Inicialización
    for ((i=0; i<N; i++)); do
        dist[$i]=999999
        prev[$i]=-1
        visit[$i]=0
    done
    dist[$start]=0

    for ((count=0; count<N; count++)); do
        min=999999
        u=-1
        for ((i=0; i<N; i++)); do
                awk_cmp="$(awk -v a="${dist[$i]}" -v b="$min" 'BEGIN {if (a < b) print 1; else print 0;}')"
                if [[ ${visit[$i]} -eq 0 && $awk_cmp -eq 1 ]]; then
                min=${dist[$i]}
                u=$i
            fi
        done
        [[ $u -eq -1 ]] && break
        visit[$u]=1
        for ((v=0; v<N; v++)); do
            peso="${matriz[$u,$v]}"
            if [[ $peso != "0" && ${visit[$v]} -eq 0 ]]; then
                alt=$(awk -v a="${dist[$u]}" -v b="$peso" 'BEGIN {printf "%.10g", a + b}')
                awk_cmp2="$(awk -v a="$alt" -v b="${dist[$v]}" 'BEGIN {if (a < b) print 1; else print 0;}')"
                if [[ $awk_cmp2 -eq 1 ]]; then
                    dist[$v]=$alt
                    prev[$v]=$u
                fi
            fi
        done
    done

    # Reconstruimos camino
    ruta=()
    u=$end
    while [[ $u -ne -1 ]]; do
        ruta=($((u+1)) "${ruta[@]}")
        u=${prev[$u]}
    done

    {
        echo "## Informe de análisis de red de transporte"
        echo "**Camino más corto: entre Estación 1 y Estación $((end+1)):**"
        echo "**Tiempo total:** ${dist[$end]} minutos"
        echo -n "**Ruta:** "
        IFS='->'; echo "${ruta[*]}"
    } > "$ruta_informe"
    echo "Informe generado en: $ruta_informe"
}

# Ejecución según parámetro
if [[ $HUB -eq 1 ]]; then
    encontrar_hub
elif [[ $CAMINO -eq 1 ]]; then
    dijkstra
fi