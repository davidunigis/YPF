/*==============================================================================
  30 - BRECHAS ENTRE VIAJES DE LA UNIDAD Y TIEMPOS DE PROGRAMACION (sin viaje)

  Una fila por viaje UM finalizado y activado de los ultimos @Dias dias. Sirve para
  decidir cuanto mirar hacia atras desde la activacion (ver
  Recomendaciones/Ventana_Hacia_Atras_y_Retorno.md):
    - Publicado / Programado / Activacion (hora local) y minutos entre cada uno
    - Viaje anterior de la MISMA unidad (cualquier operacion) que ya habia finalizado
      al activarse este: cuando termino y cuantos minutos antes de la activacion
    - RangoBrecha: SIN VIAJE PREVIO / <1 h / 1-6 h / 6-24 h / >24 h
    - ViajeAnteriorDentroDelTope = SI: el viaje anterior termino dentro de @MinutosAtras
      antes de la activacion; el SP arranca la ventana en esa finalizacion (con la regla
      vieja de 60 min fijos, esos eventos se contaban dos veces)
    - ViajesEnCursoAlActivar: otros viajes de la unidad activos en ese momento
  Exportar a Excel y armar una tabla dinamica por RangoBrecha.
==============================================================================*/
DECLARE @Dias INT = 30, @OffsetHoras INT = -3, @MinutosAtras INT = 360;

SELECT V.IdViaje, VH.Dominio, T.RazonSocial AS Transporte,
       DATEADD(HOUR, @OffsetHoras, PUB.Fecha) AS Publicado_Local,
       DATEADD(HOUR, @OffsetHoras, PROG.Fecha) AS Programado_Local,
       DATEADD(HOUR, @OffsetHoras, EA.FechaHoraEvento) AS Activacion_Local,
       DATEDIFF(MINUTE, PUB.Fecha, EA.FechaHoraEvento) AS MinPublicadoAActivacion,
       DATEDIFF(MINUTE, PROG.Fecha, EA.FechaHoraEvento) AS MinProgramadoAActivacion,
       PREV.IdViaje AS IdViajeAnterior,
       PREV.IdOperacion AS OperacionViajeAnterior,
       DATEADD(HOUR, @OffsetHoras, PREV.Fin) AS FinViajeAnterior_Local,
       DATEDIFF(MINUTE, PREV.Fin, EA.FechaHoraEvento) AS MinFinAnteriorAActivacion,
       CASE WHEN PREV.IdViaje IS NULL THEN 'SIN VIAJE PREVIO'
            WHEN DATEDIFF(MINUTE, PREV.Fin, EA.FechaHoraEvento) < 60 THEN '<1 h'
            WHEN DATEDIFF(MINUTE, PREV.Fin, EA.FechaHoraEvento) < 360 THEN '1-6 h'
            WHEN DATEDIFF(MINUTE, PREV.Fin, EA.FechaHoraEvento) < 1440 THEN '6-24 h'
            ELSE '>24 h' END AS RangoBrecha,
       CASE WHEN PREV.IdViaje IS NOT NULL
             AND PREV.Fin > DATEADD(MINUTE, -@MinutosAtras, EA.FechaHoraEvento) THEN 'SI' ELSE 'NO' END AS ViajeAnteriorDentroDelTope,
       SOL.N AS ViajesEnCursoAlActivar
FROM dbo.Viaje AS V WITH (NOLOCK)
INNER JOIN dbo.Jornada AS J WITH (NOLOCK) ON J.IdJornada = V.IdJornada
INNER JOIN dbo.Evento AS EA WITH (NOLOCK) ON EA.IdEvento = V.IdEventoActivacion
LEFT JOIN dbo.Vehiculo AS VH WITH (NOLOCK) ON VH.IdVehiculo = V.IdVehiculo
LEFT JOIN dbo.Transporte AS T WITH (NOLOCK) ON T.IdTransporte = VH.IdTransporte
OUTER APPLY (
    SELECT MIN(X.Fecha) AS Fecha
    FROM dbo.EstadoViajeTraceEstado AS X WITH (NOLOCK)
    WHERE X.IdViaje = V.IdViaje AND X.IdEstadoViajeDestino = 98
) AS PUB
OUTER APPLY (
    SELECT MIN(X.Fecha) AS Fecha
    FROM dbo.EstadoViajeTraceEstado AS X WITH (NOLOCK)
    WHERE X.IdViaje = V.IdViaje AND X.IdEstadoViajeDestino = 92
) AS PROG
OUTER APPLY (
    SELECT TOP 1 V2.IdViaje, J2.IdOperacion, EF2.FechaHoraEvento AS Fin
    FROM dbo.Viaje AS V2 WITH (NOLOCK)
    INNER JOIN dbo.Evento AS EF2 WITH (NOLOCK) ON EF2.IdEvento = V2.IdEventoFinalizacion
    LEFT JOIN dbo.Jornada AS J2 WITH (NOLOCK) ON J2.IdJornada = V2.IdJornada
    WHERE V2.IdVehiculo = V.IdVehiculo
      AND V2.IdViaje <> V.IdViaje
      AND V2.IdEventoFinalizacion > 0
      AND V2.IdEstadoViaje <> 100
      AND EF2.FechaHoraEvento <= EA.FechaHoraEvento
    ORDER BY EF2.FechaHoraEvento DESC
) AS PREV
OUTER APPLY (
    SELECT COUNT(*) AS N
    FROM dbo.Viaje AS V3 WITH (NOLOCK)
    INNER JOIN dbo.Evento AS EA3 WITH (NOLOCK) ON EA3.IdEvento = V3.IdEventoActivacion
    LEFT JOIN dbo.Evento AS EF3 WITH (NOLOCK) ON EF3.IdEvento = V3.IdEventoFinalizacion
    WHERE V3.IdVehiculo = V.IdVehiculo
      AND V3.IdViaje <> V.IdViaje
      AND V3.IdEstadoViaje <> 100
      AND EA3.FechaHoraEvento <= EA.FechaHoraEvento
      AND EA3.FechaHoraEvento >= DATEADD(DAY, -3, EA.FechaHoraEvento)
      AND (V3.IdEventoFinalizacion = 0 OR EF3.FechaHoraEvento > EA.FechaHoraEvento)
) AS SOL
WHERE J.IdOperacion = 139
  AND V.IdEstadoViaje = 99
  AND V.IdEventoActivacion > 0
  AND EA.FechaHoraEvento >= DATEADD(DAY, -@Dias, GETUTCDATE())
ORDER BY EA.FechaHoraEvento DESC;
