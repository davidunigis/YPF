# Reporte de cambios — Rama LP-Solidas

- **Fecha:** 07/10/2026
- **Autor de los cambios:** David de la Cruz
- **Base de datos:** `UNIGIS_DataRepository_YPF`
- **Objetivo:** que ciertos SP **no se ejecuten** para viajes cuya jornada pertenece a la operación **141**
  (`Viaje.IdJornada → Jornada.IdJornada → Jornada.IdOperacion = 141`), y que para el resto de las
  operaciones sigan funcionando igual.

## 1. Resumen

| SP | Parámetro | Estado | Commits |
|---|---|---|---|
| `Z_SP_YPF_SetDatosViaje` | `@IdViaje BIGINT` | Modificado | `e27e41e` original · `a7a52b9` regla · `1daf441` comentario |
| `Arenas_ActualizarDatosViaje` | `@IdViaje INT` | Modificado | `3242d3e` original · `355c408` regla |
| `Z_SP_YPF_TransicionesOrden` | `@IdOrden BIGINT` | Modificado | `3ea8a10` original · `4d1f7f2` regla y comentario |
| `Z_SP_YPF_SetDatosOT` | `@IdOrden BigInt` | Modificado | `028aa50` original · `82fe504` regla y comentario |
| `Orden_update_tipoCita` | `@IdOrden BigInt` | **No modificado** | `f4f3030` original |

Además, el informe documenta los procesos de la plataforma ligados a los SP modificados (el 352 en la
sección 3.3 y el 351 en la 3.4) y deja comentarios sobre dos configuraciones a nivel general: el proceso
Id836, vinculado a `Orden_update_tipoCita` (sección 4), y el proceso 376, que invoca
`SincronizarEstadoRuta_DesdeOrdenes`. Este último queda en **pendientes por modificar** (sección 5).

Los cambios **no se ejecutaron contra SQL Server** desde este repositorio. Para que rijan hay que ejecutar
cada `ALTER PROCEDURE` en `UNIGIS_DataRepository_YPF` y probarlos (ver sección 5).

## 2. Observación general: configuración a nivel general

Estos SP están implementados **a nivel general, para todas las operaciones**, y no debería ser así.
La salida temprana por operación 141 es la medida acordada para los SP modificados, pero **no corrige
la configuración de fondo**: solo deja fuera a la operación 141 y el resto sigue ejecutándose para todas
las demás operaciones.

## 3. Cambios realizados

### 3.1 `Z_SP_YPF_SetDatosViaje`

Archivo: `SP/Z_SP_YPF_SetDatosViaje.sql`

- Se agregó como primera instrucción del SP, antes del `BEGIN TRY`:
  - `SET NOCOUNT ON;`
  - `IF EXISTS (… Viaje JOIN Jornada … WHERE Viaje.IdViaje = @IdViaje AND Jornada.IdOperacion = 141) RETURN 0;`
- Se agregó un comentario dentro del SP con fecha y autor (07/10/2026, David de la Cruz).
- La lógica original no cambió.
- **Efecto en la 141:** no ejecuta nada. Antes igual insertaba un registro `'OK IdViaje=...'` en `Log`
  (aunque no llamaba a `Z_SP_YPF_SetDatosViajeLP`, porque la 141 no está en `(2,3,4,5,6)`). Ahora **no
  deja ninguna fila en `Log`**.
- **Efecto en el resto:** sin cambios.

### 3.2 `Arenas_ActualizarDatosViaje`

Archivo: `SP/Arenas_ActualizarDatosViaje.sql`

- Se agregó, justo después del `SET NOCOUNT ON;` que ya tenía, el mismo `IF EXISTS … RETURN 0;`.
- Se agregó un comentario dentro del SP con fecha y autor (07/10/2026, David de la Cruz).
- La lógica original no cambió.
- **Efecto en la 141:** no se actualizan en `Viaje` los campos `IdDepositoSalida`, `IdDepositoLlegada`,
  `Origen` ni `Peso`. Si algo depende de que se llenen en la 141, hay que cubrirlo por otro lado.
- **Efecto en el resto:** sin cambios.

### 3.3 `Z_SP_YPF_TransicionesOrden`

Archivo: `SP/Z_SP_YPF_TransicionesOrden.sql`

- Este SP recibe `@IdOrden`, así que la validación se hace directo sobre `Orden.IdOperacion` (no pasa por
  `Viaje`/`Jornada`). Se agregó como primera instrucción, antes del `BEGIN TRY`:
  - `SET NOCOUNT ON;`
  - `IF EXISTS (SELECT 1 FROM Orden WITH (NOLOCK) WHERE IdOrden = @IdOrden AND IdOperacion = 141) RETURN 0;`
- Se agregó un comentario dentro del SP con fecha y autor (07/10/2026, David de la Cruz).
- La lógica original no cambió.
- **Efecto en la 141:** no ejecuta nada. No se actualiza `Pack.IdEstadoPack`, no se llama a
  `Z_SP_YPF_SyncPedidoPack` y no se inserta registro en `Log` (antes se insertaba `'OK IdOrden=...'`).
- **Efecto en el resto:** sin cambios.
- Nota: el script original llegó en una sola línea; para el commit "original" se restauraron los saltos de
  línea según su indentación, sin modificar ninguna instrucción.

**Proceso vinculado: 352** — `LP|Pedido|Actualiza estado segun estados de pack`

- **Entidad:** `Orden`
- **SQL que ejecuta:** `Z_SP_YPF_TransicionesOrden [Orden.IdOrden]`
- **Condición dinámica:** `[Orden.IdOperacion] <> 141`
- **Todas las transiciones:** sí (`TodasLasTransiciones = 1`, `IdTransicion` NULL)
- **Operación del proceso:** NULL (`IdOperacion`); no está ligado a una operación específica
- **Otros valores:** Pre 0 · Post 1 · Distribuido 1 · Sincrónico 0 · Transaccional 0 · ReloadEntity 1

**Observación:** el proceso aplica a todas las transiciones y no está acotado a una operación; solo deja
fuera a la 141 mediante su condición dinámica. Esto coincide con la observación general de la sección 2. La
condición del proceso ya excluye la 141; la salida temprana dentro del SP es una segunda validación,
independiente de la configuración del proceso.

### 3.4 `Z_SP_YPF_SetDatosOT`

Archivo: `SP/Z_SP_YPF_SetDatosOT.sql`

- Recibe `@IdOrden`, así que la validación se hace directo sobre `Orden.IdOperacion`. Se agregó antes del
  `Begin Try`, con el estilo de escritura propio de este SP:
  - `Set NoCount On;`
  - `If Exists (Select 1 From Orden With(NoLock) Where IdOrden = @IdOrden And IdOperacion = 141) Return 0;`
- Se agregó un comentario dentro del SP con fecha y autor (07/10/2026, David de la Cruz).
- La lógica original no cambió.
- **Efecto en la 141:** no ejecuta nada. No se asigna el depósito de salida, no se completan domicilios ni
  campos dinámicos (UDT, CECOS, `NegocioComex`), no se pasan a estado de revisión los `OrdenItem`
  (estado 4) ni la `Orden` (estado 61), no se cargan elementos requeridos ni tipo de vehículo sugerido, no
  se ajusta `FechaEntrega`, no se actualiza línea/sublínea de `Producto` y no se inserta registro en `Log`.
- **Efecto en el resto:** sin cambios.

**Proceso vinculado: 351** — `LP|OT|Actualiza Datos en Creacion`

- **Entidad:** `Orden`
- **SQL que ejecuta:** `EXEC Z_SP_YPF_SetDatosOT [Orden.IdOrden]`
- **Condición dinámica:** `[Orden.IdOperacion] <> 141`
- **Todas las transiciones:** no (`TodasLasTransiciones = 0`, `IdTransicion = 0`)
- **Operación del proceso:** NULL (`IdOperacion`); no está ligado a una operación específica
- **ContinueWith:** 653
- **Otros valores:** Pre 0 · Post 1 · Distribuido 0 · Sincrónico 1 · Transaccional 0 · ReloadEntity 1

**Observación:** a diferencia de los procesos 352 y 376, este no está configurado para todas las
transiciones (`TodasLasTransiciones = 0`), pero tampoco está acotado a una operación; solo deja fuera a la
141 mediante su condición dinámica. La condición del proceso ya excluye la 141; la salida temprana dentro
del SP es una segunda validación, independiente de la configuración del proceso. El proceso encadena con el
proceso 653 (`ContinueWith`), cuya definición no forma parte de este informe.

Detalles comunes del patrón (aplican a los cuatro SP modificados): se usa `RETURN 0` (sin `RAISERROR` ni `THROW`, para que la plataforma no
registre un error) y `= 141` dentro de un `EXISTS` (no `!= 141`), así los viajes con `IdOperacion` NULL
siguen ejecutándose.

## 4. SP no modificado: `Orden_update_tipoCita` — mal configurado

Archivo: `SP/Orden_update_tipoCita.sql` (solo la versión original, sin cambios)

- Está vinculado al **proceso Id836**.
- **Está mal configurado:** al igual que los otros SP, está implementado a nivel general para todas las
  operaciones y no debería ser así.
- El SP no tiene ningún filtro por operación: actualiza `Orden.IdTipoCita` a `13` (si `Tipo = 'D'`) o a
  `14` (si `Tipo = 'P'`) cuando `IdDepositoLlegada = 17`, para cualquier orden que reciba.
- **No se modifica**, y el patrón de la operación 141 no se le aplicó.
- **Recomendación:** corregir la configuración del proceso Id836 para acotarla por operación, en lugar de
  modificar el SP.

## 5. Pendientes por modificar

Elementos que quedan por modificar más adelante y que **no bloquean** este frente.

### 5.1 Proceso 376

Proceso de la plataforma que invoca el SP `SincronizarEstadoRuta_DesdeOrdenes`. Ese SP **no está en este
repositorio y no se modificó**.

- **Id:** 376
- **Nombre:** `LP|Ruta|Cambia Estado de Ruta desde Ordenes`
- **SP:** `SincronizarEstadoRuta_DesdeOrdenes`
- **Entidad:** `Orden`
- **Condición configurada:** `[Orden.IdOperacion] <> 141`
- **Parámetros:** `70|2|1`
- **Todas las transiciones:** sí (`TodasLasTransiciones = 1`, `IdTransicion` NULL)

**Observación:** el proceso está aplicando a **todas las transiciones de todas las operaciones**. La
condición configurada solo excluye la operación 141; para el resto, el proceso corre en cualquier
transición.

**Estado:** **pendiente por modificar** (acotarlo por operación y transición), **no bloqueante** para este
frente. Los demás campos de la configuración del proceso no se interpretan en este informe.

## 6. Pruebas pendientes (a ejecutar en la base)

Para `Z_SP_YPF_SetDatosViaje` y `Arenas_ActualizarDatosViaje`:

| Caso | Resultado esperado |
|---|---|
| Viaje de la operación 141 | No cambia nada, no devuelve resultados, no da error. `SetDatosViaje` no inserta en `Log`. |
| Viaje de otra operación | Se comporta igual que antes del cambio. |
| Viaje cuya jornada tiene `IdOperacion` NULL | Se sigue ejecutando como antes. |

Para `Z_SP_YPF_TransicionesOrden`:

| Caso | Resultado esperado |
|---|---|
| Orden con `IdOperacion = 141` | No cambia nada (ni `Pack`, ni `Z_SP_YPF_SyncPedidoPack`), no da error y no inserta en `Log`. |
| Orden de otra operación | Se comporta igual que antes del cambio. |
| Orden con `IdOperacion` NULL | Se sigue ejecutando como antes. |

Para `Z_SP_YPF_SetDatosOT`:

| Caso | Resultado esperado |
|---|---|
| Orden con `IdOperacion = 141` | No cambia nada (depósito, domicilios, campos dinámicos, estados, etc.), no da error y no inserta en `Log`. |
| Orden de otra operación | Se comporta igual que antes del cambio. |
| Orden con `IdOperacion` NULL | Se sigue ejecutando como antes. |
