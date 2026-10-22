USE [UNIGIS_DataRepository_YPF]
GO
/****** Objeto: StoredProcedure [dbo].[Z_SP_YPF_Set_DatosRutaVC_Fijo] Fecha de script: 22/10/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[Z_SP_YPF_Set_DatosRutaVC_Fijo]
    @IdRuta BIGINT
AS
BEGIN
    /*
    Creado: 22/10/2026
    Objetivo: igual que Z_SP_YPF_Set_DatosRutaVC, pero con valores fijos: asigna en la ruta
              IdVehiculo = 7 e IdConductor = 1 (en lugar de sacar el vehiculo de TipoVehiculo.Float1).
    Llamada desde la plataforma:  EXEC [dbo].[Z_SP_YPF_Set_DatosRutaVC_Fijo] [Ruta.IdRuta]
    Registra el resultado en Log y no relanza el error, como los demas SP del repo.
    */
    SET NOCOUNT ON;

    BEGIN TRY
        UPDATE Ruta
        SET IdConductor = 1,
            IdVehiculo  = 7
        WHERE IdRuta = @IdRuta;

        INSERT Log (Categoria, Descripcion, FechaHora)
        VALUES ('SetDatosRutaVCFijo', 'OK IdRuta=' + CONVERT(VARCHAR(20), @IdRuta), GETUTCDATE());
    END TRY

    BEGIN CATCH
        INSERT Log (Categoria, Descripcion, FechaHora)
        VALUES ('SetDatosRutaVCFijo', 'IdRuta=' + CONVERT(VARCHAR(20), @IdRuta) + ' Error :' + ERROR_MESSAGE(), GETUTCDATE());
    END CATCH
END
