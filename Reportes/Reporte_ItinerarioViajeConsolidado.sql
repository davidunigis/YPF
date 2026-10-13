/**DECLARACION DE VARIABLES***/
DECLARE @FECHA_DESDE DATETIME
    ,@FECHA_HASTA DATETIME;

SET @FECHA_DESDE = CONVERT(DATETIME, CAST('!!FECHA_DESDE!!' AS VARCHAR), 103);
SET @FECHA_HASTA = CONVERT(DATETIME, CAST('!!FECHA_HASTA!!' AS VARCHAR), 103);
SET @FECHA_HASTA = DATEADD(DAY, 1, @FECHA_HASTA);

SELECT V.IdViaje
    ,Z.DescripcionViaje
    ,RTRIM(Z.Dominio) AS [Vehiculo]
    ,PO.Origen
    ,PD.Destino
    ,V.Varchar1 AS [Contrato]
    ,K.DistanciaKmTeoricos AS [KMTeoricos]
    ,K.CicloKmTeoricos
    ,Z.KmRecorridos AS [Kilometros Recorridos GPS]
    ,EV.descripcion AS [Estado Viaje]
    ,CONVERT(VARCHAR(10), TE.FechaDescarga, 103) + ' ' + CONVERT(VARCHAR(8), TE.FechaDescarga, 108) AS [Fecha y Hora Finalizacion (UTC)]
    ,dbo.Z_MinutosAHHMM(Z.MinYPF) AS [Demoras Responsabilidad YPF]
    ,dbo.Z_MinutosAHHMM(Z.MinExceso) AS [Exceso sobre Tolerancia YPF]
    ,dbo.Z_MinutosAHHMM(Z.MinTransporte) AS [Demoras Responsabilidad Transporte]
FROM dbo.Viaje AS V WITH (NOLOCK)
INNER JOIN dbo.Jornada AS J WITH (NOLOCK) ON J.IdJornada = V.IdJornada
INNER JOIN dbo.EstadoViaje AS EV WITH (NOLOCK) ON EV.IdEstadoViaje = V.IdEstadoViaje
CROSS APPLY (
    SELECT TOP 1 T.Fecha AS FechaDescarga
    FROM dbo.EstadoViajeTraceEstado AS T WITH (NOLOCK)
    WHERE T.IdViaje = V.IdViaje
        AND T.IdEstadoViajeDestino = 99
    ORDER BY T.Fecha DESC
    ) AS TE
CROSS APPLY (
    SELECT COUNT(*) AS Filas
        ,MAX(I.DescripcionViaje) AS DescripcionViaje
        ,MAX(I.Dominio) AS Dominio
        ,MAX(I.KmRecorridos) AS KmRecorridos
        ,SUM(CASE WHEN I.Novedad IN ('CARGA', 'DESCARGA') THEN I.TiempoMinutos ELSE 0 END) AS MinYPF
        ,SUM(CASE WHEN I.ResponsableDemora = 'YPF' THEN ISNULL(I.MinutosDemora, 0) ELSE 0 END) AS MinExceso
        ,SUM(CASE WHEN I.Novedad = 'DETENIDO' THEN I.TiempoMinutos - ISNULL(I.MinutosExentos, 0) ELSE 0 END) AS MinTransporte
    FROM dbo.Z_ItinerarioViaje AS I WITH (NOLOCK)
    WHERE I.IdViaje = V.IdViaje
    ) AS Z
OUTER APPLY (
    SELECT TOP 1 T2.Fecha AS FechaTransito
    FROM dbo.EstadoViajeTraceEstado AS T2 WITH (NOLOCK)
    WHERE T2.IdViaje = V.IdViaje
        AND T2.IdEstadoViajeDestino = 90
    ORDER BY T2.Fecha DESC
    ) AS TT
OUTER APPLY (
    SELECT TOP 1 PA.Descripcion AS Destino
    FROM dbo.Parada AS PA WITH (NOLOCK)
    LEFT JOIN dbo.EstadoParada AS EP WITH (NOLOCK) ON EP.IdEstadoParada = PA.IdEstadoParada
    WHERE PA.IdViaje = V.IdViaje
        AND PA.IdTipoParada = 3
        AND ISNULL(EP.Anulacion, 0) = 0
    ORDER BY CASE WHEN PA.IdEstadoParada = 91 THEN 0 ELSE 1 END
        ,PA.Orden DESC
        ,PA.IdParada DESC
    ) AS PD
OUTER APPLY (
    SELECT TOP 1 ISNULL(DP.Descripcion, PA.Descripcion) AS Origen
    FROM dbo.Parada AS PA WITH (NOLOCK)
    LEFT JOIN dbo.EstadoParada AS EP WITH (NOLOCK) ON EP.IdEstadoParada = PA.IdEstadoParada
    LEFT JOIN dbo.Deposito AS DP WITH (NOLOCK) ON DP.IdDeposito = PA.IdDeposito
    WHERE PA.IdViaje = V.IdViaje
        AND PA.IdTipoParada = 1
        AND ISNULL(EP.Anulacion, 0) = 0
    ORDER BY CASE WHEN PA.FechaCreacion <= TT.FechaTransito THEN 0 ELSE 1 END
        ,PA.FechaCreacion DESC
        ,PA.IdParada DESC
    ) AS PO
OUTER APPLY (
    SELECT TOP 1 KT.DistanciaKmTeoricos
        ,KT.CicloKmTeoricos
    FROM dbo.Z_KmTeoricos AS KT WITH (NOLOCK)
    WHERE LTRIM(RTRIM(KT.Origen)) = LTRIM(RTRIM(PO.Origen))
        AND LTRIM(RTRIM(KT.Destino)) = LTRIM(RTRIM(PD.Destino))
    ORDER BY KT.Id DESC
    ) AS K
WHERE J.IdOperacion = 139
    AND Z.Filas > 0
    AND TE.FechaDescarga BETWEEN @FECHA_DESDE
        AND @FECHA_HASTA
ORDER BY TE.FechaDescarga
    ,V.IdViaje
