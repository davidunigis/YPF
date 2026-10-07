USE [UNIGIS_DataRepository_YPF]
GO
/****** Objeto: StoredProcedure [dbo].[Z_SP_YPF_SetDatosOTUM] Fecha de script: 07/10/2026 04:16:59 p. m. ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[Z_SP_YPF_SetDatosOTUM]
    @IdOrden BIGINT
AS
BEGIN
    /*
    Modificado: 07/10/2026 - David de la Cruz
    Cambio: se agrega SET NOCOUNT ON y una salida temprana (IF EXISTS ... RETURN 0) para que el SP
            no se ejecute en órdenes de la operación 141 (Orden.IdOperacion = 141).
            Para el resto de operaciones el comportamiento no cambia.
            En órdenes de la 141 tampoco se inserta registro en Log.
    */
    SET NOCOUNT ON;

    -- Salida inmediata para órdenes de la operación 141
    IF EXISTS (
        SELECT 1
        FROM Orden WITH (NOLOCK)
        WHERE IdOrden = @IdOrden
          AND IdOperacion = 141
    )
        RETURN 0;

    BEGIN TRY
        /** Actualizo estados de OT de UM,
            llevo entrega PAS a DateTime1 | sumo +3HH a DateTime1 **/

        UPDATE Orden
        SET DateTime1 = (
            SELECT FechaEntregaPAS
            FROM Orden_Dyn
            WHERE IdOrden = @IdOrden
        )
        WHERE IdOrden = @IdOrden
          AND IdTipoOrden IN (
              SELECT IdTipoOrden
              FROM TipoOrden
              WHERE Nivel = 0
          )
          AND IdOperacion IN (7, 8, 9, 10, 11, 12, 13, 14);

        /* Actualizo campo Fecha para poder filtrar en OM */
        UPDATE Orden
        SET Fecha = DateTime1
        WHERE IdOrden = @IdOrden
          AND IdTipoOrden IN (
              SELECT IdTipoOrden
              FROM TipoOrden
              WHERE Nivel = 0
          )
          AND IdOperacion IN (7, 8, 9, 10, 11, 12, 13, 14);

		  /*Asigno IdOrdenPrioridad segun la Fechaentrega y la FechaCreacion*/

		          UPDATE o
        SET o.IdPrioridadOrden = 
            CASE 
                WHEN DATEDIFF(MINUTE, o.FechaCreacion, o.FechaEntrega) <= 720 THEN 2 /*Emergencia (<12h)*/
                WHEN DATEDIFF(MINUTE, o.FechaCreacion, o.FechaEntrega) <= 1440 THEN 3 /*Urgente (<=24h)*/
                ELSE 1 /* Normal (>24h)*/
            END
        FROM Orden o
        WHERE o.IdOrden = @IdOrden
          AND o.IdOperacion >= 7
          AND o.IdTipoOrden IN (
              SELECT IdTipoOrden
              FROM TipoOrden
              WHERE Nivel = 0
          )
          AND o.FechaCreacion IS NOT NULL
          AND o.FechaEntrega IS NOT NULL;

        /* Sumo +3HH a DateTime1 */
        UPDATE Orden
        SET DateTime1 = DATEADD(HOUR, 3, (
            SELECT DateTime1
            FROM Orden
            WHERE IdOrden = @IdOrden
        ))
        WHERE IdOrden = @IdOrden
          AND IdTipoOrden IN (
              SELECT IdTipoOrden
              FROM TipoOrden
              WHERE Nivel = 0
          )
          AND IdOperacion IN (7, 8, 9, 10, 11, 12, 13, 14);

        /* Actualizo ClaseDocMov de datos dyn para las de cargas sólidas */
        UPDATE Orden_Dyn
        SET ClaseDocMov = '201'
        WHERE IdOrden = @IdOrden
          AND 10 = (
              SELECT IdOperacion
              FROM Orden
              WHERE IdOrden = @IdOrden
          );

        INSERT Log (Categoria, Descripcion, FechaHora)
        VALUES (
            'SetDatosOTUM',
            'OK IdOrden=' + CONVERT(VARCHAR, @IdOrden),
            GETUTCDATE()
        );
    END TRY
    BEGIN CATCH
        INSERT Log (Categoria, Descripcion, FechaHora)
        VALUES (
            'SetDatosOTUM',
            'IdOrden=' + CONVERT(VARCHAR, @IdOrden) + ' Ex: ' + ERROR_MESSAGE(),
            GETUTCDATE()
        );
    END CATCH
END
