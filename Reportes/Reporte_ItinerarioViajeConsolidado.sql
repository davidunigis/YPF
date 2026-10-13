/**DECLARACION DE VARIABLES***/
DECLARE @FECHA_DESDE DATETIME
    ,@FECHA_HASTA DATETIME;

SET @FECHA_DESDE = CONVERT(DATETIME, CAST('!!FECHA_DESDE!!' AS VARCHAR), 103);
SET @FECHA_HASTA = CONVERT(DATETIME, CAST('!!FECHA_HASTA!!' AS VARCHAR), 103);
SET @FECHA_HASTA = DATEADD(DAY, 1, @FECHA_HASTA);

SELECT V.IdViaje
    ,Z.DescripcionViaje
    ,RTRIM(Z.Dominio) AS [Vehiculo]
    ,Z.Origen
    ,Z.Destino
    ,V.Varchar1 AS [Contrato]
    ,Z.KMTeoricos
    ,Z.CicloKmTeoricos
    ,Z.KmRecorridos AS [Kilometros Recorridos GPS]
    ,EV.descripcion AS [Estado Viaje]
    ,CONVERT(VARCHAR(10), TE.FechaDescarga, 103) + ' ' + CONVERT(VARCHAR(8), TE.FechaDescarga, 108) AS [Fecha y Hora Finalizacion]
    ,dbo.Z_MinutosAHHMM(Z.MinYPF) AS [Demoras Responsabilidad YPF]
    ,dbo.Z_MinutosAHHMM(Z.MinExceso) AS [Exceso sobre Tolerancia YPF]
    ,dbo.Z_MinutosAHHMM(Z.MinTransporte) AS [Demoras Responsabilidad Transporte]
FROM dbo.Viaje AS V WITH (NOLOCK)
INNER JOIN dbo.Jornada AS J WITH (NOLOCK) ON J.IdJornada = V.IdJornada
INNER JOIN dbo.EstadoViaje AS EV WITH (NOLOCK) ON EV.IdEstadoViaje = V.IdEstadoViaje
CROSS APPLY (
    SELECT TOP 1 DATEADD(HOUR, - 3, T.Fecha) AS FechaDescarga
    FROM dbo.EstadoViajeTraceEstado AS T WITH (NOLOCK)
    WHERE T.IdViaje = V.IdViaje
        AND T.IdEstadoViajeDestino = 99
    ORDER BY T.Fecha DESC
    ) AS TE
CROSS APPLY (
    SELECT COUNT(*) AS Filas
        ,MAX(I.DescripcionViaje) AS DescripcionViaje
        ,MAX(I.Dominio) AS Dominio
        ,MAX(I.Origen) AS Origen
        ,MAX(I.Destino) AS Destino
        ,MAX(I.KMTeoricos) AS KMTeoricos
        ,MAX(I.CicloKmTeoricos) AS CicloKmTeoricos
        ,MAX(I.KmRecorridos) AS KmRecorridos
        ,SUM(CASE WHEN I.Novedad IN ('CARGA', 'DESCARGA') THEN I.TiempoMinutos ELSE 0 END) AS MinYPF
        ,SUM(CASE WHEN I.ResponsableDemora = 'YPF' THEN ISNULL(I.MinutosDemora, 0) ELSE 0 END) AS MinExceso
        ,SUM(CASE WHEN I.Novedad = 'DETENIDO' THEN I.TiempoMinutos - ISNULL(I.MinutosExentos, 0) ELSE 0 END) AS MinTransporte
    FROM dbo.Z_ItinerarioViaje AS I WITH (NOLOCK)
    WHERE I.IdViaje = V.IdViaje
    ) AS Z
WHERE J.IdOperacion = 139
    AND Z.Filas > 0
    AND TE.FechaDescarga BETWEEN @FECHA_DESDE
        AND @FECHA_HASTA
ORDER BY TE.FechaDescarga
    ,V.IdViaje
