USE [UNIGIS_DataRepository_YPF]
GO
/****** Objeto: StoredProcedure [dbo].[Z_Solidas-AtributosOrden] Fecha de script: 22/10/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[Z_Solidas-AtributosOrden]
    @IdOrden BIGINT
AS
BEGIN
    /*
    Creado: 22/10/2026
    Modificado: 22/10/2026 - si la orden no tiene IdPedido (no viene de un pedido) no hace nada.
    Objetivo: se ejecuta para una orden (recibe el IdOrden) y le asigna sus atributos a partir del pedido.
              Una orden viene de un pedido cuando tiene Orden.IdPedido; si no lo tiene, el SP no hace nada.
      - Toma Pedido.Int1 del pedido de la orden (Orden.IdPedido) y lo guarda en Orden.IdTipoVehiculo y
        Orden.Int1 (el tipo de vehiculo 207 / 208 / 209 que dejo Z_SP_YPF_ValidaVehiculoPedido).
        Si Pedido.Int1 es NULL, esos dos campos no se tocan.
      - Setea Orden.InicioHorario1 = 0 y Orden.FinHorario1 = 2359.
    Llamada desde la plataforma:  EXEC [dbo].[Z_Solidas-AtributosOrden] [Orden.IdOrden]
    Notas:
      - Solo escribe si algun valor cambia.
      - Una orden sin IdPedido (o inexistente) tampoco inserta registro en Log.
      - Como el resto de los SP del repo, registra el resultado en Log y no relanza el error.
    */
    SET NOCOUNT ON;

    -- Salida inmediata para ordenes que no vienen de un pedido
    IF NOT EXISTS (
        SELECT 1
        FROM Orden WITH (NOLOCK)
        WHERE IdOrden = @IdOrden
          AND IdPedido IS NOT NULL
    )
        RETURN 0;

    BEGIN TRY
        DECLARE @Filas INT = 0;

        UPDATE o
        SET IdTipoVehiculo = ISNULL(p.Int1, o.IdTipoVehiculo),
            Int1           = ISNULL(p.Int1, o.Int1),
            InicioHorario1 = 0,
            FinHorario1    = 2359
        FROM Orden o
            LEFT JOIN Pedido p WITH (NOLOCK) ON p.IdPedido = o.IdPedido
        WHERE o.IdOrden = @IdOrden
          AND (ISNULL(o.InicioHorario1, -1) <> 0
               OR ISNULL(o.FinHorario1, -1) <> 2359
               OR (p.Int1 IS NOT NULL
                   AND (ISNULL(o.IdTipoVehiculo, -1) <> p.Int1
                        OR ISNULL(o.Int1, -1) <> p.Int1)));

        SET @Filas = @@ROWCOUNT;

        INSERT Log (Categoria, Descripcion, FechaHora)
        VALUES ('Solidas-AtributosOrden',
                'OK IdOrden=' + CONVERT(VARCHAR(20), @IdOrden) + ' Actualizada=' + CONVERT(VARCHAR(10), @Filas),
                GETUTCDATE());
    END TRY
    BEGIN CATCH
        INSERT Log (Categoria, Descripcion, FechaHora)
        VALUES ('Solidas-AtributosOrden',
                'IdOrden=' + CONVERT(VARCHAR(20), @IdOrden) + ' Error :' + ERROR_MESSAGE(),
                GETUTCDATE());
    END CATCH
END
