USE [UNIGIS_DataRepository_YPF]
GO
/****** Objeto: StoredProcedure [dbo].[Z_SP_YPF_TransporteAsinacionManual] ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[Z_SP_YPF_TransporteAsinacionManual] @IdViaje bigInt 

AS BEGIN 

SET NOCOUNT ON; 

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
