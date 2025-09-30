#
# ================================== Encabezado ==============================
# Nombre del script: ejercicio1.ps1
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

<#
.SYNOPSIS
Analiza encuestas de satisfacción para calcular promedios por día y canal.

.DESCRIPTION
Procesa archivos de encuestas (.txt) delimitados por '|' en un directorio,
calculando el tiempo de respuesta promedio y la nota de satisfacción promedio
por canal de atención y por día. Los resultados se presentan ordenados 
cronológicamente por fecha en formato JSON.

.PARAMETER directorio
Ruta del directorio con los archivos de encuestas a procesar.

.PARAMETER Archivo
Ruta del directorio donde se guardará el archivo resultado.json. (Excluyente con -Pantalla)

.PARAMETER Pantalla
Muestra la salida JSON por pantalla. (Excluyente con -Archivo)

.EXAMPLE
.\ejercicio1.ps1 -directorio ./ -pantalla
Muestra los resultados en pantalla ordenados cronológicamente por día.

.EXAMPLE
.\ejercicio1.ps1 -Directorio .\ -Archivo .\
Guarda los resultados en .\resultado.json ordenados cronológicamente.

.NOTES
Formato de salida JSON:
{
    "YYYY-MM-DD": {
        "CANAL": {
            "tiempo_respuesta_promedio": decimal,
            "nota_satisfaccion_promedio": decimal
        }
    }
}

Los días se ordenan cronológicamente de menor a mayor fecha.

#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Directorio,

    [Parameter(ParameterSetName='SalidaArchivo', Mandatory=$true)]
    [string]$Archivo,

    [Parameter(ParameterSetName='SalidaPantalla', Mandatory=$true)]
    [switch]$Pantalla
)

# -----------------------------
# 1. Validación del Entorno
# -----------------------------


# Validar que el directorio exista y sea accesible
if (-not (Test-Path -Path $Directorio -PathType Container)) {
    Write-Error "Error: El directorio '$Directorio' no existe o no es un directorio válido."
    exit 1
}

# Obtener la lista de archivos, la variable $archivos será $null si no hay coincidencias.
# -ErrorAction SilentlyContinue evita errores si no hay archivos.
$archivos = Get-ChildItem -Path $Directorio -Filter "*.txt" -ErrorAction SilentlyContinue

if (-not $archivos) {
    Write-Error "Error: No se encontraron archivos de encuestas (*.txt) en el directorio '$Directorio'."
    exit 1
}

# -----------------------------
# 2. Procesamiento de Datos
# -----------------------------

# Estructura de datos para almacenar los resultados:
# $resultadosPorDia será un HashTable, clave: "DÍA", valor: otro HashTable (canales)
$resultadosPorDia = @{}

$archivos = Get-ChildItem -Path $Directorio -Filter *.txt
# Recorrer cada archivo encontrado
foreach ($archivoActual in $archivos) {
    # Importar el contenido del archivo, especificando el delimitador '|'
    $registros = Import-Csv -Path $archivoActual -Delimiter '|' -Header "ID_ENCUESTA","FECHA_HORA","CANAL","TIEMPO_RESPUESTA","NOTA_SATISFACCION"

    # Procesar cada registro
    foreach ($registro in $registros) {
        # Extraer el día de la FECHA_HORA (yyyy-mm-dd hh:mm:ss)
        $dia = $registro.FECHA_HORA.Split(' ')[0]
        $canal = $registro.CANAL

        # Crear una clave única: Día_Canal
        $key = "${dia}_${canal}"

        # Inicializar el contador si es la primera vez que vemos esta clave
        if (-not $resultadosPorDia.ContainsKey($dia)) {
            $resultadosPorDia.$dia = @{}
        }
        if (-not $resultadosPorDia.$dia.ContainsKey($canal)) {
            $resultadosPorDia.$dia.$canal = @{
                SumaTiempo    = 0.0
                SumaNota      = 0.0
                Conteo        = 0
            }
        }

        # Acumular sumas y conteos
        # Usamos [double]::Parse() para asegurar el manejo de decimales (TIEMPO_RESPUESTA)
        # Usamos [int]::Parse() para NOTA_SATISFACCION (asumiendo que es entero, aunque las operaciones se harán con decimales)
        try {
            $tiempo = [double]::Parse($registro.TIEMPO_RESPUESTA)
            $nota = [int]::Parse($registro.NOTA_SATISFACCION)
            
            $resultadosPorDia.$dia.$canal.SumaTiempo += $tiempo
            $resultadosPorDia.$dia.$canal.SumaNota += $nota
            $resultadosPorDia.$dia.$canal.Conteo++
        } catch {
            Write-Warning "Registro inválido omitido: [$key] - $($_.Exception.Message)"
        }
    }
}


# -----------------------------
# 3. Cálculo de Promedios y Estructura JSON
# -----------------------------

# Crear el objeto final que se convertirá a JSON usando OrderedDictionary para preservar el orden
$objetoFinal = [ordered]@{}

# Ordenar los días cronológicamente (las fechas en formato YYYY-MM-DD se ordenan correctamente con Sort-Object)
$diasOrdenados = $resultadosPorDia.Keys | Sort-Object

foreach ($dia in $diasOrdenados) {
    $canalesDelDia = [ordered]@{}

    foreach ($canal in $resultadosPorDia.$dia.Keys) {
        $datos = $resultadosPorDia.$dia.$canal
        
        # Calcular promedios (usando [Math]::Round para 2 decimales)
        $avgTiempo = [Math]::Round($datos.SumaTiempo / $datos.Conteo, 2)
        $avgNota = [Math]::Round($datos.SumaNota / $datos.Conteo, 2)

        # Crear el objeto de salida para el canal
        $objetoCanal = [ordered]@{
            tiempo_respuesta_promedio = $avgTiempo
            nota_satisfaccion_promedio = $avgNota
        }
        
        $canalesDelDia.$canal = $objetoCanal
    }
    
    # Agregar el objeto de canales al objeto final del día
    $objetoFinal.$dia = $canalesDelDia
}

# -----------------------------
# 4. Salida Final
# -----------------------------

# Convertir la estructura de datos a JSON
# -Depth 100 asegura que se procesen todos los niveles de los HashTables anidados.
# -Compress evita la indentación (como tu salida sin jq), pero la quitaremos para la salida amigable.
$jsonSalida = $objetoFinal | ConvertTo-Json -Depth 100

if ($Pantalla) {
    # Muestra el JSON formateado en la consola
    Write-Output $jsonSalida
} else {
    # Verificar que sea un directorio válido (igual que se hace con -Directorio)
    if (Test-Path -Path $Archivo -PathType Container) {
        # Crear archivo con nombre fijo resultado.json
        $nombreArchivo = "resultado.json"
        $rutaCompleta = Join-Path $Archivo $nombreArchivo
        
        $jsonSalida | Out-File -FilePath $rutaCompleta -Encoding UTF8
        Write-Host "Análisis completado. Resultados guardados en: $rutaCompleta"
    } else {
        Write-Error "Error: El parámetro -Archivo debe ser un directorio válido o usar -Pantalla para mostrar en consola."
        exit 1
    }
}