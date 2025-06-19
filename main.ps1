<#
.SYNOPSIS
    Gestiona los permisos (ACL) de una carpeta de forma controlada y auditable.
.DESCRIPTION
    Este script esta diseñado para estandarizar los permisos de una estructura de carpetas NTFS. Sus funciones principales son:
    1. Respaldar los permisos actuales antes de cualquier cambio.
    2. Eliminar la herencia de permisos y remover accesos de tipo "Full Control" para grupos.
    3. Aplicar un conjunto de permisos base desde un archivo CSV.
    4. Aplicar permisos especificos para grupos o usuarios desde otro archivo CSV.
    5. Registrar cada accion en un archivo de log.
    6. Ofrecer una funcionalidad de Rollback para restaurar los permisos desde un respaldo.

    El script opera en dos modos:
    - MODO APLICAR (por defecto): Ejecuta el flujo completo de respaldo, limpieza y aplicacion de permisos.
    - MODO ROLLBACK (-Rollback): Restaura los permisos utilizando un archivo de respaldo previo.

.PARAMETER RutaObjetivo
    Ruta completa de la carpeta raiz donde se aplicaran los cambios. Obligatorio.
.PARAMETER CSV_LineaBase
    Ruta al archivo CSV que contiene los permisos de linea base. Por defecto, ".\config\config-lb.csv".
    El CSV debe tener las columnas: "Grupo o Usuario", "Permisos".
.PARAMETER CSV_Grupos
    Ruta al archivo CSV que contiene los permisos especificos para grupos o usuarios. Por defecto, ".\config\config-group.csv".
    El CSV debe tener las columnas: "Grupo o Usuario", "Permisos".
.PARAMETER Rollback
    Switch que activa el modo de restauracion. Si se usa, es necesario proporcionar el parametro -RutaBackup.
.PARAMETER RutaBackup
    Ruta completa al archivo de respaldo de ACL (generado por el script) que se usara para la restauracion.
    Es obligatorio cuando se usa el switch -Rollback.

.EXAMPLE
    .\main.ps1 -RutaObjetivo "C:\Everyone\BP_TEST\SFTP_BP" -Verbose
.EXAMPLE
    .\main.ps1 -RutaObjetivo "C:\Everyone\BP_TEST\SFTP_BP" -CSV_LineaBase "C:\config-lb.csv" -CSV_Grupos "C:\config-group.csv" -Verbose
.EXAMPLE
    .\main.ps1 -Rollback -RutaObjetivo "C:\Everyone\BP_TEST\SFTP_BP" -RutaBackup ".\backups\backup-permisos-20241028-153000.txt" -Verbose

.NOTES
    Dependencias: icacls.exe (incluido en Windows). Ejecutar como Administrador para evitar errores de acceso.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, HelpMessage = "Introduce la ruta de la carpeta a procesar")]
    [string]$RutaObjetivo,

    [Parameter(Mandatory = $false, HelpMessage = "Ruta al CSV con permisos base.")]
    [string]$CSV_LineaBase = ".\config\config-lb.csv",

    [Parameter(Mandatory = $false, HelpMessage = "Ruta al CSV con permisos especificos.")]
    [string]$CSV_Grupos = ".\config\config-group.csv",

    [Parameter(Mandatory = $false, HelpMessage = "Activa el modo Rollback para restaurar permisos.")]
    [switch]$Rollback,

    [Parameter(Mandatory = $false, HelpMessage = "Ruta del archivo de backup para el rollback.")]
    [string]$RutaBackup
)

# -------------------------------------------------------------------------------------------------------
# Comprobacion de privilegios de administrador
# -------------------------------------------------------------------------------------------------------
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "Debes ejecutar este script como Administrador."
    exit 1
}

# -------------------------------------------------------------------------------------------------------
# Crear carpetas para backups y logs si no existen
# -------------------------------------------------------------------------------------------------------
$backupDir = ".\backups"
$logDir = ".\logs"

if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir | Out-Null }
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }

# -------------------------------------------------------------------------------------------------------
# Inicializacion de log
# -------------------------------------------------------------------------------------------------------
$timestamp = Get-Date -Format "yyyy-MM-dd-HHmmss"
$logPath = "$logDir\log-cambios-$timestamp.txt"
$transcriptStarted = $false

try {
    Start-Transcript -Path $logPath -Append
    $transcriptStarted = $true
    Write-Host "`n----- Iniciando el Script para gestion de permisos -----" -ForegroundColor Cyan
    Write-Host "Fecha y Hora: $(Get-Date)"
    Write-Host "Log de esta sesion se guardara en:"
    Write-Host "`t$logPath"
}
catch {
    Write-Error "No se pudo iniciar el log (Start-Transcript). Verifica los permisos en la carpeta actual." -ForegroundColor Red
    exit 1
}

try {
    # ---------------------------------------------------------------------------------------------------
    # Validaciones Iniciales
    # ---------------------------------------------------------------------------------------------------
    if (-not (Test-Path -Path $RutaObjetivo -PathType Container)) {
        Write-Error "La ruta objetivo '$RutaObjetivo' no existe o no es una carpeta. Abortando script." -ForegroundColor Red
        throw
    }

    # ---------------------------------------------------------------------------------------------------
    # Rollback (Restauracion de permisos)
    # ---------------------------------------------------------------------------------------------------
    if ($Rollback.IsPresent) {
        Write-Host "`n----- MODO ROLLBACK ACTIVADO -----" -ForegroundColor Cyan

        if (-not $RutaBackup) {
            Write-Error "Para ejecutar el Rollback, debes proporcionar la ruta del archivo de respaldo con el parametro -RutaBackup." -ForegroundColor Red
            throw
        }

        if (-not (Test-Path -Path $RutaBackup -PathType Leaf)) {
            Write-Error "El archivo de respaldo '$RutaBackup' no fue encontrado. Abortando rollback." -ForegroundColor Red
            throw
        }

        Write-Host "`nRestaurando permisos:" -ForegroundColor Blue
        Write-Host "`tEn:'$RutaObjetivo'" -ForegroundColor Blue
        Write-Host "`tDe:'$RutaBackup'" -ForegroundColor Blue

        try {
            icacls $RutaObjetivo /restore $RutaBackup /t /c
            Write-Host "`nRollback completado exitosamente.`n" -ForegroundColor Green
        }
        catch {
            Write-Error "Ocurrio un error durante la ejecucion de icacls /restore. Revisa el log para mas detalles." -ForegroundColor Red
            throw
        }

        return
    }

    # ---------------------------------------------------------------------------------------------------
    # Respaldo de ACLs Actuales
    # ---------------------------------------------------------------------------------------------------
    $backupPath = "$backupDir\backup-permisos-$timestamp.txt"
    Write-Host "`n----- 1. Creando un Backup de los permisos NTFS -----" -ForegroundColor Cyan
    Write-Host "Archivo con los Backups: '$backupPath'" -ForegroundColor Blue
    icacls $RutaObjetivo /save $backupPath /t /c
    Write-Host "Respaldo creado exitosamente." -ForegroundColor Green

    # ---------------------------------------------------------------------------------------------------
    # Tomar Propiedad y Romper Herencia
    # ---------------------------------------------------------------------------------------------------
    $usuarioActual = "$($env:USERDOMAIN)\$($env:USERNAME)"
    Write-Host "`n----- 2. Tomando propiedad y deshabilitando herencia -----" -ForegroundColor Cyan

    # Cambiar la S por la Y en caso de sistemas en idioma ingles
    takeown /F "$RutaObjetivo" /R /D S | Out-Null
    icacls "$RutaObjetivo" /setowner "$usuarioActual" /t /c | Out-Null
    icacls "$RutaObjetivo" /inheritance:r /t /c | Out-Null
    Write-Host "Propiedad asignada y herencia eliminada." -ForegroundColor Green

    # ---------------------------------------------------------------------------------------------------
    # Limpiar permisos explicitos (excepto usuario actual) - Recursivo
    # ---------------------------------------------------------------------------------------------------
    Write-Host "`n----- 3. Limpiando permisos explicitos -----" -ForegroundColor Cyan

    $allItems += Get-Item -Path $RutaObjetivo  # Agrega la carpeta raiz

    foreach ($item in $allItems) {
        $acl = Get-Acl -Path $item.FullName
        $identidades = $acl.Access | Select-Object -ExpandProperty IdentityReference | Sort-Object -Unique
        $usuarioTienePermiso = $false

        foreach ($identidad in $identidades) {
            if ($identidad -eq $usuarioActual) {
                $usuarioTienePermiso = $true
                Write-Host "Se conservan los permisos del usuario actual: $usuarioActual en $($item.FullName)" -ForegroundColor Yellow
            } else {
                Write-Host "Eliminando permisos de: $identidad en $($item.FullName)" -ForegroundColor DarkGray
                icacls $item.FullName /remove "$identidad" /c | Out-Null
            }
        }

        # Si el usuario actual no tenia permisos explicitos, asigna FullControl
        if (-not $usuarioTienePermiso) {
            Write-Host "El usuario actual no tenia permisos en $($item.FullName). Asignando FullControl..." -ForegroundColor Yellow
            icacls $item.FullName /grant "'$usuarioActual':(OI)(CI)F" /c | Out-Null
        }
    }
    Write-Host "Limpieza de permisos completada." -ForegroundColor Green

    # ---------------------------------------------------------------------------------------------------
    # Aplicar Permisos de Linea Base desde CSV
    # ---------------------------------------------------------------------------------------------------
    Write-Host "`n----- 4. Aplicando permisos de Linea Base desde CSV -----" -ForegroundColor Cyan
    if (-not (Test-Path -Path $CSV_LineaBase)) {
        Write-Error "El archivo CSV de linea base '$CSV_LineaBase' no fue encontrado." -ForegroundColor Red
        throw
    }
    $lineaBase = Import-Csv -Path $CSV_LineaBase
    foreach ($row in $lineaBase) {
        $grupo = $row.'Grupo o Usuario'
        $permiso = $row.Permisos
        if (-not $grupo -or -not $permiso) { continue }
        Write-Host "`tAplicando permiso '$permiso' a '$grupo'..."
        icacls $RutaObjetivo /grant:r "$grupo`:$permiso" /t /c
    }
    Write-Host "Permisos de linea base aplicados." -ForegroundColor Green

    # ---------------------------------------------------------------------------------------------------
    # Aplicar Permisos Especificos desde CSV
    # ---------------------------------------------------------------------------------------------------
    Write-Host "`n----- 5. Aplicando permisos Especificos desde CSV -----" -ForegroundColor Cyan
    if (-not (Test-Path -Path $CSV_Grupos)) {
        Write-Error "El archivo CSV de grupos especificos '$CSV_Grupos' no fue encontrado." -ForegroundColor Red
        throw
    }
    $gruposEspecificos = Import-Csv -Path $CSV_Grupos
    foreach ($row in $gruposEspecificos) {
        $entidad = $row.'Grupo o Usuario'
        $permiso = $row.Permisos
        if (-not $entidad -or -not $permiso) { continue }
        Write-Host "`tAplicando permiso '$permiso' a '$entidad'..."
        icacls $RutaObjetivo /grant "$entidad`:$permiso" /t /c
    }
    Write-Host "Permisos especificos aplicados." -ForegroundColor Green

} catch {
    Write-Error "¡ERROR! Ocurrio una excepcion durante la ejecucion:"
    Write-Error $_.Exception.Message
    Write-Warning "El proceso se ha detenido. Revisa el log '$logPath' para mas detalles."
    if ($backupPath) {
        Write-Warning "Puedes usar el archivo de respaldo '$backupPath' para ejecutar un rollback si es necesario."
    }
} finally {
    if ($transcriptStarted) {
        Stop-Transcript
    }
}
