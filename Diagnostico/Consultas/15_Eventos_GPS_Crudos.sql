/*==============================================================================
  15 - EVENTOS GPS CRUDOS DE LA UNIDAD EN LA VENTANA DEL SP (+ margen)

  Cambiar @IdViaje. Una fila por evento del vehiculo, con el motivo por el que el SP
  lo usa o lo descarta. Fases:
    ANTES_DE_VENTANA  : anterior a la hora previa a la activacion (margen)
    HORA_PREVIA       : @MinutosAtras antes de la activacion
    VIAJE             : desde la activacion hasta la finalizacion
    DESPUES_DEL_CIERRE: posterior a la finalizacion (margen)
  DemoraRecepcionMin = minutos entre el evento y su recepcion (datos atrasados).
  Sin geometria: para ver en que geocerca cae cada evento usar la consulta 16.
==============================================================================*/
DECLARE @IdViaje INT = 330178;
DECLARE @MinutosAtras INT = 60, @OffsetHoras INT = -3, @MargenMin INT = 60;
DECLARE @IdVehiculo INT, @IdEventoIni BIGINT, @IdEventoFin BIGINT;
DECLARE @FechaIni DATETIME, @FechaFin DATETIME, @FechaVentana DATETIME;

SELECT @IdVehiculo = V.IdVehiculo, @IdEventoIni = V.IdEventoActivacion, @IdEventoFin = V.IdEventoFinalizacion
FROM dbo.Viaje AS V WITH (NOLOCK) WHERE V.IdViaje = @IdViaje;
SELECT @FechaIni = FechaHoraEvento FROM dbo.Evento WITH (NOLOCK) WHERE IdEvento = @IdEventoIni;
SELECT @FechaFin = FechaHoraEvento FROM dbo.Evento WITH (NOLOCK) WHERE IdEvento = @IdEventoFin;
IF @FechaIni IS NOT NULL SET @FechaVentana = DATEADD(MINUTE, -@MinutosAtras, @FechaIni);
IF @FechaIni IS NULL SELECT @FechaIni = V.FechaCreacion FROM dbo.Viaje AS V WITH (NOLOCK) WHERE V.IdViaje = @IdViaje;
IF @FechaFin IS NULL SET @FechaFin = DATEADD(HOUR, 72, @FechaIni);
IF @FechaVentana IS NULL SET @FechaVentana = @FechaIni;

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
