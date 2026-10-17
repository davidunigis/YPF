/*==============================================================================
  03 - VIAJES UM FINALIZADOS QUE NO TIENEN FILAS EN Z_ItinerarioViaje

  Son los que el reporte consolidado no muestra (porque exige filas). Causas tipicas:
  el SP nunca corrio, fallo (ver 02) o salio por viaje no encontrado.
  Operacion UM = 139, estado actual 99. Fechas en hora argentina.
==============================================================================*/
DECLARE @Dias INT = 30;

SELECT V.IdViaje, V.Descripcion, V.IdVehiculo, VH.Dominio, T.RazonSocial AS Transporte,
       EV.descripcion AS Estado, V.IdEventoActivacion, V.IdEventoFinalizacion,
       TE.FechaFinalizacionLocal
FROM dbo.Viaje AS V WITH (NOLOCK)
INNER JOIN dbo.Jornada AS J WITH (NOLOCK) ON J.IdJornada = V.IdJornada
INNER JOIN dbo.EstadoViaje AS EV WITH (NOLOCK) ON EV.IdEstadoViaje = V.IdEstadoViaje
LEFT JOIN dbo.Vehiculo AS VH WITH (NOLOCK) ON VH.IdVehiculo = V.IdVehiculo
LEFT JOIN dbo.Transporte AS T WITH (NOLOCK) ON T.IdTransporte = VH.IdTransporte
CROSS APPLY (
    SELECT TOP 1 DATEADD(HOUR, -3, X.Fecha) AS FechaFinalizacionLocal
    FROM dbo.EstadoViajeTraceEstado AS X WITH (NOLOCK)
    WHERE X.IdViaje = V.IdViaje AND X.IdEstadoViajeDestino = 99
    ORDER BY X.Fecha DESC
) AS TE
WHERE J.IdOperacion = 139
  AND V.IdEstadoViaje = 99
  AND TE.FechaFinalizacionLocal >= DATEADD(DAY, -@Dias, DATEADD(HOUR, -3, GETUTCDATE()))
  AND NOT EXISTS (SELECT 1 FROM dbo.Z_ItinerarioViaje AS Z WITH (NOLOCK) WHERE Z.IdViaje = V.IdViaje)
ORDER BY TE.FechaFinalizacionLocal DESC;
