SELECT X.Transporte AS [Transporte]
	,X.Vehiculo AS [Vehiculo]
	,X.Periodo AS [Periodo]
	,COUNT(*) AS [Viajes]
	,dbo.Z_MinutosAHHMM(SUM(X.MinOrigen)) AS [Tiempo en Origen (Espera + Carga)]
	,dbo.Z_MinutosAHHMM(SUM(X.ExcesoOrigen)) AS [Exceso sobre Tolerancia Origen]
	,dbo.Z_MinutosAHHMM(SUM(X.MinDestino)) AS [Tiempo en Destino (Espera + Descarga)]
	,dbo.Z_MinutosAHHMM(SUM(X.ExcesoDestino)) AS [Exceso sobre Tolerancia Destino]
	,dbo.Z_MinutosAHHMM(SUM(X.ExcesoOrigen + X.ExcesoDestino)) AS [Demoras Responsabilidad YPF]
	,SUM(X.CantDetenidos) AS [Detenidos Registrables]
	,dbo.Z_MinutosAHHMM(SUM(X.MinTransporte)) AS [Demoras Responsabilidad Transporte]
FROM (
	SELECT T.RazonSocial AS Transporte
		,VH.Dominio AS Vehiculo
		,CONVERT(VARCHAR(10), L.PeriodoDesde, 103) + ' al ' + CONVERT(VARCHAR(10), L.PeriodoHasta, 103) AS Periodo
		,L.PeriodoDesde
		,D.MinOrigen
		,D.ExcesoOrigen
		,D.MinDestino
		,D.ExcesoDestino
		,D.MinTransporte
		,D.CantDetenidos
	FROM (
		SELECT I.IdViaje
			,SUM(CASE WHEN I.Novedad = 'CARGA' THEN I.TiempoMinutos ELSE 0 END) AS MinOrigen
			,SUM(CASE WHEN I.Novedad = 'CARGA' THEN ISNULL(I.MinutosDemora, 0) ELSE 0 END) AS ExcesoOrigen
			,SUM(CASE WHEN I.Novedad = 'DESCARGA' THEN I.TiempoMinutos ELSE 0 END) AS MinDestino
			,SUM(CASE WHEN I.Novedad = 'DESCARGA' THEN ISNULL(I.MinutosDemora, 0) ELSE 0 END) AS ExcesoDestino
			,SUM(CASE WHEN I.ResponsableDemora = 'TRANSPORTE' THEN ISNULL(I.MinutosDemora, 0) ELSE 0 END) AS MinTransporte
			,SUM(CASE WHEN I.ResponsableDemora = 'TRANSPORTE' THEN 1 ELSE 0 END) AS CantDetenidos
		FROM dbo.Z_ItinerarioViaje AS I WITH (NOLOCK)
		WHERE I.IdViaje IN (!!ID_VIAJE!!)
		GROUP BY I.IdViaje
		) AS D
	INNER JOIN dbo.Viaje AS V WITH (NOLOCK) ON V.IdViaje = D.IdViaje
	INNER JOIN dbo.Vehiculo AS VH WITH (NOLOCK) ON VH.IdVehiculo = V.IdVehiculo
	LEFT JOIN dbo.Transporte AS T WITH (NOLOCK) ON T.IdTransporte = VH.IdTransporte
	INNER JOIN dbo.Evento AS EF WITH (NOLOCK) ON EF.IdEvento = V.IdEventoFinalizacion
	CROSS APPLY (
		SELECT DATEADD(HOUR, - 3, EF.FechaHoraEvento) AS FinLocal
		) AS F
	CROSS APPLY (
		SELECT DATEFROMPARTS(YEAR(F.FinLocal), MONTH(F.FinLocal), CASE WHEN DAY(F.FinLocal) <= 15 THEN 1 ELSE 16 END) AS PeriodoDesde
			,CASE WHEN DAY(F.FinLocal) <= 15 THEN DATEFROMPARTS(YEAR(F.FinLocal), MONTH(F.FinLocal), 15) ELSE EOMONTH(F.FinLocal) END AS PeriodoHasta
		) AS L
	WHERE V.IdEventoFinalizacion IS NOT NULL
	) AS X
GROUP BY X.Transporte
	,X.Vehiculo
	,X.Periodo
	,X.PeriodoDesde
ORDER BY X.Transporte
	,X.Vehiculo
	,X.PeriodoDesde
