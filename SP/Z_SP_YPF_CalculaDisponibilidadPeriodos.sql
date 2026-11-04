USE [UNIGIS_DataRepository_YPF]
GO
/****** Objeto: StoredProcedure [dbo].[Z_SP_YPF_CalculaDisponibilidadPeriodos] Fecha de script: 04/11/2026 ******/
-- REQUISITOS: ejecutar antes Scripts/Z_Periodos_Agregar_IdPeriodoOrigen.sql y Scripts/Z_PeriodosDisponibilidad_Crear_Tablas.sql
-- ANTES DE USARLO: completar @IdTipoIncidencia y @LoginIncidencia (ver "CONFIGURACION DE LA INCIDENCIA" mas abajo).
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[Z_SP_YPF_CalculaDisponibilidadPeriodos]
AS
BEGIN
    /*
    Creado: 02/11/2026
    Modificado: 04/11/2026 - (1) No recalcula los periodos ya procesados (Z_PeriodosDisponibilidad.Procesado = 1).
              (2) La indisponibilidad se calcula por AGRUPADOR (no por dominio) y en DIAS (no en minutos).
              (3) Paso 2: genera la Incidencia por indisponibilidad del agrupador (ver abajo).
    Objetivo: dejar la trazabilidad de la disponibilidad de los vehiculos dentro de cada periodo de Z_Periodos
              (insumo para tarifar) y generar la incidencia cuando un agrupador supera los dias de indisponibilidad.
              Corre por CRON todos los dias a las 23:59 hora Argentina (02:59 UTC), sin parametros. Se alimenta de los
              tramos que arma Z_SP_YPF_SustituyeDominioPeriodo.
              Crear las tablas con Scripts/Z_PeriodosDisponibilidad_Crear_Tablas.sql.

    Que se analiza
      - PERIODO (titular): cada fila ORIGINAL de Z_Periodos (IdPeriodoOrigen IS NULL). Va de InicioPeriodo 00:00 hasta
        el fin de FinPeriodo (inclusive). Si todavia no termino, se analiza hasta el corte. Los periodos que aun
        no empezaron se ignoran.
      - Las lineas se AGRUPAN por Agrupador + InicioPeriodo + FinPeriodo (Agrupador NULL = ''). Cada grupo es una fila de
        Z_PeriodosDisponibilidad y los dias de todas sus lineas se SUMAN.
      - TRAMOS del periodo: las filas de Z_Periodos con COALESCE(IdPeriodoOrigen, IdPeriodo) = IdPeriodo del periodo.
          Desde = FechaRegistroPeriodo (en la fila original, el inicio del periodo).
          Hasta = FechaNodisponible (NULL = el tramo sigue abierto: llega hasta el corte).
          TipoTramo = 'Titular' si Dominio es el del periodo; si no, 'Sustituto' (cubre a DominioSustituye).
      - Corte = hora Argentina actual (sin segundos). Si el SP corre a las 23:59 o despues, se considera cerrado el
        dia (corte = 00:00 del dia siguiente) para que un periodo completo de N dias de exactamente N dias.

    Paso 1 - disponibilidad (solo periodos NO procesados)
      Un periodo (agrupador + inicio + fin) con Procesado = 1 NO se toca: ni se recalcula ni se borra. Los demas se
      recalculan completos en una transaccion. Un periodo EnCurso se recalcula todas las noches porque los dias
      acumulan; uno Finalizado se calcula una vez y queda Procesado cuando se resuelve el paso 2.
      Z_PeriodosDisponibilidad (en DIAS): DiasPeriodo, DiasDisponible, DiasNoDisponible (= periodo - disponible),
      DiasSustituido, DiasSinCobertura, Sustitutos, DiasSustitutoFueraPer.
      Z_PeriodosTramos: el detalle por dominio. En los SUSTITUTOS hay DOS controles de "fuera de periodo":
        a) respecto del periodo del titular: DiasFueraPerTitular / FueraPerTitularDesde (el sustituto sigue cubriendo
           despues de que termino el periodo del titular).
        b) respecto de sus periodos PROPIOS (filas originales del dominio, uniendo las que se tocan):
           DiasFueraPerPropio / FueraPerPropioDesde / EstadoPerPropio (DENTRO, PARCIAL, FUERA, SIN PERIODO).

    Paso 2 - incidencia por indisponibilidad (solo periodos Finalizados no procesados)
      1) DiasNoDisponible ya viene SUMADO por agrupador (todas las lineas del agrupador en el periodo). Si es MENOR a
         @DiasMinIncidencia (4) o el agrupador esta vacio, no hay incidencia y el periodo queda Procesado.
      2) Si es MAYOR O IGUAL a @DiasMinIncidencia se busca en dbo.Guia la linea con Guia.Varchar1 = Agrupador y
         Guia.Fecha dentro del periodo (InicioPeriodo 00:00 hasta el fin de FinPeriodo). Si hay mas de una se usa la de
         Fecha mas reciente (queda anotado en Log). Con la guia se inserta UNA fila en dbo.Incidencia:
            IdGuia = Guia.IdGuia   |   Valor = DiasNoDisponible   |   IdTipoIncidencia y Login = los configurados
            FechaCreacion = GETUTCDATE()   |   Observaciones = texto con agrupador, periodo y dias
            (Eliminado e IdEstadoIncidencia toman su DEFAULT; el resto de los campos queda NULL.)
         y el periodo queda Procesado con IdGuia e IdIncidencia anotados.
      - Si NO existe la guia, o falta configurar @IdTipoIncidencia / @LoginIncidencia, el periodo NO queda Procesado: se
        reintenta todas las noches (asi no se pierde la incidencia si la guia se crea despues). Queda un Aviso en Log.
      - Si ya existe una incidencia no eliminada de ese tipo para esa guia, no se duplica: se anota la existente.
      - El paso 2 va en su propia transaccion: si falla (por ejemplo FK de IdTipoIncidencia o Login), no inserta nada,
        los periodos quedan sin procesar para reintentar, y el resultado del paso 1 no se pierde.

    Notas
      - Para REPROCESAR un periodo:  UPDATE Z_PeriodosDisponibilidad SET Procesado = 0 WHERE ...
      - Los minutos se calculan sobre horas truncadas al minuto (las partes suman exacto) y se pasan a dias con 4
        decimales; el umbral de 4 dias se compara con ese valor (5759 minutos = 3.9993 dias no llega a 4).
      - FechaNodisponible y FechaRegistroPeriodo son DATE en Z_Periodos: hoy solo traen la fecha, asi que los tramos
        empiezan y terminan a las 00:00 y los dias salen enteros; un cambio y retorno el mismo dia da 0 dias. Si esas dos
        columnas pasan a DATETIME, este SP calcula con la hora sin cambios.
      - Las columnas de texto de las tablas temporales usan COLLATE DATABASE_DEFAULT: sin eso toman la collation de
        tempdb y chocan con la de la base (error 468 SQL_Latin1_General_CP1_CI_AS vs Modern_Spanish_CI_AS).
      - Registra el resultado en Log (categoria DisponibilidadPer, 20 caracteres como maximo) y no relanza el error.
    */
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    /*==================== CONFIGURACION DE LA INCIDENCIA (completar) ====================*/
    DECLARE @IdTipoIncidencia  INT      = NULL;   -- <<< COMPLETAR: TipoIncidencia.IdTipoIncidencia de la incidencia por indisponibilidad
    DECLARE @LoginIncidencia   CHAR(25) = NULL;   -- <<< COMPLETAR: Usuario.Login con el que se crea la incidencia
    DECLARE @DiasMinIncidencia DECIMAL(9,2) = 4;  -- se genera incidencia si los dias no disponibles del agrupador son >= a esto
    /*====================================================================================*/

    DECLARE @Ahora     DATETIME = DATEADD(HOUR, -3, GETUTCDATE());   -- hora Argentina
    DECLARE @Hoy       DATE     = CAST(@Ahora AS DATE);
    DECLARE @Corte     DATETIME = CASE WHEN CAST(@Ahora AS TIME) >= '23:59'
                                       THEN DATEADD(DAY, 1, CAST(@Hoy AS DATETIME))              -- dia cerrado
                                       ELSE DATEADD(MINUTE, DATEDIFF(MINUTE, 0, @Ahora), 0) END; -- sin segundos
    DECLARE @CantPer   INT = 0;   -- periodos (agrupador + inicio + fin) calculados en este paso 1
    DECLARE @CantTr    INT = 0;   -- tramos
    DECLARE @CantSin   INT = 0;   -- periodos terminados sin incidencia (quedan procesados)
    DECLARE @CantInc   INT = 0;   -- incidencias nuevas
    DECLARE @CantExist INT = 0;   -- periodos cuya incidencia ya existia
    DECLARE @CantSinGu INT = 0;   -- periodos con indisponibilidad pero sin guia (quedan pendientes)
    DECLARE @CantMulti INT = 0;   -- periodos con mas de una guia (se uso la mas reciente)
    DECLARE @Pendiente INT = 0;   -- periodos terminados que siguen sin procesar
    DECLARE @FaltaCfg  BIT = 0;
    DECLARE @Paso1OK   BIT = 0;
    DECLARE @Resultado VARCHAR(10) = 'OK';
    DECLARE @Detalle   VARCHAR(400) = '';

    /*==============================================================================================
      PASO 1 - DISPONIBILIDAD POR AGRUPADOR Y PERIODO (solo periodos no procesados)
    ==============================================================================================*/
    BEGIN TRY
        /* 1) Periodos de los titulares (filas originales) que ya empezaron y cuyo grupo NO esta procesado */
        CREATE TABLE #Raices (
            IdPeriodoRaiz INT NOT NULL PRIMARY KEY,
            Agrupador     VARCHAR(50) COLLATE DATABASE_DEFAULT NOT NULL,   -- '' si es NULL
            Dominio       VARCHAR(50) COLLATE DATABASE_DEFAULT NOT NULL,
            InicioPeriodo DATE NOT NULL,
            FinPeriodo    DATE NOT NULL,
            Ini           DATETIME NOT NULL,   -- inicio del periodo (00:00 de InicioPeriodo)
            Fin           DATETIME NOT NULL,   -- fin EXCLUSIVO (00:00 del dia siguiente a FinPeriodo)
            FinEfec       DATETIME NOT NULL,   -- hasta donde se analiza: el menor entre Fin y el corte
            MinPeriodo    INT NULL
        );

        INSERT #Raices (IdPeriodoRaiz, Agrupador, Dominio, InicioPeriodo, FinPeriodo, Ini, Fin, FinEfec)
        SELECT r.IdPeriodo, ISNULL(r.Agrupador, ''), RTRIM(r.Dominio), r.InicioPeriodo, r.FinPeriodo, i.Ini, f.Fin,
               CASE WHEN f.Fin < @Corte THEN f.Fin ELSE @Corte END
        FROM Z_Periodos r
            CROSS APPLY (SELECT CAST(r.InicioPeriodo AS DATETIME) AS Ini) i
            CROSS APPLY (SELECT CASE WHEN r.FinPeriodo >= '9999-12-31' THEN CAST('9999-12-31' AS DATETIME)
                                     ELSE DATEADD(DAY, 1, CAST(r.FinPeriodo AS DATETIME)) END AS Fin) f
        WHERE r.IdPeriodoOrigen IS NULL
          AND r.FinPeriodo >= r.InicioPeriodo
          AND i.Ini < @Corte
          AND NOT EXISTS (SELECT 1 FROM dbo.Z_PeriodosDisponibilidad d
                          WHERE d.Procesado = 1
                            AND d.Agrupador = ISNULL(r.Agrupador, '')
                            AND d.InicioPeriodo = r.InicioPeriodo
                            AND d.FinPeriodo = r.FinPeriodo);

        UPDATE #Raices SET MinPeriodo = CASE WHEN FinEfec > Ini THEN DATEDIFF(MINUTE, Ini, FinEfec) ELSE 0 END;

        /* 2) Tramos de esos periodos */
        CREATE TABLE #Tramos (
            IdTramo              INT NOT NULL PRIMARY KEY,
            IdPeriodoRaiz        INT NOT NULL,
            Agrupador            VARCHAR(50) COLLATE DATABASE_DEFAULT NOT NULL,
            InicioPeriodo        DATE NOT NULL,
            FinPeriodo           DATE NOT NULL,
            Dominio              VARCHAR(50) COLLATE DATABASE_DEFAULT NOT NULL,
            DominioSustituye     VARCHAR(50) COLLATE DATABASE_DEFAULT NULL,
            TipoTramo            VARCHAR(10) COLLATE DATABASE_DEFAULT NOT NULL,
            Desde                DATETIME NOT NULL,
            Hasta                DATETIME NULL,
            Ini                  DATETIME NOT NULL,
            Fin                  DATETIME NOT NULL,
            FinEfec              DATETIME NOT NULL,
            DesdeEf              DATETIME NULL,
            HastaEf              DATETIME NULL,
            Minutos              INT NULL,
            MinDentroPerTitular  INT NULL,
            MinFueraPerTitular   INT NULL,
            FueraPerTitularDesde DATETIME NULL,
            MinFueraPerPropio    INT NULL,
            FueraPerPropioDesde  DATETIME NULL,
            EstadoPerPropio      VARCHAR(12) COLLATE DATABASE_DEFAULT NULL
        );
        CREATE INDEX IX_Tramos_Grupo ON #Tramos (Agrupador, InicioPeriodo, FinPeriodo);

        INSERT #Tramos (IdTramo, IdPeriodoRaiz, Agrupador, InicioPeriodo, FinPeriodo, Dominio, DominioSustituye, TipoTramo,
                        Desde, Hasta, Ini, Fin, FinEfec)
        SELECT t.IdPeriodo, rz.IdPeriodoRaiz, rz.Agrupador, rz.InicioPeriodo, rz.FinPeriodo, RTRIM(t.Dominio), RTRIM(t.DominioSustituye),
               CASE WHEN RTRIM(t.Dominio) = rz.Dominio THEN 'Titular' ELSE 'Sustituto' END,
               CASE WHEN t.IdPeriodoOrigen IS NULL OR t.FechaRegistroPeriodo IS NULL THEN rz.Ini
                    ELSE DATEADD(MINUTE, DATEDIFF(MINUTE, 0, CAST(t.FechaRegistroPeriodo AS DATETIME)), 0) END,
               DATEADD(MINUTE, DATEDIFF(MINUTE, 0, CAST(t.FechaNodisponible AS DATETIME)), 0),
               rz.Ini, rz.Fin, rz.FinEfec
        FROM Z_Periodos t
            JOIN #Raices rz ON rz.IdPeriodoRaiz = COALESCE(t.IdPeriodoOrigen, t.IdPeriodo);

        /* 3) Periodos PROPIOS de los dominios que sustituyeron (filas originales), uniendo los que se tocan o
              superponen (islas): sirve para saber si un sustituto estuvo dentro o fuera de sus periodos */
        CREATE TABLE #PerPropios (Dominio VARCHAR(50) COLLATE DATABASE_DEFAULT NOT NULL, S DATETIME NOT NULL, E DATETIME NOT NULL);
        CREATE INDEX IX_PerPropios ON #PerPropios (Dominio, S);

        ;WITH P AS (
            SELECT RTRIM(z.Dominio) AS Dominio,
                   CAST(z.InicioPeriodo AS DATETIME) AS S,
                   CASE WHEN z.FinPeriodo >= '9999-12-31' THEN CAST('9999-12-31' AS DATETIME)
                        ELSE DATEADD(DAY, 1, CAST(z.FinPeriodo AS DATETIME)) END AS E
            FROM Z_Periodos z
            WHERE z.IdPeriodoOrigen IS NULL AND z.FinPeriodo >= z.InicioPeriodo
              AND EXISTS (SELECT 1 FROM #Tramos t WHERE t.TipoTramo = 'Sustituto' AND t.Dominio = RTRIM(z.Dominio))
        ),
        M AS (
            SELECT Dominio, S, E,
                   MAX(E) OVER (PARTITION BY Dominio ORDER BY S, E ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS MaxPrev
            FROM P
        ),
        G AS (
            SELECT Dominio, S, E,
                   SUM(CASE WHEN MaxPrev IS NULL OR S > MaxPrev THEN 1 ELSE 0 END)
                       OVER (PARTITION BY Dominio ORDER BY S, E ROWS UNBOUNDED PRECEDING) AS Grp
            FROM M
        )
        INSERT #PerPropios (Dominio, S, E)
        SELECT Dominio, MIN(S), MAX(E) FROM G GROUP BY Dominio, Grp;

        /* 4) Tramo efectivo: el del titular se limita a su periodo; el del sustituto llega hasta el corte (aunque el
              periodo del titular ya haya terminado), asi se ve cuanto se paso */
        UPDATE t
        SET DesdeEf = CASE WHEN t.Desde > t.Ini THEN t.Desde ELSE t.Ini END,
            HastaEf = CASE WHEN t.Hasta IS NULL OR t.Hasta > p.Tope THEN p.Tope ELSE t.Hasta END
        FROM #Tramos t
            CROSS APPLY (SELECT CASE WHEN t.TipoTramo = 'Titular' THEN t.FinEfec ELSE @Corte END AS Tope) p;

        UPDATE #Tramos
        SET Minutos = CASE WHEN HastaEf > DesdeEf THEN DATEDIFF(MINUTE, DesdeEf, HastaEf) ELSE 0 END;

        -- Dentro / fuera del periodo del titular
        UPDATE #Tramos
        SET MinDentroPerTitular =
                CASE WHEN TipoTramo = 'Titular' THEN Minutos
                     WHEN HastaEf > DesdeEf AND FinEfec > DesdeEf
                          THEN DATEDIFF(MINUTE, DesdeEf, CASE WHEN HastaEf < FinEfec THEN HastaEf ELSE FinEfec END)
                     ELSE 0 END;

        UPDATE #Tramos
        SET MinFueraPerTitular = Minutos - MinDentroPerTitular,
            FueraPerTitularDesde = CASE WHEN Minutos - MinDentroPerTitular > 0
                                        THEN CASE WHEN DesdeEf > FinEfec THEN DesdeEf ELSE FinEfec END END;

        -- Dentro / fuera de los periodos PROPIOS del sustituto
        UPDATE t
        SET MinFueraPerPropio   = t.Minutos - ISNULL(i.MinDentro, 0),
            FueraPerPropioDesde = CASE WHEN t.Minutos - ISNULL(i.MinDentro, 0) > 0
                                       THEN ISNULL(c.E, t.DesdeEf) END,    -- 1er instante sin cubrir: el inicio, o el fin del periodo propio que lo cubre
            EstadoPerPropio     = CASE WHEN t.Minutos = 0 THEN NULL
                                       WHEN NOT EXISTS (SELECT 1 FROM #PerPropios p WHERE p.Dominio = t.Dominio) THEN 'SIN PERIODO'
                                       WHEN t.Minutos - ISNULL(i.MinDentro, 0) = 0 THEN 'DENTRO'
                                       WHEN ISNULL(i.MinDentro, 0) = 0 THEN 'FUERA'
                                       ELSE 'PARCIAL' END
        FROM #Tramos t
            OUTER APPLY (SELECT SUM(x.Minutos) AS MinDentro      -- el solapamiento se calcula por fila y despues se suma
                         FROM (SELECT DATEDIFF(MINUTE,
                                               CASE WHEN p.S > t.DesdeEf THEN p.S ELSE t.DesdeEf END,
                                               CASE WHEN p.E < t.HastaEf THEN p.E ELSE t.HastaEf END) AS Minutos
                               FROM #PerPropios p
                               WHERE p.Dominio = t.Dominio AND p.S < t.HastaEf AND p.E > t.DesdeEf) x) i
            OUTER APPLY (SELECT TOP 1 p.E
                         FROM #PerPropios p
                         WHERE p.Dominio = t.Dominio AND p.S <= t.DesdeEf AND p.E > t.DesdeEf) c
        WHERE t.TipoTramo = 'Sustituto';

        /* 5) Grupos agrupador + periodo (todas las lineas del grupo comparten inicio, fin y corte) */
        CREATE TABLE #Claves (
            Agrupador     VARCHAR(50) COLLATE DATABASE_DEFAULT NOT NULL,
            InicioPeriodo DATE NOT NULL,
            FinPeriodo    DATE NOT NULL,
            Fin           DATETIME NOT NULL,
            FinEfec       DATETIME NOT NULL,
            CantTitulares INT NOT NULL,
            MinPeriodo    INT NOT NULL,
            PRIMARY KEY (Agrupador, InicioPeriodo, FinPeriodo)
        );

        INSERT #Claves (Agrupador, InicioPeriodo, FinPeriodo, Fin, FinEfec, CantTitulares, MinPeriodo)
        SELECT Agrupador, InicioPeriodo, FinPeriodo, MIN(Fin), MIN(FinEfec), COUNT(*), SUM(MinPeriodo)
        FROM #Raices
        GROUP BY Agrupador, InicioPeriodo, FinPeriodo;

        /*------------------------------------------------------------------------------------------
          6) Reemplazar el resultado de los periodos NO procesados (todo o nada). Los procesados no se tocan.
        ------------------------------------------------------------------------------------------*/
        BEGIN TRAN;

        DELETE tr
        FROM dbo.Z_PeriodosTramos tr
        WHERE NOT EXISTS (SELECT 1 FROM dbo.Z_PeriodosDisponibilidad d
                          WHERE d.Procesado = 1 AND d.Agrupador = tr.Agrupador
                            AND d.InicioPeriodo = tr.InicioPeriodo AND d.FinPeriodo = tr.FinPeriodo);

        DELETE FROM dbo.Z_PeriodosDisponibilidad WHERE Procesado = 0;

        INSERT dbo.Z_PeriodosDisponibilidad
              (Agrupador, InicioPeriodo, FinPeriodo, Estado, FechaCorte, CantTitulares, DiasPeriodo, DiasDisponible,
               DiasNoDisponible, DiasSustituido, DiasSinCobertura, PorcDisponible, CantSustituciones, Sustitutos,
               DiasSustitutoFueraPer, Procesado, FechaProcesado, IdGuia, IdIncidencia, FechaCalculo)
        SELECT k.Agrupador, k.InicioPeriodo, k.FinPeriodo,
               CASE WHEN k.FinEfec >= k.Fin THEN 'Finalizado' ELSE 'EnCurso' END,
               k.FinEfec,
               k.CantTitulares,
               CAST(k.MinPeriodo / 1440.0 AS DECIMAL(12,4)),
               CAST(a.MinDisp / 1440.0 AS DECIMAL(12,4)),
               CAST((k.MinPeriodo - a.MinDisp) / 1440.0 AS DECIMAL(12,4)),
               CAST(a.MinSust / 1440.0 AS DECIMAL(12,4)),
               CAST(CASE WHEN k.MinPeriodo - a.MinDisp - a.MinSust > 0 THEN k.MinPeriodo - a.MinDisp - a.MinSust ELSE 0 END / 1440.0 AS DECIMAL(12,4)),
               CASE WHEN k.MinPeriodo > 0 THEN CAST(100.0 * a.MinDisp / k.MinPeriodo AS DECIMAL(5,2)) END,
               a.Cant,
               STUFF((SELECT DISTINCT ', ' + s.Dominio
                      FROM #Tramos s
                      WHERE s.Agrupador = k.Agrupador AND s.InicioPeriodo = k.InicioPeriodo AND s.FinPeriodo = k.FinPeriodo
                        AND s.TipoTramo = 'Sustituto'
                      FOR XML PATH(''), TYPE).value('.', 'VARCHAR(500)'), 1, 2, ''),
               CAST(a.MinFuera / 1440.0 AS DECIMAL(12,4)),
               0, NULL, NULL, NULL,
               @Ahora
        FROM #Claves k
            CROSS APPLY (SELECT ISNULL(SUM(CASE WHEN t.TipoTramo = 'Titular'   THEN t.Minutos ELSE 0 END), 0)             AS MinDisp,
                                ISNULL(SUM(CASE WHEN t.TipoTramo = 'Sustituto' THEN t.MinDentroPerTitular ELSE 0 END), 0) AS MinSust,
                                ISNULL(SUM(CASE WHEN t.TipoTramo = 'Sustituto' THEN 1 ELSE 0 END), 0)                     AS Cant,
                                ISNULL(SUM(CASE WHEN t.TipoTramo = 'Sustituto' THEN t.MinFueraPerTitular ELSE 0 END), 0)  AS MinFuera
                         FROM #Tramos t
                         WHERE t.Agrupador = k.Agrupador AND t.InicioPeriodo = k.InicioPeriodo AND t.FinPeriodo = k.FinPeriodo) a;

        SET @CantPer = @@ROWCOUNT;

        INSERT dbo.Z_PeriodosTramos
              (IdTramo, IdPeriodo, Agrupador, InicioPeriodo, FinPeriodo, Dominio, IdRecurso, TipoTramo, DominioSustituye,
               Desde, Hasta, Dias, DiasDentroPerTitular, DiasFueraPerTitular, FueraPerTitularDesde, DiasFueraPerPropio,
               FueraPerPropioDesde, EstadoPerPropio, FechaCalculo)
        SELECT t.IdTramo, t.IdPeriodoRaiz, t.Agrupador, t.InicioPeriodo, t.FinPeriodo, t.Dominio, v.IdRecurso, t.TipoTramo,
               t.DominioSustituye, t.Desde, t.Hasta,
               CAST(t.Minutos / 1440.0 AS DECIMAL(12,4)),
               CAST(t.MinDentroPerTitular / 1440.0 AS DECIMAL(12,4)),
               CAST(t.MinFueraPerTitular / 1440.0 AS DECIMAL(12,4)),
               t.FueraPerTitularDesde,
               CAST(t.MinFueraPerPropio / 1440.0 AS DECIMAL(12,4)),
               t.FueraPerPropioDesde, t.EstadoPerPropio, @Ahora
        FROM #Tramos t
            OUTER APPLY (SELECT TOP 1 vh.IdRecurso FROM Vehiculo vh WITH (NOLOCK) WHERE vh.Dominio = t.Dominio ORDER BY vh.IdVehiculo) v;

        SET @CantTr = @@ROWCOUNT;

        COMMIT TRAN;

        SET @Paso1OK = 1;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRAN;

        SELECT @Resultado = 'Error', @Detalle = 'Paso1: ' + ERROR_MESSAGE();
    END CATCH

    /*==============================================================================================
      PASO 2 - INCIDENCIA POR INDISPONIBILIDAD DEL AGRUPADOR (periodos Finalizados no procesados)
    ==============================================================================================*/
    IF @Paso1OK = 1
    BEGIN
        BEGIN TRY
            BEGIN TRAN;

            -- a) periodos terminados que no necesitan incidencia (agrupador vacio o menos dias que el minimo): procesados
            UPDATE dbo.Z_PeriodosDisponibilidad
            SET Procesado = 1, FechaProcesado = @Ahora
            WHERE Procesado = 0 AND Estado = 'Finalizado'
              AND (Agrupador = '' OR DiasNoDisponible < @DiasMinIncidencia);

            SET @CantSin = @@ROWCOUNT;

            IF @IdTipoIncidencia IS NULL OR @LoginIncidencia IS NULL
                SET @FaltaCfg = 1;   -- sin configuracion no se generan incidencias: los periodos quedan pendientes
            ELSE
            BEGIN
                -- b) periodos con indisponibilidad suficiente: guia que corresponde e incidencia ya existente
                CREATE TABLE #Cand (
                    Agrupador         VARCHAR(50) COLLATE DATABASE_DEFAULT NOT NULL,
                    InicioPeriodo     DATE NOT NULL,
                    FinPeriodo        DATE NOT NULL,
                    Dias              DECIMAL(12,4) NOT NULL,
                    IdGuia            INT NULL,
                    CantGuias         INT NOT NULL,
                    IdIncidenciaExist INT NULL,
                    PRIMARY KEY (Agrupador, InicioPeriodo, FinPeriodo)
                );

                INSERT #Cand (Agrupador, InicioPeriodo, FinPeriodo, Dias, IdGuia, CantGuias, IdIncidenciaExist)
                SELECT d.Agrupador, d.InicioPeriodo, d.FinPeriodo, d.DiasNoDisponible, g.IdGuia, ISNULL(gc.Cant, 0), e.IdIncidencia
                FROM dbo.Z_PeriodosDisponibilidad d
                    OUTER APPLY (SELECT TOP 1 gu.IdGuia
                                 FROM dbo.Guia gu WITH (NOLOCK)
                                 WHERE gu.Varchar1 = d.Agrupador
                                   AND gu.Fecha >= d.InicioPeriodo
                                   AND gu.Fecha <  DATEADD(DAY, 1, CAST(d.FinPeriodo AS DATETIME))
                                 ORDER BY gu.Fecha DESC, gu.IdGuia DESC) g
                    OUTER APPLY (SELECT COUNT(*) AS Cant
                                 FROM dbo.Guia gu WITH (NOLOCK)
                                 WHERE gu.Varchar1 = d.Agrupador
                                   AND gu.Fecha >= d.InicioPeriodo
                                   AND gu.Fecha <  DATEADD(DAY, 1, CAST(d.FinPeriodo AS DATETIME))) gc
                    OUTER APPLY (SELECT TOP 1 i.IdIncidencia
                                 FROM dbo.Incidencia i WITH (NOLOCK)
                                 WHERE i.IdGuia = g.IdGuia AND i.IdTipoIncidencia = @IdTipoIncidencia AND i.Eliminado = 0
                                 ORDER BY i.IdIncidencia) e
                WHERE d.Procesado = 0 AND d.Estado = 'Finalizado' AND d.Agrupador <> ''
                  AND d.DiasNoDisponible >= @DiasMinIncidencia;

                -- c) incidencia nueva por cada periodo con guia y sin incidencia previa
                CREATE TABLE #IncNuevas (IdIncidencia INT NOT NULL, IdGuia INT NOT NULL);

                INSERT dbo.Incidencia (IdTipoIncidencia, FechaCreacion, Login, Observaciones, IdGuia, Valor)
                OUTPUT inserted.IdIncidencia, inserted.IdGuia INTO #IncNuevas (IdIncidencia, IdGuia)
                SELECT @IdTipoIncidencia, GETUTCDATE(), @LoginIncidencia,
                       'Indisponibilidad del agrupador ' + c.Agrupador + ' en el periodo ' + CONVERT(VARCHAR(10), c.InicioPeriodo, 120)
                       + ' a ' + CONVERT(VARCHAR(10), c.FinPeriodo, 120) + ': ' + CONVERT(VARCHAR(20), c.Dias)
                       + ' dias (Z_SP_YPF_CalculaDisponibilidadPeriodos)',
                       c.IdGuia, c.Dias
                FROM #Cand c
                WHERE c.IdGuia IS NOT NULL AND c.IdIncidenciaExist IS NULL;

                SET @CantInc = @@ROWCOUNT;

                -- d) esos periodos quedan procesados con la guia y la incidencia anotadas
                UPDATE d
                SET Procesado = 1, FechaProcesado = @Ahora, IdGuia = c.IdGuia,
                    IdIncidencia = COALESCE(n.IdIncidencia, c.IdIncidenciaExist)
                FROM dbo.Z_PeriodosDisponibilidad d
                    JOIN #Cand c ON c.Agrupador = d.Agrupador AND c.InicioPeriodo = d.InicioPeriodo AND c.FinPeriodo = d.FinPeriodo
                    LEFT JOIN #IncNuevas n ON n.IdGuia = c.IdGuia
                WHERE c.IdGuia IS NOT NULL;

                SELECT @CantExist = ISNULL(SUM(CASE WHEN IdGuia IS NOT NULL AND IdIncidenciaExist IS NOT NULL THEN 1 ELSE 0 END), 0),
                       @CantSinGu = ISNULL(SUM(CASE WHEN IdGuia IS NULL THEN 1 ELSE 0 END), 0),
                       @CantMulti = ISNULL(SUM(CASE WHEN CantGuias > 1 THEN 1 ELSE 0 END), 0)
                FROM #Cand;
            END

            COMMIT TRAN;
        END TRY
        BEGIN CATCH
            IF XACT_STATE() <> 0
                ROLLBACK TRAN;

            SELECT @Resultado = 'Error', @Detalle = 'Paso2: ' + ERROR_MESSAGE(), @CantInc = 0, @CantExist = 0;
        END CATCH

        IF @Resultado <> 'Error'
        BEGIN
            SELECT @Pendiente = COUNT(*) FROM dbo.Z_PeriodosDisponibilidad WHERE Estado = 'Finalizado' AND Procesado = 0;

            SET @Detalle = 'periodos=' + CONVERT(VARCHAR(10), @CantPer) + ' tramos=' + CONVERT(VARCHAR(10), @CantTr)
                         + ' corte=' + CONVERT(VARCHAR(16), @Corte, 120)
                         + ' | sin_incidencia=' + CONVERT(VARCHAR(10), @CantSin) + ' incidencias=' + CONVERT(VARCHAR(10), @CantInc)
                         + ' ya_existian=' + CONVERT(VARCHAR(10), @CantExist) + ' sin_guia=' + CONVERT(VARCHAR(10), @CantSinGu)
                         + ' multi_guia=' + CONVERT(VARCHAR(10), @CantMulti) + ' pendientes=' + CONVERT(VARCHAR(10), @Pendiente);

            IF @FaltaCfg = 1
                SELECT @Resultado = 'Aviso', @Detalle = @Detalle + ' | FALTA CONFIGURAR @IdTipoIncidencia / @LoginIncidencia';
            ELSE IF @CantSinGu > 0 OR @CantMulti > 0
                SET @Resultado = 'Aviso';
        END
    END

    BEGIN TRY   -- el Log nunca debe hacer fallar el SP
        INSERT Log (Categoria, Descripcion, FechaHora)
        VALUES ('DisponibilidadPer', @Resultado + ' ' + @Detalle, GETUTCDATE());
    END TRY
    BEGIN CATCH
    END CATCH
END
