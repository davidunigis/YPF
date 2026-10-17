/*==============================================================================
  05 - CONTROL POR VIAJE (una fila por viaje UM finalizado, ultimos @Dias dias)

  Resumen de lo que dejo el SP en Z_ItinerarioViaje para detectar valores raros:
  km teoricos vacios, km GPS exagerados, demoras enormes, procesado antes de que
  llegaran los datos, etc. Exportar todo y filtrar en Excel.
  Fechas en hora argentina. Minutos = suma de TiempoMinutos por novedad.
  UltimoProcesamientoLocal: lo guardado por el SP nuevo es hora local; las filas cargadas
  con el SP viejo estan en UTC (3 h de mas) hasta que se reprocesen.
==============================================================================*/
DECLARE @Dias INT = 15;

SELECT V.IdViaje, V.Descripcion, VH.Dominio, T.RazonSocial AS Transporte,
       TE.FinalizacionLocal,
       Z.FilasZ, Z.SinEventosGPS,
       Z.UltimoProcesamientoLocal,
       DATEDIFF(MINUTE, TE.FinalizacionLocal, Z.UltimoProcesamientoLocal) AS MinProcesadoDespuesDeFinalizar,
       Z.Origen, Z.Destino,
       Z.KmGPS, Z.KmTeoricos, Z.CicloKmTeoricos, Z.DesvioKm,
       CASE WHEN Z.KmTeoricos IS NULL THEN 1 ELSE 0 END AS KmTeoricosVacio,
       Z.MinCarga, Z.MinDescarga, Z.MinDetenido, Z.MinCombustible, Z.MinCarreteando,
       Z.FilasCarga, Z.FilasDescarga, Z.CantDetenidos, Z.DetenidoMaxMin, Z.CantCombustible,
       Z.MinDemoraYPF, Z.MinDemoraTransporte, Z.MinExentos,
       Z.FilasFueraDeTolerancia
FROM dbo.Viaje AS V WITH (NOLOCK)
INNER JOIN dbo.Jornada AS J WITH (NOLOCK) ON J.IdJornada = V.IdJornada
LEFT JOIN dbo.Vehiculo AS VH WITH (NOLOCK) ON VH.IdVehiculo = V.IdVehiculo
LEFT JOIN dbo.Transporte AS T WITH (NOLOCK) ON T.IdTransporte = VH.IdTransporte
CROSS APPLY (
    SELECT TOP 1 DATEADD(HOUR, -3, X.Fecha) AS FinalizacionLocal
    FROM dbo.EstadoViajeTraceEstado AS X WITH (NOLOCK)
    WHERE X.IdViaje = V.IdViaje AND X.IdEstadoViajeDestino = 99
    ORDER BY X.Fecha DESC
) AS TE
OUTER APPLY (
    SELECT COUNT(*) AS FilasZ,
           MAX(CASE WHEN I.Novedad = 'SIN_EVENTOS_GPS' THEN 1 ELSE 0 END) AS SinEventosGPS,
           MAX(I.FechaProcesamiento) AS UltimoProcesamientoLocal,
           MAX(I.Origen) AS Origen, MAX(I.Destino) AS Destino,
           MAX(I.KmRecorridos) AS KmGPS, MAX(I.KmTeoricos) AS KmTeoricos,
           MAX(I.CicloKmTeoricos) AS CicloKmTeoricos, MAX(I.DesvioKm) AS DesvioKm,
           SUM(CASE WHEN I.Novedad = 'CARGA' THEN I.TiempoMinutos ELSE 0 END) AS MinCarga,
           SUM(CASE WHEN I.Novedad = 'DESCARGA' THEN I.TiempoMinutos ELSE 0 END) AS MinDescarga,
           SUM(CASE WHEN I.Novedad = 'DETENIDO' THEN I.TiempoMinutos ELSE 0 END) AS MinDetenido,
           SUM(CASE WHEN I.Novedad = 'COMBUSTIBLE' THEN I.TiempoMinutos ELSE 0 END) AS MinCombustible,
           SUM(CASE WHEN I.Novedad = 'CARRETEANDO' THEN I.TiempoMinutos ELSE 0 END) AS MinCarreteando,
           SUM(CASE WHEN I.Novedad = 'CARGA' THEN 1 ELSE 0 END) AS FilasCarga,
           SUM(CASE WHEN I.Novedad = 'DESCARGA' THEN 1 ELSE 0 END) AS FilasDescarga,
           SUM(CASE WHEN I.Novedad = 'DETENIDO' THEN 1 ELSE 0 END) AS CantDetenidos,
           MAX(CASE WHEN I.Novedad = 'DETENIDO' THEN I.TiempoMinutos END) AS DetenidoMaxMin,
           SUM(CASE WHEN I.Novedad = 'COMBUSTIBLE' THEN 1 ELSE 0 END) AS CantCombustible,
           SUM(CASE WHEN I.ResponsableDemora = 'YPF' THEN ISNULL(I.MinutosDemora, 0) ELSE 0 END) AS MinDemoraYPF,
           SUM(CASE WHEN I.ResponsableDemora = 'TRANSPORTE' THEN ISNULL(I.MinutosDemora, 0) ELSE 0 END) AS MinDemoraTransporte,
           SUM(ISNULL(I.MinutosExentos, 0)) AS MinExentos,
           SUM(CASE WHEN I.ExcedeTolerancia = 1 THEN 1 ELSE 0 END) AS FilasFueraDeTolerancia
    FROM dbo.Z_ItinerarioViaje AS I WITH (NOLOCK)
    WHERE I.IdViaje = V.IdViaje
) AS Z
WHERE J.IdOperacion = 139
  AND V.IdEstadoViaje = 99
  AND TE.FinalizacionLocal >= DATEADD(DAY, -@Dias, DATEADD(HOUR, -3, GETUTCDATE()))
ORDER BY TE.FinalizacionLocal DESC;
