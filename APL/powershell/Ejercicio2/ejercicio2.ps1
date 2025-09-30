#
# ================================== Encabezado ==============================
# Nombre del script: ejercicio2.ps1
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

<#
.SYNOPSIS
Analiza rutas en una red de transporte publico a partir de una matriz de adyacencia.

.DESCRIPTION
Permite determinar el hub de la red o calcular el camino más corto entre la primera y la ultima estacion usando Dijkstra.
Valida que la matriz sea cuadrada, simétrica y numérica.

.PARAMETER matriz
Ruta del archivo de matriz de adyacencia.

.PARAMETER hub
Analiza el hub de la red.

.PARAMETER camino
Calcula el camino mas corto entre la primera y la ultima estacion.

.PARAMETER separador
Separador de columnas (por defecto: '|').

.EXAMPLE
.\ejercicio2.ps1 -matriz matriz.txt -hub
.\ejercicio2.ps1 -matriz matriz.txt -camino -separador ','

#>

[CmdletBinding(DefaultParameterSetName="Modo")]
param(
    [Parameter(Mandatory=$true, Position=0, HelpMessage="Archivo de matriz de adyacencia")]
    [Alias("m")]
    [string]$matriz,

    [Parameter(Mandatory=$false, ParameterSetName="Hub", HelpMessage="Analiza el hub de la red")]
    [switch]$hub,

    [Parameter(Mandatory=$false, ParameterSetName="Camino", HelpMessage="Calcula el camino más corto")]
    [switch]$camino,

    [Parameter(Mandatory=$false, HelpMessage="Separador de columnas (por defecto: '|')")]
    [Alias("s")]
    [string]$separador = '|'
)

    # Validar que el separador no sea coma ni punto
    if ($separador -eq ',' -or $separador -eq '.') {
        Write-Error "El separador no puede ser coma ni punto porque se usan para decimales."
        exit 7
    }

if (($hub -and $camino) -or (-not $hub -and -not $camino)) {
    Write-Error "Debe especificar solo uno de los modos: -hub o -camino."
    exit 1
}
if (-not (Test-Path $matriz)) {
    Write-Error "Archivo de matriz no encontrado."
    exit 2
}

# Leer archivo
$lines = Get-Content $matriz
$sepFound = $false
foreach ($line in $lines) {
    if ($line -like "*$separador*") {
        $sepFound = $true
        break
    }
}
if (-not $sepFound) {
    Write-Error "El separador '$separador' no se encuentra en el archivo de entrada."
    exit 6
}

$N = $lines.Count
$matrix = @{}
for ($i=0; $i -lt $N; $i++) {
    $row = $lines[$i] -split [regex]::Escape($separador)
    # Eliminar espacios en cada valor para evitar errores por separadores pegados
    $row = $row | ForEach-Object { $_.Trim() }
    if ($row.Count -ne $N) { Write-Error "La matriz no es cuadrada."; exit 3 }
    for ($j=0; $j -lt $N; $j++) {
        $val = $row[$j]
        if (-not ($val -match '^[0-9]+([\.,][0-9]+)?$')) { Write-Error "Valor no numérico en la matriz."; exit 4 }
        # Convertir a número (reemplazar coma por punto si es necesario)
        $numVal = [double]($val -replace ',', '.')
        $matrix["$i,$j"] = $numVal
        if ($i -gt $j) {
            $numValPrev = $matrix["$j,$i"]
            # Comparar como números, permitiendo tolerancia mínima para decimales
            if ([math]::Abs($numValPrev - $numVal) -gt 1e-9) { Write-Error "La matriz no es simétrica."; exit 5 }
        }
    }
}

#$informe = "informe_$([System.IO.Path]::GetFileName($matriz))"
$informe = "informe_mapa_transporte.txt"
$dir = Split-Path $matriz
$ruta_informe = Join-Path $dir $informe

function Encontrar-Hub {
    $maxConex = 0
    $hubIdx = 0
    for ($i=0; $i -lt $N; $i++) {
        $conex = 0
        for ($j=0; $j -lt $N; $j++) {
            if ($i -ne $j -and $matrix["$i,$j"] -ne "0") { $conex++ }
        }
        if ($conex -gt $maxConex) {
            $maxConex = $conex
            $hubIdx = $i
        }
    }
    @"
## Informe de análisis de red de transporte
**Hub de la red:** Estación $($hubIdx+1) ($maxConex conexiones)
"@ | Set-Content $ruta_informe
    Write-Host "Informe generado en: $ruta_informe"
}

function Dijkstra {
    $dist = @(0..($N-1) | ForEach-Object { [double]::MaxValue })
    $prev = @(0..($N-1) | ForEach-Object { -1 })
    $visit = @(0..($N-1) | ForEach-Object { $false })
    $start = 0
    $end = $N-1
    $dist[$start] = 0

    for ($count=0; $count -lt $N; $count++) {
        $min = [double]::MaxValue
        $u = -1
        for ($i=0; $i -lt $N; $i++) {
            if (-not $visit[$i] -and $dist[$i] -lt $min) {
                $min = $dist[$i]
                $u = $i
            }
        }
        if ($u -eq -1) { break }
        $visit[$u] = $true
        for ($v=0; $v -lt $N; $v++) {
            $peso = $matrix["$u,$v"]
            if ($peso -ne "0" -and -not $visit[$v]) {
                $alt = [double]$dist[$u] + [double]$peso
                if ($alt -lt $dist[$v]) {
                    $dist[$v] = $alt
                    $prev[$v] = $u
                }
            }
        }
    }

    # Reconstruir camino
    $ruta = @()
    $u = $end
    while ($u -ne -1) {
        $ruta = ,($u+1) + $ruta
        $u = $prev[$u]
    }
    $rutaStr = $ruta -join '->'
    @"
## Informe de análisis de red de transporte
**Camino más corto: entre Estación 1 y Estación $($end+1):**
**Tiempo total:** $($dist[$end]) minutos
**Ruta:** $rutaStr
"@ | Set-Content $ruta_informe
    Write-Host "Informe generado en: $ruta_informe"
}

if ($hub) { Encontrar-Hub }
elseif ($camino) { Dijkstra }