/*==============================================================================================
  Eliminar_Operacion_141_Secuencia.sql

  Borra la operacion @IdOperacion (rutas, jornadas, viajes, paradas, ordenes y lo que cuelga de
  ellos) con una lista FIJA de DELETE, de arriba hacia abajo.

  COMO USARLO
    1) Dejar @Ejecutar = 0 y correr: ejecuta toda la lista dentro de una transaccion y al final
       hace ROLLBACK (no cambia nada). Muestra cuantas filas borra cada paso. Si algun paso choca
       con una foreign key, se corta con el error y se hace ROLLBACK.
    2) Con @Ejecutar = 1 se repite y se hace COMMIT.

  NOTA SOBRE EL ORDEN
    Es el orden de la lista original, con UN cambio: el DELETE de Jornada va AL FINAL (paso 31).
    Los pasos de viaje/parada/ruta ubican sus filas con "... FROM Jornada WHERE IdOperacion = ...";
    si Jornada se borrara antes, esas subconsultas no devolverian nada y esos pasos no borrarian
    nada (o Jornada fallaria por la FK de Viaje).

  LIMITES
    - Solo borra lo que esta en la lista. Una tabla que dependa de estas y no figure aqui hace
      fallar el paso que choca con ella (si tiene FK) o queda con filas huerfanas (si no la tiene).
      Para descubrir dependencias automaticamente existe Eliminar_Operacion_141.sql.
    - Todo corre en UNA transaccion: con muchos millones de filas puede crecer mucho el log y
      bloquear tablas. Correr en ventana de mantenimiento.
==============================================================================================*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @IdOperacion INT = 141;
DECLARE @Ejecutar    BIT = 0;   -- 0 = simulacion (ROLLBACK al final) | 1 = borrado real (COMMIT)

DECLARE @Log  TABLE (Paso INT, Tabla NVARCHAR(200), Filas BIGINT);
DECLARE @Paso NVARCHAR(200);

BEGIN TRY
    BEGIN TRAN;

    -- 1) BitacoraRuta (IdRuta)
    SET @Paso = N'1 - BitacoraRuta (IdRuta)';
    DELETE FROM BitacoraRuta WHERE IdRuta IN (SELECT IdRuta FROM Ruta WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion));
    INSERT @Log (Paso, Tabla, Filas) VALUES (1, N'BitacoraRuta (IdRuta)', @@ROWCOUNT);

    -- 2) Ruta (IdJornada)
    SET @Paso = N'2 - Ruta (IdJornada)';
    DELETE FROM Ruta WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion);
    INSERT @Log (Paso, Tabla, Filas) VALUES (2, N'Ruta (IdJornada)', @@ROWCOUNT);

    -- 3) OrdenParada (IdJornada)
    SET @Paso = N'3 - OrdenParada (IdJornada)';
    DELETE FROM OrdenParada WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion);
    INSERT @Log (Paso, Tabla, Filas) VALUES (3, N'OrdenParada (IdJornada)', @@ROWCOUNT);

    -- 4) BitacoraJornada (IdJornada)
    SET @Paso = N'4 - BitacoraJornada (IdJornada)';
    DELETE FROM BitacoraJornada WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion);
    INSERT @Log (Paso, Tabla, Filas) VALUES (4, N'BitacoraJornada (IdJornada)', @@ROWCOUNT);

    -- 5) OrdenTrayecto (IdOrdenOrigen)
    SET @Paso = N'5 - OrdenTrayecto (IdOrdenOrigen)';
    DELETE FROM OrdenTrayecto WHERE IdOrdenOrigen IN (SELECT IdOrden FROM Orden WHERE IdOperacion = @IdOperacion);
    INSERT @Log (Paso, Tabla, Filas) VALUES (5, N'OrdenTrayecto (IdOrdenOrigen)', @@ROWCOUNT);

    -- 6) OrdenTrayecto (IdOrdenDestino)
    SET @Paso = N'6 - OrdenTrayecto (IdOrdenDestino)';
    DELETE FROM OrdenTrayecto WHERE IdOrdenDestino IN (SELECT IdOrden FROM Orden WHERE IdOperacion = @IdOperacion);
    INSERT @Log (Paso, Tabla, Filas) VALUES (6, N'OrdenTrayecto (IdOrdenDestino)', @@ROWCOUNT);

    -- 7) OrdenTraceEstado (IdOrden)
    SET @Paso = N'7 - OrdenTraceEstado (IdOrden)';
    DELETE FROM OrdenTraceEstado WHERE IdOrden IN (SELECT IdOrden FROM Orden WHERE IdOperacion = @IdOperacion);
    INSERT @Log (Paso, Tabla, Filas) VALUES (7, N'OrdenTraceEstado (IdOrden)', @@ROWCOUNT);

    -- 8) OrdenPedido (IdOrden)
    SET @Paso = N'8 - OrdenPedido (IdOrden)';
    DELETE FROM OrdenPedido WHERE IdOrden IN (SELECT IdOrden FROM Orden WHERE IdOperacion = @IdOperacion);
    INSERT @Log (Paso, Tabla, Filas) VALUES (8, N'OrdenPedido (IdOrden)', @@ROWCOUNT);

    -- 9) BitacoraOrden (IdOrden)
    SET @Paso = N'9 - BitacoraOrden (IdOrden)';
    DELETE FROM BitacoraOrden WHERE IdOrden IN (SELECT IdOrden FROM Orden WHERE IdOperacion = @IdOperacion);
    INSERT @Log (Paso, Tabla, Filas) VALUES (9, N'BitacoraOrden (IdOrden)', @@ROWCOUNT);

    -- 10) OrdenItemOT (IdOrdenItem)
    SET @Paso = N'10 - OrdenItemOT (IdOrdenItem)';
    DELETE FROM OrdenItemOT WHERE IdOrdenItem IN (SELECT IdOrdenItem FROM OrdenItem WHERE IdOrden IN (SELECT IdOrden FROM Orden WHERE IdOperacion = @IdOperacion));
    INSERT @Log (Paso, Tabla, Filas) VALUES (10, N'OrdenItemOT (IdOrdenItem)', @@ROWCOUNT);

    -- 11) OrdenItemPedidoItem (IdOrdenItem)
    SET @Paso = N'11 - OrdenItemPedidoItem (IdOrdenItem)';
    DELETE FROM OrdenItemPedidoItem WHERE IdOrdenItem IN (SELECT IdOrdenItem FROM OrdenItem WHERE IdOrden IN (SELECT IdOrden FROM Orden WHERE IdOperacion = @IdOperacion));
    INSERT @Log (Paso, Tabla, Filas) VALUES (11, N'OrdenItemPedidoItem (IdOrdenItem)', @@ROWCOUNT);

    -- 12) OrdenItem_Dyn (IdOrdenItem)
    SET @Paso = N'12 - OrdenItem_Dyn (IdOrdenItem)';
    DELETE FROM OrdenItem_Dyn WHERE IdOrdenItem IN (SELECT IdOrdenItem FROM OrdenItem WHERE IdOrden IN (SELECT IdOrden FROM Orden WHERE IdOperacion = @IdOperacion));
    INSERT @Log (Paso, Tabla, Filas) VALUES (12, N'OrdenItem_Dyn (IdOrdenItem)', @@ROWCOUNT);

    -- 13) OrdenItem (IdOrden)
    SET @Paso = N'13 - OrdenItem (IdOrden)';
    DELETE FROM OrdenItem WHERE IdOrden IN (SELECT IdOrden FROM Orden WHERE IdOperacion = @IdOperacion);
    INSERT @Log (Paso, Tabla, Filas) VALUES (13, N'OrdenItem (IdOrden)', @@ROWCOUNT);

    -- 14) Orden_Dyn (IdOrden)
    SET @Paso = N'14 - Orden_Dyn (IdOrden)';
    DELETE FROM Orden_Dyn WHERE IdOrden IN (SELECT IdOrden FROM Orden WHERE IdOperacion = @IdOperacion);
    INSERT @Log (Paso, Tabla, Filas) VALUES (14, N'Orden_Dyn (IdOrden)', @@ROWCOUNT);

    -- 15) Orden (IdOperacion)
    SET @Paso = N'15 - Orden (IdOperacion)';
    DELETE FROM Orden WHERE IdOperacion = @IdOperacion;
    INSERT @Log (Paso, Tabla, Filas) VALUES (15, N'Orden (IdOperacion)', @@ROWCOUNT);

    -- 16) ViajeAgrupadorViaje (IdViaje)
    SET @Paso = N'16 - ViajeAgrupadorViaje (IdViaje)';
    DELETE FROM ViajeAgrupadorViaje WHERE IdViaje IN (SELECT IdViaje FROM Viaje WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion));
    INSERT @Log (Paso, Tabla, Filas) VALUES (16, N'ViajeAgrupadorViaje (IdViaje)', @@ROWCOUNT);

    -- 17) Alarma (IdParada)
    SET @Paso = N'17 - Alarma (IdParada)';
    DELETE FROM Alarma WHERE IdParada IN (SELECT IdParada FROM Parada WHERE IdViaje IN (SELECT IdViaje FROM Viaje WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion)));
    INSERT @Log (Paso, Tabla, Filas) VALUES (17, N'Alarma (IdParada)', @@ROWCOUNT);

    -- 18) ParadaTraceEstado (IdParada)
    SET @Paso = N'18 - ParadaTraceEstado (IdParada)';
    DELETE FROM ParadaTraceEstado WHERE IdParada IN (SELECT IdParada FROM Parada WHERE IdViaje IN (SELECT IdViaje FROM Viaje WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion)));
    INSERT @Log (Paso, Tabla, Filas) VALUES (18, N'ParadaTraceEstado (IdParada)', @@ROWCOUNT);

    -- 19) BitacoraParada (IdParada)
    SET @Paso = N'19 - BitacoraParada (IdParada)';
    DELETE FROM BitacoraParada WHERE IdParada IN (SELECT IdParada FROM Parada WHERE IdViaje IN (SELECT IdViaje FROM Viaje WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion)));
    INSERT @Log (Paso, Tabla, Filas) VALUES (19, N'BitacoraParada (IdParada)', @@ROWCOUNT);

    -- 20) ParadaItemCantidad (IdParadaItem)
    SET @Paso = N'20 - ParadaItemCantidad (IdParadaItem)';
    DELETE FROM ParadaItemCantidad WHERE IdParadaItem IN (SELECT IdParadaItem FROM ParadaItem WHERE IdParada IN (SELECT IdParada FROM Parada WHERE IdViaje IN (SELECT IdViaje FROM Viaje WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion))));
    INSERT @Log (Paso, Tabla, Filas) VALUES (20, N'ParadaItemCantidad (IdParadaItem)', @@ROWCOUNT);

    -- 21) ParadaItem_Dyn (IdParadaItem)
    SET @Paso = N'21 - ParadaItem_Dyn (IdParadaItem)';
    DELETE FROM ParadaItem_Dyn WHERE IdParadaItem IN (SELECT IdParadaItem FROM ParadaItem WHERE IdParada IN (SELECT IdParada FROM Parada WHERE IdViaje IN (SELECT IdViaje FROM Viaje WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion))));
    INSERT @Log (Paso, Tabla, Filas) VALUES (21, N'ParadaItem_Dyn (IdParadaItem)', @@ROWCOUNT);

    -- 22) ParadaItem (IdParada)
    SET @Paso = N'22 - ParadaItem (IdParada)';
    DELETE FROM ParadaItem WHERE IdParada IN (SELECT IdParada FROM Parada WHERE IdViaje IN (SELECT IdViaje FROM Viaje WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion)));
    INSERT @Log (Paso, Tabla, Filas) VALUES (22, N'ParadaItem (IdParada)', @@ROWCOUNT);

    -- 23) EstadiaParada (IdParada)
    SET @Paso = N'23 - EstadiaParada (IdParada)';
    DELETE FROM EstadiaParada WHERE IdParada IN (SELECT IdParada FROM Parada WHERE IdViaje IN (SELECT IdViaje FROM Viaje WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion)));
    INSERT @Log (Paso, Tabla, Filas) VALUES (23, N'EstadiaParada (IdParada)', @@ROWCOUNT);

    -- 24) Parada (IdViaje)
    SET @Paso = N'24 - Parada (IdViaje)';
    DELETE FROM Parada WHERE IdViaje IN (SELECT IdViaje FROM Viaje WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion));
    INSERT @Log (Paso, Tabla, Filas) VALUES (24, N'Parada (IdViaje)', @@ROWCOUNT);

    -- 25) ViajeRecurso (IdViaje)
    SET @Paso = N'25 - ViajeRecurso (IdViaje)';
    DELETE FROM ViajeRecurso WHERE IdViaje IN (SELECT IdViaje FROM Viaje WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion));
    INSERT @Log (Paso, Tabla, Filas) VALUES (25, N'ViajeRecurso (IdViaje)', @@ROWCOUNT);

    -- 26) BitacoraViaje (IdViaje)
    SET @Paso = N'26 - BitacoraViaje (IdViaje)';
    DELETE FROM BitacoraViaje WHERE IdViaje IN (SELECT IdViaje FROM Viaje WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion));
    INSERT @Log (Paso, Tabla, Filas) VALUES (26, N'BitacoraViaje (IdViaje)', @@ROWCOUNT);

    -- 27) GuiaViaje (IdViaje)
    SET @Paso = N'27 - GuiaViaje (IdViaje)';
    DELETE FROM GuiaViaje WHERE IdViaje IN (SELECT IdViaje FROM Viaje WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion));
    INSERT @Log (Paso, Tabla, Filas) VALUES (27, N'GuiaViaje (IdViaje)', @@ROWCOUNT);

    -- 28) EstadoViajeTraceEstado (IdViaje)
    SET @Paso = N'28 - EstadoViajeTraceEstado (IdViaje)';
    DELETE FROM EstadoViajeTraceEstado WHERE IdViaje IN (SELECT IdViaje FROM Viaje WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion));
    INSERT @Log (Paso, Tabla, Filas) VALUES (28, N'EstadoViajeTraceEstado (IdViaje)', @@ROWCOUNT);

    -- 29) ConceptoValorizadoGuia (IdViaje)
    SET @Paso = N'29 - ConceptoValorizadoGuia (IdViaje)';
    DELETE FROM ConceptoValorizadoGuia WHERE IdViaje IN (SELECT IdViaje FROM Viaje WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion));
    INSERT @Log (Paso, Tabla, Filas) VALUES (29, N'ConceptoValorizadoGuia (IdViaje)', @@ROWCOUNT);

    -- 30) Viaje (IdJornada)
    SET @Paso = N'30 - Viaje (IdJornada)';
    DELETE FROM Viaje WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion);
    INSERT @Log (Paso, Tabla, Filas) VALUES (30, N'Viaje (IdJornada)', @@ROWCOUNT);

    -- 31) Jornada (IdOperacion)
    --    (en la lista original era el paso 16; va al final porque los pasos de viaje dependen de Jornada)
    SET @Paso = N'31 - Jornada (IdOperacion)';
    DELETE FROM Jornada WHERE IdOperacion = @IdOperacion;
    INSERT @Log (Paso, Tabla, Filas) VALUES (31, N'Jornada (IdOperacion)', @@ROWCOUNT);

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
