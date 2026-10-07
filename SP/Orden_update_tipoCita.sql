USE [UNIGIS_DataRepository_YPF]
GO
/****** Objeto: StoredProcedure [dbo].[Orden_update_tipoCita] Fecha de script: 07/10/2026 02:11:11 p. m. ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[Orden_update_tipoCita]
    @IdOrden BigInt
AS
BEGIN
    SET NOCOUNT ON

    UPDATE Orden
    SET [IdTipoCita] = CASE 
                        WHEN [IdDepositoLlegada] = 17 AND [Tipo] = 'D' THEN 13
                        WHEN [IdDepositoLlegada] = 17 AND [Tipo] = 'P' THEN 14
                        ELSE [IdTipoCita] 
                       END
    WHERE [IdOrden] = @IdOrden
      AND [IdDepositoLlegada] = 17
    
END
