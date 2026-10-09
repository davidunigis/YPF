SELECT Z.IdViaje
	,Z.DescripcionViaje
	,RTRIM(Z.Dominio) AS [Vehiculo]
	,Z.Origen
	,Z.Destino
	,V.Varchar1 AS [Contrato]
	,Z.KMTeoricos
	,Z.CicloKmTeoricos
	,Z.KmRecorridos AS [Kilometros Recorridos GPS]
	,EV.descripcion AS [Estado Viaje]
	,dbo.Z_MinutosAHHMM(SUM(CASE WHEN Z.Novedad IN ('CARGA', 'DESCARGA') THEN Z.TiempoMinutos ELSE 0 END)) AS [Demoras Responsabilidad YPF]
	,dbo.Z_MinutosAHHMM(SUM(CASE WHEN Z.ResponsableDemora = 'YPF' THEN ISNULL(Z.MinutosDemora, 0) ELSE 0 END)) AS [Exceso sobre Tolerancia YPF]
	,dbo.Z_MinutosAHHMM(SUM(CASE WHEN Z.Novedad = 'DETENIDO' THEN Z.TiempoMinutos - ISNULL(Z.MinutosExentos, 0) ELSE 0 END)) AS [Demoras Responsabilidad Transporte]
FROM dbo.Z_ItinerarioViaje AS Z WITH (NOLOCK)
INNER JOIN dbo.Viaje AS V WITH (NOLOCK) ON V.IdViaje = Z.IdViaje
INNER JOIN dbo.Jornada J WITH (NOLOCK) ON J.IdJornada = V.IdJornada
INNER JOIN dbo.EstadoViaje AS EV WITH (NOLOCK) ON EV.IdEstadoViaje = V.IdEstadoViaje
CROSS APPLY (
	SELECT MAX(T.Fecha) AS FechaFin
	FROM dbo.EstadoViajeTraceEstado AS T WITH (NOLOCK)
	WHERE T.IdViaje = V.IdViaje
		AND T.IdEstadoViajeDestino = 99
	) AS F
WHERE F.FechaFin IS NOT NULL
	AND J.IdOperacion = 139
	AND CAST(DATEADD(HOUR, - 3, F.FechaFin) AS DATE) >= CAST('!!FECHA_DESDE!!' AS DATE)
	AND CAST(DATEADD(HOUR, - 3, F.FechaFin) AS DATE) <= CAST('!!FECHA_HASTA!!' AS DATE)
GROUP BY Z.IdViaje
	,Z.DescripcionViaje
	,RTRIM(Z.Dominio)
	,Z.Origen
	,Z.Destino
	,V.Varchar1
	,Z.KMTeoricos
	,Z.CicloKmTeoricos
	,Z.KmRecorridos
	,EV.descripcion
	,F.FechaFin
ORDER BY F.FechaFin ASC
