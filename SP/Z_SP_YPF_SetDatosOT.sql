USE [UNIGIS_DataRepository_YPF]
GO
/****** Objeto: StoredProcedure [dbo].[Z_SP_YPF_SetDatosOT] Fecha de script: 07/10/2026 04:07:11 p. m. ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER Procedure [dbo].[Z_SP_YPF_SetDatosOT] @IdOrden BigInt 
As Begin   
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

If IsNull((Select 1 From Orden With(NoLock) Where IdTipoOrden In (Select IdTipoOrden From TipoOrden Where Nivel = 0) And IdOrden = @IdOrden), 0) <> 1
Begin
	Return
End

/***		P.LP-152 Asignacion de depositos		***/

Declare 
@IdDepositoSalida As BigInt

Set @IdDepositoSalida = (
       Select 
             Case 
                    When Tipo.ReferenciaExterna In ('OCCIP', 'PDTHUB', 'COMEX') Then 2
                    When Tipo.ReferenciaExterna = 'OCCMZ'                       Then 5
                    When Tipo.ReferenciaExterna = 'OCCNQ'                       Then 6              
                    When Tipo.ReferenciaExterna = 'OCCCH'                       Then 7
                    When Tipo.ReferenciaExterna = 'PDTBAHIABLANCA'              Then 11
             End
       From 
				 Orden		O    With(NoLock)
			Join TipoOrden  Tipo With(NoLock) On Tipo.IdTipoOrden = O.IdTipoOrden
       Where 
			O.IdOrden = @IdOrden

       )

If @IdDepositoSalida Is Not Null
Begin
	Update
		Orden
	Set
		IdDepositoSalida = @IdDepositoSalida
	Where
		IdOrden = @IdOrden

	Update 
		OrdenItemOT
	Set
		IdDepositoSalida = @IdDepositoSalida
	From
			 OrdenItem  Oi With(NoLock)
		Join Orden      O   With(NoLock) On O.IdOrden = Oi.IdOrden
	Where 
			Oi.IdOrdenItem = OrdenItemOT.IdOrdenItem
		And O.IdOrden = @IdOrden
End

/* ***		P.LP-007 Para asignación de domicilios delivery	****   */  

		update oit 
		set oit.IdDomicilioOrden=ISNULL((Select top 1 IdDomicilioOrden from DomicilioOrden where IdClienteOrden=co.IdClienteOrden and RefDomicilioExterno not like '%No Determinado%' order by 1 asc),oit.IdDomicilioOrden)
		From ordenitemOt oit
		inner join ordenitem oi with (NoLock) ON oi.IdOrdenItem=oit.IdOrdenItem
		Inner Join ClienteOrden co With (NoLock) ON co.IdClienteOrden=oit.IdClienteOrden
		Inner Join Orden o With (NoLock) ON o.IdOrden=oi.IdOrden
		where 
		o.IdOrden=@IdOrden

/* ***		P.LP-007 Para asignación de domicilios pickup	****   */  

	update oit  
	set oit.IdDomicilioOrden2=isnull((Select top 1 IdDomicilioOrden from DomicilioOrden where IdClienteOrden=co.IdClienteOrden and RefDomicilioExterno not like '%No Determinado%' order by 1 asc),oit.IdDomicilioOrden2)
	From ordenitemOt oit
	Inner join OrdenItem oi With (NoLock) ON oi.IdOrdenItem=oit.IdOrdenItem
	Inner Join DomicilioOrden do With (NoLock) ON do.IdDomicilioOrden=oit.IdDomicilioOrden2
	Inner Join ClienteOrden co With (NoLock) ON co.IdClienteOrden=do.IdClienteOrden
	Inner Join Orden o With (NoLock) ON o.IdOrden=oi.IdOrden
	where 
	o.IdOrden=@IdOrden  

    /** Seteo estado de revisión a Orden y OrdenItem que no tienen DomicilioOrden **/
		/*Update OrdenItem
	set IdEstadoOrdenItem=4
	From OrdenItem oi
	Inner Join OrdenItemOT oit ON oit.IdOrdenItem=oi.IdOrdenItem
	Inner Join Orden o With (NoLock) ON o.IdOrden=oi.IdOrden
	Outer Apply (Select top 1 iddomicilioorden from DomicilioOrden where IdClienteOrden=oit.IdClienteOrden and RefDomicilioExterno like '%No Determinado%')d1
	Outer Apply (Select top 1 iddomicilioorden from DomicilioOrden where IdClienteOrden=(Select top 1 IdClienteOrden from DomicilioOrden where IdDomicilioOrden=oit.IdDomicilioOrden2) and RefDomicilioExterno like '%No Determinado%')d2
	where (d1.IddomicilioOrden=oit.IdDomicilioorden or d2.IdDomicilioOrden=oit.IdDomicilioOrden2) and o.IdOrden=@IdOrden*/

/***	P.LP-142 bis CantidadUnidadesTransporteUDT | P.LP-143 bis UDTRecibidas	***/

Update
       OrdenItem_Dyn
Set
       UDTRecibidas                  = (Oi.CantidadRecibida / Ztv.QMaterialesPorUnidad),
       CantidadUnidadesTransporteUDT = (Oi.Cantidad         / Ztv.QMaterialesPorUnidad)
From
            OrdenItem				Oi With(NoLock)
       Join Z_TipoVehiculoOcupacion Ztv With(NoLock) On Ztv.CodigoMaterial  = Oi.CodigoProducto
Where
		Oi.IdOrdenItem				= OrdenItem_Dyn.IdOrdenItem
	And Ztv.QMaterialesPorUnidad	> 0
    And Oi.IdOrden					= @IdOrden

/***			P.LP-144 - CampoDinamico.UDTPendientes			 ***/

Update
       OrdenItem_Dyn
Set
       UDTPendientes = (CantidadUnidadesTransporteUDT / UDTRecibidas)
From
       OrdenItemPedidoItem Oi With(NoLock)
Where
             Oi.IdOrdenItem = OrdenItem_Dyn.IdOrdenItem
       And UDTRecibidas     > 0
       And Oi.IdOrden       = @IdOrden

/***			P.LP-125 - Autocompletado de CECOS				***/

Declare
@ObjetoImputacionWS As Varchar(50),
@ObjetoImputacionZ  As Varchar(50),
@ReferenciaCliente  As Varchar(50)

Select 
	@ObjetoImputacionWS = Od.ObjetoImputacion,
	@ObjetoImputacionZ  = Zt.ObjetoImputacionTte,
	@ReferenciaCliente  = Co.RefClienteExterna
From 
	 OrdenItem                           Oi With(NoLock)
Join OrdenItem_Dyn                       Od With(NoLock) On Od.IdOrdenItem            = Oi.IdOrdenItem
Join Orden                               O  With(NoLock) On O.IdOrden                 = Oi.IdOrden
Left Join ClienteOrden                   Co With(NoLock) On Co.IdClienteOrden         = O.IdClienteOrden
Left Join Z_ObjetoImputacionTransporte   Zt With(NoLock) On Zt.ReferenciaClienteOrden = Co.RefClienteExterna
Where 
		Oi.IdOrden = Oi.IdOrden
	And Oi.IdOrden = @IdOrden

	--update OrdenItem_Dyn set ObjetoImputacionTransporte=ObjetoImputacion where IdOrdenItem in (Select IdOrdenItem from OrdenItem where IdOrden=@IdOrden)
	update OrdenItem_Dyn 
	set ObjetoImputacionTransporte=z.ObjetoImputacionTte
	From OrdenItem_Dyn oid
	Inner Join OrdenItem oi ON oi.IdOrdenItem=oid.IdOrdenItem
	Inner join OrdenItemOt oit on oit.IdOrdenItem=oi.IdOrdenItem
	Inner Join ClienteOrden co ON co.IdClienteOrden=oit.IdClienteOrden
	inner join Z_ObjetoImputacionTransporte z ON z.ReferenciaClienteOrden=co.RefClienteExterna
	where 
	(ObjetoImputacionTransporte='' 
	or  ObjetoImputacionTransporte is null)
	and co.RefClienteExterna=z.ReferenciaClienteOrden
	and oid.IdOrdenItem in (Select IdOrdenItem from OrdenItem where IdOrden=@IdOrden)

	/***		Updateo a estado de orden item donde objetoimputaciontransporte es nulo a req.validacion	  ***/

	update ordenitem set idestadoordenitem=4 
	where IdOrden=@IdOrden and idordenitem in 
	(Select oid.IdOrdenItem from OrdenItem_Dyn oid inner join OrdenItem oi ON oi.IdOrdenItem=oid.IdOrdenItem Inner Join Orden o ON o.IdOrden=oi.IdOrden 	
	Where o.IdOrden=@IdOrden and (oid.ObjetoImputacionTransporte='' or oid.ObjetoImputacionTransporte is null))

	/***		Updateo a estado de orden donde algun ot esta en req.validacion	  ***/

	update orden set idestadoorden=61 where 
	idorden in (Select top 1 o.idorden from orden o inner join OrdenItem oi ON oi.IdOrden=o.IdOrden Where oi.Idestadoordenitem=4 and o.IdOrden=@IdOrden)

/***		Cargamos elementos Requeridos 	  ***/
	Update
	temp
Set 
	ElementosRequeridos = t.elementosrequeridos 
From 
		 OrdenItem_Dyn temp 
	Join OrdenItem	  Pi On Pi.IdOrdenItem = temp.IdOrdenItem 
	join Z_TipoVehiculoOcupacion t On t.CodigoMaterial=Pi.CodigoProducto
Where 
	Pi.IdOrden = @IdOrden


/** 	Tipo Vehiculo Sugerido a OrdenItem 	  ***/

	Update
	OrdenItem
Set 
	IdTipoVehiculoSugerido = t.IdTipoVehiculo
From 
		 OrdenItem oi 
	join Z_TipoVehiculoOcupacion t On t.CodigoMaterial=oi.CodigoProducto
Where 
	oi.IdOrden = @IdOrden

	/** 	updateo campo Dyn NegocioComex	 a nivel de orden  ***/

	update Orden_Dyn set NegocioComex='Comex SC' from Orden_Dyn 
	Join Orden o With (NoLock) ON  o.IdOrden=Orden_Dyn.IdOrden and o.IdTipoOrden=22 
	where NegocioComex is null and Orden_Dyn.IdOrden=@IdOrden

	/** 	updateo campo Dyn NegocioComex	a nivel de orden item  ***/

Update
       OrdenItem_Dyn
Set
       NegocioComex = 'Comex SC'
From
       OrdenItem_Dyn Oid With(NoLock)
	Join OrdenItem oi With (NoLock) ON oi.IdOrdenItem=oid.IdOrdenItem
	Join Orden o With (NoLock) ON  o.IdOrden=oi.IdOrden and o.IdTipoOrden=22
where o.IdOrden=@IdOrden and Oid.NegocioComex is null


update ordenitem set 
FechaEntrega=DATEADD(HH,3,oiot.FechaEntrega)
from OrdenItem oi 
inner join OrdenItemOT oiot on oiot.IdOrdenItem=oi.IdOrdenItem
where oi.IdOrden = @IdOrden
	
	/** 	se actualiza linea y sublinea del producto  ***/

	Update
	Producto
Set 
	Linea = oid.GrupoArticulo,
	SubLinea=oid.GrupoArticulo
From 
		 Producto 
	Join OrdenItem	  oi On oi.IdProducto = Producto.IdProducto
	Join OrdenItem_Dyn	  oid On oid.IdOrdenItem = oi.IdOrdenItem 
Where 
	oi.IdOrden = @IdOrden and (Producto.Linea is null OR Producto.Linea='')



Insert Log (Categoria, Descripcion, FechaHora) Values ('SetDatosOT', 'OK IdOrden=' + Convert(varchar, @IdOrden), getutcdate())
End Try
Begin Catch
	Insert Log (Categoria, Descripcion, FechaHora) Values ('SetDatosOT', 'IdOrden=' + Convert(varchar, @IdOrden)+'Ex:'+ ERROR_MESSAGE(), getutcdate())
End Catch

End
