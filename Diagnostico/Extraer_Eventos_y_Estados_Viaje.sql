/*==============================================================================
  EXTRACCION COMPLEMENTARIA DE UN VIAJE: TODOS LOS EVENTOS Y EL HISTORIAL DE ESTADOS

  Solo LEE. Mismo formato de salida que Extraer_Datos_Viaje.sql (Seccion | Parte | Dato).
  Responde dos preguntas que quedaron abiertas:
    1) Los eventos que el SP DESCARTA: el SP filtra por tiempo y ademas por
       IdEvento <= IdEventoFinalizacion; los datos que llegan tarde (con IdEvento
       mayor pero hora anterior) quedan afuera. Aca van TODOS los de la ventana,
       con FechaHoraRecepcion, y la marca UsadoPorSP.
    2) Los estados reales del viaje y de sus paradas (trazas de estado, bitacora,
       monitor de geocercas) para contrastarlos con lo que infiere el GPS.

  Secciones: CONTEXTO, EVENTOS_TODOS, EVENTOS_RESUMEN, PARADA, PARADA_TRACE_ESTADO,
  ESTADOVIAJE_TRACE, BITACORA, MONITOR_GEOCERCA, CATALOGO_ESTADO_VIAJE,
  CATALOGO_ESTADO_PARADA, ESQUEMA y ERROR_* si algo falla.
  Mismos requisitos de SSMS que el otro script (maximo de caracteres = 2097152).
==============================================================================*/
USE [UNIGIS_DataRepository_YPF_ARENAS_QA]
GO
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @IdViaje   INT = 329958;
DECLARE @TamChunk  INT = 100;      -- eventos por fila de salida
DECLARE @MargenMin INT = 30;       -- minutos extra antes y despues de la ventana del viaje

IF OBJECT_ID('tempdb..#Salida') IS NOT NULL DROP TABLE #Salida;
IF OBJECT_ID('tempdb..#Ev')     IS NOT NULL DROP TABLE #Ev;
CREATE TABLE #Salida (Id INT IDENTITY(1,1) PRIMARY KEY, Seccion VARCHAR(40) NOT NULL, Parte INT NOT NULL, Dato NVARCHAR(MAX) NULL);

DECLARE @IdVehiculo INT, @IdEventoIni BIGINT, @IdEventoFin BIGINT, @FechaIni DATETIME, @FechaFin DATETIME;

SELECT @IdVehiculo = V.IdVehiculo, @IdEventoIni = V.IdEventoActivacion, @IdEventoFin = V.IdEventoFinalizacion
FROM dbo.Viaje V WITH (NOLOCK) WHERE V.IdViaje = @IdViaje;

IF @IdVehiculo IS NULL
BEGIN
    RAISERROR('Viaje no encontrado.', 16, 1);
    RETURN;
END;

/* Misma ventana temporal que el SP */
SELECT @FechaIni = FechaHoraEvento FROM dbo.Evento WITH (NOLOCK) WHERE IdEvento = @IdEventoIni;
SELECT @FechaFin = FechaHoraEvento FROM dbo.Evento WITH (NOLOCK) WHERE IdEvento = @IdEventoFin;
IF @FechaIni IS NULL
    SELECT @FechaIni = V.FechaCreacion FROM dbo.Viaje V WITH (NOLOCK) WHERE V.IdViaje = @IdViaje;
IF @FechaFin IS NULL
    SET @FechaFin = DATEADD(HOUR, 72, @FechaIni);

INSERT INTO #Salida (Seccion, Parte, Dato)
SELECT 'CONTEXTO', 1,
       (SELECT @IdViaje AS IdViaje, @IdVehiculo AS IdVehiculo,
               @IdEventoIni AS IdEventoActivacion, @IdEventoFin AS IdEventoFinalizacion,
               CONVERT(VARCHAR(19), @FechaIni, 120) AS FechaIni_UTC, CONVERT(VARCHAR(19), @FechaFin, 120) AS FechaFin_UTC,
               @MargenMin AS MargenMin
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

/*------------------------------------------------------------------------------
  Todos los eventos del vehiculo en la ventana (+/- margen), con su marca
------------------------------------------------------------------------------*/
SELECT
    E.IdEvento,
    E.FechaHoraEvento, E.FechaHoraRecepcion, E.FechaHoraReportado, E.FechaHoraCalculada,
    E.Latitud, E.Longitud, E.Velocidad, E.Rumbo, E.IdPrestador, E.Valido, E.Prioridad,
    CASE WHEN E.Valido = 'True'
          AND E.FechaHoraEvento >= @FechaIni AND E.FechaHoraEvento <= @FechaFin
          AND (@IdEventoIni IS NULL OR E.IdEvento >= @IdEventoIni)
          AND (@IdEventoFin IS NULL OR E.IdEvento <= @IdEventoFin)
         THEN 1 ELSE 0 END AS UsadoPorSP,
    CASE WHEN E.FechaHoraEvento >= @FechaIni AND E.FechaHoraEvento <= @FechaFin THEN 1 ELSE 0 END AS EnVentanaTiempo,
    (ROW_NUMBER() OVER (ORDER BY E.FechaHoraEvento, E.IdEvento) - 1) / @TamChunk AS Chunk
INTO #Ev
FROM dbo.Evento E WITH (NOLOCK)
WHERE E.IdVehiculo = @IdVehiculo
  AND E.FechaHoraEvento >= DATEADD(MINUTE, -@MargenMin, @FechaIni)
  AND E.FechaHoraEvento <= DATEADD(MINUTE,  @MargenMin, @FechaFin);

INSERT INTO #Salida (Seccion, Parte, Dato)
SELECT 'EVENTOS_TODOS', G.Chunk,
       (SELECT E.IdEvento,
               CONVERT(VARCHAR(19), E.FechaHoraEvento, 120)     AS Evento_UTC,
               CONVERT(VARCHAR(19), E.FechaHoraRecepcion, 120)  AS Recepcion_UTC,
               CONVERT(VARCHAR(19), E.FechaHoraReportado, 120)  AS Reportado_UTC,
               CONVERT(VARCHAR(19), E.FechaHoraCalculada, 120)  AS Calculada_UTC,
               E.Latitud, E.Longitud, E.Velocidad, E.Rumbo, E.IdPrestador, E.Valido, E.Prioridad,
               E.UsadoPorSP, E.EnVentanaTiempo
        FROM #Ev E
        WHERE E.Chunk = G.Chunk
        ORDER BY E.FechaHoraEvento, E.IdEvento
        FOR JSON PATH)
FROM (SELECT DISTINCT Chunk FROM #Ev) G;

INSERT INTO #Salida (Seccion, Parte, Dato)
SELECT 'EVENTOS_RESUMEN', 1,
       (SELECT COUNT(*) AS TotalConMargen,
               SUM(CASE WHEN UsadoPorSP = 1 THEN 1 ELSE 0 END)                         AS UsadosPorSP,
               SUM(CASE WHEN EnVentanaTiempo = 1 AND UsadoPorSP = 0 THEN 1 ELSE 0 END) AS EnVentanaPeroDescartadosPorSP,
               SUM(CASE WHEN EnVentanaTiempo = 1 AND UsadoPorSP = 0 AND IdEvento > @IdEventoFin THEN 1 ELSE 0 END) AS DescartadosPorIdMayorAlFinal,
               SUM(CASE WHEN EnVentanaTiempo = 1 AND UsadoPorSP = 0 AND IdEvento < @IdEventoIni THEN 1 ELSE 0 END) AS DescartadosPorIdMenorAlInicio,
               SUM(CASE WHEN EnVentanaTiempo = 1 AND Valido = 0 THEN 1 ELSE 0 END)     AS NoValidos,
               MAX(DATEDIFF(MINUTE, FechaHoraEvento, FechaHoraRecepcion))              AS MaxDemoraRecepcionMin
        FROM #Ev
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

/*------------------------------------------------------------------------------
  Paradas, trazas de estado, bitacora y monitor de geocercas del viaje
  (nombres de columna supuestos: si alguno no existe, sale ERROR_<seccion> con el
   mensaje y el ESQUEMA de abajo permite corregir la consulta)
------------------------------------------------------------------------------*/
BEGIN TRY
    INSERT INTO #Salida (Seccion, Parte, Dato)
    SELECT 'PARADA', 1, (SELECT X.* FROM dbo.Parada X WITH (NOLOCK) WHERE X.IdViaje = @IdViaje ORDER BY X.Orden FOR JSON PATH);
END TRY
BEGIN CATCH
    INSERT INTO #Salida (Seccion, Parte, Dato) VALUES ('ERROR_PARADA', 1, ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    INSERT INTO #Salida (Seccion, Parte, Dato)
    SELECT 'PARADA_TRACE_ESTADO', 1,
           (SELECT X.* FROM dbo.ParadaTraceEstado X WITH (NOLOCK)
            WHERE X.IdParada IN (SELECT P.IdParada FROM dbo.Parada P WITH (NOLOCK) WHERE P.IdViaje = @IdViaje)
            FOR JSON PATH);
END TRY
BEGIN CATCH
    INSERT INTO #Salida (Seccion, Parte, Dato) VALUES ('ERROR_PARADA_TRACE_ESTADO', 1, ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    INSERT INTO #Salida (Seccion, Parte, Dato)
    SELECT 'ESTADOVIAJE_TRACE', 1,
           (SELECT X.* FROM dbo.EstadoViajeTraceEstado X WITH (NOLOCK) WHERE X.IdViaje = @IdViaje FOR JSON PATH);
END TRY
BEGIN CATCH
    INSERT INTO #Salida (Seccion, Parte, Dato) VALUES ('ERROR_ESTADOVIAJE_TRACE', 1, ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    INSERT INTO #Salida (Seccion, Parte, Dato)
    SELECT 'BITACORA', 1,
           (SELECT TOP 200 X.* FROM dbo.BitacoraViaje X WITH (NOLOCK) WHERE X.IdViaje = @IdViaje FOR JSON PATH);
END TRY
BEGIN CATCH
    INSERT INTO #Salida (Seccion, Parte, Dato) VALUES ('ERROR_BITACORA', 1, ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    INSERT INTO #Salida (Seccion, Parte, Dato)
    SELECT 'MONITOR_GEOCERCA', 1,
           (SELECT TOP 200 X.* FROM dbo.Z_LPViajeMonitorGeocerca X WITH (NOLOCK) WHERE X.IdViaje = @IdViaje FOR JSON PATH);
END TRY
BEGIN CATCH
    INSERT INTO #Salida (Seccion, Parte, Dato) VALUES ('ERROR_MONITOR_GEOCERCA', 1, ERROR_MESSAGE());
END CATCH;

/* Catalogos para decodificar los estados de las trazas */
BEGIN TRY
    INSERT INTO #Salida (Seccion, Parte, Dato)
    SELECT 'CATALOGO_ESTADO_VIAJE', 1,
           (SELECT X.IdEstadoViaje, X.Descripcion, X.IdSeguimientoEstado FROM dbo.EstadoViaje X WITH (NOLOCK) ORDER BY X.IdEstadoViaje FOR JSON PATH);
END TRY
BEGIN CATCH
    INSERT INTO #Salida (Seccion, Parte, Dato) VALUES ('ERROR_CATALOGO_ESTADO_VIAJE', 1, ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    INSERT INTO #Salida (Seccion, Parte, Dato)
    SELECT 'CATALOGO_ESTADO_PARADA', 1,
           (SELECT X.* FROM dbo.EstadoParada X WITH (NOLOCK) FOR JSON PATH);
END TRY
BEGIN CATCH
    INSERT INTO #Salida (Seccion, Parte, Dato) VALUES ('ERROR_CATALOGO_ESTADO_PARADA', 1, ERROR_MESSAGE());
END CATCH;

/* Esquema de las tablas consultadas (siempre sale, aunque falle una consulta) */
BEGIN TRY
    INSERT INTO #Salida (Seccion, Parte, Dato)
    SELECT 'ESQUEMA', ROW_NUMBER() OVER (ORDER BY T.name),
           (SELECT T.name AS Tabla, C.column_id AS Id, C.name AS Columna, TY.name AS Tipo
            FROM sys.columns C
            INNER JOIN sys.types TY ON TY.user_type_id = C.user_type_id
            WHERE C.object_id = T.object_id
            ORDER BY C.column_id
            FOR JSON PATH)
    FROM sys.tables T
    WHERE T.name IN ('Parada', 'ParadaTraceEstado', 'EstadoViajeTraceEstado', 'BitacoraViaje',
                     'Z_LPViajeMonitorGeocerca', 'EstadoParada', 'EstadoViaje', 'Z_Viaje', 'Z_TViaje');
END TRY
BEGIN CATCH
    INSERT INTO #Salida (Seccion, Parte, Dato) VALUES ('ERROR_ESQUEMA', 1, ERROR_MESSAGE());
END CATCH;

SELECT Seccion, Parte, Dato FROM #Salida ORDER BY Id;
