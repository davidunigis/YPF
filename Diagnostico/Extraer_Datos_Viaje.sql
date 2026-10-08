/*==============================================================================
  EXTRACCION DE DATOS DE UN VIAJE PARA ANALISIS  (Z_SP_ItinerarioViaje)

  Solo LEE (no modifica nada). Reune lo que el SP consume para calcular y lo que
  dejo escrito en Z_ItinerarioViaje, para recalcular por fuera y comparar.

  Devuelve UN solo resultado de 3 columnas: Seccion | Parte | Dato (JSON o texto).
  Secciones: CONTEXTO, VIAJE, VEHICULO, TRANSPORTE, JORNADA, ESTADO_VIAJE,
  CATEGORIA_VIAJE, DEPOSITO_SALIDA, PARADAS, ZONA, EVENTOS_RESUMEN, EVENTOS,
  KM_TEORICOS, Z_ITINERARIO, LOG, TURNO, OBJETOS, DEF_* (codigo del SP y de la
  funcion que estan desplegados), ESQUEMA, TABLAS, RESUMEN y ERROR_* si algo falla.

  Requiere SQL Server 2016+ (FOR JSON). Como usar en SSMS:
    1) Herramientas > Opciones > Resultados de la consulta > SQL Server >
       Resultados en cuadricula > "Maximo de caracteres recuperados" (datos que no
       son XML) = 2097152.
    2) Ejecutar. Clic derecho en la cuadricula > "Guardar resultados como..." (CSV).
    3) Adjuntar el CSV a la sesion.
  Si el archivo resulta muy grande: @IncluirWKT = 0.
  La seccion ZONA puede tardar: hace la misma interseccion geografica que el SP.
==============================================================================*/
USE [UNIGIS_DataRepository_YPF_ARENAS_QA]
GO
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @IdViaje     INT = 329958;
DECLARE @OffsetHoras INT = -3;     -- igual que el SP
DECLARE @IncluirWKT  BIT = 1;      -- 0 = no incluir el WKT de las geocercas
DECLARE @TamChunk    INT = 100;    -- eventos por fila de salida

IF OBJECT_ID('tempdb..#Salida') IS NOT NULL DROP TABLE #Salida;
IF OBJECT_ID('tempdb..#Zonas')  IS NOT NULL DROP TABLE #Zonas;
IF OBJECT_ID('tempdb..#Ev')     IS NOT NULL DROP TABLE #Ev;
IF OBJECT_ID('tempdb..#It')     IS NOT NULL DROP TABLE #It;

CREATE TABLE #Salida (Id INT IDENTITY(1,1) PRIMARY KEY, Seccion VARCHAR(40) NOT NULL, Parte INT NOT NULL, Dato NVARCHAR(MAX) NULL);

/*------------------------------------------------------------------------------
  Encabezado (mismas variables y reglas que el PASO 1 del SP)
------------------------------------------------------------------------------*/
DECLARE @IdVehiculo INT, @IdTransporte INT, @IdJornada INT, @IdEventoIni BIGINT, @IdEventoFin BIGINT,
        @FechaIni DATETIME, @FechaFin DATETIME, @Origen VARCHAR(150), @Destino VARCHAR(150);

SELECT @IdVehiculo   = V.IdVehiculo,
       @IdTransporte = Veh.IdTransporte,
       @IdJornada    = V.IdJornada,
       @IdEventoIni  = V.IdEventoActivacion,
       @IdEventoFin  = V.IdEventoFinalizacion,
       @Origen       = D.Descripcion
FROM       dbo.Viaje    V   WITH (NOLOCK)
INNER JOIN dbo.Vehiculo Veh WITH (NOLOCK) ON Veh.IdVehiculo = V.IdVehiculo
LEFT  JOIN dbo.Deposito D   WITH (NOLOCK) ON D.IdDeposito   = V.IdDepositoSalida
WHERE V.IdViaje = @IdViaje;

IF @IdVehiculo IS NULL
BEGIN
    RAISERROR('Viaje no encontrado (o sin vehiculo).', 16, 1);
    RETURN;
END;

SELECT TOP 1 @Destino = C.Descripcion
FROM dbo.Z_ClasificarParadasViaje(@IdViaje) C
WHERE C.ClaseParada = 'DESCARGA'
ORDER BY C.Orden DESC;

SELECT @FechaIni = FechaHoraEvento FROM dbo.Evento WITH (NOLOCK) WHERE IdEvento = @IdEventoIni;
SELECT @FechaFin = FechaHoraEvento FROM dbo.Evento WITH (NOLOCK) WHERE IdEvento = @IdEventoFin;
IF @FechaIni IS NULL
    SELECT @FechaIni = V.FechaCreacion FROM dbo.Viaje V WITH (NOLOCK) WHERE V.IdViaje = @IdViaje;
IF @FechaFin IS NULL
    SET @FechaFin = DATEADD(HOUR, 72, @FechaIni);

INSERT INTO #Salida (Seccion, Parte, Dato)
SELECT 'CONTEXTO', 1,
       (SELECT @IdViaje AS IdViaje, @IdVehiculo AS IdVehiculo, @IdTransporte AS IdTransporte, @IdJornada AS IdJornada,
               @IdEventoIni AS IdEventoActivacion, @IdEventoFin AS IdEventoFinalizacion,
               CONVERT(VARCHAR(19), @FechaIni, 120) AS FechaIni_UTC, CONVERT(VARCHAR(19), @FechaFin, 120) AS FechaFin_UTC,
               @Origen AS Origen, @Destino AS Destino, @OffsetHoras AS OffsetHoras,
               CONVERT(VARCHAR(19), GETDATE(), 120) AS Servidor_Ahora, CONVERT(VARCHAR(19), GETUTCDATE(), 120) AS Servidor_AhoraUTC,
               DB_NAME() AS BaseDatos,
               (SELECT d.compatibility_level FROM sys.databases d WHERE d.name = DB_NAME()) AS NivelCompatibilidad,
               @@VERSION AS Version
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

/*------------------------------------------------------------------------------
  Datos maestros del viaje
------------------------------------------------------------------------------*/
BEGIN TRY
    INSERT INTO #Salida (Seccion, Parte, Dato)
    SELECT 'VIAJE', 1, (SELECT X.* FROM dbo.Viaje X WITH (NOLOCK) WHERE X.IdViaje = @IdViaje FOR JSON PATH);
END TRY
BEGIN CATCH
    INSERT INTO #Salida (Seccion, Parte, Dato) VALUES ('ERROR_VIAJE', 1, ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    INSERT INTO #Salida (Seccion, Parte, Dato)
    SELECT 'VEHICULO', 1, (SELECT X.* FROM dbo.Vehiculo X WITH (NOLOCK) WHERE X.IdVehiculo = @IdVehiculo FOR JSON PATH);
END TRY
BEGIN CATCH
    INSERT INTO #Salida (Seccion, Parte, Dato) VALUES ('ERROR_VEHICULO', 1, ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    INSERT INTO #Salida (Seccion, Parte, Dato)
    SELECT 'TRANSPORTE', 1, (SELECT X.* FROM dbo.Transporte X WITH (NOLOCK) WHERE X.IdTransporte = @IdTransporte FOR JSON PATH);
END TRY
BEGIN CATCH
    INSERT INTO #Salida (Seccion, Parte, Dato) VALUES ('ERROR_TRANSPORTE', 1, ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    INSERT INTO #Salida (Seccion, Parte, Dato)
    SELECT 'JORNADA', 1, (SELECT X.* FROM dbo.Jornada X WITH (NOLOCK) WHERE X.IdJornada = @IdJornada FOR JSON PATH);
END TRY
BEGIN CATCH
    INSERT INTO #Salida (Seccion, Parte, Dato) VALUES ('ERROR_JORNADA', 1, ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    INSERT INTO #Salida (Seccion, Parte, Dato)
    SELECT 'ESTADO_VIAJE', 1,
           (SELECT X.* FROM dbo.EstadoViaje X WITH (NOLOCK)
            WHERE X.IdEstadoViaje = (SELECT V.IdEstadoViaje FROM dbo.Viaje V WITH (NOLOCK) WHERE V.IdViaje = @IdViaje)
            FOR JSON PATH);
END TRY
BEGIN CATCH
    INSERT INTO #Salida (Seccion, Parte, Dato) VALUES ('ERROR_ESTADO_VIAJE', 1, ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    INSERT INTO #Salida (Seccion, Parte, Dato)
    SELECT 'CATEGORIA_VIAJE', 1,
           (SELECT X.* FROM dbo.CategoriaViaje X WITH (NOLOCK)
            WHERE X.IdCategoriaViaje = (SELECT V.IdCategoriaViaje FROM dbo.Viaje V WITH (NOLOCK) WHERE V.IdViaje = @IdViaje)
            FOR JSON PATH);
END TRY
BEGIN CATCH
    INSERT INTO #Salida (Seccion, Parte, Dato) VALUES ('ERROR_CATEGORIA_VIAJE', 1, ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    INSERT INTO #Salida (Seccion, Parte, Dato)
    SELECT 'DEPOSITO_SALIDA', 1,
           (SELECT D.IdDeposito, D.IdDibujo, D.Descripcion
            FROM dbo.Deposito D WITH (NOLOCK)
            WHERE D.IdDeposito = (SELECT V.IdDepositoSalida FROM dbo.Viaje V WITH (NOLOCK) WHERE V.IdViaje = @IdViaje)
            FOR JSON PATH);
END TRY
BEGIN CATCH
    INSERT INTO #Salida (Seccion, Parte, Dato) VALUES ('ERROR_DEPOSITO_SALIDA', 1, ERROR_MESSAGE());
END CATCH;

/* Paradas clasificadas (la funcion que alimenta las geocercas del SP) */
BEGIN TRY
    INSERT INTO #Salida (Seccion, Parte, Dato)
    SELECT 'PARADAS', 1,
           (SELECT C.* FROM dbo.Z_ClasificarParadasViaje(@IdViaje) C ORDER BY C.Orden FOR JSON PATH);
END TRY
BEGIN CATCH
    INSERT INTO #Salida (Seccion, Parte, Dato) VALUES ('ERROR_PARADAS', 1, ERROR_MESSAGE());
    INSERT INTO #Salida (Seccion, Parte, Dato)
    SELECT 'PARADAS', 1,
           (SELECT C.IdDibujo, C.IdParada, C.Orden, C.Descripcion, C.ClaseParada
            FROM dbo.Z_ClasificarParadasViaje(@IdViaje) C ORDER BY C.Orden FOR JSON PATH);
END CATCH;

/*------------------------------------------------------------------------------
  PASO 2 del SP: geocercas (paradas del viaje + estaciones de servicio)
------------------------------------------------------------------------------*/
CREATE TABLE #Zonas
(
    IdDibujo     INT          NOT NULL,
    Nombre       VARCHAR(150) NULL,
    ClaseZona    VARCHAR(20)  NOT NULL,
    ClaseAlterna VARCHAR(20)  NULL,
    EsDual       BIT          NOT NULL DEFAULT (0),
    IdParada     INT          NULL,
    Orden        INT          NULL,
    Prioridad    INT          NOT NULL,
    Geografia    GEOGRAPHY    NULL,
    PRIMARY KEY CLUSTERED (IdDibujo)
);

;WITH Cl AS (
    SELECT
        C.IdDibujo,
        C.IdParada,
        C.Orden,
        C.Descripcion,
        CASE C.ClaseParada
            WHEN 'DEPOSITO_ORIGEN'  THEN 'CARGA'
            WHEN 'CARGA'            THEN 'CARGA'
            WHEN 'DESCARGA'         THEN 'DESCARGA'
            ELSE 'RETORNO'
        END                                                                AS Clase,
        ROW_NUMBER() OVER (PARTITION BY C.IdDibujo ORDER BY C.Orden)       AS RnAsc,
        ROW_NUMBER() OVER (PARTITION BY C.IdDibujo ORDER BY C.Orden DESC)  AS RnDesc
    FROM dbo.Z_ClasificarParadasViaje(@IdViaje) C
    WHERE C.IdDibujo IS NOT NULL
)
INSERT INTO #Zonas (IdDibujo, Nombre, ClaseZona, ClaseAlterna, EsDual, IdParada, Orden, Prioridad, Geografia)
SELECT
    A.IdDibujo,
    ISNULL(DB.Nombre, A.Descripcion),
    A.Clase,
    U.Clase,
    CASE WHEN A.Clase <> U.Clase THEN 1 ELSE 0 END,
    A.IdParada,
    A.Orden,
    10,
    DB.Geografia
FROM       Cl A
INNER JOIN Cl U ON U.IdDibujo = A.IdDibujo AND U.RnDesc = 1
INNER JOIN dbo.Dibujo DB WITH (NOLOCK) ON DB.IdDibujo = A.IdDibujo
WHERE A.RnAsc = 1
  AND DB.Geografia IS NOT NULL;

INSERT INTO #Zonas (IdDibujo, Nombre, ClaseZona, Prioridad, Geografia)
SELECT ES.IdDibujo, ES.Nombre, 'COMBUSTIBLE', 40, ES.Geografia
FROM (
        SELECT E2.IdDibujo, E2.Nombre, E2.Geografia,
               ROW_NUMBER() OVER (PARTITION BY E2.IdDibujo ORDER BY E2.Nombre) AS Rn
        FROM dbo.Z_EstacionesDeServicioYPF E2 WITH (NOLOCK)
        WHERE E2.Geografia IS NOT NULL
          AND ISNULL(E2.Eliminado, 0) = 0
     ) ES
WHERE ES.Rn = 1
  AND NOT EXISTS (SELECT 1 FROM #Zonas Z WHERE Z.IdDibujo = ES.IdDibujo);

/*------------------------------------------------------------------------------
  PASO 3 del SP: eventos GPS, descarte, secuencia, puntos y distancia
------------------------------------------------------------------------------*/
CREATE TABLE #Ev
(
    Secuencia       INT           NULL,
    IdEvento        BIGINT        NOT NULL,
    FechaHoraEvento DATETIME      NOT NULL,
    FechaHoraLocal  DATETIME      NULL,
    LatRaw          VARCHAR(50)   NULL,
    LonRaw          VARCHAR(50)   NULL,
    Lat             FLOAT         NULL,
    Lon             FLOAT         NULL,
    Velocidad       DECIMAL(10,2) NULL,
    Descartado      VARCHAR(20)   NULL,
    Punto           GEOGRAPHY     NULL,
    DistanciaKm     FLOAT         NULL,
    IdDibujoZona    INT           NULL,
    NombreZona      VARCHAR(150)  NULL,
    ClaseZona       VARCHAR(20)   NULL,
    Chunk           INT           NULL
);

INSERT INTO #Ev (IdEvento, FechaHoraEvento, FechaHoraLocal, LatRaw, LonRaw, Lat, Lon, Velocidad)
SELECT
    E.IdEvento,
    E.FechaHoraEvento,
    DATEADD(HOUR, @OffsetHoras, E.FechaHoraEvento),
    CAST(E.Latitud  AS VARCHAR(50)),
    CAST(E.Longitud AS VARCHAR(50)),
    TRY_CAST(REPLACE(REPLACE(ISNULL(CAST(E.Latitud  AS VARCHAR(50)), '0'), ',', '.'), ' ', '') AS FLOAT),
    TRY_CAST(REPLACE(REPLACE(ISNULL(CAST(E.Longitud AS VARCHAR(50)), '0'), ',', '.'), ' ', '') AS FLOAT),
    ISNULL(E.Velocidad, 0)
FROM dbo.Evento E WITH (NOLOCK)
WHERE E.IdVehiculo      = @IdVehiculo
  AND E.Valido          = 'True'
  AND E.FechaHoraEvento >= @FechaIni
  AND E.FechaHoraEvento <= @FechaFin
  AND (@IdEventoIni IS NULL OR E.IdEvento >= @IdEventoIni)
  AND (@IdEventoFin IS NULL OR E.IdEvento <= @IdEventoFin);

/* Mismas condiciones que el DELETE del SP, pero marcando en vez de borrar */
UPDATE #Ev
   SET Descartado = CASE
                        WHEN Lat IS NULL OR Lon IS NULL                              THEN 'LATLON_NULL'
                        WHEN Lat = 0 OR Lon = 0                                      THEN 'LATLON_CERO'
                        WHEN Lat NOT BETWEEN -90 AND 90 OR Lon NOT BETWEEN -180 AND 180 THEN 'FUERA_RANGO'
                    END;

;WITH R AS (
    SELECT IdEvento, ROW_NUMBER() OVER (ORDER BY FechaHoraEvento, IdEvento) AS N
    FROM #Ev WHERE Descartado IS NULL
)
UPDATE E SET E.Secuencia = R.N FROM #Ev E INNER JOIN R ON R.IdEvento = E.IdEvento;

UPDATE #Ev SET Punto = GEOGRAPHY::Point(Lat, Lon, 4326) WHERE Descartado IS NULL;

;WITH Pares AS (
    SELECT Secuencia, Lat, Lon,
           LAG(Lat) OVER (ORDER BY Secuencia) AS LatAnt,
           LAG(Lon) OVER (ORDER BY Secuencia) AS LonAnt
    FROM #Ev WHERE Descartado IS NULL
)
UPDATE E SET E.DistanciaKm =
    CASE WHEN P.LatAnt IS NOT NULL AND ABS(P.Lat - P.LatAnt) < 1.5 AND ABS(P.Lon - P.LonAnt) < 1.5
         THEN 2.0 * 6371.0 * ASIN(SQRT(POWER(SIN(RADIANS(P.Lat - P.LatAnt) / 2.0), 2)
              + COS(RADIANS(P.LatAnt)) * COS(RADIANS(P.Lat))
              * POWER(SIN(RADIANS(P.Lon - P.LonAnt) / 2.0), 2)))
         ELSE 0.0 END
FROM #Ev E INNER JOIN Pares P ON P.Secuencia = E.Secuencia;

/*------------------------------------------------------------------------------
  PASO 4 del SP: en que geocerca cae cada evento (la de menor Prioridad gana)
------------------------------------------------------------------------------*/
UPDATE E
   SET E.IdDibujoZona = Z.IdDibujo, E.NombreZona = Z.Nombre, E.ClaseZona = Z.ClaseZona
FROM #Ev E
CROSS APPLY (
    SELECT TOP 1 ZN.IdDibujo, ZN.Nombre, ZN.ClaseZona
    FROM #Zonas ZN
    WHERE ZN.Geografia.MakeValid().STIntersects(E.Punto) = 1
    ORDER BY ZN.Prioridad, ZN.IdDibujo
) Z
WHERE E.Descartado IS NULL;

UPDATE #Ev SET Chunk = CASE WHEN Descartado IS NULL THEN (Secuencia - 1) / @TamChunk ELSE -1 END;

/*------------------------------------------------------------------------------
  Salida de zonas: las paradas del viaje y las estaciones donde cayo algun evento
------------------------------------------------------------------------------*/
BEGIN TRY
    INSERT INTO #Salida (Seccion, Parte, Dato)
    SELECT 'ZONA',
           ROW_NUMBER() OVER (ORDER BY Z.Prioridad, Z.Orden, Z.IdDibujo),
           (SELECT Z.IdDibujo, Z.Nombre, Z.ClaseZona, Z.ClaseAlterna, Z.EsDual, Z.IdParada, Z.Orden, Z.Prioridad,
                   Z.Geografia.STNumPoints() AS NumPuntos,
                   (SELECT COUNT(*) FROM #Ev E WHERE E.IdDibujoZona = Z.IdDibujo) AS EventosAdentro,
                   CASE WHEN @IncluirWKT = 1 THEN Z.Geografia.STAsText() END AS WKT
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
    FROM #Zonas Z
    WHERE Z.Prioridad = 10
       OR EXISTS (SELECT 1 FROM #Ev E WHERE E.IdDibujoZona = Z.IdDibujo);
END TRY
BEGIN CATCH
    INSERT INTO #Salida (Seccion, Parte, Dato) VALUES ('ERROR_ZONA', 1, ERROR_MESSAGE());
END CATCH;

/*------------------------------------------------------------------------------
  Eventos: resumen de lo que hay en la ventana (con y sin Valido) y detalle
------------------------------------------------------------------------------*/
BEGIN TRY
    INSERT INTO #Salida (Seccion, Parte, Dato)
    SELECT 'EVENTOS_RESUMEN', 1,
           (SELECT COUNT(*) AS TotalVentana,
                   SUM(CASE WHEN E.Valido = 'True' THEN 1 ELSE 0 END) AS ValidosTrue,
                   MIN(E.IdEvento) AS MinIdEvento, MAX(E.IdEvento) AS MaxIdEvento,
                   CONVERT(VARCHAR(19), MIN(E.FechaHoraEvento), 120) AS PrimerEvento_UTC,
                   CONVERT(VARCHAR(19), MAX(E.FechaHoraEvento), 120) AS UltimoEvento_UTC
            FROM dbo.Evento E WITH (NOLOCK)
            WHERE E.IdVehiculo = @IdVehiculo
              AND E.FechaHoraEvento >= @FechaIni
              AND E.FechaHoraEvento <= @FechaFin
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

    INSERT INTO #Salida (Seccion, Parte, Dato)
    SELECT 'EVENTOS_RESUMEN', 2,
           (SELECT CAST(E.Valido AS VARCHAR(10)) AS Valido, COUNT(*) AS N
            FROM dbo.Evento E WITH (NOLOCK)
            WHERE E.IdVehiculo = @IdVehiculo
              AND E.FechaHoraEvento >= @FechaIni
              AND E.FechaHoraEvento <= @FechaFin
            GROUP BY CAST(E.Valido AS VARCHAR(10))
            FOR JSON PATH);
END TRY
BEGIN CATCH
    INSERT INTO #Salida (Seccion, Parte, Dato) VALUES ('ERROR_EVENTOS_RESUMEN', 1, ERROR_MESSAGE());
END CATCH;

/* Parte -1 = descartados; 0..n = eventos validos en orden (@TamChunk por fila) */
INSERT INTO #Salida (Seccion, Parte, Dato)
SELECT 'EVENTOS', G.Chunk,
       (SELECT E.Secuencia, E.IdEvento,
               CONVERT(VARCHAR(19), E.FechaHoraEvento, 120) AS UTC,
               CONVERT(VARCHAR(19), E.FechaHoraLocal, 120)  AS Local,
               E.LatRaw, E.LonRaw, E.Lat, E.Lon, E.Velocidad, E.Descartado,
               E.DistanciaKm, E.IdDibujoZona, E.NombreZona, E.ClaseZona
        FROM #Ev E
        WHERE E.Chunk = G.Chunk
        ORDER BY E.FechaHoraEvento, E.IdEvento
        FOR JSON PATH)
FROM (SELECT DISTINCT Chunk FROM #Ev) G;

/*------------------------------------------------------------------------------
  Km teoricos (el SP toma TOP 1 sin ORDER BY: aca van TODAS las coincidencias)
------------------------------------------------------------------------------*/
BEGIN TRY
    INSERT INTO #Salida (Seccion, Parte, Dato)
    SELECT 'KM_TEORICOS', 1,
           (SELECT TOP 100 K.*
            FROM dbo.Z_KmTeoricos K WITH (NOLOCK)
            WHERE LTRIM(RTRIM(K.Origen))  = LTRIM(RTRIM(ISNULL(@Origen, '')))
               OR LTRIM(RTRIM(K.Destino)) = LTRIM(RTRIM(ISNULL(@Destino, '')))
            ORDER BY CASE WHEN LTRIM(RTRIM(K.Origen))  = LTRIM(RTRIM(ISNULL(@Origen, ''))) 
                           AND LTRIM(RTRIM(K.Destino)) = LTRIM(RTRIM(ISNULL(@Destino, ''))) THEN 0 ELSE 1 END
            FOR JSON PATH);
END TRY
BEGIN CATCH
    INSERT INTO #Salida (Seccion, Parte, Dato) VALUES ('ERROR_KM_TEORICOS', 1, ERROR_MESSAGE());
END CATCH;

/*------------------------------------------------------------------------------
  Lo que dejo el SP en la tabla del reporte (todas las columnas, ordenado)
------------------------------------------------------------------------------*/
BEGIN TRY
    SELECT (ROW_NUMBER() OVER (ORDER BY I.Orden) - 1) / 8 AS Chunk, I.*
    INTO #It
    FROM dbo.Z_ItinerarioViaje I WITH (NOLOCK)
    WHERE I.IdViaje = @IdViaje;

    INSERT INTO #Salida (Seccion, Parte, Dato)
    SELECT 'Z_ITINERARIO', G.Chunk,
           (SELECT T.* FROM #It T WHERE T.Chunk = G.Chunk ORDER BY T.Orden FOR JSON PATH)
    FROM (SELECT DISTINCT Chunk FROM #It) G;
END TRY
BEGIN CATCH
    INSERT INTO #Salida (Seccion, Parte, Dato) VALUES ('ERROR_Z_ITINERARIO', 1, ERROR_MESSAGE());
END CATCH;

/*------------------------------------------------------------------------------
  Log de la ultima ejecucion del SP para este viaje
------------------------------------------------------------------------------*/
BEGIN TRY
    DECLARE @IniLog DATETIME;
    SELECT @IniLog = MAX(L.FechaHora)
    FROM dbo.[Log] L WITH (NOLOCK)
    WHERE L.Categoria = 'INICIO'
      AND L.Descripcion LIKE '%IdViaje: ' + CAST(@IdViaje AS VARCHAR(10));

    INSERT INTO #Salida (Seccion, Parte, Dato)
    SELECT 'LOG', 1,
           (SELECT L.Categoria, L.Descripcion, CONVERT(VARCHAR(23), L.FechaHora, 121) AS FechaHora
            FROM dbo.[Log] L WITH (NOLOCK)
            WHERE @IniLog IS NOT NULL
              AND L.FechaHora >= @IniLog
              AND L.FechaHora <= DATEADD(MINUTE, 30, @IniLog)
              AND L.Categoria IN ('INICIO', 'PASO2', 'PASO7', 'PASO7E', 'FIN', 'ERROR')
            ORDER BY L.FechaHora
            FOR JSON PATH);
END TRY
BEGIN CATCH
    INSERT INTO #Salida (Seccion, Parte, Dato) VALUES ('ERROR_LOG', 1, ERROR_MESSAGE());
END CATCH;

/*------------------------------------------------------------------------------
  Rangos de cambio de turno del transportista (si el DDL ya se ejecuto)
------------------------------------------------------------------------------*/
IF OBJECT_ID('dbo.Z_CambioTurnoTransporte', 'U') IS NOT NULL
BEGIN
    BEGIN TRY
        INSERT INTO #Salida (Seccion, Parte, Dato)
        SELECT 'TURNO', 1,
               (SELECT T.* FROM dbo.Z_CambioTurnoTransporte T WITH (NOLOCK)
                WHERE T.IdTransporte = @IdTransporte FOR JSON PATH);
    END TRY
    BEGIN CATCH
        INSERT INTO #Salida (Seccion, Parte, Dato) VALUES ('ERROR_TURNO', 1, ERROR_MESSAGE());
    END CATCH;
END;

/*------------------------------------------------------------------------------
  Que codigo esta realmente desplegado (SP y funcion), con fecha de modificacion
  Los saltos de linea se reemplazan por ~~NL~~ para que sobrevivan al CSV.
------------------------------------------------------------------------------*/
BEGIN TRY
    INSERT INTO #Salida (Seccion, Parte, Dato)
    SELECT 'OBJETOS', 1,
           (SELECT O.name AS Objeto, O.type_desc AS Tipo,
                   CONVERT(VARCHAR(19), O.create_date, 120) AS Creado,
                   CONVERT(VARCHAR(19), O.modify_date, 120) AS Modificado
            FROM sys.objects O
            WHERE O.name IN ('Z_SP_ItinerarioViaje', 'Z_ClasificarParadasViaje', 'Z_ItinerarioViaje',
                             'Z_KmTeoricos', 'Z_CambioTurnoTransporte', 'Z_MinutosAHHMM', 'Z_EstacionesDeServicioYPF')
            FOR JSON PATH);

    DECLARE @Def NVARCHAR(MAX), @Pos INT, @N INT;

    SET @Def = REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.Z_SP_ItinerarioViaje')), CHAR(13), ''), CHAR(10), '~~NL~~');
    SET @Pos = 1; SET @N = 1;
    WHILE @Pos <= ISNULL(LEN(@Def), 0)
    BEGIN
        INSERT INTO #Salida (Seccion, Parte, Dato) VALUES ('DEF_Z_SP_ItinerarioViaje', @N, SUBSTRING(@Def, @Pos, 4000));
        SET @Pos = @Pos + 4000; SET @N = @N + 1;
    END;

    SET @Def = REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.Z_ClasificarParadasViaje')), CHAR(13), ''), CHAR(10), '~~NL~~');
    SET @Pos = 1; SET @N = 1;
    WHILE @Pos <= ISNULL(LEN(@Def), 0)
    BEGIN
        INSERT INTO #Salida (Seccion, Parte, Dato) VALUES ('DEF_Z_ClasificarParadasViaje', @N, SUBSTRING(@Def, @Pos, 4000));
        SET @Pos = @Pos + 4000; SET @N = @N + 1;
    END;
END TRY
BEGIN CATCH
    INSERT INTO #Salida (Seccion, Parte, Dato) VALUES ('ERROR_OBJETOS', 1, ERROR_MESSAGE());
END CATCH;

/*------------------------------------------------------------------------------
  Esquema de las tablas involucradas y tablas relacionadas con viajes / novedades
------------------------------------------------------------------------------*/
BEGIN TRY
    INSERT INTO #Salida (Seccion, Parte, Dato)
    SELECT 'ESQUEMA', ROW_NUMBER() OVER (ORDER BY T.name),
           (SELECT T.name AS Tabla, C.column_id AS Id, C.name AS Columna, TY.name AS Tipo,
                   C.max_length AS Largo, C.is_nullable AS Nulo
            FROM sys.columns C
            INNER JOIN sys.types TY ON TY.user_type_id = C.user_type_id
            WHERE C.object_id = T.object_id
            ORDER BY C.column_id
            FOR JSON PATH)
    FROM sys.tables T
    WHERE T.name IN ('Viaje', 'Evento', 'Vehiculo', 'Transporte', 'Jornada', 'Deposito', 'Dibujo',
                     'EstadoViaje', 'CategoriaViaje', 'Z_ItinerarioViaje', 'Z_KmTeoricos',
                     'Z_EstacionesDeServicioYPF', 'Z_CambioTurnoTransporte', 'Log');

    INSERT INTO #Salida (Seccion, Parte, Dato)
    SELECT 'TABLAS', 1,
           (SELECT T.name AS Tabla
            FROM sys.tables T
            WHERE T.name LIKE '%Viaje%' OR T.name LIKE '%Novedad%' OR T.name LIKE '%Estado%'
               OR T.name LIKE '%Hito%'  OR T.name LIKE '%Tolerancia%' OR T.name LIKE 'Z[_]%'
            ORDER BY T.name
            FOR JSON PATH);
END TRY
BEGIN CATCH
    INSERT INTO #Salida (Seccion, Parte, Dato) VALUES ('ERROR_ESQUEMA', 1, ERROR_MESSAGE());
END CATCH;

/*------------------------------------------------------------------------------
  Conteos de control
------------------------------------------------------------------------------*/
INSERT INTO #Salida (Seccion, Parte, Dato)
SELECT 'RESUMEN', 1,
       (SELECT (SELECT COUNT(*) FROM #Ev)                                   AS EventosEnVentana,
               (SELECT COUNT(*) FROM #Ev WHERE Descartado IS NULL)          AS EventosUsables,
               (SELECT COUNT(*) FROM #Ev WHERE Descartado IS NOT NULL)      AS EventosDescartados,
               (SELECT COUNT(*) FROM #Ev WHERE IdDibujoZona IS NOT NULL)    AS EventosEnGeocerca,
               (SELECT COUNT(*) FROM #Zonas WHERE Prioridad = 10)           AS ZonasParadas,
               (SELECT COUNT(*) FROM #Zonas WHERE Prioridad = 40)           AS ZonasEstacionesTotal,
               (SELECT COUNT(DISTINCT IdDibujoZona) FROM #Ev WHERE ClaseZona = 'COMBUSTIBLE') AS EstacionesConEventos,
               (SELECT ISNULL(SUM(DistanciaKm), 0) FROM #Ev)                AS KmGPS_Recalculado
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

/*------------------------------------------------------------------------------
  Resultado unico
------------------------------------------------------------------------------*/
SELECT Seccion, Parte, Dato FROM #Salida ORDER BY Id;
