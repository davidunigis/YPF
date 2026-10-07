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
 	/*
 	Modificado: 07/10/2026 - David de la Cruz
 	Cambio: se agrega SET NOCOUNT ON y una salida temprana (IF EXISTS ... RETURN 0) para que el SP
 	        no se ejecute en viajes cuya jornada pertenece a la operación 141
 	        (Viaje.IdJornada -> Jornada.IdOperacion = 141). Para el resto de operaciones
 	        el comportamiento no cambia. En viajes de la 141 tampoco se inserta registro en Log.
 	*/
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
