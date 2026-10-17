/*==============================================================================
  12 - CAMBIOS DE ESTADO DEL VIAJE (EstadoViajeTraceEstado)

  Cambiar @IdViaje. Fechas en UTC y local. EsFinDeCarga marca el PRIMER pase a
  En transito (90): el SP lo usa para decidir hasta cuando las visitas al deposito
  son carga y cuando pasan a ser retorno.
==============================================================================*/
DECLARE @IdViaje INT = 330178;
DECLARE @OffsetHoras INT = -3;

SELECT T.Fecha AS Fecha_UTC,
       DATEADD(HOUR, @OffsetHoras, T.Fecha) AS Fecha_Local,
       T.IdEstadoViajeOrigen, EO.descripcion AS EstadoOrigen,
       T.IdEstadoViajeDestino, ED.descripcion AS EstadoDestino,
       T.Login,
       CASE WHEN T.IdEstadoViajeDestino = 90
             AND T.Fecha = (SELECT MIN(X.Fecha) FROM dbo.EstadoViajeTraceEstado AS X WITH (NOLOCK)
                            WHERE X.IdViaje = T.IdViaje AND X.IdEstadoViajeDestino = 90)
            THEN 'SI' ELSE '' END AS EsFinDeCarga
FROM dbo.EstadoViajeTraceEstado AS T WITH (NOLOCK)
LEFT JOIN dbo.EstadoViaje AS EO WITH (NOLOCK) ON EO.IdEstadoViaje = T.IdEstadoViajeOrigen
LEFT JOIN dbo.EstadoViaje AS ED WITH (NOLOCK) ON ED.IdEstadoViaje = T.IdEstadoViajeDestino
WHERE T.IdViaje = @IdViaje
ORDER BY T.Fecha;
