SELECT Z.IdViaje AS [ID Viaje]
	,Z.DescripcionViaje AS [Descripcion del Viaje]
	,Z.Dominio AS [Vehiculo]
	,T.RazonSocial AS [Transporte]
	,V.Varchar1 AS [Contrato]
	,EV.descripcion AS [Estado del Viaje]
	,Z.KmTeoricos AS [Km Teoricos]
	,Z.CicloKmTeoricos AS [Ciclo Km Teoricos]
	,CASE WHEN D.MinYPF / 60 < 10 THEN '0' ELSE '' END + CAST(D.MinYPF / 60 AS VARCHAR(10)) + ':' + RIGHT('0' + CAST(D.MinYPF % 60 AS VARCHAR(2)), 2) AS [Demoras Responsabilidad YPF]
	,CASE WHEN D.MinTransporte / 60 < 10 THEN '0' ELSE '' END + CAST(D.MinTransporte / 60 AS VARCHAR(10)) + ':' + RIGHT('0' + CAST(D.MinTransporte % 60 AS VARCHAR(2)), 2) AS [Demoras Responsabilidad Transporte]
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
INNER JOIN (
	SELECT X.IdViaje
		,SUM(X.MinYPF) AS MinYPF
		,SUM(X.MinTransporte) AS MinTransporte
	FROM (
		SELECT I.IdViaje
			,CASE WHEN I.Novedad = 'COMBUSTIBLE' AND I.AplicoExcepcionCombustible = 1 THEN I.TiempoMinutos ELSE 0 END AS MinYPF
			,CASE WHEN I.Novedad IN ('DETENIDO', 'ESPERA_SIN_TAREA') THEN I.TiempoMinutos ELSE 0 END AS MinTransporte
		FROM dbo.Z_ItinerarioViaje AS I WITH (NOLOCK)
		WHERE I.IdViaje IN (!!ID_VIAJE!!)

		UNION ALL

		SELECT I.IdViaje
			,MAX(I.MinutosOperacion) - 45
			,0
		FROM dbo.Z_ItinerarioViaje AS I WITH (NOLOCK)
		WHERE I.IdViaje IN (!!ID_VIAJE!!)
			AND I.Novedad IN ('CARGA', 'DESCARGA')
			AND I.ExcedeTolerancia = 1
		GROUP BY I.IdViaje
			,I.IdDibujo
		) AS X
	GROUP BY X.IdViaje
	) AS D ON D.IdViaje = Z.IdViaje
INNER JOIN dbo.Viaje AS V WITH (NOLOCK) ON V.IdViaje = Z.IdViaje
INNER JOIN dbo.Vehiculo AS VH WITH (NOLOCK) ON VH.IdVehiculo = V.IdVehiculo
LEFT JOIN dbo.Transporte AS T WITH (NOLOCK) ON T.IdTransporte = VH.IdTransporte
INNER JOIN dbo.EstadoViaje AS EV WITH (NOLOCK) ON EV.IdEstadoViaje = V.IdEstadoViaje
LEFT JOIN dbo.CategoriaViaje AS CV WITH (NOLOCK) ON CV.IdCategoriaViaje = V.IdCategoriaViaje
LEFT JOIN dbo.Evento AS EF WITH (NOLOCK) ON EF.IdEvento = V.IdEventoFinalizacion
WHERE V.IdEventoFinalizacion IS NOT NULL
ORDER BY EF.FechaHoraEvento ASC
