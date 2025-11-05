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
Consultar a la API la información respecto de los países indicados.

.DESCRIPTION
Permite obtener información básica de los países indicados a través de una consulta a una API pública.

.PARAMETER nombre
Nombre de los países a consultar separados por coma.

.PARAMETER ttl
Tiempo que se guardará la info de consulta en caché (solo se aplica cuando se genera una nueva caché).

.EXAMPLE
.\ejercicio5.ps1 -nombre Argentina -ttl 60
.\ejercicio5.ps1 -nombre España,Colombia -ttl 120
#>

param(
    [Parameter(Mandatory = $true)]
    [string[]] $nombre,

    [Parameter(Mandatory = $true)]
    [int] $ttl
)

# Configuración de codificación
$enc = New-Object System.Text.UTF8Encoding($true)
[Console]::OutputEncoding = $enc
$OutputEncoding = $enc

$archCache = "$PSScriptRoot\cache.json"

# Cargar cache si existe
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

# Función para guardar cache
function Guardar-Cache {
    param([hashtable]$cacheData)
    $cacheData | ConvertTo-Json -Depth 5 | Out-File $archCache -Encoding UTF8
}

# Limpiar entradas vencidas
function Clean-Cache {
    param([hashtable]$cacheData)
    $ahora = Get-Date
    $clavesVencidas = @()

    foreach ($k in $cacheData.Keys) {
        $entry = $cacheData[$k]
        $timestamp = Get-Date $entry.timestamp
        $ttlGuardado = [int]$entry.ttl  # Cada entrada tiene su propio TTL
        $diferencia = ($ahora - $timestamp).TotalSeconds
        if ($diferencia -ge $ttlGuardado) {
            $clavesVencidas += $k
        }
    }

    foreach ($k in $clavesVencidas) {
        $cacheData.Remove($k)
    }
}

# Limpiar cache vencida según su propio TTL
Clean-Cache -cacheData $cache

# Procesar cada país
foreach ($pais in $nombre) {
    $paisConsulta = $pais.ToLower()

    $usarCache = $false
    if ($cache.ContainsKey($paisConsulta)) {
        $entry = $cache[$paisConsulta]
        $timestamp = Get-Date $entry.timestamp
        $ttlGuardado = [int]$entry.ttl
        $ahora = Get-Date
        $diferencia = ($ahora - $timestamp).TotalSeconds

        if ($diferencia -lt $ttlGuardado) {
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

            # Guardar en cache con timestamp actual y el TTL nuevo
            $cache[$paisConsulta] = @{
                timestamp = (Get-Date).ToString("o")
                ttl       = $ttl
                data      = $data
            }

            Guardar-Cache -cacheData $cache
        } catch {
            Write-Host "Error al consultar la API para '$pais': $_"
            continue
        }
    }

    # Mostrar resultados
    Write-Host "País: $($data.País)"
    Write-Host "Capital: $($data.Capital)"
    Write-Host "Región: $($data.Región)"
    Write-Host "Población: $($data.Población)"
    Write-Host "Moneda: $($data.Moneda)"
    Write-Host ""
}
