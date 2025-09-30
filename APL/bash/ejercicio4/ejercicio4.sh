#!/bin/bash
#
# ================================== Encabezado ==============================
# Nombre del script: ejercicio4.sh
# Numero de ejercicio: 4

# ============================================================================

# -------------------------- Integrantes del grupo ---------------------------
#
# Nombre/s	        |	Apellido/s	    |	DNI

# Karina	        | Familia Cruz		| 42.838.266 
# Luciano Dario     | Gomez		        | 41.572.055 
# Micaela Valeria	| Puca			    | 39.913.189
# Franco Damian		| Sabes			    | 38.168.884
# Florencia		    | Salvatierra		| 38.465.901 

# Variables Globales
LOG_FILE=""
REPO_PATH=""
CONFIG_FILE=""
KILL_FLAG=0
SLEEP_TIME=60 # Valor por defecto (60 segundos)
PID_FILE=""
# Ruta absoluta para el archivo de configuración para usarlo fuera del REPO_PATH
CONFIG_FILE_ABS="" 
REPO_NAME="" # Inicializada aquí para un uso seguro en todo el script
COMMITS_TO_PULL=0


# Muestra un error 
error_y_salir() {

echo "ERROR: $1" >&2
echo "Para ver la forma correcta de usar el comando, ejecute: $0 -h" >&2
# En caso de error, siempre limpiamos el PID_FILE si existe.
if [ -n "$PID_FILE" ] && [ -f "$PID_FILE" ] && [ "$(cat "$PID_FILE")" = "$$" ]; then
    rm -f "$PID_FILE" 2>/dev/null
fi
exit 1
}

# Limpieza: Asegura que el PID_FILE se borre siempre.
limpiar_temporales() {
# Solo limpia si el archivo existe y si el PID registrado es el de este proceso ($$)
if [ -f "$PID_FILE" ] && [ "$(cat "$PID_FILE")" = "$$" ]; then
     
     echo "Monitor de seguridad para $(basename "$REPO_PATH") detenido. Archivo de control eliminado."
     rm -f "$PID_FILE" 2>/dev/null
fi
}
# Configura el manejo de señales de terminación
trap limpiar_temporales EXIT TERM INT 

# Función para mostrar la ayuda
mostrar_ayuda() {
echo "Uso: $0 -r|--repo <ruta> -c|--configuracion <ruta> [-l|--log <ruta>] [-a|--alerta <segundos>] [-k|--kill]"
echo ""
echo "-r, --repo <ruta> Ruta del repositorio Git a monitorear."
echo "-c, --configuracion <ruta> Ruta del archivo de configuración con patrones."
echo "-l, --log <ruta> Ruta del archivo de logs para las alertas."
echo "-a, --alerta <segundos> Tiempo en segundos entre escaneos del repositorio (Ej: 10)."
echo "-k, --kill Flag para detener el demonio del repositorio especificado por -r."
echo "-h, --help Muestra esta ayuda."
exit 0
}

# Procesamiento de Argumentos 

while [ "$#" -gt 0 ]; do
    case "$1" in
         -r|--repo)
            REPO_PATH="$2"; shift 2 ;;
         -c|--configuracion)
         CONFIG_FILE="$2"; shift 2 ;;
         -l|--log)
             LOG_FILE="$2"; shift 2 ;;
         -a|--alerta)
             SLEEP_TIME="$2"; shift 2 ;;
         -k|--kill)
             KILL_FLAG=1; shift 1 ;;
         -h|--help)
             mostrar_ayuda ;;
         --) 
             shift; break ;;
        *)
            error_y_salir "Opción '$1' no reconocida o faltan argumentos. Use -h para ayuda." ;;
    esac
done

# Configuración y Validación Inicial
if [ -z "$REPO_PATH" ]; then error_y_salir "El parámetro -r/--repo (Ruta del repositorio) es obligatorio."; fi


REPO_PATH=$(realpath -s "$REPO_PATH" 2>/dev/null) 

# Comprobación de existencia y tipo de directorio Git
if [ ! -d "$REPO_PATH" ] || [ ! -d "$REPO_PATH/.git" ]; then 
    error_y_salir "La ruta '$REPO_PATH' no es un directorio Git válido."
fi


REPO_NAME=$(basename "$REPO_PATH")
# PID_FILE usa el nombre del repo para asegurar que solo haya un monitor por repo
PID_FILE="/tmp/audit_daemon_${REPO_NAME}.pid" 

# Validación del parámetro -a/--alerta (debe ser un número)
if ! [[ "$SLEEP_TIME" =~ ^[0-9]+$ ]] || [ "$SLEEP_TIME" -eq 0 ]; then 
    error_y_salir "El valor de -a/--alerta debe ser un número entero positivo (segundos)."
fi

# 1. Función de Detención (-k)
if [ "$KILL_FLAG" -eq 1 ]; then
    if [ ! -f "$PID_FILE" ]; then
        error_y_salir "No se encontró un monitor activo para el repositorio '$REPO_PATH'."
    fi
    TARGET_PID=$(cat "$PID_FILE")

# Si el proceso no existe, limpiamos y salimos, informando.
    if ! kill -0 "$TARGET_PID" 2>/dev/null; then 
        rm -f "$PID_FILE" 2>/dev/null
        error_y_salir "El monitor existía en el archivo de control, pero el proceso (PID $TARGET_PID) ya no está activo. Se limpió el archivo de control huérfano."
    fi

# Detener el proceso con SIGTERM para que el trap se ejecute y limpie
     kill "$TARGET_PID" 
# Esperar un poco para la limpieza y luego salir
     sleep 1
    echo "Monitor de seguridad (PID $TARGET_PID) para '$REPO_NAME' ha sido detenido."
    exit 0
fi

# 2. Validación para Inicio del Demonio
if [ -z "$CONFIG_FILE" ]; then error_y_salir "El parámetro -c/--configuracion es obligatorio para iniciar el demonio."; fi

CONFIG_FILE_ABS=$(realpath -s "$CONFIG_FILE")


if [ ! -f "$CONFIG_FILE_ABS" ]; then error_y_salir "El archivo de configuración '$CONFIG_FILE' no existe o la ruta es incorrecta."; fi

if [ -z "$LOG_FILE" ]; then error_y_salir "El parámetro -l/--log es obligatorio para iniciar el demonio."; fi

LOG_FILE=$(realpath -s "$LOG_FILE" 2>/dev/null || echo "$LOG_FILE")

# 3. Control de Unicidad
if [ -f "$PID_FILE" ]; then
     ACTIVE_PID=$(cat "$PID_FILE")
     if kill -0 "$ACTIVE_PID" 2>/dev/null; then
            error_y_salir "Ya existe un monitor activo (PID: $ACTIVE_PID) para el repositorio '$REPO_PATH'."
     else
        # Limpiar PID huérfano
         rm -f "$PID_FILE" 2>/dev/null
        echo "Advertencia: Archivo PID huérfano detectado y eliminado. Continuando con el inicio..." >&2
    fi
fi

# 4. Función de Escaneo 
escanear_cambios() {
      # Cambia al repositorio para ejecutar comandos git
    cd "$REPO_PATH" || { 
         
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: No se pudo acceder al repositorio: $REPO_PATH. Reintentando..." >> "$LOG_FILE"
        return 1
     }

     # 1. Obtener los cambios del remoto (sin salir de la rama actual)
     CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

     if ! git fetch origin > /dev/null 2>&1; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] ADVERTENCIA: No se pudo conectar al repositorio remoto (git fetch). Reintentando..." >> "$LOG_FILE"
         return 1
     fi

     # 2. Verificar si hay commits pendientes de descargar
     COMMITS_TO_PULL=$(git rev-list HEAD..origin/"$CURRENT_BRANCH" --count 2>/dev/null)
     

    # Condición para salir si no hay commits nuevos (Modificación para optimización)
     if [ "$COMMITS_TO_PULL" -eq 0 ]; then
        return 0 # No hay trabajo que hacer, el script espera el siguiente ciclo (sleep)
    fi

    # El código solo llega aquí si COMMITS_TO_PULL > 0
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Detectados $COMMITS_TO_PULL commits nuevos en 'origin/$CURRENT_BRANCH'. Escaneando..." >> "$LOG_FILE"

    # 3. Obtener la lista de archivos modificados/añadidos en estos commits
     MODIFIED_FILES=$(git diff --name-only HEAD origin/"$CURRENT_BRANCH")

    # 4. Escanear cada archivo modificado
     while IFS= read -r file; do

         # Usamos 'git show' para obtener el contenido del archivo en el commit remoto. 
        
        if CONTENT=$(git show origin/"$CURRENT_BRANCH":"$file" 2>/dev/null); then

            # 5. Escanear patrones en el contenido del commit remoto
            # La variable $file contiene la ruta del archivo modificado/añadido
            # La variable $CONTENT contiene el contenido de ese archivo en el commit remoto

            while IFS= read -r pattern; do
    
            # 1. Limpia el patrón de caracteres de formato (\r) y de espacios sobrantes
            
            pattern_limpio=$(echo "$pattern" | tr -d '\r' | xargs)

            # 2. Omitir la línea si está vacía después de la limpieza
            if [ -z "$pattern_limpio" ]; then continue; fi

            # 3. Lógica de Detección (Usando $pattern_limpio y el printf corregido)
            if [[ "$pattern_limpio" =~ ^regex: ]]; then
                REGEX_PATTERN="${pattern_limpio#regex:}"
        
            # Búsqueda Regex
          if printf '%s\n' "$CONTENT" | grep -q -i -E -- "$REGEX_PATTERN"; then
            echo "[$(date +'%Y-%m-%d %H:%M:%S')] ALERTA CRÍTICA: Patrón Regex '$REGEX_PATTERN' encontrado en el archivo remoto '$file'." >> "$LOG_FILE"
         fi
    else
        # Búsqueda de Palabra Clave Simple
        if printf '%s\n' "$CONTENT" | grep -q -i -F -- "$pattern_limpio"; then
            echo "[$(date +'%Y-%m-%d %H:%M:%S')] Alerta: Patrón '$pattern_limpio' encontrado en el archivo remoto '$file'." >> "$LOG_FILE"
        fi
    fi
done < "$CONFIG_FILE_ABS"
        fi
     done <<< "$MODIFIED_FILES"

     # 6. Actualizar el repositorio local (HEAD) para el siguiente ciclo.
     
    if ! git merge origin/"$CURRENT_BRANCH" --ff-only > /dev/null 2>&1; then
         
         git update-ref -d refs/remotes/origin/"$CURRENT_BRANCH" 2>/dev/null
         git reset --hard origin/"$CURRENT_BRANCH" > /dev/null 2>&1
        
       
        if [ $? -ne 0 ]; then
            echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR CRÍTICO: Fallo final al actualizar el repositorio. El bucle no se detuvo." >> "$LOG_FILE"
             exit 1
        fi
     fi

    
     echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: Repositorio actualizado con éxito. Escaneo detenido." >> "$LOG_FILE"

    return 0 

  
}


# --- 5. Inicio del Demonio en Segundo Plano ---
(PID=$$
    echo "$PID" > "$PID_FILE"
    
    # Bucle principal
    while true; do
        escanear_cambios
        
        # AÑADE ESTA LÍNEA CRÍTICA
        if [ $? -eq 0 ] && [ "$COMMITS_TO_PULL" -gt 0 ]; then
             # Si escanear_cambios tuvo éxito y había commits (>0) para escanear
             # esto significa que la detección terminó. Salir.
             break 
        fi
        
        sleep "$SLEEP_TIME"
    done

    # Asegura que el subshell termine si el bucle se detiene
    exit 0 
) 0< /dev/null 1> /dev/null 2> /dev/null & 

# Mensaje de confirmación en la terminal principal
echo "Demonio para el repositorio '$REPO_NAME' iniciado y corriendo en segundo plano."
echo "Para detenerlo: $0 -r \"$REPO_PATH\" -k"


