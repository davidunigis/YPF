/*==============================================================================
  10 - CABECERA DEL VIAJE (1 fila)

  Cambiar @IdViaje. Datos del viaje, vehiculo, transporte, estado, eventos de
  activacion/finalizacion (UTC y local), la ventana de eventos que usa el SP
  (hasta @MinutosAtras antes de la activacion, acotada por el viaje anterior de la unidad), origen/destino que calcula el SP
  y lo que hay hoy en Z_ItinerarioViaje.
==============================================================================*/
DECLARE @IdViaje INT = 330178;
DECLARE @MinutosAtras INT = 360, @IdOperacion INT = 139, @OffsetHoras INT = -3;
DECLARE @IdVehiculo INT, @IdEventoIni BIGINT, @IdEventoFin BIGINT;
DECLARE @FechaIni DATETIME, @FechaFin DATETIME, @FechaVentana DATETIME, @FechaPublicado DATETIME;
DECLARE @IdViajePrevio INT, @FinPrevio DATETIME, @MotivoVentana VARCHAR(100);

SELECT @IdVehiculo = V.IdVehiculo, @IdEventoIni = V.IdEventoActivacion, @IdEventoFin = V.IdEventoFinalizacion
FROM dbo.Viaje AS V WITH (NOLOCK) WHERE V.IdViaje = @IdViaje;
SELECT @FechaIni = FechaHoraEvento FROM dbo.Evento WITH (NOLOCK) WHERE IdEvento = @IdEventoIni;
SELECT @FechaFin = FechaHoraEvento FROM dbo.Evento WITH (NOLOCK) WHERE IdEvento = @IdEventoFin;

IF @FechaIni IS NOT NULL
BEGIN
    SET @FechaVentana = DATEADD(MINUTE, -@MinutosAtras, @FechaIni);
    SET @MotivoVentana = 'tope de ' + CAST(@MinutosAtras AS VARCHAR(10)) + ' min';
    IF @MinutosAtras > 0
    BEGIN
        IF EXISTS (SELECT 1
                   FROM dbo.Viaje AS V3 WITH (NOLOCK)
                   INNER JOIN dbo.Jornada AS J3 WITH (NOLOCK) ON J3.IdJornada = V3.IdJornada
                   INNER JOIN dbo.Evento AS EA3 WITH (NOLOCK) ON EA3.IdEvento = V3.IdEventoActivacion
                   LEFT JOIN dbo.Evento AS EF3 WITH (NOLOCK) ON EF3.IdEvento = V3.IdEventoFinalizacion
                   WHERE V3.IdVehiculo = @IdVehiculo AND V3.IdViaje <> @IdViaje
                     AND (@IdOperacion IS NULL OR J3.IdOperacion = @IdOperacion)
                     AND EA3.FechaHoraEvento <= @FechaIni
                     AND EA3.FechaHoraEvento >= DATEADD(DAY, -3, @FechaIni)
                     AND (EF3.FechaHoraEvento > @FechaIni
                          OR (V3.IdEventoFinalizacion = 0 AND V3.IdEstadoViaje NOT IN (99, 100))))
        BEGIN
            SET @FechaVentana = @FechaIni;
            SET @MotivoVentana = 'hay otro viaje de la unidad activo al activarse este';
        END
        ELSE
        BEGIN
            SELECT TOP 1 @IdViajePrevio = V2.IdViaje, @FinPrevio = EF2.FechaHoraEvento
            FROM dbo.Viaje AS V2 WITH (NOLOCK)
            INNER JOIN dbo.Jornada AS J2 WITH (NOLOCK) ON J2.IdJornada = V2.IdJornada
            INNER JOIN dbo.Evento AS EF2 WITH (NOLOCK) ON EF2.IdEvento = V2.IdEventoFinalizacion
            WHERE V2.IdVehiculo = @IdVehiculo AND V2.IdViaje <> @IdViaje
              AND V2.IdEventoFinalizacion > 0 AND V2.IdEstadoViaje <> 100
              AND (@IdOperacion IS NULL OR J2.IdOperacion = @IdOperacion)
              AND EF2.FechaHoraEvento <= @FechaIni AND EF2.FechaHoraEvento > @FechaVentana
            ORDER BY EF2.FechaHoraEvento DESC;
            IF @FinPrevio IS NOT NULL
            BEGIN
                SET @FechaVentana = @FinPrevio;
                SET @MotivoVentana = 'finalizacion del viaje anterior ' + CAST(@IdViajePrevio AS VARCHAR(12));
            END;
        END;
    END;
END;

IF @FechaIni IS NULL SELECT @FechaIni = V.FechaCreacion FROM dbo.Viaje AS V WITH (NOLOCK) WHERE V.IdViaje = @IdViaje;
IF @FechaFin IS NULL SET @FechaFin = DATEADD(HOUR, 72, @FechaIni);
IF @FechaVentana IS NULL SET @FechaVentana = @FechaIni;

SELECT @FechaPublicado = MIN(TE.Fecha)
FROM dbo.EstadoViajeTraceEstado AS TE WITH (NOLOCK)
WHERE TE.IdViaje = @IdViaje AND TE.IdEstadoViajeDestino IN (98, 92);

SELECT V.IdViaje, V.Descripcion, V.IdEstadoViaje, EV.descripcion AS Estado,
       J.IdOperacion, V.Varchar1 AS Contrato,
       V.IdVehiculo, VH.Dominio, VH.IdTransporte, T.RazonSocial AS Transporte,
       V.IdEventoActivacion, V.IdEventoFinalizacion,
       EA.FechaHoraEvento AS Activacion_UTC,
       DATEADD(HOUR, @OffsetHoras, EA.FechaHoraEvento) AS Activacion_Local,
       @FechaVentana AS VentanaDesde_UTC, DATEADD(HOUR, @OffsetHoras, @FechaVentana) AS VentanaDesde_Local, @MotivoVentana AS MotivoVentana,
       @IdViajePrevio AS IdViajePrevio, DATEADD(HOUR, @OffsetHoras, @FinPrevio) AS FinViajePrevio_Local,
       DATEADD(HOUR, @OffsetHoras, @FechaPublicado) AS PublicadoOProgramado_Local,
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
