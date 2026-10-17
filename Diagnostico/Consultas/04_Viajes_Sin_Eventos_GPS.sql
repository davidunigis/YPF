/*==============================================================================
  04 - VIAJES QUE QUEDARON CON LA FILA SIN_EVENTOS_GPS

  Para cada uno cuenta los eventos del vehiculo en la ventana que uso el SP:
  Total = eventos que existen, Validos = Valido = True, ConCoordenada = ademas con
  latitud/longitud utilizables. Total 0 = la unidad no reporto; Total > 0 con
  ConCoordenada 0 = reporto pero con coordenadas inservibles.
==============================================================================*/
DECLARE @Dias INT = 30;

SELECT Z.IdViaje, Z.Dominio, Z.IdVehiculo, T.RazonSocial AS Transporte, Z.Periodo,
       Z.FechaDesdeUTC, Z.FechaHastaUTC, Z.FechaProcesamiento,
       EV.Total, EV.Validos, EV.ConCoordenada
FROM dbo.Z_ItinerarioViaje AS Z WITH (NOLOCK)
LEFT JOIN dbo.Vehiculo AS VH WITH (NOLOCK) ON VH.IdVehiculo = Z.IdVehiculo
LEFT JOIN dbo.Transporte AS T WITH (NOLOCK) ON T.IdTransporte = VH.IdTransporte
OUTER APPLY (
    SELECT COUNT(*) AS Total,
           SUM(CASE WHEN E.Valido = 'True' THEN 1 ELSE 0 END) AS Validos,
           SUM(CASE WHEN E.Valido = 'True' AND X.Lat IS NOT NULL AND X.Lon IS NOT NULL AND X.Lat <> 0 AND X.Lon <> 0
                     AND X.Lat BETWEEN -90 AND 90 AND X.Lon BETWEEN -180 AND 180 THEN 1 ELSE 0 END) AS ConCoordenada
    FROM dbo.Evento AS E WITH (NOLOCK)
    CROSS APPLY (
        SELECT TRY_CAST(REPLACE(REPLACE(ISNULL(CAST(E.Latitud AS VARCHAR(50)), '0'), ',', '.'), ' ', '') AS FLOAT) AS Lat,
               TRY_CAST(REPLACE(REPLACE(ISNULL(CAST(E.Longitud AS VARCHAR(50)), '0'), ',', '.'), ' ', '') AS FLOAT) AS Lon
    ) AS X
    WHERE E.IdVehiculo = Z.IdVehiculo
      AND E.FechaHoraEvento >= Z.FechaDesdeUTC
      AND E.FechaHoraEvento <= Z.FechaHastaUTC
) AS EV
WHERE Z.Novedad = 'SIN_EVENTOS_GPS'
  AND Z.FechaProcesamiento >= DATEADD(DAY, -@Dias, GETDATE())
ORDER BY Z.FechaProcesamiento DESC;
