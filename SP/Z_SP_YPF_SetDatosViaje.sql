USE [UNIGIS_DataRepository_YPF]
GO
/****** Objeto: StoredProcedure [dbo].[Z_SP_YPF_SetDatosViaje] Fecha de script: 07/10/2026 02:00:56 p. m. ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER   PROCEDURE [dbo].[Z_SP_YPF_SetDatosViaje] @IdViaje BIGINT
 AS
 BEGIN
 	BEGIN TRY
 		DECLARE @sql AS NVARCHAR(MAX),
 			@IdOperacion INT

 		SET @IdOperacion = (
 				SELECT IdOperacion
 				FROM Jornada
 				WHERE IdJornada = (
 						(
 							SELECT IdJornada
 							FROM Viaje
 							WHERE Idviaje = @Idviaje
 							)
 						)
 				)
 		IF @IdOperacion IN (2, 3, 4, 5, 6)
 		BEGIN
 			SET @sql = 'Z_SP_YPF_SetDatosViajeLP ' + Convert(VARCHAR, @IdViaje)
 			EXEC sp_executesql @sql
 		END

 		INSERT Log (
 			Categoria,
 			Descripcion,
 			FechaHora
 			)
 		VALUES (
 			'SetDatosViaje',
 			'OK IdViaje=' + Convert(VARCHAR, @IdViaje),
 			getutcdate()
 			)
 	END TRY

 	BEGIN CATCH
 		INSERT Log (
 			Categoria,
 			Descripcion,
 			FechaHora
 			)
 		VALUES (
 			'SetDatosViaje',
 			'IdViaje=' + Convert(VARCHAR, @IdViaje) + ' Error :' + ERROR_MESSAGE(),
 			getutcdate()
 			)
 	END CATCH
 END
