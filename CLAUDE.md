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
- [ ] `Z_SP_YPF_SetDatosViaje` — primer SP identificado; aplicar el patrón de salida temprana.
- (agregar aquí los demás SP conforme se vayan subiendo a `SP/`)

## Forma de trabajo
- Antes de modificar un SP, subir primero su versión actual tal cual (commit "original"),
  y luego el cambio en otro commit, para que el diff muestre solo lo agregado.
- No alterar la lógica existente del SP más allá de la regla solicitada.
- Comunicación en español.
