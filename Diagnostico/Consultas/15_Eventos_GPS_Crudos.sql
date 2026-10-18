/*==============================================================================
  15 - EVENTOS GPS CRUDOS DE LA UNIDAD EN LA VENTANA DEL SP (+ margen)

  Cambiar @IdViaje. Una fila por evento del vehiculo, con el motivo por el que el SP
  lo usa o lo descarta. La ventana arranca hasta @MinutosAtras (360) antes de la activacion, acotada
  por la finalizacion del viaje anterior de la unidad (Ultima Milla); ver consulta 10. Fases:
    ANTES_DE_VENTANA  : anterior al inicio de la ventana (margen)
    HORA_PREVIA       : entre el inicio de la ventana y la activacion (retorno)
    VIAJE             : desde la activacion hasta la finalizacion
    DESPUES_DEL_CIERRE: posterior a la finalizacion (margen)
  DemoraRecepcionMin = minutos entre el evento y su recepcion (datos atrasados).
  Sin geometria: para ver en que geocerca cae cada evento usar la consulta 16.
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
DECLARE @MargenMin INT = 60;

SELECT ROW_NUMBER() OVER (ORDER BY E.FechaHoraEvento, E.IdEvento) AS N,
       E.IdEvento,
       E.FechaHoraEvento AS Evento_UTC,
       DATEADD(HOUR, @OffsetHoras, E.FechaHoraEvento) AS Evento_Local,
       E.FechaHoraRecepcion AS Recepcion_UTC,
       DATEDIFF(MINUTE, E.FechaHoraEvento, E.FechaHoraRecepcion) AS DemoraRecepcionMin,
       X.Lat, X.Lon, E.Velocidad, E.Rumbo, E.IdPrestador, E.Valido,
       CASE WHEN E.FechaHoraEvento < @FechaVentana THEN 'ANTES_DE_VENTANA'
            WHEN E.FechaHoraEvento < @FechaIni THEN 'HORA_PREVIA'
            WHEN E.FechaHoraEvento <= @FechaFin THEN 'VIAJE'
            ELSE 'DESPUES_DEL_CIERRE' END AS Fase,
       CASE WHEN E.Valido <> 'True' THEN 'NO_VALIDO'
            WHEN E.FechaHoraEvento < @FechaVentana OR E.FechaHoraEvento > @FechaFin THEN 'FUERA_DE_VENTANA'
            WHEN NOT (@IdEventoIni IS NULL OR E.FechaHoraEvento < @FechaIni OR E.IdEvento >= @IdEventoIni) THEN 'IDEVENTO_MENOR_A_ACTIVACION'
            WHEN X.Lat IS NULL OR X.Lon IS NULL OR X.Lat = 0 OR X.Lon = 0
              OR X.Lat NOT BETWEEN -90 AND 90 OR X.Lon NOT BETWEEN -180 AND 180 THEN 'COORDENADA_INVALIDA'
            ELSE NULL END AS MotivoDescarte,
       CASE WHEN @IdEventoFin > 0 AND E.IdEvento > @IdEventoFin THEN 1 ELSE 0 END AS IdMayorAlCierre
FROM dbo.Evento AS E WITH (NOLOCK)
CROSS APPLY (
    SELECT TRY_CAST(REPLACE(REPLACE(ISNULL(CAST(E.Latitud AS VARCHAR(50)), '0'), ',', '.'), ' ', '') AS FLOAT) AS Lat,
           TRY_CAST(REPLACE(REPLACE(ISNULL(CAST(E.Longitud AS VARCHAR(50)), '0'), ',', '.'), ' ', '') AS FLOAT) AS Lon
) AS X
WHERE E.IdVehiculo = @IdVehiculo
  AND E.FechaHoraEvento >= DATEADD(MINUTE, -@MargenMin, @FechaVentana)
  AND E.FechaHoraEvento <= DATEADD(MINUTE, @MargenMin, @FechaFin)
ORDER BY E.FechaHoraEvento, E.IdEvento;
