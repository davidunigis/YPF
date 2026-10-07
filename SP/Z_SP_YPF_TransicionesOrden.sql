USE [UNIGIS_DataRepository_YPF]
GO
/****** Objeto: StoredProcedure [dbo].[Z_SP_YPF_TransicionesOrden] Fecha de script: 07/10/2026 04:01:00 p. m. ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[Z_SP_YPF_TransicionesOrden] @IdOrden BIGINT
 AS
 BEGIN
 	BEGIN TRY
 		DECLARE @IdTipoOrden INT
 			,@IdEstadoOrden INT
 			,@IdPack INT
 			,@IdPedido BIGINT
 
 		SELECT @IdTipoOrden = IdTipoOrden
 			,@IdEstadoOrden = IdEstadoOrden
 			,@IdPack = IdPack
 			,@IdPedido = IdPedido
 		FROM Orden WITH (NOLOCK)
 		WHERE IdOrden = @IdOrden
 
 		IF (
 				@IdTipoOrden IN (
 					SELECT IdTipoOrden
 					FROM TipoOrden WITH (NOLOCK)
 					WHERE Nivel = 0
 					) OR @IdPack IS NULL
 				)
 		BEGIN
 			RETURN
 		END
 		UPDATE Pack
 			SET IdEstadoPack = (
 					SELECT IdEstadoPack
 					FROM EstadoPack WITH (NOLOCK)
 					WHERE ReferenciaExterna = (
 							SELECT ReferenciaExterna
 							FROM EstadoOrden WITH (NOLOCK)
 							WHERE IdEstadoOrden = @IdEstadoOrden
 							)
 					)
 			WHERE IdPack = (@IdPack)
 				AND @IdEstadoOrden <> 84
 
 		UPDATE Pack
 			SET IdEstadoPack = 36
 			WHERE IdPack = @IdPack
 				AND @IdEstadoOrden = 84
 
 		IF (@IdEstadoOrden IN (
 					73
 					,74
 					,75
 					,76
 					,77
 					,95
 					,96
 					,94
 					,93
 					,80
 					,81
 					,82
 					,78
 					)
 				)
 			EXEC Z_SP_YPF_SyncPedidoPack @IdOrden
 				,@IdPedido
 				,@IdEstadoOrden
 
 		INSERT Log (
 			Categoria
 			,Descripcion
 			,FechaHora
 			)
 		VALUES (
 			'TransicionesOrden'
 			,'OK IdOrden=' + Convert(VARCHAR, @IdOrden)
 			,getutcdate()
 			)
 	END TRY
 
 	BEGIN CATCH
 		INSERT Log (
 			Categoria
 			,Descripcion
 			,FechaHora
 			)
 		VALUES (
 			'TransicionesOrden'
 			,'IdOrden=' + Convert(VARCHAR, @IdOrden) + 'Ex:' + ERROR_MESSAGE()
 			,getutcdate()
 			)
 	END CATCH
 END
