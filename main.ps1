<#
.SYNOPSIS
    Gestiona los permisos (ACL) de una carpeta de forma controlada y auditable.
.DESCRIPTION
    Este script esta diseñado para estandarizar los permisos de una estructura de carpetas. Sus funciones principales son:
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
    La ruta completa de la carpeta raiz donde se aplicaran los cambios. Este parametro es obligatorio.
.PARAMETER CSV_LineaBase
    Ruta al archivo CSV que contiene los permisos de linea base. Por defecto, busca "config-lb.csv" en la misma carpeta del script.
    El CSV debe tener las columnas: "Grupo", "Permiso".
.PARAMETER CSV_Grupos
    Ruta al archivo CSV que contiene los permisos especificos para grupos o usuarios. Por defecto, busca "config-group.csv".
    El CSV debe tener las columnas: "Grupo o Usuario", "Permisos".
.PARAMETER Rollback
    Switch que activa el modo de restauracion. Si se usa, es necesario proporcionar el parametro -RutaBackup.
.PARAMETER RutaBackup
    Ruta completa al archivo de respaldo de ACL (generado por el script) que se usara para la restauracion.
    Es obligatorio cuando se usa el switch -Rollback.
.EXAMPLE
    # EJEMPLO 1: Ejecutar el flujo completo sobre la carpeta "C:\Everyone\BP_TEST\SFTP_BP"
    .\main.ps1 -RutaObjetivo "C:\Everyone\BP_TEST\SFTP_BP" -Verbose

.EXAMPLE
    # EJEMPLO 2: Ejecutar usando rutas personalizadas para los archivos CSV
    .\main.ps1 -RutaObjetivo "C:\Everyone\BP_TEST\SFTP_BP" -CSV_LineaBase "C:\Everyone\BP_TEST\config-lb.csv" -CSV_Grupos "C:\Everyone\BP_TEST\config-group.csv" -Verbose

.EXAMPLE
    # EJEMPLO 3: Ejecutar un Rollback para restaurar los permisos
    # Es necesario indicar la ruta del archivo de respaldo generado en una ejecucion anterior.
    .\main.ps1 -Rollback -RutaObjetivo "C:\Everyone\BP_TEST\SFTP_BP" -RutaBackup ".\backup-permisos-20241028-153000.txt" -Verbose

.NOTES
    Autor: Gemini
    Version: 1.0
    Dependencias: icacls.exe (incluido en Windows). Ejecutar como Administrador para evitar errores de acceso.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, HelpMessage = "Introduce la ruta de la carpeta objetivo.")]
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

#------------------------------------------------------------------------------------------------------
# Punto 6: Registro de Cambios (Log)
# Se inicia al principio para capturar absolutamente todo el proceso.
#------------------------------------------------------------------------------------------------------
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logPath = ".\logs\log-cambios-$timestamp.txt"
try {
    Start-Transcript -Path $logPath -Append
    Write-Host "--- Iniciando el script de gestion de ACLs ---" -ForegroundColor Green
    Write-Host "Fecha y Hora: $(Get-Date)"
    Write-Host "Log de esta sesion se guardara en: $logPath"
}
catch {
    Write-Error "No se pudo iniciar el log (Start-Transcript). Verifica los permisos en la carpeta actual."
    # Si el log no puede iniciar, detenemos la ejecucion para evitar acciones no registradas.
    exit 1
}


#------------------------------------------------------------------------------------------------------
# Validaciones Iniciales
#------------------------------------------------------------------------------------------------------
if (-not (Test-Path -Path $RutaObjetivo -PathType Container)) {
    Write-Error "La ruta objetivo '$RutaObjetivo' no existe o no es una carpeta. Abortando script."
    Stop-Transcript
    exit 1
}


#------------------------------------------------------------------------------------------------------
# Punto 7: Logica de Rollback (Opcional)
# Si se especifica -Rollback, el script solo ejecuta esta seccion.
#------------------------------------------------------------------------------------------------------
if ($Rollback.IsPresent) {
    Write-Host "`n[MODO ROLLBACK ACTIVADO]" -ForegroundColor Yellow

    if (-not ($PSBoundParameters.ContainsKey('RutaBackup'))) {
        Write-Error "Para ejecutar el Rollback, debes proporcionar la ruta del archivo de respaldo con el parametro -RutaBackup."
        Stop-Transcript
        exit 1
    }

    if (-not (Test-Path -Path $RutaBackup -PathType Leaf)) {
        Write-Error "El archivo de respaldo '$RutaBackup' no fue encontrado. Abortando rollback."
        Stop-Transcript
        exit 1
    }

    Write-Host "Restaurando permisos en '$RutaObjetivo' desde el archivo '$RutaBackup'..." -ForegroundColor Cyan
    try {
        # El comando /c continua aunque encuentre errores. /t aplica recursivamente.
        icacls $RutaObjetivo /restore $RutaBackup /t /c
        Write-Host " Rollback completado exitosamente." -ForegroundColor Green
    }
    catch {
        Write-Error "Ocurrio un error durante la ejecucion de icacls /restore. Revisa el log para mas detalles."
    }

    Write-Host "--- Fin del script ---"
    Stop-Transcript
    # Termina la ejecucion del script aqui, ya que el rollback esta hecho.
    exit 0
}

# --- Si no es Rollback, se ejecuta el flujo principal ---

Write-Host "`n[MODO APLICAR PERMISOS INICIADO]" -ForegroundColor Green

try {
    #------------------------------------------------------------------------------------------------------
    # Punto 2: Respaldo de ACLs Actuales
    # Crea un archivo de texto con los permisos actuales para un posible rollback manual o automatico.
    #------------------------------------------------------------------------------------------------------
    $backupPath = ".\backups\backup-permisos-$timestamp.txt"
    Write-Host "`n[Paso 2/5] Creando respaldo de ACLs actuales en '$backupPath'..." -ForegroundColor Cyan
    
    # /save guarda los ACLs. /t es para que sea recursivo. /c para continuar en caso de errores.
    icacls $RutaObjetivo /save $backupPath /t /c
    
    Write-Host " Respaldo creado exitosamente." -ForegroundColor Green

    #------------------------------------------------------------------------------------------------------
    # Punto 3: Eliminar Herencia y Grupos con Full Control
    # Este es el paso mas delicado. Primero se rompe la herencia y luego se eliminan permisos explicitos.
    #------------------------------------------------------------------------------------------------------
    Write-Host "`n[Paso 3/5] Limpiando permisos existentes..." -ForegroundColor Cyan
    
    Write-Verbose "Deshabilitando herencia de permisos en '$RutaObjetivo'."
    # /inheritance:r copia los permisos heredados como explicitos y rompe la herencia.
    # Es mas seguro que /inheritance:d que simplemente los quita.
    icacls $RutaObjetivo /inheritance:r /t /c
    
    Write-Verbose "Buscando y eliminando grupos con permisos 'FullControl'."
    $acl = Get-Acl -Path $RutaObjetivo
    $fullControlRules = $acl.Access | Where-Object { $_.FileSystemRights -eq "FullControl" -and $_.IdentityReference.Value -notlike "S-1-5-*" } # Excluir SIDs conocidos de sistema

    if ($fullControlRules.Count -gt 0) {
        foreach ($rule in $fullControlRules) {
            $identity = $rule.IdentityReference.Value
            Write-Host "   -> Removiendo 'FullControl' del grupo/usuario: $identity" -ForegroundColor Yellow
            # /remove:g quita permisos para un grupo.
            icacls $RutaObjetivo /remove:g "$identity" /t /c
        }
    } else {
        Write-Host "   -> No se encontraron grupos con 'FullControl' para eliminar."
    }
    Write-Host " Limpieza de permisos completada." -ForegroundColor Green

    #------------------------------------------------------------------------------------------------------
    # Punto 4: Aplicar Permisos de Linea Base desde CSV
    # Lee el primer CSV y aplica los permisos base.
    #------------------------------------------------------------------------------------------------------
    Write-Host "`n[Paso 4/5] Aplicando permisos de Linea Base desde '$CSV_LineaBase'..." -ForegroundColor Cyan
    if (-not (Test-Path -Path $CSV_LineaBase)) {
        throw "El archivo CSV de linea base '$CSV_LineaBase' no fue encontrado."
    }
    
    $lineaBase = Import-Csv -Path $CSV_LineaBase
    foreach ($row in $lineaBase) {
        $grupo = $row.Grupo
        $permiso = $row.Permiso
        Write-Host "   -> Aplicando permiso '$permiso' a '$grupo'..."
        # /grant:r reemplaza los permisos existentes para este grupo.
        icacls $RutaObjetivo /grant:r "$grupo`:$permiso" /t /c
    }
    Write-Host " Permisos de linea base aplicados." -ForegroundColor Green

    #------------------------------------------------------------------------------------------------------
    # Punto 5: Aplicar Permisos Especificos desde CSV
    # Lee el segundo CSV y aplica permisos adicionales o especificos.
    #------------------------------------------------------------------------------------------------------
    Write-Host "`n[Paso 5/5] Aplicando permisos Especificos desde '$CSV_Grupos'..." -ForegroundColor Cyan
    if (-not (Test-Path -Path $CSV_Grupos)) {
        throw "El archivo CSV de grupos especificos '$CSV_Grupos' no fue encontrado."
    }

    $gruposEspecificos = Import-Csv -Path $CSV_Grupos
    foreach ($row in $gruposEspecificos) {
        # Usamos los nombres de columna del flujo
        $entidad = $row.'Grupo o Usuario'
        $permiso = $row.Permisos
        Write-Host "   -> Aplicando permiso '$permiso' a '$entidad'..."
        icacls $RutaObjetivo /grant:r "$entidad`:$permiso" /t /c
    }
    Write-Host " Permisos especificos aplicados.`n`n" -ForegroundColor Green

}
catch {
    # Captura cualquier error que ocurra en el bloque try
    Write-Error "¡ERROR FATAL! Ocurrio una excepcion durante la ejecucion:"
    Write-Error $_.Exception.Message
    Write-Warning "El proceso se ha detenido. Revisa el log '$logPath' para mas detalles."
    Write-Warning "Puedes usar el archivo de respaldo '$backupPath' para ejecutar un rollback si es necesario."
}
finally {
    # Este bloque siempre se ejecuta, haya o no errores.
    Stop-Transcript
}



# Prueba 1

# .\main.ps1 -RutaObjetivo "C:\Everyone\BP_TEST\SFTP_BP\dir_c2278304\dir_7d146f60\dir_b3c9235f" -Verbose

# C:\Everyone\BP_TEST\SFTP_BP\dir_c2278304\dir_7d146f60\dir_b3c9235f Sin herencia, con grupos definidos
# MICROSOFT\usuario1 con permisos de Full Control