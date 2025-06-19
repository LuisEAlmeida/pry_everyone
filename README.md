# Script de Gestión de Permisos NTFS con PowerShell

## Descripción general

Este repositorio contiene **`main.ps1`**, un script de PowerShell que estandariza y audita los permisos (ACL) de una estructura de carpetas NTFS. Sus capacidades principales incluyen:

1. **Respaldo de ACL existentes** antes de cualquier modificación.
2. **Eliminación de herencia** y depuración de entradas "Full Control" para grupos.
3. Aplicación de **permisos de línea base** y **permisos específicos** a partir de archivos CSV.
4. **Registro (logging)** exhaustivo de cada acción ejecutada.
5. **Rollback** para restaurar permisos desde un respaldo anterior.

> **Nota:** El script debe ejecutarse con privilegios de **Administrador** para evitar errores de acceso.

---

## Requisitos

| Requisito            | Versión / Detalle                |
| -------------------- | -------------------------------- |
| Windows              | 10, 11 o Server 2016 en adelante |
| PowerShell           | 5.1 o superior                   |
| Ejecutar como        | Administrador                    |
| Herramientas nativas | `icacls.exe`, `takeown.exe`      |

---

## Estructura del repositorio

```
.
├─ main.ps1                # Script principal
├─ config
│  ├─ config-lb.csv        # Permisos de línea base
│  └─ config-group.csv     # Permisos específicos
├─ backups\                # Respaldos generados
└─ logs\                   # Bitácoras de ejecución
```

---

## Sintaxis

```powershell
# Ejecución estándar
.\main.ps1 -RutaObjetivo "<RutaCompleta>" [-CSV_LineaBase "<rutaLB.csv>"] [-CSV_Grupos "<rutaGrupos.csv>"] [-Verbose]

# Rollback
.\main.ps1 -Rollback -RutaObjetivo "<RutaCompleta>" -RutaBackup "<backup.txt>" [-Verbose]
```

### Parámetros

| Parámetro        | Tipo     | Descripción                                                     |
| ---------------- | -------- | --------------------------------------------------------------- |
| `-RutaObjetivo`  | `string` | Carpeta raíz donde se aplicarán los cambios.                    |
| `-CSV_LineaBase` | `string` | Predeterminado: `./config/config-lb.csv`.                       |
| `-CSV_Grupos`    | `string` | Predeterminado: `./config/config-group.csv`.                    |
| `-Rollback`      | `switch` | Activa modo restauración de ACL (requiere `-RutaBackup`).       |
| `-RutaBackup`    | `string` | Ruta al archivo de respaldo generado previamente por el script. |
| `-Verbose`       | `switch` | Muestra salida detallada en consola.                            |

**Nota**: Al restaurar permisos debes situarte un nivel por encima de la carpeta afectada. Por ejemplo, si los cambios se realizaron en `F:\BP\Aplicativos\Bancs`, el valor correcto para `-RutaObjetivo` durante el rollback será `F:\BP\Aplicativos`. Esto garantiza que `icacls /restore` pueda reaplicar las ACE a todos los elementos originales.

## Formato de los CSV

### 1. CSV de Línea Base (`config-lb.csv`)

Debe contener **solo dos columnas** con encabezados exactamente como se muestra:

```csv
"Grupo o Usuario","Permisos"
"Domain Users","(OI)(CI)RX"
"Administrators","F"
```

### 2. CSV de Permisos Específicos (`config-group.csv`)

```csv
"Grupo o Usuario","Permisos"
"PRJ_Marketing_RW","(OI)(CI)M"
"svc_backup","(CI)R"
```

**Leyenda de accesos abreviados y acciones permitidas**

A continuación se detalla **qué derechos NTFS incluye cada abreviatura**, qué operaciones permite en el Explorador de Windows y **qué puede hacer un usuario cuando se conecta con WinSCP** (ya sea vía SFTP o uso local) bajo esas mismas ACL.  Las descripciones asumen que _no existen reglas DENY implícitas_ y que el usuario hereda los permisos señalados.

| Código                                | Derechos NTFS agregados (_high‑level_)                                                                                                                     | Operaciones Windows (GUI/CLI)                                                                                                                        | Acciones WinSCP                                                                                                                                                                    |
| ------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **`F` – Full Control**                | Todos los derechos estándar más los avanzados: <br>Read, Write, Execute, Delete, Change Permissions (WRITE_DAC), Take Ownership (WRITE_OWNER), Synchronize | Listar, leer/abrir, crear, modificar, eliminar, renombrar, cambiar permisos, tomar propiedad.                                                        | Listar directorios, descargar, cargar (upload), sobrescribir, renombrar, mover, eliminar, cambiar **atributos/ACL** desde la pestaña _Properties_ de WinSCP.                       |
| **`M` – Modify**                      | Read, Write, Execute, Delete, Synchronize                                                                                                                  | Igual que Full Control **excepto** cambiar permisos y tomar propiedad.                                                                               | Todas las operaciones habituales de archivo/carpeta (listar, descargar, cargar, sobrescribir, renombrar, mover, eliminar). **No** permite cambiar ACL ni propietario desde WinSCP. |
| **`RX` – Read & Execute**             | Read Data, List Directory, Read/Write Attributes, Read/Write Extended Attributes, Execute, Synchronize                                                     | Navegar carpetas, abrir/leer archivos y ejecutar _.exe_/_scripts_ que residan en esa ruta; no puede crear ni borrar.                                 | Listar directorios, descargar archivos, abrir/editar localmente (solo lectura). **No** puede subir ni eliminar.                                                                    |
| **`R` – Read**                        | Igual que _RX_ pero **sin Execute/Traverse**                                                                                                               | Listar y leer archivos; no puede ejecutar binarios ni scripts y puede fallar al "traversar" subcarpetas si no dispone de _Traverse Folder_ heredado. | Listar y descargar.  Si el árbol contiene subcarpetas, necesitará permiso de _Traverse_ para entrar en ellas.                                                                      |
| **`W` – Write**                       | Write Data/Add Files, Append Data, Write Attributes, Write Extended Attributes, Read Permissions, Synchronize                                              | Crear archivos/carpetas y modificar atributos; **no** puede borrar ni leer contenido si falta el derecho de _Read Data_.                             | Subir (upload) nuevos archivos, modificar marcas de tiempo/atributos.  Sin _R_ no verá listado; necesitará combinación.                                                            |
| **`D` – Delete**                      | Delete                                                                                                                                                     | Eliminar archivos/carpetas (si se posee este derecho sobre el objeto **o** `Delete Subfolders & Files` en el contenedor).                            | Permite `Delete`/`Move to Recycle Bin` dentro de WinSCP.                                                                                                                           |
| **`DC` – Delete Subfolders & Files**  | Delete Child                                                                                                                                               | Eliminar **cualquier** ítem hijo dentro del directorio aun cuando no tenga derecho `D` en cada objeto.                                               | Borrar carpetas/archivos subordinados mediante WinSCP.                                                                                                                             |
| **`RA` – Read Attributes**            | Read Attributes                                                                                                                                            | Ver atributos básicos (solo/oculto, tamaño, timestamps).                                                                                             | Listado de columnas con tamaño/fecha funciona.                                                                                                                                     |
| **`REA` – Read Extended Attributes**  | Read EA                                                                                                                                                    | Ver ADS/propiedades extendidas.                                                                                                                      | WinSCP muestra/despliega etiquetas ADS cuando corresponda.                                                                                                                         |
| **`WA` – Write Attributes**           | Write Attributes                                                                                                                                           | Cambiar fecha/hora, atributo solo/oculto, etc.                                                                                                       | Permite modificar timestamps desde _Properties_ _Set permissions_.                                                                                                                 |
| **`WEA` – Write Extended Attributes** | Write EA                                                                                                                                                   | Guardar flujos alternos u «Otras propiedades».                                                                                                       | WinSCP puede preservar/metadatos ADS al cargar si el servidor lo soporta.                                                                                                          |
| **`WDAC` – Change Permissions**       | WRITE_DAC                                                                                                                                                  | Cambiar ACL a otros usuarios/grupos.                                                                                                                 | En la ficha _Properties → Permissions_ de WinSCP aparece habilitada la edición.                                                                                                    |
| **`WO` – Take Ownership**             | WRITE_OWNER                                                                                                                                                | Tomar la propiedad del objeto.                                                                                                                       | WinSCP mostrará opción _Properties → Set owner_ (solo en SFTP con privilegios).                                                                                                    |

> **Prefijos y modificadores de herencia**
>
> | Marcador | Significado                                                                   | Ejemplo                                                                  |
> | -------- | ----------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
> | `(OI)`   | _Object Inheritance_ – se aplica a archivos (objetos) dentro de la carpeta.   | `(OI)(CI)M` ↔ todos los archivos y subcarpetas heredan **Modify**.       |
> | `(CI)`   | _Container Inheritance_ – se aplica a subcarpetas (contenedores).             | `(CI)RX` ↔ solo subcarpetas heredan **Read/Execute**.                    |
> | `(IO)`   | _Inherit Only_ – la ACE **no** afecta al contenedor actual, solo a los hijos. | `(CI)(IO)RX` ↔ la carpeta actual no expone RX, las subcarpetas sí.       |
> | `(NP)`   | _No Propagate_ – hijos directos heredan, nietos no.                           | `(CI)(NP)RX` ↔ subcarpetas inmediatas heredan RX, niveles inferiores no. |

---

>

### Combinaciones frecuentes y su efecto en WinSCP

| ACE completa    | Efecto resumido                                                       | Uso típico                                                                       | Operaciones WinSCP                                                                            |
| --------------- | --------------------------------------------------------------------- | -------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| `(OI)(CI)F`     | Hereda **Full Control** a todos los niveles.                          | Carpetas de administradores o servicios de copia de seguridad.                   | Libre total: listar, subir, descargar, renombrar, borrar, editar ACL.                         |
| `(OI)(CI)M`     | Hereda **Modify** completo.                                           | Repositorios de código, carpetas de proyectos colaborativos.                     | Todas las operaciones excepto cambiar ACL/propietario.                                        |
| `(CI)(IO)RX`    | Concede solo RX a subcarpetas; carpeta raíz queda sin acceso directo. | Share donde la raíz es un _junction_ y solo se entra a subdirectorios concretos. | El usuario puede navegar y descargar dentro de subcarpetas pero la raíz no aparece accesible. |
| `(OI)(CI)R`     | Lectura recursiva sin ejecución.                                      | Repositorio de artefactos de _build_ o librerías.                                | Solo descarga/listado; upload y delete bloqueados.                                            |
| `(OI)(CI)(NP)W` | Puede crear/editar en primer nivel, no en nietos.                     | Recepción de archivos (_drop‑zone_).                                             | Subir archivos a la carpeta raíz; no puede crear subcarpetas dentro de subdirectorios.        |

> **Sugerencia:** Cuando diseñes permisos para accesos SFTP/WinSCP procura otorgar siempre rights por grupos, añadiendo `(OI)(CI)` para herencia recursiva y **evitando** asignar `F` a cuentas de usuario finales salvo necesidad explícita.
>
> \--------|-------------|
> \| `F` | Full Control |
> \| `M` | Modify |
> \| `RX` | Read & Execute |
> \| `R` | Read |
> \| `W` | Write |
> \| Prefijos `(OI)`/`(CI)` | Object Inheritance / Container Inheritance |

---

## Ejemplos de Uso

### 1. Aplicar permisos con archivos CSV predeterminados

```powershell
.\main.ps1 -RutaObjetivo "C:\Everyone\BP_TEST\SFTP_BP" -Verbose
```

### 2. Usar CSV personalizados y obtener salida detallada

```powershell
.\main.ps1 \
  -RutaObjetivo "D:\Datos\Proyectos\Alpha" \
  -CSV_LineaBase "C:\permisos\lb.csv" \
  -CSV_Grupos "C:\permisos\grupos.csv" \
  -Verbose
```

### 3. Restaurar permisos (Rollback)

```powershell
.\main.ps1 -Rollback \
  -RutaObjetivo "D:\Datos\Proyectos\Alpha" \
  -RutaBackup ".\backups\backup-permisos-20250619-120501.txt" \
  -Verbose
```

---

## Flujo interno de trabajo

1. **Verificación de privilegios** – Confirma que la sesión se ejecuta como Administrador.
2. **Creación de carpetas** – Genera `backups\` y `logs\` si no existen.
3. **Inicio de transcript** – Todo se registra en `logs\log-cambios-<timestamp>.txt`.
4. **Backup de ACL** – `icacls <ruta> /save ...` guarda el estado previo.
5. **Toma de propiedad & ruptura de herencia** – `takeown` + `icacls /setowner` + `icacls /inheritance:r`.
6. **Limpieza de permisos** – Elimina ACE explícitas, excepto las del usuario que ejecuta el script.
7. **Aplicación de permisos de Línea Base** – Lee `config-lb.csv` y aplica con `/grant:r`.
8. **Aplicación de permisos Específicos** – Lee `config-group.csv` y aplica con `/grant`.
9. **Fin de transcript** – Cierra log; backup disponible para rollback.

---

## Carpetas generadas

| Carpeta    | Contenido                                                          |
| ---------- | ------------------------------------------------------------------ |
| `backups\` | Archivos `.txt` resultado de `icacls /save`. Úsalos para rollback. |
| `logs\`    | Transcripts detallados con todas las operaciones ejecutadas.       |

---

## Buenas prácticas

- **Prueba primero en un entorno de laboratorio.**
- Mantén los **CSV bajo control de versiones** para auditar cambios de permisos.
- Conserva los **archivos de backup** en un repositorio seguro.
- Usa `-Verbose` para diagnósticos; revisa los logs ante errores.

---

## Solución de problemas

| Mensaje / Síntoma                       | Causa probable                  | Acción recomendada                                                               |
| --------------------------------------- | ------------------------------- | -------------------------------------------------------------------------------- |
| "Access is denied" al ejecutar `icacls` | Falta de privilegios            | Ejecutar la consola **como Administrador**.                                      |
| "Invalid parameter /grant\:r"           | Sintaxis de permisos incorrecta | Verifica la columna **Permisos** en el CSV (mayúsculas, paréntesis, dos puntos). |
| Rollback falla "file not found"         | Ruta errónea al backup          | Usa la ruta completa al archivo `.txt` generado.                                 |
