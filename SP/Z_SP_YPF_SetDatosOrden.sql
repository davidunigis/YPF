USE [UNIGIS_DataRepository_YPF]
GO
/****** Objeto: StoredProcedure [dbo].[Z_SP_YPF_SetDatosOrden] Fecha de script: 07/10/2026 04:21:43 p. m. ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- ==========================================================================================
-- Author           : UNIGIS
-- Create date      : 2 Febrero 2023
-- Description      : Se actualizan datos de las ordenes una ves que se crean por proceso.
-- 
----------------------------------------------------------------------------------
-- Fecha		Descripcion											Responsable
----------------------------------------------------------------------------------   			
-- 30-11-2023  Se suma actualizacion codigo producto por error en carga 
--			   de archivos manuales por cliente ypf				 
----------------------------------------------------------------------------------
-- 07-10-2026  Se agrega salida temprana para ordenes de la operacion 141
--			   (Orden.IdOperacion = 141): no se ejecuta el SP ni se inserta Log.	David de la Cruz
----------------------------------------------------------------------------------
-- Parametros : Se debe recibir el IdOrden
-- ==========================================================================================
ALTER Procedure [dbo].[Z_SP_YPF_SetDatosOrden] @IdOrden BigInt
As
Begin 
/*
Modificado: 07/10/2026 - David de la Cruz
Cambio: se agrega Set NoCount On y una salida temprana (If Exists ... Return 0) para que el SP
        no se ejecute en órdenes de la operación 141 (Orden.IdOperacion = 141).
        Para el resto de operaciones el comportamiento no cambia.
        En órdenes de la 141 tampoco se inserta registro en Log.
*/
Set NoCount On;

-- Salida inmediata para órdenes de la operación 141
If Exists (
		Select 1
		From Orden With(NoLock)
		Where IdOrden = @IdOrden
			And IdOperacion = 141
		)
	Return 0;

Begin Try


/*********************************************************************************/
/*  		Actualiza categoria de orden para que sea igual a la del pedido		 */
/*********************************************************************************/
Declare
@TipoOrden As BigInt

Set @TipoOrden = (Select IdTipoOrden From Orden With(NoLock) Where IdOrden = @IdOrden)

If @TipoOrden In (Select IdTipoOrden From TipoOrden Where Nivel = 0) --Or ( Select 1 From Orden O With(NoLock) Where IdOrden = @IdOrden And IdOperacion = 6 ) = 1 
    Begin
		Return
	End

/*********************************************************************************/
/*  Se asigna valores en campos dyn de la orden y ordenitem para comunicacion	 */
/*  con INFOR solo para el caso de que sea un pedido con salida o entrada   	 */
/*  asociada a un almacen de infor.											   	 */
/*********************************************************************************/
IF ((select 1 from orden o With(NoLock) inner join ClienteOrden co With(NoLock) on co.IdClienteOrden=o.IdClienteOrden 
inner join z_WMSWarehouse zwwh With(NoLock) on zwwh.PropietarioWMS=co.RefClienteExterna 
where o.IdOrden=@IdOrden)=1)
BEGIN
	IF (select top 1 1 from OrdenItem_Dyn With(NoLock) where IdOrdenItem in (select IdOrdenItem from OrdenItem With(NoLock) where IdOrden in (@IdOrden) and ISNULL(Descripcion,'')<>'Pack')) IS NULL
		insert OrdenItem_Dyn (IdOrdenItem) select IdOrdenItem from OrdenItem With(NoLock) where IdOrden in (@IdOrden) and ISNULL(Descripcion,'')<>'Pack'
	IF (select 1 from Orden_Dyn With(NoLock) where IdOrden in (@IdOrden)) IS NULL
		insert Orden_Dyn (IdOrden) select IdOrden from Orden With(NoLock) where IdOrden in (@IdOrden)
	update OrdenItem_Dyn set
	PosItemExterno=T.PosItemExterno
	from (select oi.IdOrdenItem,oidot.PosItemExterno from OrdenItem oi  With(NoLock)
	inner join OrdenItemPedidoItem oipi With(NoLock) on oipi.IdPedidoItem=oi.IdPedidoItem 
	inner join OrdenItem oiOt With(NoLock) on oiOt.IdOrdenItem=oipi.IdOrdenItem
	inner join OrdenItem_dyn oidot With(NoLock) on oidot.IdOrdenItem=oiOt.IdOrdenItem
	where oi.IdOrden=@IdOrden AND ISNULL(oi.Descripcion,'')<>'Pack')T
	where OrdenItem_Dyn.IdOrdenItem=T.IdOrdenItem
	update Orden_Dyn set
	ClaseDocMov=T.ClaseDocMov
	from (select top 1 o.IdOrden,odot.ClaseDocMov from Orden o With(NoLock)
	inner join OrdenPedido op With(NoLock) on op.IdPedido=o.IdPedido 
	inner join Orden_dyn odot With(NoLock) on odot.IdOrden=op.IdOrden
	where o.IdOrden=@IdOrden)T
	where Orden_Dyn.IdOrden=@IdOrden
	update o set
	PropietarioWMS=zwwh.PropietarioWMS,
	IdEstadoOrden=69,
	MultiplicadorCarga=null
	from orden o  With(NoLock)
	inner join ClienteOrden co With(NoLock) on co.IdClienteOrden=o.IdClienteOrden 
	inner join z_WMSWarehouse zwwh With(NoLock) on zwwh.PropietarioWMS=co.RefClienteExterna 
	where o.IdOrden=@IdOrden
	update OrdenItem 
	set CodigoProducto=(REPLACE(REPLACE(REPLACE(CodigoProducto,'0000000000',''),'000000000',''),'00000000',''))
	where IdOrden=@IdOrden and CodigoProducto like '00000000%'
END

--Hereda UM de OT
update OrdenItem set
	IdUnidadMedida=T.IdUnidadMedida
	from (select oi.IdOrdenItem,oiOt.IdUnidadMedida from OrdenItem oi  With(NoLock)
	inner join OrdenItemPedidoItem oipi With(NoLock) on oipi.IdPedidoItem=oi.IdPedidoItem 
	inner join OrdenItem oiOt With(NoLock) on oiOt.IdOrdenItem=oipi.IdOrdenItem
	where oi.IdOrden=@IdOrden AND ISNULL(oi.Descripcion,'')<>'Pack')T
	where OrdenItem.IdOrdenItem=T.IdOrdenItem


	-- Se actualiza Tramo(Varchar1) de la Orden de pickup, ya que se crea antes del delivery
/* se asigna grupo ruta segun tramo asociado para el ruteo. */ 

Declare
@Corredor As Varchar(30),
@Pedido AS BIGINT,
@IdTipoPedido	As BigInt,
@IdEstadoPedido	As BigInt,
@IdDepositoSalida As BigInt,
@IdDepositoLlegada As BigInt,
@IdJornada	As BigInt,
@OrdenesJornada AS int
select	@Pedido		=IdPedido,
		@IdJornada	=IdJornada
from Orden With(NoLock) where IdOrden=@IdOrden

Select  @IdDepositoSalida	= IdDepositoSalida,
		@IdDepositoLlegada	= IdDepositoLlegada,
		@IdTipoPedido		= IdTipoPedido,
		@IdEstadoPedido		= IdEstadoPedido
		From Pedido With(NoLock) Where IdPedido = @Pedido


DECLARE @Origen Varchar(4),
		@Destino varchar (4);
Set @Origen= ISNULL((select GrupoTramo from DomicilioOrden With(NoLock) where IdDomicilioOrden in (Select IdDomicilioOrden2 from Pedido With(NoLock) where IdPedido in (Select IdPedido From Orden With(NoLock) where IdOrden=@IdOrden)) and @IdDepositoSalida IS NULL),
						(Select GrupoTramo From Deposito With(NoLock) Where IdDeposito in (Select @IdDepositoSalida from Pedido With(NoLock) where IdPedido in (Select IdPedido From Orden With(NoLock) where IdOrden=@IdOrden)))) 
Set @Destino=ISNULL((select GrupoTramo from DomicilioOrden With(NoLock) where IdDomicilioOrden in (Select IdDomicilioOrden from Pedido With(NoLock) where IdPedido in (Select IdPedido From Orden With(NoLock) where IdOrden=@IdOrden)) and @IdDepositoLlegada IS NULL),
						(Select GrupoTramo From Deposito With(NoLock) Where IdDeposito in (Select IdDepositoLlegada from Pedido With(NoLock) where IdPedido in (Select IdPedido From Orden With(NoLock) where IdOrden=@IdOrden))))

--IF (ISNULL((Select top 1 1 From Jornada With(NoLock) Where IdOperacion=1),0)=0)
--	INSERT INTO Jornada (IdOperacion,IdEstadoJornada,Descripcion,Fecha,FechaCreacion,Activa,Eliminado) Values (1,1,'Jornada Default',GETUTCDATE(),GETUTCDATE(),1,0)

	/* ***					Movemos la Orden a Jornada de Operacion Default	
						Se asigna Tramo en campo varchar1****	*/
Update 
	o1 
Set 
	IdJornada   = CASE WHEN (o1.IdOperacion in (2,6) and @IdEstadoPedido<>4) THEN ( Select top 1 IdJornada from Jornada where IdOperacion = 1 order by 1 desc )
	Else IdJornada END,
	Telefono3   = 'SetDatosOrden_CambioJornada=' + Convert(varchar, IdJornada),
	varchar4	= @Origen,
	Varchar1    = @Origen + '-' + @Destino,
	Varchar2	= @Destino
	
	 from orden o1 With(NoLock) inner join pedido p With(NoLock) on p.IdPedido=o1.IdPedido
Where 
	 o1.idorden=@IdOrden
select @Corredor=Varchar1 from orden With(NoLock) where IdOrden=@IdOrden
If @IdTipoPedido In ( 2, 45, 46, 50, 52, 57 )
Begin
	If ( @IdEstadoPedido = 1083 Or @IdEstadoPedido = 1106 Or @IdEstadoPedido = 1113 )
	Begin
		If ( @IdDepositoSalida Is Not Null AND (Select 1 from Orden With(NoLock) where IdOrden=@IdOrden and IdDepositoSalida IS NULL and Tipo='P')=1)
		Begin
			Update
				Orden 
			Set
				Eliminado = 1
			Where
				IdOrden=@IdOrden
			Return
		End
	End
End

	If ( @IdDepositoSalida Is Not Null)
		Begin
			Update
				Orden 
			Set
				IdOrdenRecoleccion = (Select top 1 IdOrden from Orden op With(NoLock) where op.IdPedido=@Pedido and op.Tipo='P' and op.IdEstadoOrden in (69,100) and op.IdEstadoOrden<>84 
				and op.Eliminado=0 and op.RefOrdenExterna=Orden.RefOrdenExterna)
			Where
				IdOrden=@IdOrden and Tipo='D'
			Update
				Od 
			Set
				Od.IdOrdenRecoleccion = @IdOrden
				From Orden Od With(NoLock) inner join Orden Op With(NoLock)  
				on Op.RefOrdenExterna=Od.RefOrdenExterna and Od.Tipo='D' AND Od.IdEstadoOrden in (69,100) and Od.IdEstadoOrden<>84 and Od.Eliminado=0
			Where
				Op.IdOrden=@IdOrden and Op.Tipo='P'
		End
		Update 
		Orden 
		Set 
		GrupoRutas=Convert(int,REPLACE(REPLACE(REPLACE(@Corredor,'R',''),' ',''),'-',''))
		Where 
		IdOrden = @IdOrden
		Update Op 
		set 
		Varchar1=oD.Varchar1,
		GrupoRutas=oD.GrupoRutas
		From Orden Op With(NoLock) inner join Orden Od With(NoLock) on Op.IdOrden=Od.IdOrdenRecoleccion
		Where oD.IdOrden=@IdOrden
		--Update Pedido set IdDomicilioOrden2=Float3 where IdPedido=@Pedido and Float3 is not null
/* se actualiza corredor actual del pedido*/

Update Pedido_Dyn
Set
	CorredorActual=@Corredor
Where IdPedido=@Pedido

Update
    Pack_Dyn
Set
    CorredorActual = @Corredor
From
    Pack Pk With(NoLock)
Where
        Pk.IdPack   = Pack_Dyn.IdPack
    And Pk.IdPedido = @Pedido

/* ***	 updateo grupo consolidacion de la orden  ***	 */
UPDATE 
	Orden
SET    
    --CantidadDias		= 10,
    Ruteable			= 1,
	GrupoConsolidacion  = Pe.IdPedido,
    IdCategoriaOrden	= Co.IdCategoriaOrden,
	int2=ISNULL(Orden.int2,0)+1,
	InicioHorario1=pe.InicioHorario1,
	FinHorario1=pe.FinHorario1
From
	Pedido					Pe With(NoLock) 
	LEFT JOIN CategoriaPedido	Cp With(NoLock) On Cp.IdCategoriaPedido = Pe.IdCategoriaPedido
	LEFT JOIN CategoriaOrden		Co with(NoLock) On Co.ReferenciaExterna = Cp.ReferenciaExterna
WHERE 
		Pe.IdPedido		= Orden.IdPedido
	And IdOrden			= @IdOrden

/* ***	 updateo Orden Varchar 9 ***	 */

		update o set
	Varchar3=pd.NumRemitoPickUp,
	Varchar9=p.ReferenciaOT
	from orden o  With(NoLock)
	inner join pedido p With(NoLock) on p.idPedido=o.IdPedido
	Left join pedido_dyn pd With(NoLock) on pd.IdPedido=p.IdPedido
	where o.IdOrden=@IdOrden

/** se actualiza region actual pedido*/
Update Pedido
Set
	Varchar1= @Origen
Where IdPedido=@Pedido

/* ***					Eliminamos Jornada de Orden						****	*/
select @OrdenesJornada=COUNT(IdOrden) from Orden With(NoLock) where IdJornada=@IdJornada and IdEstadoOrden<>84
Update 
	Jornada 
Set 
	Descripcion = '-X-'+Descripcion
Where 
	IdJornada = @IdJornada And Descripcion like 'Creada desde Pedido%' 
	and IdOperacion in (2,6) and @IdEstadoPedido<>4 and @OrdenesJornada=0

Update 
	Jornada 
Set 
	Descripcion = '-X-'+Descripcion
Where
	IdJornada = @IdJornada And Descripcion like 'Creada desde Pack%' 
	and IdOperacion in (2,6) and @IdEstadoPedido<>4 and @OrdenesJornada=0


	Insert Log (Categoria, Descripcion, FechaHora) Values ('SetDatosOrden', 'OK IdOrden=' + Convert(varchar, @IdOrden), getutcdate())
End Try
Begin Catch
	Insert Log (Categoria, Descripcion, FechaHora) Values ('SetDatosOrden', 'IdOrden=' + Convert(varchar, @IdOrden)+' Ex:'+ ERROR_MESSAGE(), getutcdate())
End Catch
End
