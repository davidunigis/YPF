USE [UNIGIS_DataRepository_YPF]
GO
/****** Objeto: StoredProcedure [dbo].[Z_SP_YPF_TransporteAsinacionManual] ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[Z_SP_YPF_TransporteAsinacionManual] @IdViaje bigInt 

AS BEGIN 
	/*
	Modificado: 22/10/2026 - David de la Cruz
	Cambio: se agrega una salida temprana para que el SP no valide viajes cuya jornada pertenece a la
	        operacion 141 (Viaje.IdJornada -> Jornada.IdOperacion = 141). Como es un SP de validacion que
	        devuelve [Resultado]/[Mensaje], en esos viajes devuelve 'OK' (no valida, no bloquea), igual que
	        ya hace el SP con las jornadas excluidas de abajo, y no inserta registro en Log.
	        Para el resto de operaciones el comportamiento no cambia. Se usa CREATE OR ALTER para poder
	        aplicarlo exista o no el SP.
	*/

SET NOCOUNT ON; 

-- Salida inmediata para viajes de la operacion 141: no se valida, se devuelve OK
IF EXISTS (
		SELECT 1
		FROM Viaje WITH (NOLOCK)
		JOIN Jornada WITH (NOLOCK) ON Viaje.IdJornada = Jornada.IdJornada
		WHERE Viaje.IdViaje = @IdViaje
			AND Jornada.IdOperacion = 141
		)
BEGIN
	SELECT 'OK' [Resultado], NULL [Mensaje];
	RETURN 0;
END

begin try

 

DECLARE @Mensaje VARCHAR(500) = ''

 

/*Validaciones*/ 

    SELECT @Mensaje= 

        Case 

            When (Select IdTransporte From Seguimiento where IdSeguimiento=(Select IdSeguimiento from Viaje where IdViaje=@IdViaje))<>(Select IdTransporte from Vehiculo where IdVehiculo=(Select IdVehiculo From Viaje where IdViaje=@IdViaje))

            Then 'Transporte del vehiculo debe coincidir con el del viaje'

			When (Select IdTransporte from Vehiculo where IdVehiculo=(Select IdVehiculo From Viaje where IdViaje=@IdViaje))=1

            Then 'Transporte del vehiculo debe ser distinto a NO DETERMINADO'

			When (Select IdTipoVehiculo from Vehiculo where IdVehiculo=(Select IdVehiculo From Viaje where IdViaje=@IdViaje))<>(Select IdTipoVehiculo from Ruta where IdRuta=(Select IdRutaFK from Viaje where IdViaje=@IdViaje))

            Then 'El tipo de vehiculo asignado al viaje debe ser igual al solicitado en la Ruta'


        End 

        From Viaje v With(NoLock) 

            WHERE V.IdViaje=@IdViaje 
			and v.IdJornada not in (Select top 500 IdJornada from jornada Where idoperacion in (3,4) order by idjornada desc)

     

/*Si Mensaje no es vacío se devuelve NULL y el mensaje a mostrar*/ 

    IF ISNULL(@Mensaje,'')<>'' 

        SELECT NULL [Resultado], @Mensaje [Mensaje] 

        ELSE SELECT 'OK' [Resultado], NULL [Mensaje]

 

Insert log (Categoria,Descripcion,FechaHora) values ('TransporteAsinacionManual','Proceso_Ejecutado_Exito ' + CONVERT(VARCHAR, @IdViaje) ,getutcdate()) end try 

begin catch insert log (Categoria,Descripcion,FechaHora) values ('TransporteAsinacionManual','Error:'+ CONVERT(VARCHAR, @IdViaje) +ERROR_MESSAGE(),getutcdate()) end catch 

END
