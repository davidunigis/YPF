/*==============================================================================================
  Eliminar_Operacion_141_Secuencia.sql

  Borra la operacion @IdOperacion (rutas, jornadas, viajes, paradas, ordenes, pedidos y lo que
  cuelga de ellos) con una lista FIJA de DELETE, de arriba hacia abajo.

  COMO USARLO
    1) Dejar @Ejecutar = 0 y correr: ejecuta toda la lista dentro de una transaccion y al final
       hace ROLLBACK (no cambia nada). Muestra cuantas filas borra cada paso. Si algun paso choca
       con una foreign key, se corta con el error y se hace ROLLBACK.
    2) Con @Ejecutar = 1 se repite y se hace COMMIT.
    Se puede volver a correr las veces que haga falta: los DELETE que ya se aplicaron afectan 0
    filas. Sirve para terminar un borrado que quedo a medias por haber corrido los DELETE sueltos
    (sin transaccion cada DELETE se confirma por separado y el lote sigue aunque otro falle).

  NOTA SOBRE EL ORDEN
    No es el orden de la lista original: se reordeno para respetar las foreign keys REALES de la
    base, que dieron estos errores 547 con la lista original (hijo -> padre; el hijo se borra antes):
      - FK_OrdenItem_PedidoItem : OrdenItem.IdPedidoItem -> PedidoItem   (PedidoItem despues de OrdenItem)
      - FK_Orden_Pedido         : Orden.IdPedido         -> Pedido       (Pedido despues de Orden)
      - FK_Viaje_Ruta           : Viaje.IdRutaFK         -> Ruta         (Ruta despues de Viaje)
      - FK_Orden_OrdenParada    : Orden.IdOrdenParada    -> OrdenParada  (OrdenParada despues de Orden)
      - FK_Parada_Orden         : Parada.IdOrden         -> Orden        (Orden despues de Parada)
      - FK_Orden_Jornada        : Orden.IdJornada        -> Jornada      (Jornada despues de Orden)
      - FK_RutaTraceEstado_Ruta : RutaTraceEstado.IdRuta -> Ruta         (RutaTraceEstado antes de Ruta; se agrego a la lista)
      - FK_PedidoTraceEstado_OrdenTraceEstado : PedidoTraceEstado.IdOrdenTraceEstado -> OrdenTraceEstado
                                                 (PedidoTraceEstado antes de OrdenTraceEstado)
    Jornada va ademas AL FINAL porque los pasos de viaje/parada/ruta ubican sus filas con
    "... FROM Jornada WHERE IdOperacion = ...": si Jornada se borrara antes, esas subconsultas no
    devolverian nada y esos pasos no borrarian nada.
    Orden resultante: viajes y paradas -> ordenes -> pedidos -> rutas/OrdenParada -> Jornada.

  DIAGNOSTICO (solo lectura, al empezar)
    Antes de borrar busca las tablas con foreign key hacia las de esta lista que NO figuran en ella y
    que tienen filas apuntando a lo que se va a borrar (resultado "Tablas FUERA de la lista"). Cada una
    haria fallar su paso con el error 547: agregar su DELETE a la lista (antes de la tabla a la que
    apunta) y volver a correr. Cubre las FK de una sola columna; las de varias columnas se informan
    como "no verificada".
    Ademas revisa las FK ENTRE las tablas de la lista (resultado "Problemas de orden o cobertura"):
      - ORDEN: la tabla hija se borra en un paso POSTERIOR al de su tabla padre. Mover el DELETE de la
        hija antes que el de la padre.
      - COBERTURA: hay filas de la hija que apuntan a lo que se va a borrar en la padre y que ningun
        DELETE de la hija alcanza; bloquean el borrado sin importar el orden. Ampliar el DELETE de la hija
        o revisar esos datos (columna Filas = cuantas son).

  LIMITES
    - Solo borra lo que esta en la lista. Una tabla que dependa de estas y no figure aqui hace
      fallar el paso que choca con ella (si tiene FK) o queda con filas huerfanas (si no la tiene).
      Para descubrir dependencias automaticamente existe Eliminar_Operacion_141.sql.
    - Un pedido de la operacion que tambien usa una orden de otra operacion hace fallar el borrado
      de Pedido (FK_Orden_Pedido) y revierte todo.
    - Todo corre en UNA transaccion: con muchos millones de filas puede crecer mucho el log y
      bloquear tablas. Correr en ventana de mantenimiento.
==============================================================================================*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @IdOperacion INT = 141;
DECLARE @Ejecutar    BIT = 0;   -- 0 = simulacion (ROLLBACK al final) | 1 = borrado real (COMMIT)

DECLARE @Log  TABLE (Paso INT, Tabla NVARCHAR(200), Filas BIGINT);
DECLARE @Paso NVARCHAR(200);

-- DIAGNOSTICO (solo lectura): tablas con FK hacia las de la lista que NO estan en ella y tienen filas por borrar
BEGIN TRY
    DECLARE @Cub TABLE (Tabla SYSNAME PRIMARY KEY, Pred NVARCHAR(MAX));
    INSERT @Cub (Tabla, Pred) VALUES
        (N'ViajeAgrupadorViaje', N'IdViaje IN (SELECT IdViaje FROM Viaje WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion))'),
        (N'Alarma', N'IdParada IN (SELECT IdParada FROM Parada WHERE IdViaje IN (SELECT IdViaje FROM Viaje WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion)))'),
        (N'ParadaTraceEstado', N'IdParada IN (SELECT IdParada FROM Parada WHERE IdViaje IN (SELECT IdViaje FROM Viaje WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion)))'),
        (N'BitacoraParada', N'IdParada IN (SELECT IdParada FROM Parada WHERE IdViaje IN (SELECT IdViaje FROM Viaje WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion)))'),
        (N'ParadaItemCantidad', N'IdParadaItem IN (SELECT IdParadaItem FROM ParadaItem WHERE IdParada IN (SELECT IdParada FROM Parada WHERE IdViaje IN (SELECT IdViaje FROM Viaje WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion))))'),
        (N'ParadaItem_Dyn', N'IdParadaItem IN (SELECT IdParadaItem FROM ParadaItem WHERE IdParada IN (SELECT IdParada FROM Parada WHERE IdViaje IN (SELECT IdViaje FROM Viaje WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion))))'),
        (N'ParadaItem', N'IdParada IN (SELECT IdParada FROM Parada WHERE IdViaje IN (SELECT IdViaje FROM Viaje WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion)))'),
        (N'EstadiaParada', N'IdParada IN (SELECT IdParada FROM Parada WHERE IdViaje IN (SELECT IdViaje FROM Viaje WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion)))'),
        (N'Parada', N'IdViaje IN (SELECT IdViaje FROM Viaje WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion))'),
        (N'ViajeRecurso', N'IdViaje IN (SELECT IdViaje FROM Viaje WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion))'),
        (N'BitacoraViaje', N'IdViaje IN (SELECT IdViaje FROM Viaje WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion))'),
        (N'GuiaViaje', N'IdViaje IN (SELECT IdViaje FROM Viaje WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion))'),
        (N'EstadoViajeTraceEstado', N'IdViaje IN (SELECT IdViaje FROM Viaje WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion))'),
        (N'ConceptoValorizadoGuia', N'IdViaje IN (SELECT IdViaje FROM Viaje WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion))'),
        (N'Viaje', N'IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion)'),
        (N'OrdenTrayecto', N'(IdOrdenOrigen IN (SELECT IdOrden FROM Orden WHERE IdOperacion = @IdOperacion)) OR (IdOrdenDestino IN (SELECT IdOrden FROM Orden WHERE IdOperacion = @IdOperacion))'),
        (N'PedidoTraceEstado', N'IdPedido IN (SELECT IdPedido FROM Pedido WHERE IdOperacion = @IdOperacion)'),
        (N'OrdenTraceEstado', N'IdOrden IN (SELECT IdOrden FROM Orden WHERE IdOperacion = @IdOperacion)'),
        (N'OrdenPedido', N'(IdPedido IN (SELECT IdPedido FROM Pedido WHERE IdOperacion = @IdOperacion)) OR (IdOrden IN (SELECT IdOrden FROM Orden WHERE IdOperacion = @IdOperacion))'),
        (N'BitacoraOrden', N'IdOrden IN (SELECT IdOrden FROM Orden WHERE IdOperacion = @IdOperacion)'),
        (N'OrdenItemOT', N'IdOrdenItem IN (SELECT IdOrdenItem FROM OrdenItem WHERE IdOrden IN (SELECT IdOrden FROM Orden WHERE IdOperacion = @IdOperacion))'),
        (N'OrdenItemPedidoItem', N'(IdPedidoItem IN (SELECT IdPedidoItem FROM PedidoItem WHERE IdPedido IN (SELECT IdPedido FROM Pedido WHERE IdOperacion = @IdOperacion))) OR (IdOrdenItem IN (SELECT IdOrdenItem FROM OrdenItem WHERE IdOrden IN (SELECT IdOrden FROM Orden WHERE IdOperacion = @IdOperacion)))'),
        (N'OrdenItem_Dyn', N'IdOrdenItem IN (SELECT IdOrdenItem FROM OrdenItem WHERE IdOrden IN (SELECT IdOrden FROM Orden WHERE IdOperacion = @IdOperacion))'),
        (N'OrdenItem', N'IdOrden IN (SELECT IdOrden FROM Orden WHERE IdOperacion = @IdOperacion)'),
        (N'Orden_Dyn', N'IdOrden IN (SELECT IdOrden FROM Orden WHERE IdOperacion = @IdOperacion)'),
        (N'Orden', N'IdOperacion = @IdOperacion'),
        (N'PedidoItem_Dyn', N'IdPedidoItem IN (SELECT IdPedidoItem FROM PedidoItem WHERE IdPedido IN (SELECT IdPedido FROM Pedido WHERE IdOperacion = @IdOperacion))'),
        (N'PedidoItem', N'IdPedido IN (SELECT IdPedido FROM Pedido WHERE IdOperacion = @IdOperacion)'),
        (N'Pedido_Dyn', N'IdPedido IN (SELECT IdPedido FROM Pedido WHERE IdOperacion = @IdOperacion)'),
        (N'BitacoraPedido', N'IdPedido IN (SELECT IdPedido FROM Pedido WHERE IdOperacion = @IdOperacion)'),
        (N'Pedido', N'IdOperacion = @IdOperacion'),
        (N'BitacoraRuta', N'IdRuta IN (SELECT IdRuta FROM Ruta WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion))'),
        (N'RutaTraceEstado', N'IdRuta IN (SELECT IdRuta FROM Ruta WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion))'),
        (N'Ruta', N'IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion)'),
        (N'OrdenParada', N'IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion)'),
        (N'BitacoraJornada', N'IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion)'),
        (N'Jornada', N'IdOperacion = @IdOperacion')
    ;

    DECLARE @Falta TABLE (FK SYSNAME, TablaHija NVARCHAR(300), ApuntaA SYSNAME, Filas BIGINT NULL);
    DECLARE @dfk SYSNAME, @dh NVARCHAR(300), @dp SYSNAME, @dsql NVARCHAR(MAX), @dn BIGINT;

    DECLARE dcur CURSOR LOCAL FAST_FORWARD FOR
        SELECT fk.name,
               QUOTENAME(OBJECT_SCHEMA_NAME(fk.parent_object_id)) + N'.' + QUOTENAME(OBJECT_NAME(fk.parent_object_id)),
               OBJECT_NAME(fk.referenced_object_id),
               CASE WHEN k.N = 1
                    THEN N'SELECT @n = COUNT_BIG(*) FROM ' + QUOTENAME(OBJECT_SCHEMA_NAME(fk.parent_object_id)) + N'.' + QUOTENAME(OBJECT_NAME(fk.parent_object_id))
                       + N' WHERE ' + QUOTENAME(COL_NAME(fk.parent_object_id, k.PCol)) + N' IN (SELECT ' + QUOTENAME(COL_NAME(fk.referenced_object_id, k.RCol))
                       + N' FROM ' + QUOTENAME(OBJECT_SCHEMA_NAME(fk.referenced_object_id)) + N'.' + QUOTENAME(OBJECT_NAME(fk.referenced_object_id)) + N' WHERE ' + c.Pred + N')'
               END
        FROM sys.foreign_keys fk
        JOIN @Cub c ON c.Tabla = OBJECT_NAME(fk.referenced_object_id)
        CROSS APPLY (SELECT COUNT(*) AS N, MIN(parent_column_id) AS PCol, MIN(referenced_column_id) AS RCol
                     FROM sys.foreign_key_columns WHERE constraint_object_id = fk.object_id) k
        WHERE NOT EXISTS (SELECT 1 FROM @Cub h WHERE h.Tabla = OBJECT_NAME(fk.parent_object_id));

    OPEN dcur;
    FETCH NEXT FROM dcur INTO @dfk, @dh, @dp, @dsql;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF @dsql IS NULL
            INSERT @Falta VALUES (@dfk, @dh, @dp, NULL);                    -- FK de varias columnas: no verificada
        ELSE
        BEGIN
            SET @dn = 0;
            EXEC sp_executesql @dsql, N'@n BIGINT OUTPUT, @IdOperacion INT', @n = @dn OUTPUT, @IdOperacion = @IdOperacion;
            IF @dn > 0 INSERT @Falta VALUES (@dfk, @dh, @dp, @dn);
        END
        FETCH NEXT FROM dcur INTO @dfk, @dh, @dp, @dsql;
    END
    CLOSE dcur; DEALLOCATE dcur;

    IF EXISTS (SELECT 1 FROM @Falta)
    BEGIN
        PRINT N'*** ATENCION: hay tablas FUERA de la lista con filas que dependen de lo que se va a borrar (resultado "Tablas FUERA de la lista").';
        PRINT N'    Agregar su DELETE a la lista (antes de la tabla a la que apuntan) o el borrado fallara con el error 547.';
        SELECT [Tablas FUERA de la lista] = TablaHija, FK, ApuntaA, Filas = ISNULL(CAST(Filas AS VARCHAR(20)), 'no verificada') FROM @Falta ORDER BY ApuntaA, TablaHija;
    END
    ELSE PRINT N'Diagnostico: no se encontraron tablas fuera de la lista con filas que bloqueen el borrado.';
END TRY
BEGIN CATCH
    PRINT N'No se pudo ejecutar el diagnostico (el borrado sigue): ' + ERROR_MESSAGE();
END CATCH


-- DIAGNOSTICO B (solo lectura): FK entre tablas de la lista -> orden de borrado y filas sin cubrir
BEGIN TRY
    DECLARE @Pasos TABLE (Paso INT PRIMARY KEY, Tabla SYSNAME, Col SYSNAME);
    INSERT @Pasos (Paso, Tabla, Col) VALUES
        (1, N'ViajeAgrupadorViaje', N'IdViaje'),
        (2, N'Alarma', N'IdParada'),
        (3, N'ParadaTraceEstado', N'IdParada'),
        (4, N'BitacoraParada', N'IdParada'),
        (5, N'ParadaItemCantidad', N'IdParadaItem'),
        (6, N'ParadaItem_Dyn', N'IdParadaItem'),
        (7, N'ParadaItem', N'IdParada'),
        (8, N'EstadiaParada', N'IdParada'),
        (9, N'Parada', N'IdViaje'),
        (10, N'ViajeRecurso', N'IdViaje'),
        (11, N'BitacoraViaje', N'IdViaje'),
        (12, N'GuiaViaje', N'IdViaje'),
        (13, N'EstadoViajeTraceEstado', N'IdViaje'),
        (14, N'ConceptoValorizadoGuia', N'IdViaje'),
        (15, N'Viaje', N'IdJornada'),
        (16, N'OrdenTrayecto', N'IdOrdenOrigen'),
        (17, N'OrdenTrayecto', N'IdOrdenDestino'),
        (18, N'PedidoTraceEstado', N'IdPedido'),
        (19, N'OrdenTraceEstado', N'IdOrden'),
        (20, N'OrdenPedido', N'IdOrden'),
        (21, N'BitacoraOrden', N'IdOrden'),
        (22, N'OrdenItemOT', N'IdOrdenItem'),
        (23, N'OrdenItemPedidoItem', N'IdOrdenItem'),
        (24, N'OrdenItem_Dyn', N'IdOrdenItem'),
        (25, N'OrdenItem', N'IdOrden'),
        (26, N'Orden_Dyn', N'IdOrden'),
        (27, N'Orden', N'IdOperacion'),
        (28, N'OrdenPedido', N'IdPedido'),
        (29, N'OrdenItemPedidoItem', N'IdPedidoItem'),
        (30, N'PedidoItem_Dyn', N'IdPedidoItem'),
        (31, N'PedidoItem', N'IdPedido'),
        (32, N'Pedido_Dyn', N'IdPedido'),
        (33, N'BitacoraPedido', N'IdPedido'),
        (34, N'Pedido', N'IdOperacion'),
        (35, N'BitacoraRuta', N'IdRuta'),
        (36, N'RutaTraceEstado', N'IdRuta'),
        (37, N'Ruta', N'IdJornada'),
        (38, N'OrdenParada', N'IdJornada'),
        (39, N'BitacoraJornada', N'IdJornada'),
        (40, N'Jornada', N'IdOperacion')
    ;

    DECLARE @Prob TABLE (Problema VARCHAR(10), FK SYSNAME, TablaHija SYSNAME, PasoHija INT, ApuntaA SYSNAME, PasoPadre INT, Filas BIGINT NULL);
    DECLARE @bfk SYSNAME, @bh SYSNAME, @bp SYSNAME, @bhp INT, @bpp INT, @bsql NVARCHAR(MAX), @bn BIGINT;

    DECLARE bcur CURSOR LOCAL FAST_FORWARD FOR
        SELECT fk.name, ch.Tabla, pa.Tabla,
               ISNULL((SELECT MAX(Paso) FROM @Pasos WHERE Tabla = ch.Tabla AND Col = COL_NAME(fk.parent_object_id, k.PCol)),
                      (SELECT MAX(Paso) FROM @Pasos WHERE Tabla = ch.Tabla)),
               (SELECT MIN(Paso) FROM @Pasos WHERE Tabla = pa.Tabla),
               N'SELECT @n = COUNT_BIG(*) FROM ' + QUOTENAME(OBJECT_SCHEMA_NAME(fk.parent_object_id)) + N'.' + QUOTENAME(ch.Tabla)
             + N' WHERE ' + QUOTENAME(COL_NAME(fk.parent_object_id, k.PCol)) + N' IN (SELECT ' + QUOTENAME(COL_NAME(fk.referenced_object_id, k.RCol))
             + N' FROM ' + QUOTENAME(OBJECT_SCHEMA_NAME(fk.referenced_object_id)) + N'.' + QUOTENAME(pa.Tabla) + N' WHERE ' + pa.Pred + N')'
             + N' AND (CASE WHEN ' + ch.Pred + N' THEN 0 ELSE 1 END) = 1'
        FROM sys.foreign_keys fk
        JOIN @Cub ch ON ch.Tabla = OBJECT_NAME(fk.parent_object_id)
        JOIN @Cub pa ON pa.Tabla = OBJECT_NAME(fk.referenced_object_id)
        CROSS APPLY (SELECT COUNT(*) AS N, MIN(parent_column_id) AS PCol, MIN(referenced_column_id) AS RCol
                     FROM sys.foreign_key_columns WHERE constraint_object_id = fk.object_id) k
        WHERE ch.Tabla <> pa.Tabla AND k.N = 1;             -- solo FK de una columna entre tablas distintas de la lista

    OPEN bcur;
    FETCH NEXT FROM bcur INTO @bfk, @bh, @bp, @bhp, @bpp, @bsql;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF @bhp > @bpp                                       -- la hija se borra DESPUES que la padre
            INSERT @Prob VALUES ('ORDEN', @bfk, @bh, @bhp, @bp, @bpp, NULL);

        SET @bn = 0;                                         -- filas de la hija que apuntan a lo que se borra y ningun DELETE de la hija alcanza
        EXEC sp_executesql @bsql, N'@n BIGINT OUTPUT, @IdOperacion INT', @n = @bn OUTPUT, @IdOperacion = @IdOperacion;
        IF @bn > 0
            INSERT @Prob VALUES ('COBERTURA', @bfk, @bh, @bhp, @bp, @bpp, @bn);

        FETCH NEXT FROM bcur INTO @bfk, @bh, @bp, @bhp, @bpp, @bsql;
    END
    CLOSE bcur; DEALLOCATE bcur;

    IF EXISTS (SELECT 1 FROM @Prob)
    BEGIN
        PRINT N'*** ATENCION: hay FK entre tablas de la lista que el orden actual no respeta o que dejan filas sin cubrir (resultado "Problemas de orden o cobertura").';
        PRINT N'    ORDEN: mover el DELETE de la tabla hija antes que el de la padre. COBERTURA: ampliar el DELETE de la hija o revisar esas filas.';
        SELECT [Problemas de orden o cobertura] = Problema, FK, TablaHija, PasoHija, ApuntaA, PasoPadre, Filas FROM @Prob ORDER BY Problema, PasoHija;
    END
    ELSE PRINT N'Diagnostico: el orden de la lista respeta las FK entre sus tablas y no hay filas sin cubrir.';
END TRY
BEGIN CATCH
    PRINT N'No se pudo ejecutar el diagnostico de orden (el borrado sigue): ' + ERROR_MESSAGE();
END CATCH

BEGIN TRY
    BEGIN TRAN;

    ----- GRUPO 1 - Viajes y paradas (antes que Orden: Parada.IdOrden -> Orden; antes que Ruta: Viaje.IdRutaFK -> Ruta) -----

    -- 1) ViajeAgrupadorViaje (IdViaje)
    SET @Paso = N'1 - ViajeAgrupadorViaje (IdViaje)';
    DELETE FROM ViajeAgrupadorViaje WHERE IdViaje IN (SELECT IdViaje FROM Viaje WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion));
    INSERT @Log (Paso, Tabla, Filas) VALUES (1, N'ViajeAgrupadorViaje (IdViaje)', @@ROWCOUNT);

    -- 2) Alarma (IdParada)
    SET @Paso = N'2 - Alarma (IdParada)';
    DELETE FROM Alarma WHERE IdParada IN (SELECT IdParada FROM Parada WHERE IdViaje IN (SELECT IdViaje FROM Viaje WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion)));
    INSERT @Log (Paso, Tabla, Filas) VALUES (2, N'Alarma (IdParada)', @@ROWCOUNT);

    -- 3) ParadaTraceEstado (IdParada)
    SET @Paso = N'3 - ParadaTraceEstado (IdParada)';
    DELETE FROM ParadaTraceEstado WHERE IdParada IN (SELECT IdParada FROM Parada WHERE IdViaje IN (SELECT IdViaje FROM Viaje WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion)));
    INSERT @Log (Paso, Tabla, Filas) VALUES (3, N'ParadaTraceEstado (IdParada)', @@ROWCOUNT);

    -- 4) BitacoraParada (IdParada)
    SET @Paso = N'4 - BitacoraParada (IdParada)';
    DELETE FROM BitacoraParada WHERE IdParada IN (SELECT IdParada FROM Parada WHERE IdViaje IN (SELECT IdViaje FROM Viaje WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion)));
    INSERT @Log (Paso, Tabla, Filas) VALUES (4, N'BitacoraParada (IdParada)', @@ROWCOUNT);

    -- 5) ParadaItemCantidad (IdParadaItem)
    SET @Paso = N'5 - ParadaItemCantidad (IdParadaItem)';
    DELETE FROM ParadaItemCantidad WHERE IdParadaItem IN (SELECT IdParadaItem FROM ParadaItem WHERE IdParada IN (SELECT IdParada FROM Parada WHERE IdViaje IN (SELECT IdViaje FROM Viaje WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion))));
    INSERT @Log (Paso, Tabla, Filas) VALUES (5, N'ParadaItemCantidad (IdParadaItem)', @@ROWCOUNT);

    -- 6) ParadaItem_Dyn (IdParadaItem)
    SET @Paso = N'6 - ParadaItem_Dyn (IdParadaItem)';
    DELETE FROM ParadaItem_Dyn WHERE IdParadaItem IN (SELECT IdParadaItem FROM ParadaItem WHERE IdParada IN (SELECT IdParada FROM Parada WHERE IdViaje IN (SELECT IdViaje FROM Viaje WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion))));
    INSERT @Log (Paso, Tabla, Filas) VALUES (6, N'ParadaItem_Dyn (IdParadaItem)', @@ROWCOUNT);

    -- 7) ParadaItem (IdParada)
    SET @Paso = N'7 - ParadaItem (IdParada)';
    DELETE FROM ParadaItem WHERE IdParada IN (SELECT IdParada FROM Parada WHERE IdViaje IN (SELECT IdViaje FROM Viaje WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion)));
    INSERT @Log (Paso, Tabla, Filas) VALUES (7, N'ParadaItem (IdParada)', @@ROWCOUNT);

    -- 8) EstadiaParada (IdParada)
    SET @Paso = N'8 - EstadiaParada (IdParada)';
    DELETE FROM EstadiaParada WHERE IdParada IN (SELECT IdParada FROM Parada WHERE IdViaje IN (SELECT IdViaje FROM Viaje WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion)));
    INSERT @Log (Paso, Tabla, Filas) VALUES (8, N'EstadiaParada (IdParada)', @@ROWCOUNT);

    -- 9) Parada (IdViaje)
    SET @Paso = N'9 - Parada (IdViaje)';
    DELETE FROM Parada WHERE IdViaje IN (SELECT IdViaje FROM Viaje WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion));
    INSERT @Log (Paso, Tabla, Filas) VALUES (9, N'Parada (IdViaje)', @@ROWCOUNT);

    -- 10) ViajeRecurso (IdViaje)
    SET @Paso = N'10 - ViajeRecurso (IdViaje)';
    DELETE FROM ViajeRecurso WHERE IdViaje IN (SELECT IdViaje FROM Viaje WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion));
    INSERT @Log (Paso, Tabla, Filas) VALUES (10, N'ViajeRecurso (IdViaje)', @@ROWCOUNT);

    -- 11) BitacoraViaje (IdViaje)
    SET @Paso = N'11 - BitacoraViaje (IdViaje)';
    DELETE FROM BitacoraViaje WHERE IdViaje IN (SELECT IdViaje FROM Viaje WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion));
    INSERT @Log (Paso, Tabla, Filas) VALUES (11, N'BitacoraViaje (IdViaje)', @@ROWCOUNT);

    -- 12) GuiaViaje (IdViaje)
    SET @Paso = N'12 - GuiaViaje (IdViaje)';
    DELETE FROM GuiaViaje WHERE IdViaje IN (SELECT IdViaje FROM Viaje WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion));
    INSERT @Log (Paso, Tabla, Filas) VALUES (12, N'GuiaViaje (IdViaje)', @@ROWCOUNT);

    -- 13) EstadoViajeTraceEstado (IdViaje)
    SET @Paso = N'13 - EstadoViajeTraceEstado (IdViaje)';
    DELETE FROM EstadoViajeTraceEstado WHERE IdViaje IN (SELECT IdViaje FROM Viaje WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion));
    INSERT @Log (Paso, Tabla, Filas) VALUES (13, N'EstadoViajeTraceEstado (IdViaje)', @@ROWCOUNT);

    -- 14) ConceptoValorizadoGuia (IdViaje)
    SET @Paso = N'14 - ConceptoValorizadoGuia (IdViaje)';
    DELETE FROM ConceptoValorizadoGuia WHERE IdViaje IN (SELECT IdViaje FROM Viaje WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion));
    INSERT @Log (Paso, Tabla, Filas) VALUES (14, N'ConceptoValorizadoGuia (IdViaje)', @@ROWCOUNT);

    -- 15) Viaje (IdJornada)
    SET @Paso = N'15 - Viaje (IdJornada)';
    DELETE FROM Viaje WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion);
    INSERT @Log (Paso, Tabla, Filas) VALUES (15, N'Viaje (IdJornada)', @@ROWCOUNT);

    ----- GRUPO 2 - Ordenes (PedidoTraceEstado antes que OrdenTraceEstado: PedidoTraceEstado.IdOrdenTraceEstado -> OrdenTraceEstado; Ordenes antes que Pedido: Orden.IdPedido -> Pedido; antes que OrdenParada y Jornada) -----

    -- 16) OrdenTrayecto (IdOrdenOrigen)
    SET @Paso = N'16 - OrdenTrayecto (IdOrdenOrigen)';
    DELETE FROM OrdenTrayecto WHERE IdOrdenOrigen IN (SELECT IdOrden FROM Orden WHERE IdOperacion = @IdOperacion);
    INSERT @Log (Paso, Tabla, Filas) VALUES (16, N'OrdenTrayecto (IdOrdenOrigen)', @@ROWCOUNT);

    -- 17) OrdenTrayecto (IdOrdenDestino)
    SET @Paso = N'17 - OrdenTrayecto (IdOrdenDestino)';
    DELETE FROM OrdenTrayecto WHERE IdOrdenDestino IN (SELECT IdOrden FROM Orden WHERE IdOperacion = @IdOperacion);
    INSERT @Log (Paso, Tabla, Filas) VALUES (17, N'OrdenTrayecto (IdOrdenDestino)', @@ROWCOUNT);

    -- 18) PedidoTraceEstado (IdPedido)
    SET @Paso = N'18 - PedidoTraceEstado (IdPedido)';
    DELETE FROM PedidoTraceEstado WHERE IdPedido IN (SELECT IdPedido FROM Pedido WHERE IdOperacion = @IdOperacion);
    INSERT @Log (Paso, Tabla, Filas) VALUES (18, N'PedidoTraceEstado (IdPedido)', @@ROWCOUNT);

    -- 19) OrdenTraceEstado (IdOrden)
    SET @Paso = N'19 - OrdenTraceEstado (IdOrden)';
    DELETE FROM OrdenTraceEstado WHERE IdOrden IN (SELECT IdOrden FROM Orden WHERE IdOperacion = @IdOperacion);
    INSERT @Log (Paso, Tabla, Filas) VALUES (19, N'OrdenTraceEstado (IdOrden)', @@ROWCOUNT);

    -- 20) OrdenPedido (IdOrden)
    SET @Paso = N'20 - OrdenPedido (IdOrden)';
    DELETE FROM OrdenPedido WHERE IdOrden IN (SELECT IdOrden FROM Orden WHERE IdOperacion = @IdOperacion);
    INSERT @Log (Paso, Tabla, Filas) VALUES (20, N'OrdenPedido (IdOrden)', @@ROWCOUNT);

    -- 21) BitacoraOrden (IdOrden)
    SET @Paso = N'21 - BitacoraOrden (IdOrden)';
    DELETE FROM BitacoraOrden WHERE IdOrden IN (SELECT IdOrden FROM Orden WHERE IdOperacion = @IdOperacion);
    INSERT @Log (Paso, Tabla, Filas) VALUES (21, N'BitacoraOrden (IdOrden)', @@ROWCOUNT);

    -- 22) OrdenItemOT (IdOrdenItem)
    SET @Paso = N'22 - OrdenItemOT (IdOrdenItem)';
    DELETE FROM OrdenItemOT WHERE IdOrdenItem IN (SELECT IdOrdenItem FROM OrdenItem WHERE IdOrden IN (SELECT IdOrden FROM Orden WHERE IdOperacion = @IdOperacion));
    INSERT @Log (Paso, Tabla, Filas) VALUES (22, N'OrdenItemOT (IdOrdenItem)', @@ROWCOUNT);

    -- 23) OrdenItemPedidoItem (IdOrdenItem)
    SET @Paso = N'23 - OrdenItemPedidoItem (IdOrdenItem)';
    DELETE FROM OrdenItemPedidoItem WHERE IdOrdenItem IN (SELECT IdOrdenItem FROM OrdenItem WHERE IdOrden IN (SELECT IdOrden FROM Orden WHERE IdOperacion = @IdOperacion));
    INSERT @Log (Paso, Tabla, Filas) VALUES (23, N'OrdenItemPedidoItem (IdOrdenItem)', @@ROWCOUNT);

    -- 24) OrdenItem_Dyn (IdOrdenItem)
    SET @Paso = N'24 - OrdenItem_Dyn (IdOrdenItem)';
    DELETE FROM OrdenItem_Dyn WHERE IdOrdenItem IN (SELECT IdOrdenItem FROM OrdenItem WHERE IdOrden IN (SELECT IdOrden FROM Orden WHERE IdOperacion = @IdOperacion));
    INSERT @Log (Paso, Tabla, Filas) VALUES (24, N'OrdenItem_Dyn (IdOrdenItem)', @@ROWCOUNT);

    -- 25) OrdenItem (IdOrden)
    SET @Paso = N'25 - OrdenItem (IdOrden)';
    DELETE FROM OrdenItem WHERE IdOrden IN (SELECT IdOrden FROM Orden WHERE IdOperacion = @IdOperacion);
    INSERT @Log (Paso, Tabla, Filas) VALUES (25, N'OrdenItem (IdOrden)', @@ROWCOUNT);

    -- 26) Orden_Dyn (IdOrden)
    SET @Paso = N'26 - Orden_Dyn (IdOrden)';
    DELETE FROM Orden_Dyn WHERE IdOrden IN (SELECT IdOrden FROM Orden WHERE IdOperacion = @IdOperacion);
    INSERT @Log (Paso, Tabla, Filas) VALUES (26, N'Orden_Dyn (IdOrden)', @@ROWCOUNT);

    -- 27) Orden (IdOperacion)
    SET @Paso = N'27 - Orden (IdOperacion)';
    DELETE FROM Orden WHERE IdOperacion = @IdOperacion;
    INSERT @Log (Paso, Tabla, Filas) VALUES (27, N'Orden (IdOperacion)', @@ROWCOUNT);

    ----- GRUPO 3 - Pedidos (despues de OrdenItem y Orden: OrdenItem.IdPedidoItem -> PedidoItem, Orden.IdPedido -> Pedido) -----

    -- 28) OrdenPedido (IdPedido)
    SET @Paso = N'28 - OrdenPedido (IdPedido)';
    DELETE FROM OrdenPedido WHERE IdPedido IN (SELECT IdPedido FROM Pedido WHERE IdOperacion = @IdOperacion);
    INSERT @Log (Paso, Tabla, Filas) VALUES (28, N'OrdenPedido (IdPedido)', @@ROWCOUNT);

    -- 29) OrdenItemPedidoItem (IdPedidoItem)
    SET @Paso = N'29 - OrdenItemPedidoItem (IdPedidoItem)';
    DELETE FROM OrdenItemPedidoItem WHERE IdPedidoItem IN (SELECT IdPedidoItem FROM PedidoItem WHERE IdPedido IN (SELECT IdPedido FROM Pedido WHERE IdOperacion = @IdOperacion));
    INSERT @Log (Paso, Tabla, Filas) VALUES (29, N'OrdenItemPedidoItem (IdPedidoItem)', @@ROWCOUNT);

    -- 30) PedidoItem_Dyn (IdPedidoItem)
    SET @Paso = N'30 - PedidoItem_Dyn (IdPedidoItem)';
    DELETE FROM PedidoItem_Dyn WHERE IdPedidoItem IN (SELECT IdPedidoItem FROM PedidoItem WHERE IdPedido IN (SELECT IdPedido FROM Pedido WHERE IdOperacion = @IdOperacion));
    INSERT @Log (Paso, Tabla, Filas) VALUES (30, N'PedidoItem_Dyn (IdPedidoItem)', @@ROWCOUNT);

    -- 31) PedidoItem (IdPedido)
    SET @Paso = N'31 - PedidoItem (IdPedido)';
    DELETE FROM PedidoItem WHERE IdPedido IN (SELECT IdPedido FROM Pedido WHERE IdOperacion = @IdOperacion);
    INSERT @Log (Paso, Tabla, Filas) VALUES (31, N'PedidoItem (IdPedido)', @@ROWCOUNT);

    -- 32) Pedido_Dyn (IdPedido)
    SET @Paso = N'32 - Pedido_Dyn (IdPedido)';
    DELETE FROM Pedido_Dyn WHERE IdPedido IN (SELECT IdPedido FROM Pedido WHERE IdOperacion = @IdOperacion);
    INSERT @Log (Paso, Tabla, Filas) VALUES (32, N'Pedido_Dyn (IdPedido)', @@ROWCOUNT);

    -- 33) BitacoraPedido (IdPedido)
    SET @Paso = N'33 - BitacoraPedido (IdPedido)';
    DELETE FROM BitacoraPedido WHERE IdPedido IN (SELECT IdPedido FROM Pedido WHERE IdOperacion = @IdOperacion);
    INSERT @Log (Paso, Tabla, Filas) VALUES (33, N'BitacoraPedido (IdPedido)', @@ROWCOUNT);

    -- 34) Pedido (IdOperacion)
    SET @Paso = N'34 - Pedido (IdOperacion)';
    DELETE FROM Pedido WHERE IdOperacion = @IdOperacion;
    INSERT @Log (Paso, Tabla, Filas) VALUES (34, N'Pedido (IdOperacion)', @@ROWCOUNT);

    ----- GRUPO 4 - Rutas y lo que cuelga de la jornada (despues de Viaje y Orden: Viaje.IdRutaFK -> Ruta, Orden.IdOrdenParada -> OrdenParada) -----

    -- 35) BitacoraRuta (IdRuta)
    SET @Paso = N'35 - BitacoraRuta (IdRuta)';
    DELETE FROM BitacoraRuta WHERE IdRuta IN (SELECT IdRuta FROM Ruta WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion));
    INSERT @Log (Paso, Tabla, Filas) VALUES (35, N'BitacoraRuta (IdRuta)', @@ROWCOUNT);

    -- 36) RutaTraceEstado (IdRuta)
    SET @Paso = N'36 - RutaTraceEstado (IdRuta)';
    DELETE FROM RutaTraceEstado WHERE IdRuta IN (SELECT IdRuta FROM Ruta WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion));
    INSERT @Log (Paso, Tabla, Filas) VALUES (36, N'RutaTraceEstado (IdRuta)', @@ROWCOUNT);

    -- 37) Ruta (IdJornada)
    SET @Paso = N'37 - Ruta (IdJornada)';
    DELETE FROM Ruta WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion);
    INSERT @Log (Paso, Tabla, Filas) VALUES (37, N'Ruta (IdJornada)', @@ROWCOUNT);

    -- 38) OrdenParada (IdJornada)
    SET @Paso = N'38 - OrdenParada (IdJornada)';
    DELETE FROM OrdenParada WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion);
    INSERT @Log (Paso, Tabla, Filas) VALUES (38, N'OrdenParada (IdJornada)', @@ROWCOUNT);

    -- 39) BitacoraJornada (IdJornada)
    SET @Paso = N'39 - BitacoraJornada (IdJornada)';
    DELETE FROM BitacoraJornada WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion);
    INSERT @Log (Paso, Tabla, Filas) VALUES (39, N'BitacoraJornada (IdJornada)', @@ROWCOUNT);

    ----- GRUPO 5 - Jornada, siempre al final (Orden.IdJornada -> Jornada; ademas los pasos de arriba ubican sus filas a traves de Jornada) -----

    -- 40) Jornada (IdOperacion)
    SET @Paso = N'40 - Jornada (IdOperacion)';
    DELETE FROM Jornada WHERE IdOperacion = @IdOperacion;
    INSERT @Log (Paso, Tabla, Filas) VALUES (40, N'Jornada (IdOperacion)', @@ROWCOUNT);

    IF @Ejecutar = 1
    BEGIN
        COMMIT TRAN;
        PRINT N'*** EJECUTADO: cambios confirmados (COMMIT). ***';
    END
    ELSE
    BEGIN
        ROLLBACK TRAN;
        PRINT N'*** SIMULACION: se hizo ROLLBACK, no se modifico nada. Poner @Ejecutar = 1 para borrar de verdad. ***';
    END

    SELECT Paso, Tabla, Filas FROM @Log WHERE Filas > 0 ORDER BY Paso;
    SELECT [Total filas borradas] = ISNULL(SUM(Filas), 0) FROM @Log;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRAN;
    PRINT N'*** CANCELADO, se hizo ROLLBACK (no se modifico nada). Paso que fallo: ' + ISNULL(@Paso, N'-');
    THROW;
END CATCH
