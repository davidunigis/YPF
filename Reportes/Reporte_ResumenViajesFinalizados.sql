SELECT Z.IdViaje AS [ID Viaje]
	,Z.DescripcionViaje AS [Descripcion del Viaje]
	,Z.Dominio AS [Vehiculo]
	,T.RazonSocial AS [Transporte]
	,V.Varchar1 AS [Contrato]
	,EV.descripcion AS [Estado del Viaje]
	,Z.KmTeoricos AS [Km Teoricos]
	,Z.CicloKmTeoricos AS [Ciclo Km Teoricos]
	,CONVERT(VARCHAR(10), DATEADD(HOUR, - 3, EF.FechaHoraEvento), 103) + ' ' + CONVERT(VARCHAR(5), DATEADD(HOUR, - 3, EF.FechaHoraEvento), 108) AS [Fecha y Hora de Finalizacion]
	,Z.Origen AS [Origen]
	,Z.Destino AS [Destino]
	,CV.Descripcion AS [Tipo de Servicio]
FROM (
	SELECT DISTINCT IdViaje
		,DescripcionViaje
		,Dominio
		,Origen
		,Destino
		,KmTeoricos
		,CicloKmTeoricos
	FROM dbo.Z_ItinerarioViaje WITH (NOLOCK)
	WHERE IdViaje IN (!!ID_VIAJE!!)
	) AS Z
INNER JOIN dbo.Viaje AS V WITH (NOLOCK) ON V.IdViaje = Z.IdViaje
INNER JOIN dbo.Vehiculo AS VH WITH (NOLOCK) ON VH.IdVehiculo = V.IdVehiculo
LEFT JOIN dbo.Transporte AS T WITH (NOLOCK) ON T.IdTransporte = VH.IdTransporte
INNER JOIN dbo.EstadoViaje AS EV WITH (NOLOCK) ON EV.IdEstadoViaje = V.IdEstadoViaje
LEFT JOIN dbo.CategoriaViaje AS CV WITH (NOLOCK) ON CV.IdCategoriaViaje = V.IdCategoriaViaje
LEFT JOIN dbo.Evento AS EF WITH (NOLOCK) ON EF.IdEvento = V.IdEventoFinalizacion
WHERE V.IdEventoFinalizacion IS NOT NULL
ORDER BY EF.FechaHoraEvento ASC
