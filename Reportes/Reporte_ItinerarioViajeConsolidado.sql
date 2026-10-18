/**DECLARACION DE VARIABLES***/
DECLARE @FECHA_DESDE DATETIME
    ,@FECHA_HASTA DATETIME
    ,@TOLERANCIA INT;

SET @TOLERANCIA = 45;

SET @FECHA_DESDE = CONVERT(DATETIME, CAST('!!FECHA_DESDE!!' AS VARCHAR), 103);
SET @FECHA_HASTA = CONVERT(DATETIME, CAST('!!FECHA_HASTA!!' AS VARCHAR), 103);
SET @FECHA_HASTA = DATEADD(DAY, 1, @FECHA_HASTA);

SELECT V.IdViaje
    ,Z.DescripcionViaje
    ,RTRIM(Z.Dominio) AS [Vehiculo]
    ,ISNULL(PO.Origen, Z.Origen) AS [Origen]
    ,ISNULL(PD.Destino, Z.Destino) AS [Destino]
    ,V.Varchar1 AS [Contrato]
    ,K.DistanciaKmTeoricos AS [KMTeoricos]
    ,K.CicloKmTeoricos
    ,CASE WHEN Z.SinGPS = 1 THEN 'Sin eventos GPS' ELSE CONVERT(VARCHAR(20), Z.KmRecorridos) END AS [Kilometros Recorridos GPS]
    ,EV.descripcion AS [Estado Viaje]
    ,CONVERT(VARCHAR(10), TE.FechaDescarga, 103) + ' ' + CONVERT(VARCHAR(8), TE.FechaDescarga, 108) AS [Fecha y Hora Finalizacion]
    ,CASE WHEN Z.SinGPS = 0 THEN dbo.Z_MinutosAHHMM(Z.MinYPF) END AS [Demoras Responsabilidad YPF]
    ,CASE WHEN Z.SinGPS = 0 THEN dbo.Z_MinutosAHHMM(Z.MinExceso) END AS [Exceso sobre Tolerancia YPF]
    ,CASE WHEN Z.SinGPS = 0 THEN dbo.Z_MinutosAHHMM(Z.MinTransporte) END AS [Demoras Responsabilidad Transporte]
    ,CASE WHEN Z.SinGPS = 0 THEN ISNULL(P.MinOrigen, 0) END AS [Tiempo Total Origen (min)]
    ,CASE WHEN Z.SinGPS = 0 THEN ISNULL(P.ExcOrigen, 0) END AS [Tiempo Excedente Origen (min)]
    ,CASE WHEN Z.SinGPS = 0 THEN ISNULL(P.MinDestino, 0) END AS [Tiempo Total Destino (min)]
    ,CASE WHEN Z.SinGPS = 0 THEN ISNULL(P.ExcDestino, 0) END AS [Tiempo Excedente Destino (min)]
    ,CASE WHEN Z.SinGPS = 0 THEN Z.MinTransporte END AS [Demoras Responsabilidad Transporte (min)]
    ,CASE WHEN Z.SinGPS = 0 THEN ISNULL(P.ExcOrigen, 0) + ISNULL(P.ExcDestino, 0) - Z.MinTransporte END AS [Tiempo a Reconocer (min)]
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
        ,MAX(I.KmRecorridos) AS KmRecorridos
        ,MAX(CASE WHEN I.Novedad = 'SIN_EVENTOS_GPS' THEN 1 ELSE 0 END) AS SinGPS
        ,SUM(CASE WHEN I.Novedad IN ('CARGA', 'DESCARGA') THEN I.TiempoMinutos ELSE 0 END) AS MinYPF
        ,SUM(CASE WHEN I.ResponsableDemora = 'YPF' THEN ISNULL(I.MinutosDemora, 0) ELSE 0 END) AS MinExceso
        ,SUM(CASE WHEN I.Novedad = 'DETENIDO' THEN I.TiempoMinutos - ISNULL(I.MinutosExentos, 0) ELSE 0 END) AS MinTransporte
    FROM dbo.Z_ItinerarioViaje AS I WITH (NOLOCK)
    WHERE I.IdViaje = V.IdViaje
    ) AS Z
OUTER APPLY (
    SELECT SUM(CASE WHEN S.Novedad = 'CARGA' THEN S.Minutos ELSE 0 END) AS MinOrigen
        ,SUM(CASE WHEN S.Novedad = 'CARGA' AND S.Minutos > @TOLERANCIA THEN S.Minutos - @TOLERANCIA ELSE 0 END) AS ExcOrigen
        ,SUM(CASE WHEN S.Novedad = 'DESCARGA' THEN S.Minutos ELSE 0 END) AS MinDestino
        ,SUM(CASE WHEN S.Novedad = 'DESCARGA' AND S.Minutos > @TOLERANCIA THEN S.Minutos - @TOLERANCIA ELSE 0 END) AS ExcDestino
    FROM (
        SELECT I.Novedad
            ,I.IdDibujo
            ,SUM(I.TiempoMinutos) AS Minutos
        FROM dbo.Z_ItinerarioViaje AS I WITH (NOLOCK)
        WHERE I.IdViaje = V.IdViaje
            AND I.Novedad IN ('CARGA', 'DESCARGA')
        GROUP BY I.Novedad
            ,I.IdDibujo
        ) AS S
    ) AS P
OUTER APPLY (
    SELECT TOP 1 DATEADD(HOUR, - 3, T2.Fecha) AS TransitoLocal
    FROM dbo.EstadoViajeTraceEstado AS T2 WITH (NOLOCK)
    WHERE T2.IdViaje = V.IdViaje
        AND T2.IdEstadoViajeDestino = 90
    ORDER BY T2.Fecha DESC
    ) AS TT
OUTER APPLY (
    SELECT TOP 1 ISNULL(PA.Descripcion, I.Ubicacion) AS Destino
    FROM dbo.Z_ItinerarioViaje AS I WITH (NOLOCK)
    LEFT JOIN dbo.Parada AS PA WITH (NOLOCK) ON PA.IdParada = I.IdParada
    WHERE I.IdViaje = V.IdViaje
        AND I.Novedad = 'DESCARGA'
    ORDER BY I.FechaHoraDesde DESC
        ,I.Orden DESC
    ) AS PD
OUTER APPLY (
    SELECT TOP 1 ISNULL(DP.Descripcion, ISNULL(PA.Descripcion, I.Ubicacion)) AS Origen
    FROM dbo.Z_ItinerarioViaje AS I WITH (NOLOCK)
    LEFT JOIN dbo.Parada AS PA WITH (NOLOCK) ON PA.IdParada = I.IdParada
    LEFT JOIN dbo.Deposito AS DP WITH (NOLOCK) ON DP.IdDeposito = PA.IdDeposito
    WHERE I.IdViaje = V.IdViaje
        AND I.Novedad = 'CARGA'
    ORDER BY CASE WHEN I.FechaHoraDesde <= TT.TransitoLocal THEN 0 ELSE 1 END
        ,CASE WHEN I.FechaHoraDesde <= TT.TransitoLocal THEN I.FechaHoraDesde END DESC
        ,I.FechaHoraDesde ASC
    ) AS PO
OUTER APPLY (
    SELECT TOP 1 KT.DistanciaKmTeoricos
        ,KT.CicloKmTeoricos
    FROM dbo.Z_KmTeoricos AS KT WITH (NOLOCK)
    WHERE LTRIM(RTRIM(KT.Origen)) = LTRIM(RTRIM(ISNULL(PO.Origen, Z.Origen)))
        AND LTRIM(RTRIM(KT.Destino)) = LTRIM(RTRIM(ISNULL(PD.Destino, Z.Destino)))
    ORDER BY KT.Id DESC
    ) AS K
WHERE J.IdOperacion = 139
    AND V.IdEstadoViaje = 99
    AND Z.Filas > 0
    AND TE.FechaDescarga BETWEEN @FECHA_DESDE
        AND @FECHA_HASTA
ORDER BY TE.FechaDescarga
    ,V.IdViaje
