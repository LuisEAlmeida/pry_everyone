# Gestor de Permisos de Carpetas (ACL) con PowerShell

Este script de PowerShell proporciona una solución robusta y auditable para estandarizar y gestionar los permisos de acceso (ACL) en una estructura de carpetas de Windows. Automatiza el proceso de respaldo, limpieza y aplicación de permisos controlados a través de archivos de configuración.

## Características Principales

- **Respaldo Automático**: Crea una copia de seguridad de los permisos actuales antes de realizar cualquier modificación.
- **Función de Rollback**: Permite restaurar los permisos a su estado anterior utilizando un archivo de respaldo.
- **Limpieza de Permisos**: Elimina la herencia y revoca permisos de "Control Total" (Full Control) para evitar accesos no deseados.
- **Configuración Centralizada**: Utiliza archivos CSV para definir los permisos, facilitando la gestión y auditoría.
- **Aplicación en Capas**: Aplica primero una "línea base" de permisos y luego permisos específicos para grupos o usuarios.
- **Registro Detallado**: Cada ejecución y acción se registra en un archivo de log con marca de tiempo para una auditoría completa.

## Requisitos

- **Sistema Operativo**: Windows.
- **PowerShell**: Versión 5.1 o superior.
- **Dependencias**: `icacls.exe` (herramienta nativa de Windows).
- **Privilegios**: Se debe ejecutar la consola de PowerShell con **privilegios de Administrador**.

## Estructura de Archivos y Carpetas Recomendada

Para un funcionamiento correcto, el script espera la siguiente estructura de directorios en su ubicación raíz:

```
/tu_proyecto/
|
|-- main.ps1                   # El script principal
|
|-- /config/
|   |-- config-lb.csv          # CSV para permisos de Línea Base
|   |-- config-group.csv       # CSV para permisos Específicos
|
|-- /backups/
|   |-- (Aquí se guardarán los respaldos, ej: backup-permisos-20241028-153000.txt)
|
|-- /logs/
|   |-- (Aquí se guardarán los logs, ej: log-cambios-20241028-153000.txt)

```

## Configuración de Archivos CSV

El comportamiento del script se define mediante dos archivos CSV ubicados en la carpeta `config`.

### 1. `config-lb.csv` (Línea Base)

Define los permisos fundamentales que se aplicarán a la carpeta objetivo.

- **Formato**:
  | Grupo | Permiso |
  | :---- | :------ |
  | `BUILTIN\Administrators` | `(OI)(CI)F` |
  | `NT AUTHORITY\SYSTEM` | `(OI)(CI)F` |
  | `CREATOR OWNER` | `(OI)(CI)(IO)F` |

- **Columnas**:
  - `Grupo`: El nombre del grupo de seguridad.
  - `Permiso`: La cadena de permiso en formato `icacls` (ej. `F` para Full Control, `M` para Modify, `RX` para Read and Execute). `(OI)(CI)` asegura la herencia a subcarpetas y archivos.

### 2. `config-group.csv` (Grupos Específicos)

Define los permisos específicos para usuarios o grupos que necesitan un acceso particular a la carpeta.

- **Formato**:
  | Grupo o Usuario | Permisos |
  | :-------------- | :------- |
  | `DOMINIO\GrupoDeLectura` | `(OI)(CI)RX` |
  | `DOMINIO\GrupoDeEscritura`| `(OI)(CI)M` |
  | `DOMINIO\UsuarioEspecial`| `(OI)(CI)M` |

- **Columnas**:
  - `Grupo o Usuario`: El nombre del grupo o usuario de dominio/local.
  - `Permisos`: La cadena de permiso en formato `icacls`.

## Uso

El script tiene dos modos de operación: **Aplicar Permisos** (por defecto) y **Rollback**.

### Parámetros

| Parámetro        | Descripción                                                         | Obligatorio            | Valor por Defecto           |
| :--------------- | :------------------------------------------------------------------ | :--------------------- | :-------------------------- |
| `-RutaObjetivo`  | La ruta completa de la carpeta raíz donde se aplicarán los cambios. | **Sí**                 | N/A                         |
| `-CSV_LineaBase` | Ruta al archivo CSV que contiene los permisos de línea base.        | No                     | `.\config\config-lb.csv`    |
| `-CSV_Grupos`    | Ruta al CSV con permisos específicos para grupos/usuarios.          | No                     | `.\config\config-group.csv` |
| `-Rollback`      | Switch que activa el modo de restauración de permisos.              | No                     | N/A                         |
| `-RutaBackup`    | Ruta al archivo de respaldo de ACL a usar para la restauración.     | **Sí (con -Rollback)** | N/A                         |

---

### **Ejemplos de Ejecución**

#### Ejemplo 1: Aplicar permisos en una carpeta

Ejecuta el flujo completo (respaldo, limpieza y aplicación) sobre la carpeta indicada, usando los archivos CSV por defecto. El flag `-Verbose` muestra información detallada.

```powershell
.\main.ps1 -RutaObjetivo "C:\Rutas\MiCarpetaSegura" -Verbose
```

#### Ejemplo 2: Usar archivos de configuración personalizados

Ejecuta el flujo completo, pero especifica ubicaciones personalizadas para los archivos CSV de configuración.

```powershell
.\main.ps1 -RutaObjetivo "D:\Proyectos\DATA" -CSV_LineaBase "C:\configs\base.csv" -CSV_Grupos "C:\configs\grupos_proyecto.csv" -Verbose
```

#### Ejemplo 3: Restaurar permisos desde un respaldo (Rollback)

Activa el modo Rollback para deshacer los cambios. Es **necesario** indicar la ruta al archivo de respaldo generado en una ejecución anterior.

```powershell
.\main.ps1 -Rollback -RutaObjetivo "C:\Rutas\MiCarpetaSegura" -RutaBackup ".\backups\backup-permisos-20241028-153000.txt" -Verbose
```

---

## Flujo de Trabajo (Modo Aplicar)

Cuando se ejecuta en el modo por defecto, el script sigue estos pasos de forma secuencial:

1.  **Iniciar Log**: Crea un archivo de transcripción en la carpeta `.\logs\` para registrar todas las acciones y salidas de la consola.
2.  **Respaldar ACLs**: Usa `icacls /save` para guardar el estado actual de los permisos de la `RutaObjetivo` y todas sus subcarpetas en un archivo `.txt` dentro de `.\backups\`.
3.  **Limpiar Permisos**:
    - **Desactiva la herencia** en la carpeta objetivo, copiando los permisos heredados como explícitos (`icacls /inheritance:r`).
    - Busca y **elimina las reglas de acceso (ACEs)** que concedan "FullControl" a grupos (excluyendo entidades de sistema conocidas) para forzar un control más granular.
4.  **Aplicar Línea Base**: Lee el archivo `config-lb.csv` y aplica los permisos definidos a la carpeta y su contenido, reemplazando (`/grant:r`) cualquier permiso previo para esos grupos.
5.  **Aplicar Permisos Específicos**: Lee el archivo `config-group.csv` y aplica los permisos adicionales de la misma manera.

## Manejo de Errores y Seguridad

- El script está encapsulado en un bloque `try...catch` para gestionar errores inesperados.
- Si ocurre un error fatal, la ejecución se detiene y se muestra un mensaje indicando la ruta del log y del archivo de respaldo, sugiriendo la posibilidad de un rollback manual.
- El bloque `finally` asegura que el registro de log (`Stop-Transcript`) se detenga siempre, incluso si hay errores.
