# Rama LP-Solidas — contexto para Claude Code

Repositorio de consultas, SP y reportes de UNIGIS para YPF (SQL Server / T-SQL).
En esta rama se agrupan los SP que se van a modificar para el frente **LP Solidas**.

## Estructura
- `SP/` — un archivo `.sql` por procedimiento, con el nombre exacto del SP
  (ej. `SP/Z_SP_YPF_SetDatosViaje.sql`). Cada archivo contiene el `ALTER PROCEDURE` completo.

## Regla en curso: excluir la operación 141

Objetivo: ciertos SP **no deben ejecutarse** para viajes cuya jornada pertenezca a
`IdOperacion = 141`. Para el resto de operaciones deben seguir funcionando igual.

La relación es `Viaje.IdJornada -> Jornada.IdJornada -> Jornada.IdOperacion`.

### Patrón acordado: salida temprana dentro del SP

La validación va como **primera instrucción** del SP, antes de cualquier `BEGIN TRAN`,
`INSERT`, `UPDATE` o `SELECT` que devuelva datos, para que la ejecución quede anulada por
completo (sin cambios, sin resultados, sin error):

```sql
ALTER PROCEDURE [dbo].[NombreDelSP]
    @IdViaje INT   -- respetar nombre y tipo reales del parámetro
AS
BEGIN
    SET NOCOUNT ON;

    -- Salida inmediata para viajes de la operación 141
    IF EXISTS (
        SELECT 1
        FROM Viaje
            JOIN Jornada ON Viaje.IdJornada = Jornada.IdJornada
        WHERE Viaje.IdViaje = @IdViaje
          AND Jornada.IdOperacion = 141
    )
        RETURN 0;

    -- ... cuerpo original del SP, sin cambios ...
END
```

Reglas del patrón:
- Usar `RETURN 0`, **no** `RAISERROR` ni `THROW` (la plataforma lo registraría como error).
- `SET NOCOUNT ON` para que no salgan mensajes de filas afectadas.
- Usar `= 141` con `EXISTS` (no `!= 141`), así los viajes con `IdOperacion` NULL siguen ejecutándose.
- Si la condición solo puede evaluarse a mitad del SP, después de hacer cambios, envolver el
  cuerpo en transacción y hacer `ROLLBACK` antes del `RETURN`.

### Variante para SP que reciben `@IdOrden`

`Orden` tiene `IdOperacion` propio, así que no hace falta pasar por `Viaje`/`Jornada`:

```sql
IF EXISTS (
    SELECT 1
    FROM Orden WITH (NOLOCK)
    WHERE IdOrden = @IdOrden
      AND IdOperacion = 141
)
    RETURN 0;
```

### Alternativa desde la llamada en la plataforma

En la configuración de UNIGIS el SP se invoca con el placeholder `[Viaje.IdViaje]`, que la
plataforma reemplaza en todas sus apariciones. Si se prefiere filtrar en la llamada y no en el SP:

```sql
DECLARE @IdViaje INT = [Viaje.IdViaje];

IF NOT EXISTS (
    SELECT 1
    FROM Viaje
        JOIN Jornada ON Viaje.IdJornada = Jornada.IdJornada
    WHERE Viaje.IdViaje = @IdViaje
      AND Jornada.IdOperacion = 141
)
    EXEC [dbo].[Z_SP_YPF_SetDatosViaje] @IdViaje;
```

## SP en alcance
- [ ] `Z_SP_YPF_SetDatosViaje` — salida temprana aplicada (07/10/2026); pendiente de probar en la base.
- [ ] `Arenas_ActualizarDatosViaje` — salida temprana aplicada (07/10/2026); pendiente de probar en la base.
- [ ] `Z_SP_YPF_TransicionesOrden` — salida temprana aplicada (07/10/2026) sobre `Orden.IdOperacion = 141`; pendiente de probar en la base. Ligado al proceso 352.
- [x] `Orden_update_tipoCita` — **NO se modifica**. Solo se subió el original. Ver "Hallazgos para el informe".
- (agregar aquí los demás SP conforme se vayan subiendo a `SP/`)

## Hallazgos para el informe
Se pidió generar un **reporte de cambios** de esta rama (`REPORTE_CAMBIOS.md`); mantenerlo actualizado
cuando se agreguen más SP.

- Según David de la Cruz, estos SP están implementados **a nivel general para todas las operaciones**
  y no debería ser así. La salida temprana por operación 141 es la medida acordada para los SP
  modificados, pero no corrige esa configuración de fondo.
- `Orden_update_tipoCita` (recibe `@IdOrden`) está vinculado al **proceso Id836**. No se modifica, y el
  informe debe indicar expresamente que **está mal configurado** (aplica a todas las operaciones).
  Tampoco se le aplicó el patrón.
- `Z_SP_YPF_TransicionesOrden` está ligado al proceso **352** `LP|Pedido|Actualiza estado segun estados de pack`
  (entidad `Orden`, condición `[Orden.IdOperacion] <> 141`, `TodasLasTransiciones = 1`, `IdOperacion` NULL).
  El proceso ya excluye la 141 por condición y aplica a todas las transiciones; la salida temprana en el SP
  es una segunda validación. Va comentado en el informe (3.3).

## Pendientes por modificar (no bloqueantes)
- [ ] Proceso **376** `LP|Ruta|Cambia Estado de Ruta desde Ordenes` (SP `SincronizarEstadoRuta_DesdeOrdenes`,
  entidad `Orden`, condición `[Orden.IdOperacion] <> 141`): según David de la Cruz aplica a **todas las
  transiciones de todas las operaciones**. Va comentado en el informe (sección 5). El SP no está en el
  repo y no se modifica por ahora.

## Forma de trabajo
- Antes de modificar un SP, subir primero su versión actual tal cual (commit "original"),
  y luego el cambio en otro commit, para que el diff muestre solo lo agregado.
- No alterar la lógica existente del SP más allá de la regla solicitada.
- Comunicación en español.
