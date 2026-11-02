USE [UNIGIS_DataRepository_YPF]
GO
/****** Objeto: StoredProcedure [dbo].[Z_SP_YPF_CalculaDisponibilidadPeriodos] Fecha de script: 02/11/2026 ******/
-- REQUISITOS: ejecutar antes Scripts/Z_Periodos_Agregar_IdPeriodoOrigen.sql y Scripts/Z_PeriodosDisponibilidad_Crear_Tablas.sql
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[Z_SP_YPF_CalculaDisponibilidadPeriodos]
AS
BEGIN
    /*
    Creado: 02/11/2026
    Objetivo: dejar la trazabilidad de la disponibilidad de los vehiculos dentro de cada periodo de Z_Periodos
              (insumo para tarifar). Corre por CRON todos los dias a las 23:59 hora Argentina (02:59 UTC), sin
              parametros: analiza todos los periodos. Se alimenta de los tramos que arma
              Z_SP_YPF_SustituyeDominioPeriodo. Recalcula por completo las tablas de resultado en cada corrida
              (idempotente): Z_PeriodosDisponibilidad (una fila por periodo) y Z_PeriodosTramos (una fila por tramo).
              Crear las tablas con Scripts/Z_PeriodosDisponibilidad_Crear_Tablas.sql.

    Que se analiza
      - PERIODO (titular): cada fila ORIGINAL de Z_Periodos (IdPeriodoOrigen IS NULL). Va de InicioPeriodo 00:00 hasta
        el fin de FinPeriodo (inclusive). Si todavia no termino, se analiza hasta el corte. Los periodos que aun
        no empezaron se ignoran.
      - TRAMOS del periodo: las filas de Z_Periodos con COALESCE(IdPeriodoOrigen, IdPeriodo) = IdPeriodo del periodo.
          Desde = FechaRegistroPeriodo (en la fila original, el inicio del periodo).
          Hasta = FechaNodisponible (NULL = el tramo sigue abierto: llega hasta el corte).
          TipoTramo = 'Titular' si Dominio es el del periodo; si no, 'Sustituto' (cubre a DominioSustituye).
      - Corte = hora Argentina actual (sin segundos). Si el SP corre a las 23:59 o despues, se considera cerrado el
        dia (corte = 00:00 del dia siguiente) para que un periodo completo de N dias de exactamente N*1440 minutos.

    Z_PeriodosDisponibilidad (por periodo del titular), todo en minutos:
      MinPeriodo      = minutos del periodo analizados.
      MinDisponible   = minutos en que el titular estuvo disponible (suma de sus tramos, solo dentro del periodo).
      MinNoDisponible = MinPeriodo - MinDisponible.
      MinSustituido   = de los no disponibles, minutos cubiertos por sustitutos (dentro del periodo).
      MinSinCobertura = de los no disponibles, minutos que nadie cubrio.
      Sustitutos / SustitutoActual / CantSustituciones = quien lo sustituyo.
      MinSustitutoFueraPer = minutos que un sustituto siguio cubriendo MAS ALLA del fin del periodo del titular.

    Z_PeriodosTramos (por tramo): Minutos = duracion hasta el corte. En los SUSTITUTOS ademas hay DOS controles de
    "fuera de periodo":
      a) respecto del periodo del titular al que sustituye: MinFueraPerTitular / FueraPerTitularDesde = el sustituto
         sigue cubriendo despues de que termino el periodo del titular (nadie cerro el tramo).
      b) respecto de los periodos PROPIOS del sustituto (sus filas originales en Z_Periodos, uniendo los que se
         tocan o se superponen): MinFueraPerPropio / FueraPerPropioDesde = minutos (y desde cuando) en que sustituyo
         estando fuera de sus propios periodos. EstadoPerPropio: DENTRO (todo el tramo dentro), PARCIAL, FUERA
         (todo fuera), SIN PERIODO (el dominio no tiene periodos propios en Z_Periodos).

    Notas
      - Los minutos se calculan sobre horas truncadas al minuto, asi las partes suman exacto.
      - FechaNodisponible y FechaRegistroPeriodo son DATE en Z_Periodos: hoy solo traen la fecha, asi que los tramos
        empiezan y terminan a las 00:00 y los minutos salen en multiplos de 1440; un cambio y retorno el mismo dia
        da 0 minutos. Si esas dos columnas pasan a DATETIME, este SP calcula con la hora sin cambios.
      - El resultado se reemplaza dentro de una transaccion: las tablas nunca quedan a medias.
      - Registra el resultado en Log (categoria DisponibilidadPer, 20 caracteres como maximo) y no relanza el error.
    */
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Ahora     DATETIME = DATEADD(HOUR, -3, GETUTCDATE());   -- hora Argentina
    DECLARE @Hoy       DATE     = CAST(@Ahora AS DATE);
    DECLARE @Corte     DATETIME = CASE WHEN CAST(@Ahora AS TIME) >= '23:59'
                                       THEN DATEADD(DAY, 1, CAST(@Hoy AS DATETIME))              -- dia cerrado
                                       ELSE DATEADD(MINUTE, DATEDIFF(MINUTE, 0, @Ahora), 0) END; -- sin segundos
    DECLARE @CantPer   INT = 0;
    DECLARE @CantTr    INT = 0;
    DECLARE @Resultado VARCHAR(10);
    DECLARE @Detalle   VARCHAR(300);

    BEGIN TRY
        /*--------------------------------------------------------------------------------------------
          1) Periodos de los titulares (filas originales) que ya empezaron
        --------------------------------------------------------------------------------------------*/
        CREATE TABLE #Raices (
            IdPeriodoRaiz INT NOT NULL PRIMARY KEY,
            Agrupador     VARCHAR(50) NULL,
            Dominio       VARCHAR(50) NOT NULL,
            InicioPeriodo DATE NOT NULL,
            FinPeriodo    DATE NOT NULL,
            Ini           DATETIME NOT NULL,   -- inicio del periodo (00:00 de InicioPeriodo)
            Fin           DATETIME NOT NULL,   -- fin EXCLUSIVO (00:00 del dia siguiente a FinPeriodo)
            FinEfec       DATETIME NOT NULL    -- hasta donde se analiza: el menor entre Fin y el corte
        );

        INSERT #Raices (IdPeriodoRaiz, Agrupador, Dominio, InicioPeriodo, FinPeriodo, Ini, Fin, FinEfec)
        SELECT r.IdPeriodo, r.Agrupador, RTRIM(r.Dominio), r.InicioPeriodo, r.FinPeriodo, i.Ini, f.Fin,
               CASE WHEN f.Fin < @Corte THEN f.Fin ELSE @Corte END
        FROM Z_Periodos r
            CROSS APPLY (SELECT CAST(r.InicioPeriodo AS DATETIME) AS Ini) i
            CROSS APPLY (SELECT CASE WHEN r.FinPeriodo >= '9999-12-31' THEN CAST('9999-12-31' AS DATETIME)
                                     ELSE DATEADD(DAY, 1, CAST(r.FinPeriodo AS DATETIME)) END AS Fin) f
        WHERE r.IdPeriodoOrigen IS NULL
          AND r.FinPeriodo >= r.InicioPeriodo
          AND i.Ini < @Corte;

        /*--------------------------------------------------------------------------------------------
          2) Periodos PROPIOS de cada dominio (filas originales), uniendo los que se tocan o superponen
             (islas): sirve para saber si un sustituto estuvo dentro o fuera de sus periodos
        --------------------------------------------------------------------------------------------*/
        CREATE TABLE #PerPropios (Dominio VARCHAR(50) NOT NULL, S DATETIME NOT NULL, E DATETIME NOT NULL);

        ;WITH P AS (
            SELECT RTRIM(Dominio) AS Dominio,
                   CAST(InicioPeriodo AS DATETIME) AS S,
                   CASE WHEN FinPeriodo >= '9999-12-31' THEN CAST('9999-12-31' AS DATETIME)
                        ELSE DATEADD(DAY, 1, CAST(FinPeriodo AS DATETIME)) END AS E
            FROM Z_Periodos
            WHERE IdPeriodoOrigen IS NULL AND FinPeriodo >= InicioPeriodo
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

        /*--------------------------------------------------------------------------------------------
          3) Tramos de esos periodos
        --------------------------------------------------------------------------------------------*/
        CREATE TABLE #Tramos (
            IdTramo              INT NOT NULL PRIMARY KEY,
            IdPeriodoRaiz        INT NOT NULL,
            Agrupador            VARCHAR(50) NULL,
            Dominio              VARCHAR(50) NOT NULL,
            DominioSustituye     VARCHAR(50) NULL,
            TipoTramo            VARCHAR(10) NOT NULL,
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
            EstadoPerPropio      VARCHAR(12) NULL
        );

        INSERT #Tramos (IdTramo, IdPeriodoRaiz, Agrupador, Dominio, DominioSustituye, TipoTramo, Desde, Hasta, Ini, Fin, FinEfec)
        SELECT t.IdPeriodo, rz.IdPeriodoRaiz, rz.Agrupador, RTRIM(t.Dominio), RTRIM(t.DominioSustituye),
               CASE WHEN RTRIM(t.Dominio) = rz.Dominio THEN 'Titular' ELSE 'Sustituto' END,
               CASE WHEN t.IdPeriodoOrigen IS NULL OR t.FechaRegistroPeriodo IS NULL THEN rz.Ini
                    ELSE DATEADD(MINUTE, DATEDIFF(MINUTE, 0, CAST(t.FechaRegistroPeriodo AS DATETIME)), 0) END,
               DATEADD(MINUTE, DATEDIFF(MINUTE, 0, CAST(t.FechaNodisponible AS DATETIME)), 0),
               rz.Ini, rz.Fin, rz.FinEfec
        FROM Z_Periodos t
            JOIN #Raices rz ON rz.IdPeriodoRaiz = COALESCE(t.IdPeriodoOrigen, t.IdPeriodo);

        -- Tramo efectivo: el del titular se limita a su periodo; el del sustituto llega hasta el corte (aunque el
        -- periodo del titular ya haya terminado), asi se ve cuanto se paso
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

        /*--------------------------------------------------------------------------------------------
          4) Reemplazar el resultado (todo o nada)
        --------------------------------------------------------------------------------------------*/
        BEGIN TRAN;

        DELETE FROM dbo.Z_PeriodosTramos;
        DELETE FROM dbo.Z_PeriodosDisponibilidad;

        INSERT dbo.Z_PeriodosDisponibilidad
              (IdPeriodo, Agrupador, Dominio, IdRecurso, InicioPeriodo, FinPeriodo, Estado, FechaCorte,
               MinPeriodo, MinDisponible, MinNoDisponible, MinSustituido, MinSinCobertura, PorcDisponible,
               CantSustituciones, Sustitutos, SustitutoActual, MinSustitutoFueraPer, FechaCalculo)
        SELECT rz.IdPeriodoRaiz, rz.Agrupador, rz.Dominio, v.IdRecurso, rz.InicioPeriodo, rz.FinPeriodo,
               CASE WHEN rz.FinEfec >= rz.Fin THEN 'Finalizado' ELSE 'EnCurso' END,
               rz.FinEfec,
               mp.Minutos,
               a.MinDisp,
               mp.Minutos - a.MinDisp,
               a.MinSust,
               CASE WHEN mp.Minutos - a.MinDisp - a.MinSust > 0 THEN mp.Minutos - a.MinDisp - a.MinSust ELSE 0 END,
               CASE WHEN mp.Minutos > 0 THEN CAST(100.0 * a.MinDisp / mp.Minutos AS DECIMAL(5,2)) END,
               a.Cant,
               STUFF((SELECT DISTINCT ', ' + s.Dominio
                      FROM #Tramos s
                      WHERE s.IdPeriodoRaiz = rz.IdPeriodoRaiz AND s.TipoTramo = 'Sustituto'
                      FOR XML PATH(''), TYPE).value('.', 'VARCHAR(500)'), 1, 2, ''),
               (SELECT TOP 1 s.Dominio
                FROM #Tramos s
                WHERE s.IdPeriodoRaiz = rz.IdPeriodoRaiz AND s.TipoTramo = 'Sustituto' AND s.Hasta IS NULL
                ORDER BY s.IdTramo DESC),
               a.MinFuera,
               @Ahora
        FROM #Raices rz
            CROSS APPLY (SELECT CASE WHEN rz.FinEfec > rz.Ini THEN DATEDIFF(MINUTE, rz.Ini, rz.FinEfec) ELSE 0 END AS Minutos) mp
            CROSS APPLY (SELECT ISNULL(SUM(CASE WHEN t.TipoTramo = 'Titular'   THEN t.Minutos ELSE 0 END), 0)             AS MinDisp,
                                ISNULL(SUM(CASE WHEN t.TipoTramo = 'Sustituto' THEN t.MinDentroPerTitular ELSE 0 END), 0) AS MinSust,
                                ISNULL(SUM(CASE WHEN t.TipoTramo = 'Sustituto' THEN 1 ELSE 0 END), 0)                     AS Cant,
                                ISNULL(SUM(CASE WHEN t.TipoTramo = 'Sustituto' THEN t.MinFueraPerTitular ELSE 0 END), 0)  AS MinFuera
                         FROM #Tramos t
                         WHERE t.IdPeriodoRaiz = rz.IdPeriodoRaiz) a
            OUTER APPLY (SELECT TOP 1 vh.IdRecurso FROM Vehiculo vh WITH (NOLOCK) WHERE vh.Dominio = rz.Dominio ORDER BY vh.IdVehiculo) v;

        SET @CantPer = @@ROWCOUNT;

        INSERT dbo.Z_PeriodosTramos
              (IdTramo, IdPeriodo, Agrupador, Dominio, IdRecurso, TipoTramo, DominioSustituye, Desde, Hasta, Minutos,
               MinDentroPerTitular, MinFueraPerTitular, FueraPerTitularDesde, MinFueraPerPropio, FueraPerPropioDesde,
               EstadoPerPropio, FechaCalculo)
        SELECT t.IdTramo, t.IdPeriodoRaiz, t.Agrupador, t.Dominio, v.IdRecurso, t.TipoTramo, t.DominioSustituye,
               t.Desde, t.Hasta, t.Minutos, t.MinDentroPerTitular, t.MinFueraPerTitular, t.FueraPerTitularDesde,
               t.MinFueraPerPropio, t.FueraPerPropioDesde, t.EstadoPerPropio, @Ahora
        FROM #Tramos t
            OUTER APPLY (SELECT TOP 1 vh.IdRecurso FROM Vehiculo vh WITH (NOLOCK) WHERE vh.Dominio = t.Dominio ORDER BY vh.IdVehiculo) v;

        SET @CantTr = @@ROWCOUNT;

        COMMIT TRAN;

        SELECT @Resultado = 'OK',
               @Detalle   = 'periodos=' + CONVERT(VARCHAR(10), @CantPer) + ' tramos=' + CONVERT(VARCHAR(10), @CantTr)
                          + ' corte=' + CONVERT(VARCHAR(16), @Corte, 120);
    END TRY

    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRAN;

        SELECT @Resultado = 'Error', @Detalle = ERROR_MESSAGE();
    END CATCH

    BEGIN TRY   -- el Log nunca debe hacer fallar el SP
        INSERT Log (Categoria, Descripcion, FechaHora)
        VALUES ('DisponibilidadPer', @Resultado + ' ' + @Detalle, GETUTCDATE());
    END TRY
    BEGIN CATCH
    END CATCH
END
