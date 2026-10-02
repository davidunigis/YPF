/* =============================================================================
   YPF_ValidarTipoVehiculoViaje
   -----------------------------------------------------------------------------
   Valida que el vehiculo asignado a un viaje sea de un tipo habilitado segun la
   matriz de asignacion (Z_MatrizAsignacionVehiculo, leida a traves de la vista
   ReglaAsignacionVehiculo). Ver Tablas/Z_MatrizAsignacionVehiculo.sql.

   Responde igual que YPF_PreSetDatosViaje (UNIGIS lee Resultado / Mensaje):
     Resultado = 'OK'  , Mensaje = NULL   -> se puede continuar
     Resultado = NULL  , Mensaje = texto  -> no se permite; se muestra el texto

   QUE HACE
     1) Guarda en Viaje.Int1 el IdTipoVehiculo con el que se creo el viaje (tipo
        requerido original). Solo la primera vez: si el usuario cambia despues el
        tipo del viaje, Int1 conserva el original. Si el tipo actual es 1
        (Pendiente de Asignacion) no se guarda nada.
     2) Si el viaje tiene vehiculo asignado (Viaje.IdVehiculo) compara el tipo de
        ese vehiculo con la matriz usando el tipo original:
          - Sin vehiculo, o vehiculo de tipo 1 (Sin Asignar)     -> OK
          - Tipo original sin fila en la matriz (no parametrizado) -> OK
          - Combinacion con "x" en la matriz                      -> OK
          - Cualquier otra combinacion                            -> Mensaje

   CUANDO LLAMARLO (configurarlo en UNIGIS)
     - Al crear el viaje: para que Int1 quede guardado con el tipo original.
     - Al asignar o cambiar el vehiculo: para validar.
     Con un solo llamado a la vez tambien funciona, pero el original se guarda en
     la primera ejecucion; si ya se cambio el tipo del viaje antes, se guardaria
     el tipo cambiado.

   PRUEBA
     EXEC dbo.YPF_ValidarTipoVehiculoViaje @IdViaje = <IdViaje>
     SELECT Int1 FROM Viaje WHERE IdViaje = <IdViaje>   -- tipo original guardado
     SELECT TOP 20 * FROM Log WHERE Categoria = 'ValidarTipoVehiculoViaje' ORDER BY 1 DESC
   ============================================================================= */
USE [UNIGIS_DataRepository_YPF]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[YPF_ValidarTipoVehiculoViaje] @IdViaje BIGINT
AS
BEGIN
	SET NOCOUNT ON;

	BEGIN TRY
		DECLARE @Mensaje VARCHAR(500) = NULL
			,@IdTipoVehiculoViaje INT
			,@IdTipoVehiculoOriginal INT
			,@IdVehiculo INT
			,@IdTipoVehiculoAsignado INT
			,@NombreOriginal VARCHAR(100)
			,@NombreAsignado VARCHAR(100)
			,@Permitidos VARCHAR(300);

		SELECT @IdTipoVehiculoViaje = V.IdTipoVehiculo
			,@IdTipoVehiculoOriginal = NULLIF(V.Int1, 0)
			,@IdVehiculo = V.IdVehiculo
		FROM Viaje V
		WHERE V.IdViaje = @IdViaje

		/* Se guarda el tipo requerido original solo la primera vez (1 = Pendiente de Asignacion) */
		IF @IdTipoVehiculoOriginal IS NULL
			AND @IdTipoVehiculoViaje > 1
		BEGIN
			UPDATE Viaje
			SET Int1 = @IdTipoVehiculoViaje
			WHERE IdViaje = @IdViaje
				AND ISNULL(Int1, 0) = 0

			SET @IdTipoVehiculoOriginal = @IdTipoVehiculoViaje
		END

		/* Validacion del vehiculo asignado contra la matriz de asignacion */
		IF @IdTipoVehiculoOriginal IS NOT NULL
			AND ISNULL(@IdVehiculo, 0) > 0
		BEGIN
			SELECT @IdTipoVehiculoAsignado = IdTipoVehiculo
			FROM Vehiculo WITH (NOLOCK)
			WHERE IdVehiculo = @IdVehiculo

			IF @IdTipoVehiculoAsignado > 1 /* 1 = Pendiente de Asignacion (Sin Asignar) */
				AND EXISTS (
					SELECT 1
					FROM ReglaAsignacionVehiculo WITH (NOLOCK)
					WHERE IdTipoVehiculoViaje = @IdTipoVehiculoOriginal
					) /* Tipo original parametrizado en la matriz */
				AND NOT EXISTS (
					SELECT 1
					FROM ReglaAsignacionVehiculo WITH (NOLOCK)
					WHERE IdTipoVehiculoViaje = @IdTipoVehiculoOriginal
						AND IdTipoVehiculoHabilitado = @IdTipoVehiculoAsignado
						AND Habilitado = 1
					)
			BEGIN
				SELECT @NombreOriginal = TipoViaje
				FROM Z_MatrizAsignacionVehiculo WITH (NOLOCK)
				WHERE Id = @IdTipoVehiculoOriginal

				SELECT @NombreAsignado = TipoViaje
				FROM Z_MatrizAsignacionVehiculo WITH (NOLOCK)
				WHERE Id = @IdTipoVehiculoAsignado

				SELECT @Permitidos = STUFF((
							SELECT '; ' + m.TipoViaje
							FROM ReglaAsignacionVehiculo r WITH (NOLOCK)
							INNER JOIN Z_MatrizAsignacionVehiculo m WITH (NOLOCK) ON m.Id = r.IdTipoVehiculoHabilitado
							WHERE r.IdTipoVehiculoViaje = @IdTipoVehiculoOriginal
								AND r.Habilitado = 1
							ORDER BY m.TipoViaje
							FOR XML PATH('')
								,TYPE
							).value('.', 'VARCHAR(300)'), 1, 2, '')

				SET @Mensaje = LEFT('El vehiculo asignado es de tipo ' + ISNULL(@NombreAsignado, 'Id ' + CONVERT(VARCHAR(10), @IdTipoVehiculoAsignado)) + ' y el viaje requiere ' + ISNULL(@NombreOriginal, 'Id ' + CONVERT(VARCHAR(10), @IdTipoVehiculoOriginal)) + '. Tipos permitidos: ' + ISNULL(@Permitidos, 'ninguno') + '.', 500)
			END
		END

		IF ISNULL(@Mensaje, '') <> ''
		BEGIN
			SELECT NULL [Resultado]
				,@Mensaje [Mensaje]
		END
		ELSE
		BEGIN
			SELECT 'OK' [Resultado]
				,NULL [Mensaje]
		END

		INSERT Log (
			Categoria
			,Descripcion
			,FechaHora
			)
		VALUES (
			'ValidarTipoVehiculoViaje'
			,CASE
				WHEN ISNULL(@Mensaje, '') <> ''
					THEN 'Rechazado IdViaje=' + Convert(VARCHAR, @IdViaje) + ' Original=' + Convert(VARCHAR, @IdTipoVehiculoOriginal) + ' Asignado=' + Convert(VARCHAR, @IdTipoVehiculoAsignado)
				ELSE 'OK IdViaje=' + Convert(VARCHAR, @IdViaje)
				END
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
			'ValidarTipoVehiculoViaje'
			,'IdViaje=' + Convert(VARCHAR, @IdViaje) + ' Error :' + ERROR_MESSAGE()
			,getutcdate()
			)
	END CATCH
END
GO
