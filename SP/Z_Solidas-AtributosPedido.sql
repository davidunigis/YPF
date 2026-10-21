USE [UNIGIS_DataRepository_YPF]
GO
/****** Objeto: StoredProcedure [dbo].[Z_Solidas-AtributosPedido] Fecha de script: 21/10/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[Z_Solidas-AtributosPedido]
    @IdPedido BIGINT
AS
BEGIN
    /*
    Creado: 21/10/2026
    Objetivo: se ejecuta cuando se crea un pedido (recibe el IdPedido). Busca la OT de la que nacio
              el pedido (OrdenPedido.IdOrden) y, si la OT esta en IdEstadoOrden = 60 (OT Ingresado),
              pide su cambio a 62 (OT En Proceso) con una solicitud en CambioEstadoSolicitud.
    Llamada desde la plataforma:  EXEC [dbo].[Z_Solidas-AtributosPedido] [Pedido.IdPedido]
    Notas:
      - El cambio de estado es de la OT (Entidad = 'Orden'), no del pedido.
      - Si la OT ya tiene una solicitud PENDIENTE hacia el estado 62 (por ejemplo, otro pedido de la
        misma OT) no se crea otra.
      - Como el resto de los SP del repo, registra el resultado en Log y no relanza el error.
    */
    SET NOCOUNT ON;

    BEGIN TRY
        DECLARE @Solicitudes INT = 0;

        INSERT INTO CambioEstadoSolicitud (
            Entidad, IdEntidad, IdEstadoDestino, ValidarTransicion, MismoEstado,
            FechaCreacion, FechaEjecucion, Observacion, Estado, Intento
        )
        SELECT 'Orden',
               o.IdOrden,
               62,
               0,
               0,
               GETUTCDATE(),
               GETUTCDATE(),
               'Se cambia el estado de la OT a OT En Proceso porque se genero el pedido ' + CONVERT(VARCHAR(20), @IdPedido),
               'PENDIENTE',
               0
        FROM Orden o WITH (NOLOCK)
        WHERE o.IdEstadoOrden = 60
          AND o.IdOrden IN (
              SELECT op.IdOrden
              FROM OrdenPedido op WITH (NOLOCK)
              WHERE op.IdPedido = @IdPedido
          )
          AND NOT EXISTS (
              SELECT 1
              FROM CambioEstadoSolicitud c WITH (NOLOCK)
              WHERE c.Entidad = 'Orden'
                AND c.IdEntidad = o.IdOrden
                AND c.IdEstadoDestino = 62
                AND c.Estado = 'PENDIENTE'
          );

        SET @Solicitudes = @@ROWCOUNT;

        INSERT Log (Categoria, Descripcion, FechaHora)
        VALUES ('Solidas-AtributosPedido',
                'OK IdPedido=' + CONVERT(VARCHAR(20), @IdPedido) + ' Solicitudes=' + CONVERT(VARCHAR(10), @Solicitudes),
                GETUTCDATE());
    END TRY
    BEGIN CATCH
        INSERT Log (Categoria, Descripcion, FechaHora)
        VALUES ('Solidas-AtributosPedido',
                'IdPedido=' + CONVERT(VARCHAR(20), @IdPedido) + ' Error :' + ERROR_MESSAGE(),
                GETUTCDATE());
    END CATCH
END
