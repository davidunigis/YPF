USE [UNIGIS_DataRepository_YPF]
GO
/*
Creado: 02/11/2026
Modificado: 04/11/2026 - Z_PeriodosDisponibilidad pasa a ser por AGRUPADOR + periodo (antes por dominio), con los
          tiempos en DIAS (antes minutos) y con la columna Procesado (BIT) para no recalcular periodos ya procesados;
          guarda ademas la guia y la incidencia generadas. Z_PeriodosTramos tambien pasa a dias.
Objetivo: crear las dos tablas donde Z_SP_YPF_CalculaDisponibilidadPeriodos deja, cada noche, la trazabilidad de la
          disponibilidad de los vehiculos dentro de cada periodo de Z_Periodos (insumo para tarifar).
          Se puede ejecutar mas de una vez. Ejecutar ANTES de crear/actualizar el SP.

!! SI YA TENIAS LAS TABLAS DE LA VERSION ANTERIOR (por dominio y en minutos) este script las ELIMINA y las vuelve a
!! crear con la estructura nueva: cambia la granularidad y no se pueden convertir con ALTER. Son tablas DERIVADAS:
!! la primera corrida del SP las recalcula completas desde Z_Periodos. Si ya tienen la estructura nueva no se tocan.

Los tiempos se guardan en DIAS con 4 decimales (con fechas DATE salen enteros; con DATETIME salen fracciones).
Fechas y horas en horario de Argentina (igual que Z_Periodos).

1) Z_PeriodosDisponibilidad  -  UNA fila por AGRUPADOR + periodo (InicioPeriodo, FinPeriodo). Suma las lineas (vehiculos
       titulares) de ese agrupador en ese periodo: dias disponible, no disponible, sustituido, quien sustituyo, y el
       resultado del paso de incidencias. Agrupador '' = lineas de Z_Periodos con Agrupador NULL.
       Procesado = 1  ->  periodo terminado y resuelto: el SP no lo vuelve a calcular.
       Para REPROCESAR un periodo:  UPDATE Z_PeriodosDisponibilidad SET Procesado = 0 WHERE Agrupador = '...' AND ...
2) Z_PeriodosTramos          -  UNA fila por cada tramo (cada fila de Z_Periodos que compone esos periodos): detalle por
       dominio, titular o sustituto, a quien reemplazo y si el sustituto estuvo dentro o fuera de periodo.

Consultas utiles:
    -- dias no disponibles por agrupador y periodo, y su incidencia
    SELECT Agrupador, InicioPeriodo, FinPeriodo, Estado, DiasNoDisponible, Sustitutos, Procesado, IdGuia, IdIncidencia
    FROM Z_PeriodosDisponibilidad ORDER BY Agrupador, InicioPeriodo;
    -- periodos terminados con incidencia pendiente (hay indisponibilidad pero falta la guia o la configuracion)
    SELECT * FROM Z_PeriodosDisponibilidad WHERE Estado = 'Finalizado' AND Procesado = 0;
    -- a quien sustituyo cada vehiculo y por cuanto tiempo
    SELECT Dominio AS Sustituto, DominioSustituye AS Sustituido, Desde, Hasta, Dias, EstadoPerPropio
    FROM Z_PeriodosTramos WHERE TipoTramo = 'Sustituto' ORDER BY Dominio, Desde;
*/

-- Version anterior (por dominio, en minutos): se recrea
IF OBJECT_ID('dbo.Z_PeriodosDisponibilidad', 'U') IS NOT NULL AND COL_LENGTH('dbo.Z_PeriodosDisponibilidad', 'Procesado') IS NULL
    DROP TABLE dbo.Z_PeriodosDisponibilidad;
GO
IF OBJECT_ID('dbo.Z_PeriodosTramos', 'U') IS NOT NULL AND COL_LENGTH('dbo.Z_PeriodosTramos', 'Dias') IS NULL
    DROP TABLE dbo.Z_PeriodosTramos;
GO

IF OBJECT_ID('dbo.Z_PeriodosDisponibilidad', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Z_PeriodosDisponibilidad (
        Agrupador             VARCHAR(50)   NOT NULL,   -- Z_Periodos.Agrupador ('' si es NULL)
        InicioPeriodo         DATE          NOT NULL,
        FinPeriodo            DATE          NOT NULL,
        Estado                VARCHAR(10)   NOT NULL,   -- 'EnCurso' (el periodo no termino) | 'Finalizado'
        FechaCorte            DATETIME      NOT NULL,   -- hasta que momento se analizo (el fin del periodo, si ya termino)
        CantTitulares         INT           NOT NULL,   -- lineas (vehiculos titulares) del agrupador en el periodo
        DiasPeriodo           DECIMAL(12,4) NOT NULL,   -- dias del periodo analizados, sumados por linea (vehiculo-dias)
        DiasDisponible        DECIMAL(12,4) NOT NULL,   -- dias en que los titulares estuvieron disponibles
        DiasNoDisponible      DECIMAL(12,4) NOT NULL,   -- dias en que NO estuvieron disponibles (los que se suman por agrupador)
        DiasSustituido        DECIMAL(12,4) NOT NULL,   -- de los no disponibles, dias cubiertos por un sustituto
        DiasSinCobertura      DECIMAL(12,4) NOT NULL,   -- de los no disponibles, dias que nadie cubrio
        PorcDisponible        DECIMAL(5,2)  NULL,       -- DiasDisponible / DiasPeriodo * 100
        CantSustituciones     INT           NOT NULL,   -- cantidad de tramos de sustitutos
        Sustitutos            VARCHAR(500)  NULL,       -- dominios que sustituyeron (separados por coma)
        DiasSustitutoFueraPer DECIMAL(12,4) NOT NULL,   -- dias de sustitutos MAS ALLA del fin del periodo del titular
        Procesado             BIT           NOT NULL CONSTRAINT DF_Z_PeriodosDisponibilidad_Procesado DEFAULT (0),
        FechaProcesado        DATETIME      NULL,       -- cuando quedo procesado
        IdGuia                INT           NULL,       -- Guia.IdGuia usada para la incidencia
        IdIncidencia          INT           NULL,       -- Incidencia.IdIncidencia generada (o la que ya existia)
        FechaCalculo          DATETIME      NOT NULL,   -- cuando corrio el SP (hora Argentina)
        CONSTRAINT PK_Z_PeriodosDisponibilidad PRIMARY KEY (Agrupador, InicioPeriodo, FinPeriodo)
    );
    CREATE INDEX IX_Z_PeriodosDisponibilidad_Procesado ON dbo.Z_PeriodosDisponibilidad (Procesado, Estado);
END
GO

IF OBJECT_ID('dbo.Z_PeriodosTramos', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Z_PeriodosTramos (
        IdTramo               INT           NOT NULL,   -- Z_Periodos.IdPeriodo de la fila de ese tramo
        IdPeriodo             INT           NOT NULL,   -- IdPeriodo de la fila ORIGINAL del periodo (el titular)
        Agrupador             VARCHAR(50)   NOT NULL,   -- junto con Inicio/FinPeriodo liga con Z_PeriodosDisponibilidad
        InicioPeriodo         DATE          NOT NULL,
        FinPeriodo            DATE          NOT NULL,
        Dominio               VARCHAR(50)   NOT NULL,   -- dominio que cubrio el tramo
        IdRecurso             INT           NULL,       -- Vehiculo.IdRecurso de ese dominio
        TipoTramo             VARCHAR(10)   NOT NULL,   -- 'Titular' | 'Sustituto'
        DominioSustituye      VARCHAR(50)   NULL,       -- a quien reemplazo este tramo
        Desde                 DATETIME      NOT NULL,   -- inicio del tramo
        Hasta                 DATETIME      NULL,       -- fin del tramo; NULL = sigue abierto
        Dias                  DECIMAL(12,4) NOT NULL,   -- duracion hasta el corte (la del titular, solo dentro de su periodo)
        DiasDentroPerTitular  DECIMAL(12,4) NOT NULL,   -- dias dentro del periodo del titular
        DiasFueraPerTitular   DECIMAL(12,4) NOT NULL,   -- SUSTITUTO: dias mas alla del fin del periodo del titular
        FueraPerTitularDesde  DATETIME      NULL,       -- desde cuando (fin del periodo del titular)
        DiasFueraPerPropio    DECIMAL(12,4) NULL,       -- SUSTITUTO: dias fuera de SUS PROPIOS periodos en Z_Periodos
        FueraPerPropioDesde   DATETIME      NULL,       -- SUSTITUTO: desde cuando esta fuera de sus propios periodos
        EstadoPerPropio       VARCHAR(12)   NULL,       -- 'DENTRO' | 'PARCIAL' | 'FUERA' | 'SIN PERIODO' (NULL en los del titular)
        FechaCalculo          DATETIME      NOT NULL,
        CONSTRAINT PK_Z_PeriodosTramos PRIMARY KEY (IdTramo)
    );
    CREATE INDEX IX_Z_PeriodosTramos_Periodo ON dbo.Z_PeriodosTramos (Agrupador, InicioPeriodo, FinPeriodo);
    CREATE INDEX IX_Z_PeriodosTramos_Dominio ON dbo.Z_PeriodosTramos (Dominio, Desde);
END
GO
