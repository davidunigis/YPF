/*==============================================================================
  10 - CABECERA DEL VIAJE (1 fila)

  Cambiar @IdViaje. Datos del viaje, vehiculo, transporte, estado, eventos de
  activacion/finalizacion (UTC y local), la ventana de eventos que usa el SP
  (desde @MinutosAtras antes de la activacion), origen/destino que calcula el SP
  y lo que hay hoy en Z_ItinerarioViaje.
==============================================================================*/
DECLARE @IdViaje INT = 330178;
DECLARE @MinutosAtras INT = 60, @OffsetHoras INT = -3;

SELECT V.IdViaje, V.Descripcion, V.IdEstadoViaje, EV.descripcion AS Estado,
       J.IdOperacion, V.Varchar1 AS Contrato,
       V.IdVehiculo, VH.Dominio, VH.IdTransporte, T.RazonSocial AS Transporte,
       V.IdEventoActivacion, V.IdEventoFinalizacion,
       EA.FechaHoraEvento AS Activacion_UTC,
       DATEADD(HOUR, @OffsetHoras, EA.FechaHoraEvento) AS Activacion_Local,
       DATEADD(MINUTE, -@MinutosAtras, EA.FechaHoraEvento) AS VentanaDesde_UTC,
       EF.FechaHoraEvento AS Finalizacion_UTC,
       DATEADD(HOUR, @OffsetHoras, EF.FechaHoraEvento) AS Finalizacion_Local,
       V.FechaCreacion AS Creacion_UTC, V.FechaInicioReal, V.FechaFinReal,
       V.IdDepositoSalida, D.Descripcion AS DepositoSalida,
       V.Origen AS Origen_Viaje, V.Destino AS Destino_Viaje,
       (SELECT TOP 1 C.Descripcion FROM dbo.Z_ClasificarParadasViaje(V.IdViaje) AS C
        WHERE C.ClaseParada = 'DESCARGA' ORDER BY C.Orden DESC) AS DestinoQueUsaElSP,
       (SELECT COUNT(*) FROM dbo.Z_ItinerarioViaje AS Z WITH (NOLOCK) WHERE Z.IdViaje = V.IdViaje) AS FilasEnZ,
       (SELECT MAX(Z.FechaProcesamiento) FROM dbo.Z_ItinerarioViaje AS Z WITH (NOLOCK) WHERE Z.IdViaje = V.IdViaje) AS UltimoProcesamiento_Local
FROM dbo.Viaje AS V WITH (NOLOCK)
LEFT JOIN dbo.Jornada AS J WITH (NOLOCK) ON J.IdJornada = V.IdJornada
LEFT JOIN dbo.EstadoViaje AS EV WITH (NOLOCK) ON EV.IdEstadoViaje = V.IdEstadoViaje
LEFT JOIN dbo.Vehiculo AS VH WITH (NOLOCK) ON VH.IdVehiculo = V.IdVehiculo
LEFT JOIN dbo.Transporte AS T WITH (NOLOCK) ON T.IdTransporte = VH.IdTransporte
LEFT JOIN dbo.Evento AS EA WITH (NOLOCK) ON EA.IdEvento = V.IdEventoActivacion
LEFT JOIN dbo.Evento AS EF WITH (NOLOCK) ON EF.IdEvento = V.IdEventoFinalizacion
LEFT JOIN dbo.Deposito AS D WITH (NOLOCK) ON D.IdDeposito = V.IdDepositoSalida
WHERE V.IdViaje = @IdViaje;
