SELECT Z.IdViaje
	,Z.DescripcionViaje
	,Z.Dominio AS [Vehiculo]
	,Z.Origen
	,Z.Destino
	,V.Varchar1 AS [Contrato]
	,Z.KMTeoricos
	,Z.CicloKmTeoricos
	,Z.KmRecorridos AS [Kilometros Recorridos GPS]
	,Z.TipoSuceso AS [Evento]
	,Z.Ubicacion AS [Ubicacion Evento]
	,Z.Periodo AS [Periodo Evento]
	,Z.Duracion
	,Z.TiempoMinutos
	,Z.VelocidadPromedio
	,Z.VelocidadMaxima
	,Z.Detalle
	,EV.descripcion AS [Estado Viaje]
	,Z.ResponsableDemora AS [Responsable Demora]
	,Z.MinutosDemora AS [Minutos Imputados]
	,Z.MinutosExentos AS [Minutos Exentos]
	,Z.MotivoExencion AS [Motivo Exencion]
	,Z.Latitud AS [Latitud]
	,Z.Longitud AS [Longitud]
FROM dbo.Z_ItinerarioViaje AS Z WITH (NOLOCK)
INNER JOIN dbo.Viaje AS V WITH (NOLOCK) ON V.IdViaje = Z.IdViaje
INNER JOIN dbo.Jornada J WITH (NOLOCK) ON J.IdJornada = V.IdJornada
INNER JOIN dbo.EstadoViaje AS EV WITH (NOLOCK) ON EV.IdEstadoViaje = V.IdEstadoViaje
WHERE Z.IdViaje IN (!!ID_VIAJE!!)
ORDER BY Z.FechaHoraDesde ASC
