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
    Jornada va ademas AL FINAL porque los pasos de viaje/parada/ruta ubican sus filas con
    "... FROM Jornada WHERE IdOperacion = ...": si Jornada se borrara antes, esas subconsultas no
    devolverian nada y esos pasos no borrarian nada.
    Orden resultante: viajes y paradas -> ordenes -> pedidos -> rutas/OrdenParada -> Jornada.

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

    ----- GRUPO 2 - Ordenes (antes que Pedido: Orden.IdPedido -> Pedido; antes que OrdenParada y Jornada) -----

    -- 16) OrdenTrayecto (IdOrdenOrigen)
    SET @Paso = N'16 - OrdenTrayecto (IdOrdenOrigen)';
    DELETE FROM OrdenTrayecto WHERE IdOrdenOrigen IN (SELECT IdOrden FROM Orden WHERE IdOperacion = @IdOperacion);
    INSERT @Log (Paso, Tabla, Filas) VALUES (16, N'OrdenTrayecto (IdOrdenOrigen)', @@ROWCOUNT);

    -- 17) OrdenTrayecto (IdOrdenDestino)
    SET @Paso = N'17 - OrdenTrayecto (IdOrdenDestino)';
    DELETE FROM OrdenTrayecto WHERE IdOrdenDestino IN (SELECT IdOrden FROM Orden WHERE IdOperacion = @IdOperacion);
    INSERT @Log (Paso, Tabla, Filas) VALUES (17, N'OrdenTrayecto (IdOrdenDestino)', @@ROWCOUNT);

    -- 18) OrdenTraceEstado (IdOrden)
    SET @Paso = N'18 - OrdenTraceEstado (IdOrden)';
    DELETE FROM OrdenTraceEstado WHERE IdOrden IN (SELECT IdOrden FROM Orden WHERE IdOperacion = @IdOperacion);
    INSERT @Log (Paso, Tabla, Filas) VALUES (18, N'OrdenTraceEstado (IdOrden)', @@ROWCOUNT);

    -- 19) OrdenPedido (IdOrden)
    SET @Paso = N'19 - OrdenPedido (IdOrden)';
    DELETE FROM OrdenPedido WHERE IdOrden IN (SELECT IdOrden FROM Orden WHERE IdOperacion = @IdOperacion);
    INSERT @Log (Paso, Tabla, Filas) VALUES (19, N'OrdenPedido (IdOrden)', @@ROWCOUNT);

    -- 20) BitacoraOrden (IdOrden)
    SET @Paso = N'20 - BitacoraOrden (IdOrden)';
    DELETE FROM BitacoraOrden WHERE IdOrden IN (SELECT IdOrden FROM Orden WHERE IdOperacion = @IdOperacion);
    INSERT @Log (Paso, Tabla, Filas) VALUES (20, N'BitacoraOrden (IdOrden)', @@ROWCOUNT);

    -- 21) OrdenItemOT (IdOrdenItem)
    SET @Paso = N'21 - OrdenItemOT (IdOrdenItem)';
    DELETE FROM OrdenItemOT WHERE IdOrdenItem IN (SELECT IdOrdenItem FROM OrdenItem WHERE IdOrden IN (SELECT IdOrden FROM Orden WHERE IdOperacion = @IdOperacion));
    INSERT @Log (Paso, Tabla, Filas) VALUES (21, N'OrdenItemOT (IdOrdenItem)', @@ROWCOUNT);

    -- 22) OrdenItemPedidoItem (IdOrdenItem)
    SET @Paso = N'22 - OrdenItemPedidoItem (IdOrdenItem)';
    DELETE FROM OrdenItemPedidoItem WHERE IdOrdenItem IN (SELECT IdOrdenItem FROM OrdenItem WHERE IdOrden IN (SELECT IdOrden FROM Orden WHERE IdOperacion = @IdOperacion));
    INSERT @Log (Paso, Tabla, Filas) VALUES (22, N'OrdenItemPedidoItem (IdOrdenItem)', @@ROWCOUNT);

    -- 23) OrdenItem_Dyn (IdOrdenItem)
    SET @Paso = N'23 - OrdenItem_Dyn (IdOrdenItem)';
    DELETE FROM OrdenItem_Dyn WHERE IdOrdenItem IN (SELECT IdOrdenItem FROM OrdenItem WHERE IdOrden IN (SELECT IdOrden FROM Orden WHERE IdOperacion = @IdOperacion));
    INSERT @Log (Paso, Tabla, Filas) VALUES (23, N'OrdenItem_Dyn (IdOrdenItem)', @@ROWCOUNT);

    -- 24) OrdenItem (IdOrden)
    SET @Paso = N'24 - OrdenItem (IdOrden)';
    DELETE FROM OrdenItem WHERE IdOrden IN (SELECT IdOrden FROM Orden WHERE IdOperacion = @IdOperacion);
    INSERT @Log (Paso, Tabla, Filas) VALUES (24, N'OrdenItem (IdOrden)', @@ROWCOUNT);

    -- 25) Orden_Dyn (IdOrden)
    SET @Paso = N'25 - Orden_Dyn (IdOrden)';
    DELETE FROM Orden_Dyn WHERE IdOrden IN (SELECT IdOrden FROM Orden WHERE IdOperacion = @IdOperacion);
    INSERT @Log (Paso, Tabla, Filas) VALUES (25, N'Orden_Dyn (IdOrden)', @@ROWCOUNT);

    -- 26) Orden (IdOperacion)
    SET @Paso = N'26 - Orden (IdOperacion)';
    DELETE FROM Orden WHERE IdOperacion = @IdOperacion;
    INSERT @Log (Paso, Tabla, Filas) VALUES (26, N'Orden (IdOperacion)', @@ROWCOUNT);

    ----- GRUPO 3 - Pedidos (despues de OrdenItem y Orden: OrdenItem.IdPedidoItem -> PedidoItem, Orden.IdPedido -> Pedido) -----

    -- 27) OrdenPedido (IdPedido)
    SET @Paso = N'27 - OrdenPedido (IdPedido)';
    DELETE FROM OrdenPedido WHERE IdPedido IN (SELECT IdPedido FROM Pedido WHERE IdOperacion = @IdOperacion);
    INSERT @Log (Paso, Tabla, Filas) VALUES (27, N'OrdenPedido (IdPedido)', @@ROWCOUNT);

    -- 28) OrdenItemPedidoItem (IdPedidoItem)
    SET @Paso = N'28 - OrdenItemPedidoItem (IdPedidoItem)';
    DELETE FROM OrdenItemPedidoItem WHERE IdPedidoItem IN (SELECT IdPedidoItem FROM PedidoItem WHERE IdPedido IN (SELECT IdPedido FROM Pedido WHERE IdOperacion = @IdOperacion));
    INSERT @Log (Paso, Tabla, Filas) VALUES (28, N'OrdenItemPedidoItem (IdPedidoItem)', @@ROWCOUNT);

    -- 29) PedidoItem_Dyn (IdPedidoItem)
    SET @Paso = N'29 - PedidoItem_Dyn (IdPedidoItem)';
    DELETE FROM PedidoItem_Dyn WHERE IdPedidoItem IN (SELECT IdPedidoItem FROM PedidoItem WHERE IdPedido IN (SELECT IdPedido FROM Pedido WHERE IdOperacion = @IdOperacion));
    INSERT @Log (Paso, Tabla, Filas) VALUES (29, N'PedidoItem_Dyn (IdPedidoItem)', @@ROWCOUNT);

    -- 30) PedidoItem (IdPedido)
    SET @Paso = N'30 - PedidoItem (IdPedido)';
    DELETE FROM PedidoItem WHERE IdPedido IN (SELECT IdPedido FROM Pedido WHERE IdOperacion = @IdOperacion);
    INSERT @Log (Paso, Tabla, Filas) VALUES (30, N'PedidoItem (IdPedido)', @@ROWCOUNT);

    -- 31) Pedido_Dyn (IdPedido)
    SET @Paso = N'31 - Pedido_Dyn (IdPedido)';
    DELETE FROM Pedido_Dyn WHERE IdPedido IN (SELECT IdPedido FROM Pedido WHERE IdOperacion = @IdOperacion);
    INSERT @Log (Paso, Tabla, Filas) VALUES (31, N'Pedido_Dyn (IdPedido)', @@ROWCOUNT);

    -- 32) BitacoraPedido (IdPedido)
    SET @Paso = N'32 - BitacoraPedido (IdPedido)';
    DELETE FROM BitacoraPedido WHERE IdPedido IN (SELECT IdPedido FROM Pedido WHERE IdOperacion = @IdOperacion);
    INSERT @Log (Paso, Tabla, Filas) VALUES (32, N'BitacoraPedido (IdPedido)', @@ROWCOUNT);

    -- 33) PedidoTraceEstado (IdPedido)
    SET @Paso = N'33 - PedidoTraceEstado (IdPedido)';
    DELETE FROM PedidoTraceEstado WHERE IdPedido IN (SELECT IdPedido FROM Pedido WHERE IdOperacion = @IdOperacion);
    INSERT @Log (Paso, Tabla, Filas) VALUES (33, N'PedidoTraceEstado (IdPedido)', @@ROWCOUNT);

    -- 34) Pedido (IdOperacion)
    SET @Paso = N'34 - Pedido (IdOperacion)';
    DELETE FROM Pedido WHERE IdOperacion = @IdOperacion;
    INSERT @Log (Paso, Tabla, Filas) VALUES (34, N'Pedido (IdOperacion)', @@ROWCOUNT);

    ----- GRUPO 4 - Rutas y lo que cuelga de la jornada (despues de Viaje y Orden: Viaje.IdRutaFK -> Ruta, Orden.IdOrdenParada -> OrdenParada) -----

    -- 35) BitacoraRuta (IdRuta)
    SET @Paso = N'35 - BitacoraRuta (IdRuta)';
    DELETE FROM BitacoraRuta WHERE IdRuta IN (SELECT IdRuta FROM Ruta WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion));
    INSERT @Log (Paso, Tabla, Filas) VALUES (35, N'BitacoraRuta (IdRuta)', @@ROWCOUNT);

    -- 36) Ruta (IdJornada)
    SET @Paso = N'36 - Ruta (IdJornada)';
    DELETE FROM Ruta WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion);
    INSERT @Log (Paso, Tabla, Filas) VALUES (36, N'Ruta (IdJornada)', @@ROWCOUNT);

    -- 37) OrdenParada (IdJornada)
    SET @Paso = N'37 - OrdenParada (IdJornada)';
    DELETE FROM OrdenParada WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion);
    INSERT @Log (Paso, Tabla, Filas) VALUES (37, N'OrdenParada (IdJornada)', @@ROWCOUNT);

    -- 38) BitacoraJornada (IdJornada)
    SET @Paso = N'38 - BitacoraJornada (IdJornada)';
    DELETE FROM BitacoraJornada WHERE IdJornada IN (SELECT IdJornada FROM Jornada WHERE IdOperacion = @IdOperacion);
    INSERT @Log (Paso, Tabla, Filas) VALUES (38, N'BitacoraJornada (IdJornada)', @@ROWCOUNT);

    ----- GRUPO 5 - Jornada, siempre al final (Orden.IdJornada -> Jornada; ademas los pasos de arriba ubican sus filas a traves de Jornada) -----

    -- 39) Jornada (IdOperacion)
    SET @Paso = N'39 - Jornada (IdOperacion)';
    DELETE FROM Jornada WHERE IdOperacion = @IdOperacion;
    INSERT @Log (Paso, Tabla, Filas) VALUES (39, N'Jornada (IdOperacion)', @@ROWCOUNT);

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
