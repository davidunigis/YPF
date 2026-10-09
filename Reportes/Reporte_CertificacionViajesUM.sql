SELECT V.IdViaje AS [ID Viaje]
	,V.Descripcion AS [Descripcion del Viaje]
	,RTRIM(VH.Dominio) AS [Vehiculo]
	,T.RazonSocial AS [Transporte]
	,V.Varchar1 AS [Contrato]
	,EV.descripcion AS [Estado del Viaje]
	,Z.KmTeoricos AS [Km Teoricos]
	,Z.CicloKmTeoricos AS [Ciclo Km Teoricos]
	,CASE WHEN D.Filas > 0 THEN dbo.Z_MinutosAHHMM(D.MinYPF) END AS [Demoras Responsabilidad YPF]
	,CASE WHEN D.Filas > 0 THEN dbo.Z_MinutosAHHMM(D.MinTransporte) END AS [Demoras Responsabilidad Transporte]
	,CONVERT(VARCHAR(10), DATEADD(HOUR, - 3, EF.FechaHoraEvento), 103) + ' ' + CONVERT(VARCHAR(5), DATEADD(HOUR, - 3, EF.FechaHoraEvento), 108) AS [Fecha y Hora de Finalizacion]
	,ISNULL(Z.Origen, V.Origen) AS [Origen]
	,ISNULL(Z.Destino, V.Destino) AS [Destino]
	,CV.Descripcion AS [Tipo de Servicio]
FROM dbo.Viaje AS V WITH (NOLOCK)
LEFT JOIN dbo.Vehiculo AS VH WITH (NOLOCK) ON VH.IdVehiculo = V.IdVehiculo
LEFT JOIN dbo.Transporte AS T WITH (NOLOCK) ON T.IdTransporte = VH.IdTransporte
INNER JOIN dbo.EstadoViaje AS EV WITH (NOLOCK) ON EV.IdEstadoViaje = V.IdEstadoViaje
LEFT JOIN dbo.CategoriaViaje AS CV WITH (NOLOCK) ON CV.IdCategoriaViaje = V.IdCategoriaViaje
LEFT JOIN dbo.Evento AS EF WITH (NOLOCK) ON EF.IdEvento = V.IdEventoFinalizacion
OUTER APPLY (
	SELECT TOP 1 I.Origen
		,I.Destino
		,I.KmTeoricos
		,I.CicloKmTeoricos
	FROM dbo.Z_ItinerarioViaje AS I WITH (NOLOCK)
	WHERE I.IdViaje = V.IdViaje
	) AS Z
OUTER APPLY (
	SELECT COUNT(*) AS Filas
		,SUM(CASE WHEN I.Novedad IN ('CARGA', 'DESCARGA') THEN I.TiempoMinutos ELSE 0 END) AS MinYPF
		,SUM(CASE WHEN I.Novedad = 'DETENIDO' THEN I.TiempoMinutos - ISNULL(I.MinutosExentos, 0) ELSE 0 END) AS MinTransporte
	FROM dbo.Z_ItinerarioViaje AS I WITH (NOLOCK)
	WHERE I.IdViaje = V.IdViaje
	) AS D
WHERE V.IdEventoFinalizacion IS NOT NULL
ORDER BY EF.FechaHoraEvento ASC
