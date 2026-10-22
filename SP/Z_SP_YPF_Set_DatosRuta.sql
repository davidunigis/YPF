USE [UNIGIS_DataRepository_YPF]
GO
/****** Objeto: StoredProcedure [dbo].[Z_SP_YPF_Set_DatosRuta] Fecha de script: 22/10/2026 12:38:15 p. m. ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER Procedure [dbo].[Z_SP_YPF_Set_DatosRuta] @IdRuta BigInt As Begin
	/*
	Modificado: 22/10/2026 - David de la Cruz
	Cambio: se agrega SET NOCOUNT ON y una salida temprana (IF EXISTS ... RETURN 0) para que el SP
	        no se ejecute en rutas cuya jornada pertenece a la operacion 141
	        (Ruta.IdJornada -> Jornada.IdOperacion = 141). Para el resto de operaciones
	        el comportamiento no cambia. En rutas de la 141 tampoco se inserta registro en Log.
	*/
	SET NOCOUNT ON;

	-- Salida inmediata para rutas de la operacion 141
	IF EXISTS (
		SELECT 1
		FROM Ruta With(NoLock)
		JOIN Jornada With(NoLock) ON Ruta.IdJornada = Jornada.IdJornada
		WHERE Ruta.IdRuta = @IdRuta
			AND Jornada.IdOperacion = 141
	)
		RETURN 0;

	Begin try
		DECLARE @IdOperacion Bigint=0,@IdPedido Bigint=0,@IdEstadoPedido Int=0,@Ruta Bigint=0,@IdJornada Bigint=0,@TvSugerido Varchar (50)=''
		SELECT TOP 1 @IdOperacion=P.IdOperacion,@IdPedido=P.IdPedido,@IdJornada=O.IdJornada,@Ruta=R.Ruta,@IdEstadoPedido=P.IdEstadoPedido
		from Pedido P With(NoLock)
		inner join Orden O With(NoLock) ON O.IdPedido=P.IdPedido
		inner join Ruta R  With(NoLock) ON R.IdJornada=O.IdJornada and R.Ruta=O.IdRuta
		Where R.IdRuta=@IdRuta
		/* validar variables*/
		/*SELECT  @IdOperacion ,@IdPedido ,@Ruta ,@IdJornada ,@IdEstadoPedido*/
		IF(@IdOperacion in (2,6))
		Begin
			Update
				Ruta
			set
				IdConductor = 1,
				IdVehiculo = 7
			Where
			IdRuta = @IdRuta
			/* ***  Cargo en OrdenItem la Unidad Requerida de existir en cada uno de ellos    ***  */
			Update oi
					Set varchar1 =t.TipoUnidadRequerida
					From
					OrdenItem oi
					inner join Orden o						With(NoLock)   ON o.IdOrden					= oi.IdOrden
					inner join Producto p					With(NoLock)   ON p.IdProducto				= oi.IdProducto
					inner join Z_TipoVehiculoOcupacion t	With(NoLock)   ON t.CodigoMaterial			= p.ReferenciaExterna
					inner join ruta r						With(NoLock)   ON r.idjornada				= o.idjornada and r.ruta=o.IdRuta
					Where
						r.IdRuta = @IdRuta
			/* ***  Update la Orden con el Tipo de Vehiculo Sugerido    ***  */
			SET @TvSugerido= (Case When (Select Count(Distinct Varchar1) From OrdenItem oi With(NoLock)
							Where oi.IdOrden in (Select IdOrden from orden With(NoLock) where IdRuta=@Ruta and IdJornada=@IdJornada)) > 1
							Then 'Distintos Tipos de Vehiculos Sugeridos'
							ELSE (Select Top 1 Varchar1 From OrdenItem With(NoLock) Where IdOrden in (Select IdOrden from orden With(NoLock) where IdRuta=@Ruta and IdJornada=@IdJornada))
							end)
			Update
					Orden
					Set Telefono2 = @TvSugerido
					where IdRuta=@Ruta and IdJornada=@IdJornada and @TvSugerido is not null
			/* ***  Update la Ruta con el Tipo de Vehiculo Sugerido    ***  */
			Update
					Ruta
					Set Varchar1 = @TvSugerido
					where IdRuta=@IdRuta and @TvSugerido is not null
			/* ***  Exec [dbo].[Z_SP_YPF_MoverRutaYViajeB2B] @IdRuta */
			/*Actualizo distancia y tiempos de la ruta con KM reales, restando los del depo a la primera igual    ***  */
		end
		Update Ruta
		Set
			Distancia            = ISNULL(Distancia,Distancia - DistanciaPrimeraDS),
			Tiempo                = ISNULL(Tiempo,Tiempo - TiempoPrimeraDS),
			TiempoViaje            =  ISNULL(Tiempo,Tiempo - TiempoPrimeraDS)
		Where
			IdRuta=@IdRuta and DistanciaPrimeraDS is not null
		/* ***  Se genera cambio estado solicitud para generar viajes en estado de pedido 4    ***  */
		IF(@IdEstadoPedido=4) BEGIN
			/* *** INSERT [dbo].[CambioEstadoSolicitud] ([Entidad], [IdEntidad], [IdEstadoDestino], [ValidarTransicion], [MismoEstado], [FechaCreacion], [FechaEjecucion], [Observacion], [Estado], [Intento])
					VALUES (N'Ruta',@IdRuta, 10, 0, 1, GETUTCDATE(), GETUTCDATE(),'Cambio realiazado por IdRuta:'+Convert(varchar, @IdRuta),'',0)***  */
			Update Ruta set IdEstadoRuta=8 where IdRuta=@IdRuta
				DECLARE @IdOrden BIGINT;
				DECLARE @IdEstadoOrden INT;
				DECLARE db_cursor CURSOR FOR
				SELECT IdOrden,IdEstadoOrden
				FROM Orden With(NoLock)
				WHERE Orden.IdPedido = @IdPedido
				OPEN db_cursor
				FETCH NEXT FROM db_cursor INTO @IdOrden,@IdEstadoOrden;
				WHILE @@FETCH_STATUS = 0
					BEGIN
					IF (@IdEstadoOrden=69)
						INSERT [dbo].[CambioEstadoSolicitud] ([Entidad], [IdEntidad], [IdEstadoDestino], [ValidarTransicion], [MismoEstado], [FechaCreacion], [FechaEjecucion], [Observacion], [Estado], [Intento])
						VALUES (N'Orden',@IdOrden, 97, 0, 0, GETUTCDATE(), GETUTCDATE(),'Cambio realiazado por IdRuta:'+Convert(varchar, @IdRuta),'',0)
					ELSE
					IF (@IdEstadoOrden=100)
						BEGIN
							INSERT [dbo].[CambioEstadoSolicitud] ([Entidad], [IdEntidad], [IdEstadoDestino], [ValidarTransicion], [MismoEstado], [FechaCreacion], [FechaEjecucion], [Observacion], [Estado], [Intento])
									VALUES (N'Orden',@IdOrden, 70, 0, 0, GETUTCDATE(), GETUTCDATE(),'Cambio realiazado por IdRuta:'+Convert(varchar, @IdRuta),'',0)
						END
					FETCH NEXT FROM db_cursor INTO @IdOrden,@IdEstadoOrden
					END
				CLOSE db_cursor
				DEALLOCATE db_cursor
		END
		Insert Log (Categoria, Descripcion, FechaHora) Values ('SetDatosRuta', 'OK IdRuta=' + Convert(varchar, @IdRuta), getutcdate())
	End Try
	Begin Catch
		Insert log (Categoria, Descripcion, FechaHora) Values ('SetDatosRuta', 'IdRuta=' + Convert(varchar, @IdRuta) + ' Error :' + ERROR_MESSAGE(), getutcdate())
	End Catch
End
