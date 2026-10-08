SELECT Z.IdViaje AS [ID Viaje]
	,Z.DescripcionViaje AS [Descripcion del Viaje]
	,Z.Dominio AS [Vehiculo]
	,T.RazonSocial AS [Transporte]
	,V.Varchar1 AS [Contrato]
	,EV.descripcion AS [Estado del Viaje]
	,Z.KmTeoricos AS [Km Teoricos]
	,Z.CicloKmTeoricos AS [Ciclo Km Teoricos]
	,dbo.Z_MinutosAHHMM(D.ExcesoOrigen + D.ExcesoDestino) AS [Demoras Responsabilidad YPF]
	,dbo.Z_MinutosAHHMM(D.MinTransporte) AS [Demoras Responsabilidad Transporte]
	,CONVERT(VARCHAR(10), DATEADD(HOUR, - 3, EF.FechaHoraEvento), 103) + ' ' + CONVERT(VARCHAR(5), DATEADD(HOUR, - 3, EF.FechaHoraEvento), 108) AS [Fecha y Hora de Finalizacion]
	,Z.Origen AS [Origen]
	,Z.Destino AS [Destino]
	,CV.Descripcion AS [Tipo de Servicio]
	,dbo.Z_MinutosAHHMM(D.MinOrigen) AS [Tiempo en Origen (Espera + Carga)]
	,dbo.Z_MinutosAHHMM(D.ExcesoOrigen) AS [Exceso sobre Tolerancia Origen]
	,dbo.Z_MinutosAHHMM(D.MinDestino) AS [Tiempo en Destino (Espera + Descarga)]
	,dbo.Z_MinutosAHHMM(D.ExcesoDestino) AS [Exceso sobre Tolerancia Destino]
	,D.CantDetenidos AS [Cantidad de Detenidos]
	,dbo.Z_MinutosAHHMM(D.MinExentos) AS [Tiempo Exento (Combustible / Cambio de Turno)]
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
INNER JOIN (
	SELECT I.IdViaje
		,SUM(CASE WHEN I.Novedad = 'CARGA' THEN I.TiempoMinutos ELSE 0 END) AS MinOrigen
		,SUM(CASE WHEN I.Novedad = 'CARGA' THEN ISNULL(I.MinutosDemora, 0) ELSE 0 END) AS ExcesoOrigen
		,SUM(CASE WHEN I.Novedad = 'DESCARGA' THEN I.TiempoMinutos ELSE 0 END) AS MinDestino
		,SUM(CASE WHEN I.Novedad = 'DESCARGA' THEN ISNULL(I.MinutosDemora, 0) ELSE 0 END) AS ExcesoDestino
		,SUM(CASE WHEN I.ResponsableDemora = 'TRANSPORTE' THEN ISNULL(I.MinutosDemora, 0) ELSE 0 END) AS MinTransporte
		,SUM(CASE WHEN I.ResponsableDemora = 'TRANSPORTE' THEN 1 ELSE 0 END) AS CantDetenidos
		,SUM(ISNULL(I.MinutosExentos, 0)) AS MinExentos
	FROM dbo.Z_ItinerarioViaje AS I WITH (NOLOCK)
	WHERE I.IdViaje IN (!!ID_VIAJE!!)
	GROUP BY I.IdViaje
	) AS D ON D.IdViaje = Z.IdViaje
INNER JOIN dbo.Viaje AS V WITH (NOLOCK) ON V.IdViaje = Z.IdViaje
INNER JOIN dbo.Vehiculo AS VH WITH (NOLOCK) ON VH.IdVehiculo = V.IdVehiculo
LEFT JOIN dbo.Transporte AS T WITH (NOLOCK) ON T.IdTransporte = VH.IdTransporte
INNER JOIN dbo.EstadoViaje AS EV WITH (NOLOCK) ON EV.IdEstadoViaje = V.IdEstadoViaje
LEFT JOIN dbo.CategoriaViaje AS CV WITH (NOLOCK) ON CV.IdCategoriaViaje = V.IdCategoriaViaje
LEFT JOIN dbo.Evento AS EF WITH (NOLOCK) ON EF.IdEvento = V.IdEventoFinalizacion
WHERE V.IdEventoFinalizacion IS NOT NULL
ORDER BY EF.FechaHoraEvento ASC
