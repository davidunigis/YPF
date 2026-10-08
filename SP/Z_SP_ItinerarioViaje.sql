USE [UNIGIS_DataRepository_YPF_ARENAS_QA]
GO
/****** Object:  StoredProcedure [dbo].[Z_SP_ItinerarioViaje]    Script Date: 10/8/2026 6:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[Z_SP_ItinerarioViaje]
(
    @IdViaje                INT,
    @VelocidadDetenido      DECIMAL(6,2) = 0,   -- "velocidad = 0" del requerimiento
    @MinutosDetenido        INT          = 5,   -- mas de 5 min detenido = novedad
    @MinutosCombustible     INT          = 30,  -- excepcion en estacion de servicio
    @MinutosTolerancia      INT          = 45,  -- tolerancia en carga y descarga
    @MinutosMinPermanencia  INT          = 2,   -- minimo en geocerca para contar visita
    @OffsetHoras            INT          = -3,
    @Debug                  BIT          = 0
)
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('tempdb..#Zonas')   IS NOT NULL DROP TABLE #Zonas;
    IF OBJECT_ID('tempdb..#Eventos') IS NOT NULL DROP TABLE #Eventos;
    IF OBJECT_ID('tempdb..#Tramos')  IS NOT NULL DROP TABLE #Tramos;

    INSERT INTO dbo.[Log] (Categoria, Descripcion, FechaHora)
    VALUES ('INICIO', 'Z_SP_ItinerarioViaje | IdViaje: ' + CAST(@IdViaje AS VARCHAR(10)), GETDATE());

    /*==========================================================================
      PASO 1 - Encabezado
    ==========================================================================*/
    DECLARE @IdVehiculo INT, @Dominio VARCHAR(50), @FechaViaje DATE,
            @DescripcionViaje VARCHAR(250), @IdDibujoOrigen INT, @Origen VARCHAR(150),
            @IdDibujoDestino INT, @Destino VARCHAR(150),
            @IdEventoIni BIGINT, @IdEventoFin BIGINT,
            @FechaIni DATETIME, @FechaFin DATETIME,
            @KmTeoricos INT, @TiempoEstandar DECIMAL(10,2), @CicloKmTeoricos INT,
            @KmViaje DECIMAL(12,2), @MinutosViaje INT,
            @FinUltimaOperacion DATETIME;

    SELECT
        @IdVehiculo       = V.IdVehiculo,
        @Dominio          = Veh.Dominio,
        @FechaViaje       = CAST(DATEADD(HOUR, @OffsetHoras, V.FechaCreacion) AS DATE),
        @DescripcionViaje = V.Descripcion,
        @IdDibujoOrigen   = D.IdDibujo,
        @Origen           = D.Descripcion,
        @IdEventoIni      = V.IdEventoActivacion,
        @IdEventoFin      = V.IdEventoFinalizacion
    FROM       dbo.Viaje    V   WITH (NOLOCK)
    INNER JOIN dbo.Vehiculo Veh WITH (NOLOCK) ON Veh.IdVehiculo = V.IdVehiculo
    LEFT  JOIN dbo.Deposito D   WITH (NOLOCK) ON D.IdDeposito   = V.IdDepositoSalida
    WHERE V.IdViaje = @IdViaje;

    IF @IdVehiculo IS NULL
    BEGIN
        INSERT INTO dbo.[Log] (Categoria, Descripcion, FechaHora)
        VALUES ('ERROR', 'Viaje ' + CAST(@IdViaje AS VARCHAR(10)) + ' no encontrado.', GETDATE());
        RETURN;
    END;

    SELECT TOP 1 @IdDibujoDestino = C.IdDibujo, @Destino = C.Descripcion
    FROM dbo.Z_ClasificarParadasViaje(@IdViaje) C
    WHERE C.ClaseParada = 'DESCARGA'
    ORDER BY C.Orden DESC;

    SELECT @FechaIni = FechaHoraEvento FROM dbo.Evento WITH (NOLOCK) WHERE IdEvento = @IdEventoIni;
    SELECT @FechaFin = FechaHoraEvento FROM dbo.Evento WITH (NOLOCK) WHERE IdEvento = @IdEventoFin;

    IF @FechaIni IS NULL
        SELECT @FechaIni = V.FechaCreacion FROM dbo.Viaje V WITH (NOLOCK) WHERE V.IdViaje = @IdViaje;
    IF @FechaFin IS NULL
        SET @FechaFin = DATEADD(HOUR, 72, @FechaIni);

    SELECT TOP 1
        @KmTeoricos = K.DistanciaKmTeoricos, @TiempoEstandar = K.TiempoEstandar,
        @CicloKmTeoricos = K.CicloKmTeoricos
    FROM dbo.Z_KmTeoricos K WITH (NOLOCK)
    WHERE LTRIM(RTRIM(K.Origen))  = LTRIM(RTRIM(ISNULL(@Origen, '')))
      AND LTRIM(RTRIM(K.Destino)) = LTRIM(RTRIM(ISNULL(@Destino, '')));


    /*==========================================================================
      PASO 2 - Geocercas: paradas clasificadas + estaciones de servicio
    ==========================================================================*/
    CREATE TABLE #Zonas
    (
        IdDibujo    INT           NOT NULL,
        Nombre      VARCHAR(150)  NULL,
        ClaseZona    VARCHAR(20)  NOT NULL,   -- CARGA | DESCARGA | RETORNO | COMBUSTIBLE
        ClaseAlterna VARCHAR(20)  NULL,       -- rol en la ultima visita, si difiere
        EsDual       BIT          NOT NULL DEFAULT (0),
        IdParada    INT           NULL,
        Orden       INT           NULL,
        Prioridad   INT           NOT NULL,
        Geografia   GEOGRAPHY     NULL,
        PRIMARY KEY CLUSTERED (IdDibujo)
    );

    /* Paradas del viaje.
       El deposito figura DOS VECES en el mismo viaje (salida y retorno) y ambas
       paradas comparten el mismo IdDibujo: una sola geocerca con dos roles.
       Por eso se inserta UNA fila por dibujo, guardando el rol de la primera
       parada en ClaseZona y el de la ultima en ClaseAlterna. Cual aplica se
       resuelve por tiempo en el PASO 7, no por identidad de zona. */
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

    /* Estaciones de servicio YPF */
    /* Una fila por dibujo: la tabla puede traer el mismo IdDibujo repetido */
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

    INSERT INTO dbo.[Log] (Categoria, Descripcion, FechaHora)
    VALUES ('PASO2', 'Geocercas | Carga: ' + CAST((SELECT COUNT(*) FROM #Zonas WHERE ClaseZona='CARGA') AS VARCHAR(10)) +
            ' | Descarga: ' + CAST((SELECT COUNT(*) FROM #Zonas WHERE ClaseZona='DESCARGA') AS VARCHAR(10)) +
            ' | Retorno: '  + CAST((SELECT COUNT(*) FROM #Zonas WHERE ClaseZona='RETORNO') AS VARCHAR(10)) +
            ' | EESS: '     + CAST((SELECT COUNT(*) FROM #Zonas WHERE ClaseZona='COMBUSTIBLE') AS VARCHAR(10)), GETDATE());


    /*==========================================================================
      PASO 3 - Eventos GPS y distancia
    ==========================================================================*/
    CREATE TABLE #Eventos
    (
        Secuencia       INT           NOT NULL,
        IdEvento        BIGINT        NOT NULL,
        FechaHoraEvento DATETIME      NOT NULL,
        FechaLocal      DATE          NULL,
        Lat             FLOAT         NULL,
        Lon             FLOAT         NULL,
        Velocidad       DECIMAL(10,2) NULL,
        Punto           GEOGRAPHY     NULL,
        DistanciaKm     FLOAT         NULL,
        IdDibujoZona    INT           NULL,
        NombreZona      VARCHAR(150)  NULL,
        ClaseZona       VARCHAR(20)   NULL,
        IdParada        INT           NULL,
        Novedad         VARCHAR(30)   NULL,
        Grupo           INT           NULL,
        PRIMARY KEY CLUSTERED (Secuencia)
    );

    INSERT INTO #Eventos (Secuencia, IdEvento, FechaHoraEvento, FechaLocal, Lat, Lon, Velocidad)
    SELECT
        ROW_NUMBER() OVER (ORDER BY E.FechaHoraEvento, E.IdEvento),
        E.IdEvento,
        E.FechaHoraEvento,
        CAST(DATEADD(HOUR, @OffsetHoras, E.FechaHoraEvento) AS DATE),
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

    DELETE FROM #Eventos
    WHERE Lat IS NULL OR Lon IS NULL OR Lat = 0 OR Lon = 0
       OR Lat NOT BETWEEN -90 AND 90 OR Lon NOT BETWEEN -180 AND 180;

    IF NOT EXISTS (SELECT 1 FROM #Eventos)
    BEGIN
        INSERT INTO dbo.[Log] (Categoria, Descripcion, FechaHora)
        VALUES ('ERROR', 'Viaje ' + CAST(@IdViaje AS VARCHAR(10)) + ' sin eventos GPS validos.', GETDATE());
        RETURN;
    END;

    ;WITH Renum AS (SELECT Secuencia, ROW_NUMBER() OVER (ORDER BY FechaHoraEvento, IdEvento) AS N FROM #Eventos)
    UPDATE E SET E.Secuencia = R.N FROM #Eventos E INNER JOIN Renum R ON R.Secuencia = E.Secuencia;

    UPDATE #Eventos SET Punto = GEOGRAPHY::Point(Lat, Lon, 4326);

    ;WITH Pares AS (
        SELECT Secuencia, Lat, Lon,
               LAG(Lat) OVER (ORDER BY Secuencia) AS LatAnt,
               LAG(Lon) OVER (ORDER BY Secuencia) AS LonAnt
        FROM #Eventos
    )
    UPDATE E SET E.DistanciaKm =
        CASE WHEN P.LatAnt IS NOT NULL AND ABS(P.Lat - P.LatAnt) < 1.5 AND ABS(P.Lon - P.LonAnt) < 1.5
             THEN 2.0 * 6371.0 * ASIN(SQRT(POWER(SIN(RADIANS(P.Lat - P.LatAnt) / 2.0), 2)
                  + COS(RADIANS(P.LatAnt)) * COS(RADIANS(P.Lat))
                  * POWER(SIN(RADIANS(P.Lon - P.LonAnt) / 2.0), 2)))
             ELSE 0.0 END
    FROM #Eventos E INNER JOIN Pares P ON P.Secuencia = E.Secuencia;

    SELECT @KmViaje = CAST(SUM(DistanciaKm) AS DECIMAL(12,2)),
           @MinutosViaje = DATEDIFF(MINUTE, MIN(FechaHoraEvento), MAX(FechaHoraEvento))
    FROM #Eventos;


    /*==========================================================================
      PASO 4 - Invasion de geocercas
    ==========================================================================*/
    UPDATE E
        SET E.IdDibujoZona = Z.IdDibujo, E.NombreZona = Z.Nombre,
            E.ClaseZona = Z.ClaseZona, E.IdParada = Z.IdParada
    FROM #Eventos E
    CROSS APPLY (
        SELECT TOP 1 ZN.IdDibujo, ZN.Nombre, ZN.ClaseZona, ZN.IdParada
        FROM #Zonas ZN
        WHERE ZN.Geografia.MakeValid().STIntersects(E.Punto) = 1
        ORDER BY ZN.Prioridad, ZN.IdDibujo
    ) Z;


    /*==========================================================================
      PASO 5 - Novedad preliminar por evento
      La geocerca manda sobre la velocidad: estar quieto dentro del deposito es
      CARGA, no DETENIDO.
    ==========================================================================*/
    UPDATE #Eventos
        SET Novedad =
            CASE
                WHEN ClaseZona = 'CARGA'       THEN 'CARGA'
                WHEN ClaseZona = 'DESCARGA'    THEN 'DESCARGA'
                WHEN ClaseZona = 'RETORNO'     THEN 'RETORNO'
                WHEN ClaseZona = 'COMBUSTIBLE' THEN 'COMBUSTIBLE'
                WHEN Velocidad <= @VelocidadDetenido THEN 'DETENIDO'
                ELSE 'CARRETEANDO'
            END;


    /*==========================================================================
      PASO 6 - Agrupacion de eventos consecutivos
    ==========================================================================*/
    ;WITH Islas AS (
        SELECT Secuencia,
               ROW_NUMBER() OVER (ORDER BY Secuencia)
             - ROW_NUMBER() OVER (PARTITION BY Novedad, ISNULL(IdDibujoZona, -1) ORDER BY Secuencia) AS G
        FROM #Eventos
    )
    UPDATE E SET E.Grupo = I.G FROM #Eventos E INNER JOIN Islas I ON I.Secuencia = E.Secuencia;

    SELECT
        ROW_NUMBER() OVER (ORDER BY MIN(E.Secuencia))   AS Orden,
        E.Novedad,
        E.ClaseZona,
        E.IdDibujoZona,
        E.NombreZona,
        E.IdParada,
        MIN(E.Secuencia)                                AS SecIni,
        MIN(E.FechaHoraEvento)                          AS FechaDesde,
        MAX(E.FechaHoraEvento)                          AS FechaHastaRaw,
        CAST(NULL AS DATETIME)                          AS FechaHasta,
        MIN(E.FechaLocal)                               AS FechaLocal,
        MIN(E.Lat)                                      AS Lat,
        MIN(E.Lon)                                      AS Lon,
        COUNT(*)                                        AS Eventos,
        CAST(SUM(E.DistanciaKm) AS DECIMAL(12,2))       AS Kms,
        CAST(AVG(E.Velocidad)   AS DECIMAL(10,2))       AS VelProm,
        CAST(MAX(E.Velocidad)   AS DECIMAL(10,2))       AS VelMax,
        CAST(0 AS BIT)                                  AS AplicoExcepcion,
        CAST(NULL AS INT)                               AS Minutos
    INTO #Tramos
    FROM #Eventos E
    GROUP BY E.Grupo, E.Novedad, E.ClaseZona, E.IdDibujoZona, E.NombreZona, E.IdParada;

    /* El fin de cada tramo es el inicio del siguiente: linea de tiempo continua */
    ;WITH Sig AS (SELECT Orden, LEAD(FechaDesde) OVER (ORDER BY Orden) AS Sigue FROM #Tramos)
    UPDATE T SET T.FechaHasta = ISNULL(S.Sigue, T.FechaHastaRaw)
    FROM #Tramos T INNER JOIN Sig S ON S.Orden = T.Orden;

    UPDATE #Tramos SET Minutos = DATEDIFF(MINUTE, FechaDesde, FechaHasta);

    /* Pasos fugaces por una geocerca: el vehiculo cruzo sin operar */
    UPDATE #Tramos
        SET Novedad   = CASE WHEN VelProm > @VelocidadDetenido THEN 'CARRETEANDO' ELSE 'DETENIDO' END,
            ClaseZona = NULL
    WHERE Novedad IN ('CARGA','DESCARGA','RETORNO')
      AND Minutos < @MinutosMinPermanencia;


    /*==========================================================================
      PASO 7 - Reglas de duracion
    ==========================================================================*/

    /* 7.a  EXCEPCION COMBUSTIBLE
            La primera detencion en estacion de servicio de cada dia tolera
            @MinutosCombustible. Si los supera, es DETENIDO. Las siguientes del
            mismo dia se evaluan con la regla general. */
    ;WITH Comb AS (
        SELECT Orden, Minutos,
               ROW_NUMBER() OVER (PARTITION BY FechaLocal ORDER BY FechaDesde) AS NroDelDia
        FROM #Tramos
        WHERE Novedad = 'COMBUSTIBLE'
    )
    UPDATE T
        SET T.Novedad = CASE
                            WHEN C.NroDelDia = 1 AND C.Minutos <= @MinutosCombustible THEN 'COMBUSTIBLE'
                            WHEN C.NroDelDia = 1                                      THEN 'DETENIDO'
                            WHEN C.Minutos    >  @MinutosDetenido                     THEN 'DETENIDO'
                            ELSE 'COMBUSTIBLE'
                        END,
            T.AplicoExcepcion = CASE WHEN C.NroDelDia = 1 THEN 1 ELSE 0 END
    FROM #Tramos T INNER JOIN Comb C ON C.Orden = T.Orden;

    /* 7.b  Detenciones cortas fuera de geocerca: no son novedad, son el viaje */
    UPDATE #Tramos
        SET Novedad = 'CARRETEANDO'
    WHERE Novedad   = 'DETENIDO'
      AND ClaseZona IS NULL
      AND Minutos  <= @MinutosDetenido;

    /* 7.c  GEOCERCA COMPARTIDA (deposito de salida y de retorno)
            Una sola zona cumple dos roles segun el momento del viaje. La primera
            visita es la operacion; las siguientes toman el rol alterno. Resolver
            esto por tiempo evita que el regreso al deposito se contabilice como
            una segunda carga. */
    ;WITH Visitas AS (
        SELECT T.Orden,
               ROW_NUMBER() OVER (PARTITION BY T.IdDibujoZona ORDER BY T.FechaDesde) AS NroVisita
        FROM       #Tramos T
        INNER JOIN #Zonas  Z ON Z.IdDibujo = T.IdDibujoZona AND Z.EsDual = 1
        WHERE T.Novedad IN ('CARGA', 'DESCARGA', 'RETORNO')
    )
    UPDATE T
        SET T.Novedad = Z.ClaseAlterna
    FROM       #Tramos T
    INNER JOIN Visitas V ON V.Orden    = T.Orden AND V.NroVisita > 1
    INNER JOIN #Zonas  Z ON Z.IdDibujo = T.IdDibujoZona;

    /* 7.d  ESPERA SIN TAREA
            Sin parada pendiente por delante, lo que el vehiculo haga detenido ya
            no es una detencion en ruta: es espera sin tarea asignada. */
    SELECT @FinUltimaOperacion = MAX(FechaHasta)
    FROM #Tramos
    WHERE Novedad IN ('CARGA', 'DESCARGA');

    UPDATE #Tramos
        SET Novedad = 'ESPERA_SIN_TAREA'
    WHERE @FinUltimaOperacion IS NOT NULL
      AND FechaDesde >= @FinUltimaOperacion
      AND Novedad IN ('DETENIDO', 'RETORNO');

    /* Reagrupa tramos contiguos que quedaron con la misma novedad tras las reglas */
    ;WITH Fusion AS (
        SELECT Orden, Novedad, ISNULL(IdDibujoZona, -1) AS Z,
               ROW_NUMBER() OVER (ORDER BY Orden)
             - ROW_NUMBER() OVER (PARTITION BY Novedad, ISNULL(IdDibujoZona, -1) ORDER BY Orden) AS G
        FROM #Tramos
    ),
    Consol AS (
        SELECT F.Novedad, F.Z, F.G,
               MIN(T.Orden)       AS OrdenBase,
               MIN(T.FechaDesde)  AS Desde,
               MAX(T.FechaHasta)  AS Hasta,
               SUM(T.Kms)         AS Kms,
               SUM(T.Eventos)     AS Eventos,
               MAX(T.VelMax)      AS VelMax,
               MAX(CAST(T.AplicoExcepcion AS INT)) AS Exc
        FROM Fusion F INNER JOIN #Tramos T ON T.Orden = F.Orden
        GROUP BY F.Novedad, F.Z, F.G
    )
    UPDATE T
        SET T.FechaHasta      = C.Hasta,
            T.Kms             = C.Kms,
            T.Eventos         = C.Eventos,
            T.VelMax          = C.VelMax,
            T.AplicoExcepcion = CAST(C.Exc AS BIT),
            T.Minutos         = DATEDIFF(MINUTE, C.Desde, C.Hasta)
    FROM #Tramos T INNER JOIN Consol C ON C.OrdenBase = T.Orden;

    DELETE T
    FROM #Tramos T
    WHERE EXISTS (
        SELECT 1 FROM #Tramos T2
        WHERE T2.Orden < T.Orden
          AND T2.Novedad = T.Novedad
          AND ISNULL(T2.IdDibujoZona, -1) = ISNULL(T.IdDibujoZona, -1)
          AND T2.FechaHasta >= T.FechaHasta
    );

    INSERT INTO dbo.[Log] (Categoria, Descripcion, FechaHora)
    VALUES ('PASO7', 'Novedades | Carga: ' + CAST((SELECT COUNT(*) FROM #Tramos WHERE Novedad='CARGA') AS VARCHAR(5)) +
            ' | Descarga: '    + CAST((SELECT COUNT(*) FROM #Tramos WHERE Novedad='DESCARGA') AS VARCHAR(5)) +
            ' | Carreteando: ' + CAST((SELECT COUNT(*) FROM #Tramos WHERE Novedad='CARRETEANDO') AS VARCHAR(5)) +
            ' | Detenido: '    + CAST((SELECT COUNT(*) FROM #Tramos WHERE Novedad='DETENIDO') AS VARCHAR(5)) +
            ' | Combustible: ' + CAST((SELECT COUNT(*) FROM #Tramos WHERE Novedad='COMBUSTIBLE') AS VARCHAR(5)) +
            ' | Espera s/tarea: ' + CAST((SELECT COUNT(*) FROM #Tramos WHERE Novedad='ESPERA_SIN_TAREA') AS VARCHAR(5)), GETDATE());

    IF @Debug = 1
    BEGIN
        SELECT 'ZONAS'   AS T, IdDibujo, Nombre, ClaseZona, IdParada, Orden FROM #Zonas ORDER BY Prioridad, Orden;
        SELECT 'TRAMOS'  AS T, * FROM #Tramos ORDER BY Orden;
        SELECT 'EVENTOS' AS T, * FROM #Eventos ORDER BY Secuencia;
    END;


    /*==========================================================================
      PASO 8 - Carga del reporte
    ==========================================================================*/
    DELETE FROM dbo.Z_ItinerarioViaje WHERE IdViaje = @IdViaje;

    ;WITH Oper AS (
        /* Tolerancia: minutos totales por operacion en cada parada */
        SELECT IdDibujoZona, SUM(Minutos) AS MinutosOperacion
        FROM #Tramos
        WHERE Novedad IN ('CARGA','DESCARGA')
        GROUP BY IdDibujoZona
    ),
    Fmt AS (
        SELECT
            T.*,
            OP.MinutosOperacion,
            DATEADD(HOUR, @OffsetHoras, T.FechaDesde) AS DesdeLocal,
            DATEADD(HOUR, @OffsetHoras, T.FechaHasta) AS HastaLocal,
            SUM(T.Kms) OVER (ORDER BY T.Orden ROWS UNBOUNDED PRECEDING) AS KmAcum,
            CASE WHEN T.Minutos / 60 < 10 THEN '0' ELSE '' END
              + CAST(T.Minutos / 60 AS VARCHAR(10)) + ':'
              + RIGHT('0' + CAST(T.Minutos % 60 AS VARCHAR(2)), 2) AS Duracion,
            ROW_NUMBER() OVER (PARTITION BY T.Novedad ORDER BY T.Orden) AS NroTipo,
            COUNT(*)    OVER (PARTITION BY T.Novedad)                   AS TotalTipo
        FROM #Tramos T
        LEFT JOIN Oper OP ON OP.IdDibujoZona = T.IdDibujoZona
    )
    INSERT INTO dbo.Z_ItinerarioViaje
    (
        IdViaje, DescripcionViaje, IdVehiculo, Dominio, FechaViaje,
        IdDibujoOrigen, Origen, IdDibujoDestino, Destino,
        KmTeoricos, TiempoEstandar, CicloKmTeoricos, KmRecorridos, DesvioKm,
        Orden, DiaViaje, TipoSuceso, Suceso, Novedad, ClaseZona, Ubicacion,
        IdDibujo, IdParada, EstacionServicio,
        Periodo, FechaHoraDesde, FechaHoraHasta, FechaDesdeUTC, FechaHastaUTC,
        Duracion, TiempoMinutos, PorcentajeTiempo,
        Kms, KmAcumulado, VelocidadPromedio, VelocidadMaxima,
        MinutosOperacion, ExcedeTolerancia, AplicoExcepcionCombustible,
        Detalle, Observacion,
        CantidadEventos, Latitud, Longitud, FechaProcesamiento
    )
    SELECT
        @IdViaje, @DescripcionViaje, @IdVehiculo, @Dominio, @FechaViaje,
        @IdDibujoOrigen, @Origen, @IdDibujoDestino, @Destino,
        @KmTeoricos, @TiempoEstandar, @CicloKmTeoricos, @KmViaje,
        CASE WHEN @KmTeoricos IS NULL THEN NULL ELSE @KmViaje - @KmTeoricos END,

        ROW_NUMBER() OVER (ORDER BY F.FechaDesde),
        DATEDIFF(DAY, CAST(DATEADD(HOUR, @OffsetHoras, @FechaIni) AS DATE), CAST(F.DesdeLocal AS DATE)) + 1,
        F.Novedad,

        CASE F.Novedad
            WHEN 'CARGA'            THEN 'Carga'
            WHEN 'DESCARGA'         THEN 'Descarga'
            WHEN 'CARRETEANDO'      THEN 'Carreteando'
            WHEN 'DETENIDO'         THEN 'Detenido' + CASE WHEN F.TotalTipo > 1 THEN ' #' + CAST(F.NroTipo AS VARCHAR(5)) ELSE '' END
            WHEN 'COMBUSTIBLE'      THEN 'Carga de combustible'
            WHEN 'ESPERA_SIN_TAREA' THEN 'Espera sin tarea'
            WHEN 'RETORNO'          THEN 'En deposito de retorno'
            ELSE 'Sin clasificar'
        END,
        F.Novedad,
        F.ClaseZona,
        ISNULL(F.NombreZona, '-'),
        F.IdDibujoZona,
        F.IdParada,
        CASE WHEN F.Novedad = 'COMBUSTIBLE' THEN F.NombreZona END,

        LEFT(CONVERT(VARCHAR(10), F.DesdeLocal, 103), 5) + ' ' + CONVERT(VARCHAR(5), F.DesdeLocal, 108)
          + ' -> ' +
        LEFT(CONVERT(VARCHAR(10), F.HastaLocal, 103), 5) + ' ' + CONVERT(VARCHAR(5), F.HastaLocal, 108),
        F.DesdeLocal, F.HastaLocal, F.FechaDesde, F.FechaHasta,
        F.Duracion, F.Minutos,
        CASE WHEN ISNULL(@MinutosViaje, 0) = 0 THEN NULL
             ELSE CAST(F.Minutos * 100.0 / @MinutosViaje AS DECIMAL(6,2)) END,

        CASE WHEN F.Novedad = 'CARRETEANDO' THEN F.Kms ELSE 0 END,
        CAST(F.KmAcum AS DECIMAL(12,2)),
        CASE WHEN F.Novedad = 'CARRETEANDO' THEN F.VelProm ELSE NULL END,
        CASE WHEN F.Novedad = 'CARRETEANDO' THEN F.VelMax  ELSE NULL END,

        CASE WHEN F.Novedad IN ('CARGA','DESCARGA') THEN F.MinutosOperacion END,
        CASE WHEN F.Novedad NOT IN ('CARGA','DESCARGA') THEN NULL
             WHEN F.MinutosOperacion > @MinutosTolerancia THEN 1 ELSE 0 END,
        F.AplicoExcepcion,

        /* Detalle narrado */
        CASE F.Novedad
            WHEN 'CARGA'
            THEN 'Ingreso a ' + ISNULL(F.NombreZona, '(sin nombre)') + ' a las ' +
                 CONVERT(VARCHAR(5), F.DesdeLocal, 108) + ' hs y permanecio ' + F.Duracion +
                 ' hs. Salio cargado a las ' + CONVERT(VARCHAR(5), F.HastaLocal, 108) + ' hs.'
            WHEN 'DESCARGA'
            THEN 'Llego a ' + ISNULL(F.NombreZona, '(sin nombre)') + ' a las ' +
                 CONVERT(VARCHAR(5), F.DesdeLocal, 108) + ' hs y permanecio ' + F.Duracion +
                 ' hs. Salio descargado a las ' + CONVERT(VARCHAR(5), F.HastaLocal, 108) + ' hs.'
            WHEN 'CARRETEANDO'
            THEN 'Carreteando ' + F.Duracion + ' hs, ' + CAST(F.Kms AS VARCHAR(20)) + ' km (promedio ' +
                 CAST(CAST(F.VelProm AS INT) AS VARCHAR(5)) + ' km/h). Acumulado: ' +
                 CAST(CAST(F.KmAcum AS DECIMAL(12,2)) AS VARCHAR(20)) + ' km.'
            WHEN 'DETENIDO'
            THEN 'Detenido ' + F.Duracion + ' hs' +
                 CASE WHEN F.ClaseZona = 'COMBUSTIBLE'
                      THEN ' en la estacion de servicio ' + ISNULL(F.NombreZona, '(sin nombre)') +
                           ', superando los ' + CAST(@MinutosCombustible AS VARCHAR(5)) + ' min tolerados.'
                      ELSE ', fuera de parada y fuera de estacion de servicio (lat ' +
                           CAST(CAST(F.Lat AS DECIMAL(9,5)) AS VARCHAR(20)) + ', lon ' +
                           CAST(CAST(F.Lon AS DECIMAL(9,5)) AS VARCHAR(20)) + ').' END
            WHEN 'COMBUSTIBLE'
            THEN 'Carga de combustible en ' + ISNULL(F.NombreZona, '(sin nombre)') + ' durante ' + F.Duracion + ' hs.' +
                 CASE WHEN F.AplicoExcepcion = 1
                      THEN ' Aplica la excepcion diaria de ' + CAST(@MinutosCombustible AS VARCHAR(5)) + ' min.'
                      ELSE ' La excepcion del dia ya fue consumida.' END
            WHEN 'ESPERA_SIN_TAREA'
            THEN 'Sin parada pendiente por delante. Espera de ' + F.Duracion + ' hs' +
                 CASE WHEN F.NombreZona IS NOT NULL THEN ' en ' + F.NombreZona + '.' ELSE '.' END
            ELSE 'Suceso de ' + F.Duracion + ' hs.'
        END,

        /* Observacion */
        CASE
            WHEN F.Novedad IN ('CARGA','DESCARGA') AND F.MinutosOperacion > @MinutosTolerancia
            THEN 'Excede la tolerancia de ' + CAST(@MinutosTolerancia AS VARCHAR(5)) + ' min: la permanencia total en esta parada fue de ' +
                 CAST(F.MinutosOperacion AS VARCHAR(10)) + ' min (' +
                 CAST(F.MinutosOperacion - @MinutosTolerancia AS VARCHAR(10)) + ' min de exceso).'
            WHEN F.Novedad = 'ESPERA_SIN_TAREA'
            THEN 'Derivado por ausencia de parada pendiente. La plataforma no registra un hito propio de espera sin tarea.'
            WHEN F.Novedad = 'DETENIDO' AND F.Minutos >= 60
            THEN 'Detencion prolongada (' + F.Duracion + ' hs). Revisar.'
            ELSE NULL
        END,

        F.Eventos, F.Lat, F.Lon, GETUTCDATE()
    FROM Fmt F
    ORDER BY F.FechaDesde;


    /*==========================================================================
      PASO 9 - Salidas
    ==========================================================================*/
    /* 1 - Resumen de novedades */
    SELECT
        MAX(I.Suceso)                                       AS [Novedad],
        COUNT(*)                                            AS [Ocurrencias],
        SUM(I.TiempoMinutos)                                AS [Minutos],
        CAST(SUM(I.TiempoMinutos) / 60.0 AS DECIMAL(10,2))  AS [Horas],
        CAST(SUM(I.TiempoMinutos) * 100.0 / NULLIF(@MinutosViaje, 0) AS DECIMAL(6,2)) AS [% Viaje],
        SUM(I.Kms)                                          AS [Km],
        SUM(CASE WHEN I.ExcedeTolerancia = 1 THEN 1 ELSE 0 END) AS [Fuera de Tolerancia]
    FROM dbo.Z_ItinerarioViaje I WITH (NOLOCK)
    WHERE I.IdViaje = @IdViaje
    GROUP BY I.Novedad
    ORDER BY SUM(I.TiempoMinutos) DESC;

    /* 2 - Itinerario cronologico */
    SELECT
        I.Orden                 AS [#],
        I.DiaViaje              AS [Dia],
        I.Suceso                AS [Novedad],
        I.Ubicacion             AS [Ubicacion],
        I.EstacionServicio      AS [Estacion de Servicio],
        I.Periodo               AS [Periodo],
        I.Duracion              AS [Duracion],
        I.Kms                   AS [Km Tramo],
        I.KmAcumulado           AS [Km Acum],
        I.MinutosOperacion      AS [Min en Parada],
        CASE I.ExcedeTolerancia WHEN 1 THEN 'SI' WHEN 0 THEN 'NO' ELSE '' END AS [Excede 45 min],
        I.Detalle               AS [Detalle],
        I.Observacion           AS [Observacion]
    FROM dbo.Z_ItinerarioViaje I WITH (NOLOCK)
    WHERE I.IdViaje = @IdViaje
    ORDER BY I.Orden;

    /* 3 - Metrica de control por parada */
    SELECT
        I.Ubicacion             AS [Parada],
        MAX(I.Suceso)           AS [Operacion],
        MAX(I.MinutosOperacion) AS [Minutos],
        @MinutosTolerancia      AS [Tolerancia],
        MAX(I.MinutosOperacion) - @MinutosTolerancia AS [Desvio],
        CASE WHEN MAX(CAST(I.ExcedeTolerancia AS INT)) = 1 THEN 'FUERA DE TOLERANCIA' ELSE 'OK' END AS [Estado]
    FROM dbo.Z_ItinerarioViaje I WITH (NOLOCK)
    WHERE I.IdViaje = @IdViaje AND I.Novedad IN ('CARGA','DESCARGA')
    GROUP BY I.Ubicacion
    ORDER BY MIN(I.Orden);

    IF OBJECT_ID('tempdb..#Zonas')   IS NOT NULL DROP TABLE #Zonas;
    IF OBJECT_ID('tempdb..#Eventos') IS NOT NULL DROP TABLE #Eventos;
    IF OBJECT_ID('tempdb..#Tramos')  IS NOT NULL DROP TABLE #Tramos;

    INSERT INTO dbo.[Log] (Categoria, Descripcion, FechaHora)
    VALUES ('FIN', 'Z_SP_ItinerarioViaje finalizado | IdViaje: ' + CAST(@IdViaje AS VARCHAR(10)), GETDATE());
END;
