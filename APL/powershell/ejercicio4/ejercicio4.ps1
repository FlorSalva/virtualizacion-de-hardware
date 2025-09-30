#
# ================================== Encabezado ==============================
# Nombre del script: ejercicio4.ps1
# Numero de ejercicio: 4
#
# -------------------------- Integrantes del grupo ---------------------------
#
# Nombre/s      |  Apellido/s      |  DNI
#
# Karina        | Familia Cruz     | 42.838.266 
# Luciano Dario | Gomez            | 41.572.055 
# Micaela Valeria | Puca           | 39.913.189
# Franco Damian | Sabes            | 38.168.884
# Florencia     | Salvatierra      | 38.465.901 
#------------------------------------------------------------------------------

<#
.SYNOPSIS
 Monitorea un repositorio Git para detectar credenciales sensibles.
.DESCRIPTION
 Este script se ejecuta como un demonio, escaneando los cambios en la rama principal
 de un repositorio Git en busca de patrones definidos en un archivo de configuracion.
 Si encuentra coincidencias, registra una alerta y detiene la ejecucion. Puede iniciarse o detenerse.
.PARAMETER repo
 Ruta absoluta o relativa al directorio del repositorio Git a auditar. (Obligatorio).
.PARAMETER configuracion
 Ruta al archivo de configuracion que contiene los patrones (palabras clave o regex) a buscar. (Obligatorio al iniciar).
.PARAMETER alerta
 Tiempo en segundos entre escaneos del repositorio.
.PARAMETER detener
 Flag booleano. Si se establece ($true), detiene el proceso demonio activo para el repositorio especificado.
.EXAMPLE
 .\ejercicio4.ps1 -repo "mi_repo_final_ps" -configuracion "patrones.conf" -alerta 5
 Inicia el monitoreo del repositorio.
.EXAMPLE
 .\ejercicio4.ps1 -repo "mi_repo_final_ps" -detener
 Detiene el monitoreo del repositorio.
#>


[CmdletBinding(DefaultParameterSetName='Run')]
param(
    [Parameter(Mandatory=$true, ParameterSetName='Run')]
    [Parameter(Mandatory=$true, ParameterSetName='Kill')]
    [ValidateScript({Test-Path $_ -PathType Container})]
    [string]$repo,

    [Parameter(Mandatory=$false, ParameterSetName='Run')] 
    [ValidateScript({Test-Path $_ -PathType Leaf})]
    [string]$configuracion,

    [Parameter(Mandatory=$false, ParameterSetName='Run')]
    [int]$alerta = 60,
    
    [Parameter(Mandatory=$false, ParameterSetName='Kill')]
    [switch]$detener
)

# Variables Globales
# Usamos el nombre del repositorio para crear un ID unico

# La ruta absoluta se construye correctamente usando $PSScriptRoot para mayor portabilidad.
$RepoPathAbs = Join-Path -Path $PSScriptRoot -ChildPath $repo 

$RepoName = (Split-Path -Path $RepoPathAbs -Leaf)
$MonitorID = "GitSecurityMonitor-$RepoName" 
$PIDFile = Join-Path -Path $env:TEMP -ChildPath "$($MonitorID).pid"
$global:CommitsToPull = 0 # Usada globalmente para la logica de detencion

# Rutas para el Log y la Configuracion.
$LogFile = Join-Path -Path $PSScriptRoot -ChildPath "logs/audit.log"
$ConfigPathAbs = Join-Path -Path $PSScriptRoot -ChildPath $configuracion




function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [string]$Level = "INFO"
    )
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "$Timestamp [$Level]: $Message"
    
    # Crear el directorio de logs si no existe
    $LogDirectory = Split-Path -Parent $LogFile
    if (-not (Test-Path $LogDirectory)) {
        New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
    }
    
    # Escribir el log al archivo
    $LogEntry | Out-File -FilePath $LogFile -Append -Force
    
    # Si es una alerta, escribir tambien a la consola para visibilidad inmediata
    if ($Level -match "ALERTA") {
        Write-Host ">>> $LogEntry" -ForegroundColor Red
    }
}

function Write-ErrorAndExit {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message
    )
    Write-Host "ERROR: $Message" -ForegroundColor Red
    
    # Limpiar el PID_FILE si existe y si pertenece a este proceso
    if (Test-Path $PIDFile) {
        $FilePID = Get-Content $PIDFile -ErrorAction SilentlyContinue
        if ($PID -eq $FilePID) {
            Remove-Item $PIDFile -Force 2>$null
        }
    }
    exit 1
}

function Invoke-Scan {
    $global:CommitsToPull = 0
    
    # 1. Determinar la rama local
    # Intenta obtener la rama actual. Si falla, el script no puede operar.
    $CurrentBranch = & git -C $RepoPathAbs rev-parse --abbrev-ref HEAD 2>$null
    if ([string]::IsNullOrWhiteSpace($CurrentBranch)) {
        Write-Log -Message "No se pudo determinar la rama actual en el repositorio '$RepoName'. Asegurese de estar en una rama y que Git este configurado." -Level "ERROR"
        return $false
    }
    Write-Log -Message "Escaneando rama local: '$CurrentBranch'." -Level "DEBUG"


    # 2. Obtener los cambios del remoto (git fetch)
    try {
        # Ejecutar fetch para actualizar las referencias remotas (origin/master)
        $FetchResult = & git -C $RepoPathAbs fetch origin 2>&1
        if ($FetchResult -match "fatal") {
            Write-Log -Message "Error fatal en git fetch: $($FetchResult -join ' ')" -Level "ERROR"
            return $false 
        }
    }
    catch {
        Write-Log -Message "Excepcion al ejecutar git fetch: $($_.Exception.Message). Reintentando..." -Level "ADVERTENCIA"
        return $true 

    # 3. Verificar si hay commits pendientes de descargar

    $CompareTarget = "origin/$CurrentBranch"
    $CommitsResult = & git -C $RepoPathAbs rev-list HEAD..$CompareTarget --count 2>$null
    
    if ([string]::IsNullOrWhiteSpace($CommitsResult)) {
        Write-Log -Message "La verificacion de commits fallo (resultado vacio). Objetivo de comparacion: $CompareTarget" -Level "ADVERTENCIA"
        return $true
    }
    
    $global:CommitsToPull = [int]$CommitsResult
    
    if ($global:CommitsToPull -eq 0) {
        return $true 
    }
    
    # Mostrar inmediatamente en consola que se ha detectado actividad para feedback (AMARILLO)
    $DetectionMessage = "Detectados $global:CommitsToPull commits nuevos en '$CompareTarget'. Escaneando..."
    Write-Host ">>> $DetectionMessage" -ForegroundColor Yellow
    Write-Log -Message $DetectionMessage -Level "INFO"

    # 4. Obtener la lista de archivos modificados/anadidos
    
    $ModifiedFiles = & git -C $RepoPathAbs diff --name-only HEAD $CompareTarget 2>$null

    # 5. Leer patrones
    $Patrones = Get-Content -Path $ConfigPathAbs -Encoding UTF8

    $AlertFound = $false # Flag para rastrear la deteccion
    foreach ($File in $ModifiedFiles) {
        # 6. Usamos 'git show' para obtener el contenido del archivo en el commit remoto.
        $GitShowArg = "{0}:{1}" -f $CompareTarget, $File
        $Content = & git -C $RepoPathAbs show $GitShowArg 2>$null
        
        if (-not $Content) { continue }

        # 7. Escanear patrones
        foreach ($Pattern in $Patrones) {
            $Pattern = $Pattern.Trim()
            if ([string]::IsNullOrWhiteSpace($Pattern)) { continue }
            
            # Logica de Deteccion
            if ($Pattern -clike "regex:*") {
                $RegexPattern = $Pattern.Substring(6)
                
                # Busqueda Regex 
                if ($Content -match $RegexPattern) {
                    Write-Log -Message "Patron Regex '$RegexPattern' encontrado en el archivo remoto '$File'." -Level "ALERTA CRITICA"
                    $AlertFound = $true
                    break # Alerta detectada, salimos del bucle de patrones
                }
            }
            else {
                # Busqueda de Palabra Clave
                # Escapamos el patron para tratarlo como texto literal y no como regex complejo.
                $EscapedPattern = [regex]::Escape($Pattern)
                if ($Content -match $EscapedPattern) { # -match es case-insensitive por defecto en PowerShell
                    Write-Log -Message "Patron '$Pattern' encontrado en el archivo remoto '$File'." -Level "ALERTA CRITICA"
                    $AlertFound = $true # Usamos ALERTA CRITICA para que se detenga con cualquier coincidencia
                    break # Alerta detectada, salimos del bucle de patrones
                }
            }
        }
        if ($AlertFound) { break } # Si se detecto alerta, salimos del bucle de archivos
    }

    # 8. Actualizar el repositorio local (HEAD) solo si NO se detecto una alerta.
    if (-not $AlertFound) {
        try {
            # Usamos git reset --hard al HEAD remoto, que es el metodo mas seguro
            # Redirigimos todos los streams de salida y error a Out-Null para silenciar el error 'unknown switch E'
            & git -C $RepoPathAbs reset --hard $CompareTarget -ErrorAction Stop *>&1 | Out-Null
            $UpdateMessage = "Repositorio actualizado con exito a $CompareTarget."
            Write-Host ">>> $UpdateMessage" -ForegroundColor Cyan 
            Write-Log -Message $UpdateMessage -Level "INFO"
        }
        catch {
            Write-Log -Message "Error al actualizar el repositorio con 'git reset --hard': $($_.Exception.Message)" -Level "ERROR"
            return $false # Indica fallo irrecuperable, detener el demonio
        }
    }
    
    # Retorna $false si hay alerta (para que el bucle principal rompa), $true si todo OK.
    return -not $AlertFound 
}

# DETENER
if ($detener) {
    if (-not (Test-Path $PIDFile)) {
        Write-Host "Monitor para '$($RepoName)' no esta activo. Archivo PID no encontrado."
        exit 0
    }

    $TargetPID = Get-Content $PIDFile -ErrorAction Stop
    
    try {
        Get-Process -Id $TargetPID -ErrorAction Stop | Out-Null # Verifica que el proceso exista
        
        Stop-Process -Id $TargetPID -Force
        
        Remove-Item $PIDFile -Force 2>$null
        
        Write-Host "Monitor de seguridad (PID $TargetPID) para '$($RepoName)' ha sido detenido." -ForegroundColor Green
        exit 0
    }
    catch {
        # PID huerfano
        Remove-Item $PIDFile -Force 2>$null
        Write-Host "El monitor existia en el archivo de control, pero el proceso ($TargetPID) ya no esta activo. Se limpio el archivo de control huerfano." -ForegroundColor Yellow
        exit 0
    }
}


if (-not $configuracion -or -not (Test-Path $ConfigPathAbs)) {
    Write-ErrorAndExit "El parametro '-configuracion' es obligatorio al iniciar el monitoreo y el archivo debe existir."
}



# Preparamos el LogFile (creamos el directorio y el archivo si no existen)
$LogDirectory = Split-Path -Parent $LogFile
if (-not (Test-Path $LogDirectory)) {
    New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
}
if (-not (Test-Path $LogFile)) {
    New-Item -Path $LogFile -ItemType File -Force | Out-Null
}

# DEMONIO

# Chequear si ya hay un proceso con este ID corriendo
if (Test-Path $PIDFile) {
    $ExistingPID = Get-Content $PIDFile 
    if (Get-Process -Id $ExistingPID -ErrorAction SilentlyContinue) {
        Write-ErrorAndExit "Ya existe un monitor para '$($RepoName)' con PID $ExistingPID."
    } else {
        # Limpiar PID huerfano
        Remove-Item $PIDFile -Force 2>$null
    }
}

# Escribir el PID actual en el archivo de control
$PID | Out-File -FilePath $PIDFile -Force

# Log de INICIO
Write-Log -Message "Demonio iniciado para el repositorio '$RepoName'. Intervalo: $alerta segundos." -Level "INICIO"

Write-Host "Demonio para el repositorio '$RepoName' iniciado y corriendo en segundo plano." -ForegroundColor Green
Write-Host "Para detenerlo: $($MyInvocation.MyCommand.Name) -repo '$repo' -detener" -ForegroundColor Yellow


while ($true) {
    # ScanResult es $false si se encontro una alerta o si hubo un error de Git irrecuperable.
    $ScanResult = Invoke-Scan
    
    # Si ScanResult es $false, la funcion Write-Log ya notifico la ALERTA o ERROR.
    
    if (-not $ScanResult) {
        Write-Log -Message "Alerta detectada o error de Git irrecuperable. Finalizando la ejecucion." -Level "INFO"
        break # Termina el bucle (salida por detencion)
    }

    # Dormimos y reintentamos si no hubo alerta.
    Start-Sleep -Seconds $alerta
}


# Limpiamos el PID despues de una ejecucion exitosa
if (Test-Path $PIDFile) {
    Remove-Item $PIDFile -Force 2>$null
    Write-Host "Ejecucion de auditoria finalizada y PID limpiado." -ForegroundColor Green
}


