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
| `Orden_update_tipoCita` | `@IdOrden BigInt` | **No modificado** | `f4f3030` original |

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

Detalles comunes del patrón: se usa `RETURN 0` (sin `RAISERROR` ni `THROW`, para que la plataforma no
registre un error) y `= 141` dentro de un `EXISTS` (no `!= 141`), así los viajes con `IdOperacion` NULL
siguen ejecutándose.

## 4. SP no modificado: `Orden_update_tipoCita` — mal configurado

Archivo: `SP/Orden_update_tipoCita.sql` (solo la versión original, sin cambios)

- Está vinculado al **proceso Id836**.
- **Está mal configurado:** al igual que los otros SP, está implementado a nivel general para todas las
  operaciones y no debería ser así.
- El SP no tiene ningún filtro por operación: actualiza `Orden.IdTipoCita` a `13` (si `Tipo = 'D'`) o a
  `14` (si `Tipo = 'P'`) cuando `IdDepositoLlegada = 17`, para cualquier orden que reciba.
- **No se modifica.** Además, recibe `@IdOrden` y no `@IdViaje`, y no está confirmado cómo se relaciona
  `Orden` con `Viaje`/`Jornada`, por lo que el patrón de la operación 141 no se le aplicó.
- **Recomendación:** corregir la configuración del proceso Id836 para acotarla por operación, en lugar de
  modificar el SP.

## 5. Pruebas pendientes (a ejecutar en la base)

Para `Z_SP_YPF_SetDatosViaje` y `Arenas_ActualizarDatosViaje`:

| Caso | Resultado esperado |
|---|---|
| Viaje de la operación 141 | No cambia nada, no devuelve resultados, no da error. `SetDatosViaje` no inserta en `Log`. |
| Viaje de otra operación | Se comporta igual que antes del cambio. |
| Viaje cuya jornada tiene `IdOperacion` NULL | Se sigue ejecutando como antes. |
