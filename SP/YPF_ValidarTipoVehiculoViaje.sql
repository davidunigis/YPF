/* =============================================================================
   YPF_ValidarTipoVehiculoViaje
   -----------------------------------------------------------------------------
   Valida que el vehiculo asignado a un viaje sea de un tipo habilitado segun la
   matriz de asignacion (Z_MatrizAsignacionVehiculo, leida a traves de la vista
   ReglaAsignacionVehiculo). Ver Tablas/Z_MatrizAsignacionVehiculo.sql.

   Responde igual que YPF_PreSetDatosViaje (UNIGIS lee Resultado / Mensaje):
     Resultado = 'OK'  , Mensaje = NULL   -> se puede continuar
     Resultado = NULL  , Mensaje = texto  -> no se permite; se muestra el texto

   DE DONDE SALE EL TIPO DE VEHICULO REQUERIDO
     De Viaje.Varchar6, que llega de la entidad anterior. Viaje.IdTipoVehiculo NO
     se usa (por ahora esta en NULL). El SP no modifica el viaje: solo lee y
     escribe en Log. Varchar6 puede traer, probado en este orden:
       1) El IdTipoVehiculo                          ej. '208'
       2) La referencia externa del tipo             TipoVehiculo.RefVehiculoExterno
       3) El nombre del tipo como figura en la matriz ej. 'HG TI  30-35 tn/m'
          (no distingue mayusculas ni espacios repetidos)

   QUE HACE
     1) Determina el tipo requerido a partir de Varchar6:
          - Varchar6 vacio                       -> OK (no hay tipo que validar)
          - Varchar6 que no corresponde a un tipo -> Mensaje (no se pudo determinar)
     2) Compara el tipo del vehiculo asignado (Viaje.IdVehiculo) con la matriz:
          - Tipo requerido sin fila en la matriz (no parametrizado) -> OK
          - Vehiculo de un tipo con "x" en la matriz                -> OK
          - Vehiculo "Sin Asignar" (tipo 1) o sin vehiculo          -> Mensaje
          - Vehiculo de un tipo sin "x" en la matriz                -> Mensaje

   CUANDO LLAMARLO (configurarlo en UNIGIS)
     Cuando el viaje ya debe tener un vehiculo valido (asignar, confirmar o
     publicar). Todo viaje nace con el vehiculo "Sin Asignar", asi que si se llama
     al crearlo responde con Mensaje.

   PRUEBA
     EXEC dbo.YPF_ValidarTipoVehiculoViaje @IdViaje = <IdViaje>
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
			,@LogDescripcion VARCHAR(200) = NULL
			,@TipoRequerido VARCHAR(100)
			,@TipoRequeridoNormalizado NVARCHAR(100)
			,@IdTipoVehiculoOriginal INT
			,@IdVehiculo INT
			,@IdTipoVehiculoAsignado INT
			,@SinVehiculo BIT = 0
			,@NombreOriginal VARCHAR(100)
			,@NombreAsignado VARCHAR(100)
			,@Permitidos VARCHAR(300);

		SELECT @TipoRequerido = LTRIM(RTRIM(V.Varchar6))
			,@IdVehiculo = V.IdVehiculo
		FROM Viaje V
		WHERE V.IdViaje = @IdViaje

		/* Tipo de vehiculo requerido: viene en Varchar6 desde la entidad anterior */
		IF ISNULL(@TipoRequerido, '') = ''
			SET @LogDescripcion = 'Varchar6 vacio, no se valida IdViaje=' + Convert(VARCHAR, @IdViaje)
		ELSE
		BEGIN
			/* 1) Varchar6 trae el IdTipoVehiculo (1 = Pendiente de Asignacion, no cuenta) */
			SELECT @IdTipoVehiculoOriginal = IdTipoVehiculo
			FROM TipoVehiculo WITH (NOLOCK)
			WHERE IdTipoVehiculo = TRY_CONVERT(INT, @TipoRequerido)
				AND IdTipoVehiculo > 1

			/* 2) Varchar6 trae la referencia externa del tipo */
			IF @IdTipoVehiculoOriginal IS NULL
				SELECT TOP 1 @IdTipoVehiculoOriginal = IdTipoVehiculo
				FROM TipoVehiculo WITH (NOLOCK)
				WHERE RefVehiculoExterno = @TipoRequerido
					AND IdTipoVehiculo > 1
				ORDER BY IdTipoVehiculo

			/* 3) Varchar6 trae el nombre del tipo como figura en la matriz */
			IF @IdTipoVehiculoOriginal IS NULL
			BEGIN
				SET @TipoRequeridoNormalizado = REPLACE(REPLACE(REPLACE(REPLACE(@TipoRequerido, NCHAR(160), N' '), N'  ', N' '), N'  ', N' '), N'  ', N' ')

				SELECT TOP 1 @IdTipoVehiculoOriginal = Id
				FROM Z_MatrizAsignacionVehiculo WITH (NOLOCK)
				WHERE REPLACE(REPLACE(REPLACE(REPLACE(TipoViaje, NCHAR(160), N' '), N'  ', N' '), N'  ', N' '), N'  ', N' ') = @TipoRequeridoNormalizado
				ORDER BY Id
			END

			IF @IdTipoVehiculoOriginal IS NULL
			BEGIN
				SET @Mensaje = LEFT('No se pudo determinar el tipo de vehiculo requerido del viaje (Varchar6 = ' + @TipoRequerido + ').', 500)
				SET @LogDescripcion = 'Tipo requerido no reconocido IdViaje=' + Convert(VARCHAR, @IdViaje) + ' Valor=' + LEFT(@TipoRequerido, 30)
			END
		END

		/* Validacion del vehiculo asignado contra la matriz de asignacion */
		IF @IdTipoVehiculoOriginal IS NOT NULL
			AND EXISTS (
				SELECT 1
				FROM ReglaAsignacionVehiculo WITH (NOLOCK)
				WHERE IdTipoVehiculoViaje = @IdTipoVehiculoOriginal
				) /* Tipo requerido parametrizado en la matriz */
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

				SET @LogDescripcion = 'Rechazado IdViaje=' + Convert(VARCHAR, @IdViaje) + ' Original=' + Convert(VARCHAR, @IdTipoVehiculoOriginal) + ' Asignado=' + Convert(VARCHAR, @IdTipoVehiculoAsignado)
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
			,ISNULL(@LogDescripcion, 'OK IdViaje=' + Convert(VARCHAR, @IdViaje))
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
