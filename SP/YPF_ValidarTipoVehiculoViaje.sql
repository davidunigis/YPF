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
     1) Guarda en Viaje.Varchar6 (varchar 100) el IdTipoVehiculo con el que se creo
        el viaje, como texto (ej. '208'): es el tipo requerido original. Solo la
        primera vez: si el usuario cambia despues el tipo del viaje, Varchar6
        conserva el original. Si el tipo actual es 1 (Pendiente de Asignacion) no
        se guarda nada. Si Varchar6 ya tiene otro dato (no es un IdTipoVehiculo)
        no se toca, no se valida y se deja constancia en Log.
     2) Compara el tipo del vehiculo asignado (Viaje.IdVehiculo) con la matriz,
        usando el tipo original:
          - Tipo original sin fila en la matriz (no parametrizado)  -> OK
          - Vehiculo de un tipo con "x" en la matriz                -> OK
          - Vehiculo "Sin Asignar" (tipo 1) o sin vehiculo          -> Mensaje
          - Vehiculo de un tipo sin "x" en la matriz                -> Mensaje
        Si el viaje no tiene tipo original (su tipo actual es 1 = Pendiente de
        Asignacion, o Varchar6 tiene otro dato) no hay nada que validar -> OK.

   CUANDO LLAMARLO (configurarlo en UNIGIS)
     Cuando el viaje ya debe tener un vehiculo valido (asignar, confirmar o
     publicar). Todo viaje nace con el vehiculo "Sin Asignar", asi que si se llama
     al crearlo responde con Mensaje (aunque ya deja guardado el tipo original en
     Varchar6). El original se guarda en la primera ejecucion: si antes de ella
     ya se cambio el tipo del viaje, se guardaria el tipo cambiado.

   PRUEBA
     EXEC dbo.YPF_ValidarTipoVehiculoViaje @IdViaje = <IdViaje>
     SELECT Varchar6 FROM Viaje WHERE IdViaje = <IdViaje>   -- tipo original guardado
     SELECT TOP 20 * FROM Log WHERE Categoria = 'ValidarTipoVehiculo' ORDER BY 1 DESC
     (Log.Categoria admite solo 20 caracteres; por eso no se usa el nombre completo)
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
			,@CampoOriginal VARCHAR(100)
			,@CampoEnUso BIT = 0
			,@IdVehiculo INT
			,@IdTipoVehiculoAsignado INT
			,@SinVehiculo BIT = 0
			,@NombreOriginal VARCHAR(100)
			,@NombreAsignado VARCHAR(100)
			,@Permitidos VARCHAR(300);

		SELECT @IdTipoVehiculoViaje = V.IdTipoVehiculo
			,@CampoOriginal = LTRIM(RTRIM(V.Varchar6))
			,@IdVehiculo = V.IdVehiculo
		FROM Viaje V
		WHERE V.IdViaje = @IdViaje

		/* Varchar6 guarda el IdTipoVehiculo original como texto (ej. '208') */
		IF ISNULL(@CampoOriginal, '') = ''
		BEGIN
			/* Vacio: se guarda el tipo actual solo la primera vez (1 = Pendiente de Asignacion) */
			IF @IdTipoVehiculoViaje > 1
			BEGIN
				UPDATE Viaje
				SET Varchar6 = CONVERT(VARCHAR(10), @IdTipoVehiculoViaje)
				WHERE IdViaje = @IdViaje
					AND ISNULL(LTRIM(RTRIM(Varchar6)), '') = ''

				SET @IdTipoVehiculoOriginal = @IdTipoVehiculoViaje
			END
		END
		ELSE IF TRY_CONVERT(INT, @CampoOriginal) > 1
			SET @IdTipoVehiculoOriginal = TRY_CONVERT(INT, @CampoOriginal)
		ELSE
			SET @CampoEnUso = 1 /* Varchar6 tiene otro dato: no se modifica ni se valida */

		/* Validacion del vehiculo asignado contra la matriz de asignacion */
		IF @IdTipoVehiculoOriginal IS NOT NULL
			AND EXISTS (
				SELECT 1
				FROM ReglaAsignacionVehiculo WITH (NOLOCK)
				WHERE IdTipoVehiculoViaje = @IdTipoVehiculoOriginal
				) /* Tipo original parametrizado en la matriz */
		BEGIN
			SELECT @IdTipoVehiculoAsignado = IdTipoVehiculo
			FROM Vehiculo WITH (NOLOCK)
			WHERE IdVehiculo = @IdVehiculo

			/* Vehiculo inexistente o "Sin Asignar" (tipo 1): el viaje no tiene vehiculo asignado */
			SET @IdTipoVehiculoAsignado = ISNULL(@IdTipoVehiculoAsignado, 1)

			IF @IdTipoVehiculoAsignado <= 1
				SET @SinVehiculo = 1

			IF @SinVehiculo = 1
				OR NOT EXISTS (
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

				IF @SinVehiculo = 1
					SET @Mensaje = LEFT('El viaje no tiene un vehiculo asignado. Tipos permitidos para ' + ISNULL(@NombreOriginal, 'Id ' + CONVERT(VARCHAR(10), @IdTipoVehiculoOriginal)) + ': ' + ISNULL(@Permitidos, 'ninguno') + '.', 500)
				ELSE
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
			'ValidarTipoVehiculo'
			,CASE
				WHEN ISNULL(@Mensaje, '') <> ''
					THEN 'Rechazado IdViaje=' + Convert(VARCHAR, @IdViaje) + ' Original=' + Convert(VARCHAR, @IdTipoVehiculoOriginal) + ' Asignado=' + Convert(VARCHAR, @IdTipoVehiculoAsignado)
				WHEN @CampoEnUso = 1
					THEN 'Varchar6 con otro dato, no se valida IdViaje=' + Convert(VARCHAR, @IdViaje) + ' Valor=' + LEFT(@CampoOriginal, 30)
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
			'ValidarTipoVehiculo'
			,'IdViaje=' + Convert(VARCHAR, @IdViaje) + ' Error :' + ERROR_MESSAGE()
			,getutcdate()
			)
	END CATCH
END
GO
