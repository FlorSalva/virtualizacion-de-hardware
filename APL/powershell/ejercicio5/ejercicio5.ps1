#
# ================================== Encabezado ==============================
# Nombre del script: ejercicio5.ps1
# Numero de ejercicio: 5
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
Consultar a la API la información respecto de los paises indicados.

.DESCRIPTION
Permite obtener información basica de los paises indicados a travesde una consulta a una API publica.

.PARAMETER paises
Nombre de los paises a consultar separados por coma.

.PARAMETER ttl
Tiempo que se guardara la info de consulta en cache.

.EXAMPLE
.\ejercicio5.ps1 -paises Argentina -ttl 60
.\ejercicio5.ps1 -paises España,Colombia -ttl 120
#>

param(
    [Parameter(Mandatory = $true)]
    [string[]] $paises,

    [Parameter(Mandatory = $true)]
    [int] $ttl
)
$enc = New-Object System.Text.UTF8Encoding($true)
[Console]::OutputEncoding = $enc
$OutputEncoding = $enc

$archCache = "$PSScriptRoot\cache.json"

if (Test-Path $archCache) {
    try {
        $json = Get-Content $archCache -Raw | ConvertFrom-Json
        $cache = @{}
        foreach ($k in $json.PSObject.Properties.Name) {
            $cache[$k] = $json.$k
        }
    } catch {
        $cache = @{}
    }
} else {
    $cache = @{}
}

function Guardar-Cache {
    param([hashtable]$cacheData)
    $cacheData | ConvertTo-Json -Depth 5 | Out-File $archCache -Encoding UTF8
}

function Clean-Cache {
    param([hashtable]$cacheData, [int]$tiempottl)
    $ahora = Get-Date
    $clavesVencidas = @()
    foreach ($k in $cacheData.Keys) {
        $entry = $cacheData[$k]
        $timestamp = Get-Date $entry.timestamp
        $diferencia = ($ahora - $timestamp).TotalSeconds
        if ($diferencia -ge $tiempottl) {
            $clavesVencidas += $k
        }
    }
    foreach ($k in $clavesVencidas) {
        $cacheData.Remove($k)
    }
}

Clean-Cache -cacheData $cache -tiempottl $ttl

foreach ($pais in $paises) {
    $paisConsulta = $pais.ToLower()

    $usarCache = $false
    if ($cache.ContainsKey($paisConsulta)) {
        $entry = $cache[$paisConsulta]
        $timestamp = Get-Date $entry.timestamp
        $ahora = Get-Date
        $diferencia = ($ahora - $timestamp).TotalSeconds

        if ($diferencia -lt $ttl) {
            $usarCache = $true
        }
    }

    if ($usarCache) {
        $data = $cache[$paisConsulta].data
    } else {
        try {
            $url = "https://restcountries.com/v3.1/name/$pais"

            $response = Invoke-WebRequest -Uri $url -UseBasicParsing
            $stream = New-Object System.IO.StreamReader($response.RawContentStream, [System.Text.Encoding]::UTF8)
            $jsonText = $stream.ReadToEnd()
            $stream.Close()

            $infoArray = $jsonText | ConvertFrom-Json
            $info = $infoArray[0]

            $data = [PSCustomObject]@{
                País      = $info.name.common
                Capital   = ($info.capital -join ", ")
                Región    = $info.region
                Población = $info.population
                Moneda    = ($info.currencies.PSObject.Properties | ForEach-Object { "$($_.Value.name) ($($_.Name))" }) -join ", "
            }

            $cache[$paisConsulta] = @{
                timestamp = (Get-Date).ToString("o")
                data      = $data
            }

            Guardar-Cache -cacheData $cache
        } catch {
            Write-Host "Error al consultar la API para '$pais': $_"
            continue
        }
    }

    # Mostrar resultados en pantalla
    Write-Host "País: $($data.País)"
    Write-Host "Capital: $($data.Capital)"
    Write-Host "Región: $($data.Región)"
    Write-Host "Población: $($data.Población)"
    Write-Host "Moneda: $($data.Moneda)"
    Write-Host ""
}
