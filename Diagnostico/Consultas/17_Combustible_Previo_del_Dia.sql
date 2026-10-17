/*==============================================================================
  17 - CARGAS DE COMBUSTIBLE PREVIAS DEL DIA (excepcion una vez por dia y unidad)

  Cambiar @IdViaje. Reproduce el PASO 7.a.0 del SP: desde las 00:00 locales del primer
  dia del viaje hasta el primer evento del viaje, visitas de la unidad a estaciones
  de servicio. CuentaComoCargaPrevia = SI cuando la visita cumple permanencia minima
  y al menos un evento detenido (misma regla que un tramo COMBUSTIBLE valido).
  Cada SI hace que la primera carga del viaje ya NO tenga la excepcion de 30 min.
  Sin filas = ninguna carga previa. EsUltimaVisita = SI: si es la misma estacion en la que
  arranca el viaje (ver consulta 16) el SP NO la cuenta (es la misma detencion).
==============================================================================*/
DECLARE @IdViaje INT = 330178;
DECLARE @MinutosAtras INT = 60, @OffsetHoras INT = -3;
DECLARE @MinutosMinPermanencia INT = 2, @VelocidadDetenido DECIMAL(6,2) = 0;
DECLARE @IdVehiculo INT, @IdEventoIni BIGINT, @IdEventoFin BIGINT;
DECLARE @FechaIni DATETIME, @FechaFin DATETIME, @FechaVentana DATETIME;
DECLARE @HastaPrevio DATETIME, @DiaPrimero DATE, @DesdeDia DATETIME;

SELECT @IdVehiculo = V.IdVehiculo, @IdEventoIni = V.IdEventoActivacion, @IdEventoFin = V.IdEventoFinalizacion
FROM dbo.Viaje AS V WITH (NOLOCK) WHERE V.IdViaje = @IdViaje;
SELECT @FechaIni = FechaHoraEvento FROM dbo.Evento WITH (NOLOCK) WHERE IdEvento = @IdEventoIni;
SELECT @FechaFin = FechaHoraEvento FROM dbo.Evento WITH (NOLOCK) WHERE IdEvento = @IdEventoFin;
IF @FechaIni IS NOT NULL SET @FechaVentana = DATEADD(MINUTE, -@MinutosAtras, @FechaIni);
IF @FechaIni IS NULL SELECT @FechaIni = V.FechaCreacion FROM dbo.Viaje AS V WITH (NOLOCK) WHERE V.IdViaje = @IdViaje;
IF @FechaFin IS NULL SET @FechaFin = DATEADD(HOUR, 72, @FechaIni);
IF @FechaVentana IS NULL SET @FechaVentana = @FechaIni;

SELECT @HastaPrevio = MIN(E.FechaHoraEvento)
FROM dbo.Evento AS E WITH (NOLOCK)
CROSS APPLY (
    SELECT TRY_CAST(REPLACE(REPLACE(ISNULL(CAST(E.Latitud AS VARCHAR(50)), '0'), ',', '.'), ' ', '') AS FLOAT) AS Lat,
           TRY_CAST(REPLACE(REPLACE(ISNULL(CAST(E.Longitud AS VARCHAR(50)), '0'), ',', '.'), ' ', '') AS FLOAT) AS Lon
) AS X
WHERE E.IdVehiculo = @IdVehiculo
  AND E.Valido = 'True'
  AND E.FechaHoraEvento >= @FechaVentana
  AND E.FechaHoraEvento <= @FechaFin
  AND (@IdEventoIni IS NULL OR E.FechaHoraEvento < @FechaIni OR E.IdEvento >= @IdEventoIni)
  AND X.Lat IS NOT NULL AND X.Lon IS NOT NULL AND X.Lat <> 0 AND X.Lon <> 0
  AND X.Lat BETWEEN -90 AND 90 AND X.Lon BETWEEN -180 AND 180;

SET @DiaPrimero = CAST(DATEADD(HOUR, @OffsetHoras, @HastaPrevio) AS DATE);
SET @DesdeDia = DATEADD(HOUR, -@OffsetHoras, CAST(@DiaPrimero AS DATETIME));

IF OBJECT_ID('tempdb..#ZonasDx17') IS NOT NULL DROP TABLE #ZonasDx17;
IF OBJECT_ID('tempdb..#EvDx17') IS NOT NULL DROP TABLE #EvDx17;

CREATE TABLE #ZonasDx17
(
    IdDibujo  INT          NOT NULL PRIMARY KEY,
    Nombre    VARCHAR(150) NULL,
    ClaseZona VARCHAR(20)  NOT NULL,
    Prioridad INT          NOT NULL,
    Geografia GEOGRAPHY    NULL
);

INSERT INTO #ZonasDx17 (IdDibujo, Nombre, ClaseZona, Prioridad, Geografia)
SELECT A.IdDibujo, ISNULL(DB.Nombre, A.Descripcion),
       CASE A.ClaseParada WHEN 'DEPOSITO_ORIGEN' THEN 'CARGA' WHEN 'CARGA' THEN 'CARGA'
                          WHEN 'DESCARGA' THEN 'DESCARGA' ELSE 'RETORNO' END,
       10, DB.Geografia
FROM (SELECT C.*, ROW_NUMBER() OVER (PARTITION BY C.IdDibujo ORDER BY C.Orden) AS RnAsc
      FROM dbo.Z_ClasificarParadasViaje(@IdViaje) AS C WHERE C.IdDibujo IS NOT NULL) AS A
INNER JOIN dbo.Dibujo AS DB WITH (NOLOCK) ON DB.IdDibujo = A.IdDibujo
WHERE A.RnAsc = 1 AND DB.Geografia IS NOT NULL;

INSERT INTO #ZonasDx17 (IdDibujo, Nombre, ClaseZona, Prioridad, Geografia)
SELECT ES.IdDibujo, ES.Nombre, 'COMBUSTIBLE', 40, ES.Geografia
FROM (SELECT E2.IdDibujo, E2.Nombre, E2.Geografia,
             ROW_NUMBER() OVER (PARTITION BY E2.IdDibujo ORDER BY E2.Nombre) AS Rn
      FROM dbo.Z_EstacionesDeServicioYPF AS E2 WITH (NOLOCK)
      WHERE E2.Geografia IS NOT NULL AND ISNULL(E2.Eliminado, 0) = 0) AS ES
WHERE ES.Rn = 1
  AND NOT EXISTS (SELECT 1 FROM #ZonasDx17 AS Z WHERE Z.IdDibujo = ES.IdDibujo);

SELECT ROW_NUMBER() OVER (ORDER BY E.FechaHoraEvento, E.IdEvento) AS Secuencia,
       E.FechaHoraEvento, X.Lat, X.Lon, ISNULL(E.Velocidad, 0) AS Velocidad,
       CAST(NULL AS GEOGRAPHY) AS Punto,
       CAST(NULL AS INT) AS IdDibujoZona, CAST(NULL AS VARCHAR(150)) AS NombreZona, CAST(NULL AS VARCHAR(20)) AS ClaseZona
INTO #EvDx17
FROM dbo.Evento AS E WITH (NOLOCK)
CROSS APPLY (
    SELECT TRY_CAST(REPLACE(REPLACE(ISNULL(CAST(E.Latitud AS VARCHAR(50)), '0'), ',', '.'), ' ', '') AS FLOAT) AS Lat,
           TRY_CAST(REPLACE(REPLACE(ISNULL(CAST(E.Longitud AS VARCHAR(50)), '0'), ',', '.'), ' ', '') AS FLOAT) AS Lon
) AS X
WHERE E.IdVehiculo = @IdVehiculo
  AND E.Valido = 'True'
  AND E.FechaHoraEvento >= @DesdeDia
  AND E.FechaHoraEvento < @HastaPrevio
  AND X.Lat IS NOT NULL AND X.Lon IS NOT NULL AND X.Lat <> 0 AND X.Lon <> 0
  AND X.Lat BETWEEN -90 AND 90 AND X.Lon BETWEEN -180 AND 180;

UPDATE #EvDx17 SET Punto = GEOGRAPHY::Point(Lat, Lon, 4326);

UPDATE E
    SET E.IdDibujoZona = Z.IdDibujo, E.NombreZona = Z.Nombre, E.ClaseZona = Z.ClaseZona
FROM #EvDx17 AS E
CROSS APPLY (
    SELECT TOP 1 ZN.IdDibujo, ZN.Nombre, ZN.ClaseZona
    FROM #ZonasDx17 AS ZN
    WHERE ZN.Geografia.MakeValid().STIntersects(E.Punto) = 1
    ORDER BY ZN.Prioridad, ZN.IdDibujo
) AS Z;

;WITH Isl AS (
    SELECT Secuencia, FechaHoraEvento, Velocidad, IdDibujoZona, NombreZona, ClaseZona,
           ROW_NUMBER() OVER (ORDER BY Secuencia)
         - ROW_NUMBER() OVER (PARTITION BY ISNULL(IdDibujoZona, -1) ORDER BY Secuencia) AS G
    FROM #EvDx17
),
Vis AS (
    SELECT MIN(Secuencia) AS SecIni, MIN(FechaHoraEvento) AS Desde, MAX(FechaHoraEvento) AS UltimoEvento,
           COUNT(*) AS Eventos, MIN(Velocidad) AS VelMin,
           MAX(ClaseZona) AS ClaseZona, MAX(IdDibujoZona) AS IdDibujoZona, MAX(NombreZona) AS NombreZona
    FROM Isl
    GROUP BY G, ISNULL(IdDibujoZona, -1)
),
Fin AS (
    SELECT V.*,
           ISNULL(LEAD(V.Desde) OVER (ORDER BY V.SecIni), @HastaPrevio) AS Hasta,
           CASE WHEN LEAD(V.Desde) OVER (ORDER BY V.SecIni) IS NULL THEN 1 ELSE 0 END AS EsUltima
    FROM Vis AS V
)
SELECT F.IdDibujoZona, F.NombreZona,
       F.Desde AS Desde_UTC, DATEADD(HOUR, @OffsetHoras, F.Desde) AS Desde_Local,
       F.Hasta AS Hasta_UTC, DATEDIFF(MINUTE, F.Desde, F.Hasta) AS Minutos,
       F.Eventos, F.VelMin,
       CASE WHEN DATEDIFF(MINUTE, F.Desde, F.Hasta) >= @MinutosMinPermanencia THEN 'SI' ELSE 'NO' END AS CumplePermanencia,
       CASE WHEN F.VelMin <= @VelocidadDetenido THEN 'SI' ELSE 'NO' END AS TuvoEventoDetenido,
       CASE WHEN F.EsUltima = 1 THEN 'SI' ELSE 'NO' END AS EsUltimaVisita,
       CASE WHEN DATEDIFF(MINUTE, F.Desde, F.Hasta) >= @MinutosMinPermanencia AND F.VelMin <= @VelocidadDetenido
            THEN 'SI' ELSE 'NO' END AS CuentaComoCargaPrevia,
       @DesdeDia AS ConsultaDesde_UTC, @HastaPrevio AS ConsultaHasta_UTC
FROM Fin AS F
WHERE F.ClaseZona = 'COMBUSTIBLE'
ORDER BY F.SecIni;

DROP TABLE #EvDx17;
DROP TABLE #ZonasDx17;
