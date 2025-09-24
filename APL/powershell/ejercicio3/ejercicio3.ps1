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

<#
.SYNOPSIS
Script para contar ocurrencias de eventos específicos en archivos de log.

.DESCRIPTION
Este script busca y cuenta ocurrencias de palabras clave específicas en archivos .log,
incluyendo subdirectorios. La búsqueda es case-insensitive y considera palabras completas.

.PARAMETER directorio
El directorio donde se encuentran los archivos .log (obligatorio)

.PARAMETER palabras
Array de palabras clave a buscar (obligatorio)

.EXAMPLE
PS> .\ejercicio3.ps1 -directorio C:\logs -palabras USB,Invalid,Error
Busca las palabras USB, Invalid y Error en todos los archivos .log en C:\logs

.EXAMPLE
PS> .\ejercicio3.ps1 -directorio . -palabras "USB","Invalid","Error"
Busca las palabras en el directorio actual usando un array de strings
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true,
              Position=0,
              HelpMessage="Directorio donde se encuentran los archivos .log")]
    [string]$directorio,
    
    [Parameter(Mandatory=$true,
              Position=1,
              HelpMessage="Array de palabras clave a buscar")]
    [string[]]$palabras
)

# Validar parámetros obligatorios
if (-not $directorio) {
    Write-Host "Error: El parámetro -directorio es obligatorio."
    exit 1
}

if (-not $palabras) {
    Write-Host "Error: El parámetro -palabras es obligatorio."
    exit 1
}

# Validar que el directorio existe
if (-not (Test-Path -Path $directorio -PathType Container)) {
    Write-Host "Error: El directorio '$directorio' no existe o no es accesible."
    exit 1
}

# Validar que el array de palabras no está vacío
if (-not $palabras -or $palabras.Count -eq 0) {
    Write-Host "Error: Debe especificar al menos una palabra clave."
    exit 1
}

# Usar directamente el array de palabras
$PalabrasBuscar = $palabras

$Conteos = @{}
foreach ($palabra in $PalabrasBuscar) {
    $Conteos[$palabra] = 0
}

# Buscar en todos los archivos .log, incluyendo subdirectorios
Get-ChildItem -Path $directorio -Filter "*.log" -Recurse | ForEach-Object {
    $contenido = Get-Content $_.FullName
    foreach ($palabra in $PalabrasBuscar) {
        # Contar ocurrencias (case-insensitive)
        $conteo = ($contenido | Select-String -Pattern "\b$palabra\b" -AllMatches -CaseSensitive:$false).Matches.Count
        $Conteos[$palabra] += $conteo
    }
}

# Determinar el ancho máximo para la columna de palabras
$maxPalabraLength = ($PalabrasBuscar | Measure-Object -Maximum -Property Length).Maximum
$maxPalabraLength = [Math]::Max($maxPalabraLength, "PALABRA".Length)

# Determinar el ancho máximo para la columna de ocurrencias
$maxOcurrenciasLength = ($Conteos.Values | Measure-Object -Maximum).Maximum.ToString().Length
$maxOcurrenciasLength = [Math]::Max($maxOcurrenciasLength, "OCURRENCIAS".Length)

# Crear la línea separadora
$separador = "+-" + ("-" * $maxPalabraLength) + "-+-" + ("-" * $maxOcurrenciasLength) + "-+"

# Imprimir la tabla
Write-Host $separador
$formatString = "| {0,-$maxPalabraLength} | {1,$maxOcurrenciasLength} |"
Write-Host ($formatString -f "PALABRA", "OCURRENCIAS")
Write-Host $separador

foreach ($palabra in $PalabrasBuscar) {
    Write-Host ($formatString -f $palabra, $Conteos[$palabra])
}
Write-Host $separador