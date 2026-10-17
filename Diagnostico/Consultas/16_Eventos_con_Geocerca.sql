/*==============================================================================
  16 - EVENTOS QUE USA EL SP, CON SU GEOCERCA, DISTANCIA Y NOVEDAD PRELIMINAR

  Cambiar @IdViaje. Reproduce los PASOS 3 a 5 del SP: eventos de la ventana (con la
  hora previa a la activacion), en que geocerca cae cada uno (gana la de menor
  Prioridad: 10 = paradas del viaje, 40 = estaciones de servicio), distancia al
  evento anterior (haversine) y la novedad preliminar por evento. Es lo mas util
  para entender por que un tramo quedo como quedo. Puede tardar unos segundos.
  Fase: HORA_PREVIA (antes de la activacion) o VIAJE.
==============================================================================*/
DECLARE @IdViaje INT = 330178;
DECLARE @MinutosAtras INT = 60, @OffsetHoras INT = -3, @VelocidadDetenido DECIMAL(6,2) = 0;
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

IF OBJECT_ID('tempdb..#ZonasDx16') IS NOT NULL DROP TABLE #ZonasDx16;
IF OBJECT_ID('tempdb..#EvDx16') IS NOT NULL DROP TABLE #EvDx16;

CREATE TABLE #ZonasDx16
(
    IdDibujo     INT          NOT NULL PRIMARY KEY,
    Nombre       VARCHAR(150) NULL,
    ClaseZona    VARCHAR(20)  NOT NULL,
    ClaseAlterna VARCHAR(20)  NULL,
    Prioridad    INT          NOT NULL,
    Geografia    GEOGRAPHY    NULL
);

;WITH Cl AS (
    SELECT C.IdDibujo, C.IdParada, C.Orden, C.Descripcion,
           CASE C.ClaseParada WHEN 'DEPOSITO_ORIGEN' THEN 'CARGA' WHEN 'CARGA' THEN 'CARGA'
                              WHEN 'DESCARGA' THEN 'DESCARGA' ELSE 'RETORNO' END AS Clase,
           ROW_NUMBER() OVER (PARTITION BY C.IdDibujo ORDER BY C.Orden)      AS RnAsc,
           ROW_NUMBER() OVER (PARTITION BY C.IdDibujo ORDER BY C.Orden DESC) AS RnDesc
    FROM dbo.Z_ClasificarParadasViaje(@IdViaje) AS C
    WHERE C.IdDibujo IS NOT NULL
)
INSERT INTO #ZonasDx16 (IdDibujo, Nombre, ClaseZona, ClaseAlterna, Prioridad, Geografia)
SELECT A.IdDibujo, ISNULL(DB.Nombre, A.Descripcion), A.Clase, U.Clase, 10, DB.Geografia
FROM Cl AS A
INNER JOIN Cl AS U ON U.IdDibujo = A.IdDibujo AND U.RnDesc = 1
INNER JOIN dbo.Dibujo AS DB WITH (NOLOCK) ON DB.IdDibujo = A.IdDibujo
WHERE A.RnAsc = 1 AND DB.Geografia IS NOT NULL;

INSERT INTO #ZonasDx16 (IdDibujo, Nombre, ClaseZona, ClaseAlterna, Prioridad, Geografia)
SELECT ES.IdDibujo, ES.Nombre, 'COMBUSTIBLE', NULL, 40, ES.Geografia
FROM (SELECT E2.IdDibujo, E2.Nombre, E2.Geografia,
             ROW_NUMBER() OVER (PARTITION BY E2.IdDibujo ORDER BY E2.Nombre) AS Rn
      FROM dbo.Z_EstacionesDeServicioYPF AS E2 WITH (NOLOCK)
      WHERE E2.Geografia IS NOT NULL AND ISNULL(E2.Eliminado, 0) = 0) AS ES
WHERE ES.Rn = 1
  AND NOT EXISTS (SELECT 1 FROM #ZonasDx16 AS Z WHERE Z.IdDibujo = ES.IdDibujo);

SELECT ROW_NUMBER() OVER (ORDER BY E.FechaHoraEvento, E.IdEvento) AS Secuencia,
       E.IdEvento, E.FechaHoraEvento, X.Lat, X.Lon, ISNULL(E.Velocidad, 0) AS Velocidad,
       CASE WHEN E.FechaHoraEvento < @FechaIni THEN 'HORA_PREVIA' ELSE 'VIAJE' END AS Fase,
       CAST(NULL AS GEOGRAPHY) AS Punto,
       CAST(NULL AS FLOAT) AS DistanciaKm,
       CAST(NULL AS INT) AS IdDibujoZona, CAST(NULL AS VARCHAR(150)) AS NombreZona,
       CAST(NULL AS VARCHAR(20)) AS ClaseZona, CAST(NULL AS INT) AS Prioridad
INTO #EvDx16
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

UPDATE #EvDx16 SET Punto = GEOGRAPHY::Point(Lat, Lon, 4326);

;WITH Pares AS (
    SELECT Secuencia, Lat, Lon,
           LAG(Lat) OVER (ORDER BY Secuencia) AS LatAnt,
           LAG(Lon) OVER (ORDER BY Secuencia) AS LonAnt
    FROM #EvDx16
)
UPDATE E SET E.DistanciaKm =
    CASE WHEN P.LatAnt IS NOT NULL AND ABS(P.Lat - P.LatAnt) < 1.5 AND ABS(P.Lon - P.LonAnt) < 1.5
         THEN 2.0 * 6371.0 * ASIN(SQRT(POWER(SIN(RADIANS(P.Lat - P.LatAnt) / 2.0), 2)
              + COS(RADIANS(P.LatAnt)) * COS(RADIANS(P.Lat))
              * POWER(SIN(RADIANS(P.Lon - P.LonAnt) / 2.0), 2)))
         ELSE 0.0 END
FROM #EvDx16 AS E INNER JOIN Pares AS P ON P.Secuencia = E.Secuencia;

UPDATE E
    SET E.IdDibujoZona = Z.IdDibujo, E.NombreZona = Z.Nombre, E.ClaseZona = Z.ClaseZona, E.Prioridad = Z.Prioridad
FROM #EvDx16 AS E
CROSS APPLY (
    SELECT TOP 1 ZN.IdDibujo, ZN.Nombre, ZN.ClaseZona, ZN.Prioridad
    FROM #ZonasDx16 AS ZN
    WHERE ZN.Geografia.MakeValid().STIntersects(E.Punto) = 1
    ORDER BY ZN.Prioridad, ZN.IdDibujo
) AS Z;

SELECT E.Secuencia, E.IdEvento, E.Fase,
       E.FechaHoraEvento AS Evento_UTC,
       DATEADD(HOUR, @OffsetHoras, E.FechaHoraEvento) AS Evento_Local,
       E.Lat, E.Lon, E.Velocidad,
       CAST(E.DistanciaKm AS DECIMAL(10,3)) AS DistanciaKm,
       E.IdDibujoZona, E.NombreZona, E.ClaseZona, E.Prioridad,
       Z.ClaseAlterna,
       CASE WHEN E.ClaseZona IN ('CARGA', 'DESCARGA', 'RETORNO', 'COMBUSTIBLE') THEN E.ClaseZona
            WHEN E.Velocidad <= @VelocidadDetenido THEN 'DETENIDO'
            ELSE 'CARRETEANDO' END AS NovedadPreliminar
FROM #EvDx16 AS E
LEFT JOIN #ZonasDx16 AS Z ON Z.IdDibujo = E.IdDibujoZona
ORDER BY E.Secuencia;

DROP TABLE #EvDx16;
DROP TABLE #ZonasDx16;
