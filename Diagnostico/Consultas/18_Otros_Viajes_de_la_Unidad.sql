/*==============================================================================
  18 - OTROS VIAJES DE LA MISMA UNIDAD CERCA DE ESTE VIAJE

  Cambiar @IdViaje. Viajes del mismo vehiculo creados +/- 3 dias de la activacion,
  con su activacion/finalizacion y cuantas cargas de combustible dejo el SP en cada
  uno (y cuantas con la excepcion aplicada). Sirve para analizar la regla de una
  carga de combustible por dia y unidad, y superposiciones entre viajes.
==============================================================================*/
DECLARE @IdViaje INT = 330178;
DECLARE @OffsetHoras INT = -3;
DECLARE @IdVehiculo INT, @Referencia DATETIME;

SELECT @IdVehiculo = V.IdVehiculo,
       @Referencia = ISNULL((SELECT EA.FechaHoraEvento FROM dbo.Evento AS EA WITH (NOLOCK) WHERE EA.IdEvento = V.IdEventoActivacion), V.FechaCreacion)
FROM dbo.Viaje AS V WITH (NOLOCK) WHERE V.IdViaje = @IdViaje;

SELECT V2.IdViaje, CASE WHEN V2.IdViaje = @IdViaje THEN 'ESTE VIAJE' ELSE '' END AS Marca,
       V2.Descripcion, EV.descripcion AS Estado,
       DATEADD(HOUR, @OffsetHoras, EA.FechaHoraEvento) AS Activacion_Local,
       DATEADD(HOUR, @OffsetHoras, EF.FechaHoraEvento) AS Finalizacion_Local,
       DATEADD(HOUR, @OffsetHoras, V2.FechaCreacion) AS Creacion_Local,
       Z.Filas, Z.CargasCombustible, Z.CargasConExcepcion, Z.MinCombustible,
       Z.UltimoProcesamiento
FROM dbo.Viaje AS V2 WITH (NOLOCK)
LEFT JOIN dbo.EstadoViaje AS EV WITH (NOLOCK) ON EV.IdEstadoViaje = V2.IdEstadoViaje
LEFT JOIN dbo.Evento AS EA WITH (NOLOCK) ON EA.IdEvento = V2.IdEventoActivacion
LEFT JOIN dbo.Evento AS EF WITH (NOLOCK) ON EF.IdEvento = V2.IdEventoFinalizacion
OUTER APPLY (
    SELECT COUNT(*) AS Filas,
           SUM(CASE WHEN I.Novedad = 'COMBUSTIBLE' THEN 1 ELSE 0 END) AS CargasCombustible,
           SUM(CASE WHEN I.Novedad = 'COMBUSTIBLE' AND I.AplicoExcepcionCombustible = 1 THEN 1 ELSE 0 END) AS CargasConExcepcion,
           SUM(CASE WHEN I.Novedad = 'COMBUSTIBLE' THEN I.TiempoMinutos ELSE 0 END) AS MinCombustible,
           MAX(I.FechaProcesamiento) AS UltimoProcesamiento
    FROM dbo.Z_ItinerarioViaje AS I WITH (NOLOCK)
    WHERE I.IdViaje = V2.IdViaje
) AS Z
WHERE V2.IdVehiculo = @IdVehiculo
  AND V2.FechaCreacion >= DATEADD(DAY, -3, @Referencia)
  AND V2.FechaCreacion <= DATEADD(DAY, 3, @Referencia)
ORDER BY V2.FechaCreacion;
