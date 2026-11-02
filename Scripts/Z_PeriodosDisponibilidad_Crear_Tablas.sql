USE [UNIGIS_DataRepository_YPF]
GO
/*
Creado: 02/11/2026
Objetivo: crear las dos tablas donde Z_SP_YPF_CalculaDisponibilidadPeriodos deja, cada noche, la trazabilidad de la
          disponibilidad de los vehiculos dentro de cada periodo de Z_Periodos (insumo para tarifar).
          Se pueden ejecutar mas de una vez (solo crean lo que falta). Ejecutar ANTES de crear el SP.

Las dos tablas se RECALCULAN completas en cada corrida del SP: no se editan a mano.
Los tiempos se guardan en MINUTOS. Fechas y horas en horario de Argentina (igual que Z_Periodos).

1) Z_PeriodosDisponibilidad  -  UNA fila por periodo de un vehiculo (fila original de Z_Periodos, o sea el TITULAR):
       cuanto tiempo del periodo estuvo disponible, cuanto no, cuanto lo cubrio un sustituto y quien lo sustituyo.
2) Z_PeriodosTramos          -  UNA fila por cada tramo de esos periodos (cada fila de Z_Periodos que lo compone):
       cuanto tiempo duro cada tramo del titular y de cada sustituto, a quien reemplazo, y si el sustituto
       estuvo dentro o fuera de periodo (desde cuando y por cuanto tiempo).

Consultas utiles:
    -- disponibilidad por vehiculo y periodo
    SELECT Dominio, Agrupador, InicioPeriodo, FinPeriodo, Estado, MinDisponible, MinNoDisponible, Sustitutos
    FROM Z_PeriodosDisponibilidad ORDER BY Dominio, InicioPeriodo;
    -- a quien sustituyo cada vehiculo y por cuanto tiempo
    SELECT Dominio AS Sustituto, DominioSustituye AS Sustituido, Desde, Hasta, Minutos, EstadoPerPropio
    FROM Z_PeriodosTramos WHERE TipoTramo = 'Sustituto' ORDER BY Dominio, Desde;
    -- sustitutos que estan o estuvieron fuera de periodo
    SELECT * FROM Z_PeriodosTramos WHERE MinFueraPerPropio > 0 OR MinFueraPerTitular > 0;
*/
IF OBJECT_ID('dbo.Z_PeriodosDisponibilidad', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Z_PeriodosDisponibilidad (
        IdPeriodo            INT           NOT NULL,   -- Z_Periodos.IdPeriodo de la fila ORIGINAL del periodo (el titular)
        Agrupador            VARCHAR(50)   NULL,
        Dominio              VARCHAR(50)   NOT NULL,   -- dominio TITULAR del periodo
        IdRecurso            INT           NULL,       -- Vehiculo.IdRecurso del titular (NULL si el dominio no esta en Vehiculo)
        InicioPeriodo        DATE          NOT NULL,
        FinPeriodo           DATE          NOT NULL,
        Estado               VARCHAR(10)   NOT NULL,   -- 'EnCurso' (el periodo no termino) | 'Finalizado'
        FechaCorte           DATETIME      NOT NULL,   -- hasta que momento se analizo (el fin del periodo, si ya termino)
        MinPeriodo           INT           NOT NULL,   -- minutos del periodo analizados (inicio -> corte o fin del periodo)
        MinDisponible        INT           NOT NULL,   -- minutos en que el TITULAR estuvo disponible
        MinNoDisponible      INT           NOT NULL,   -- minutos en que el titular NO estuvo disponible
        MinSustituido        INT           NOT NULL,   -- de los no disponibles, minutos cubiertos por un sustituto
        MinSinCobertura      INT           NOT NULL,   -- de los no disponibles, minutos que nadie cubrio
        PorcDisponible       DECIMAL(5,2)  NULL,       -- MinDisponible / MinPeriodo * 100
        CantSustituciones    INT           NOT NULL,   -- cantidad de tramos de sustitutos en el periodo
        Sustitutos           VARCHAR(500)  NULL,       -- dominios que lo sustituyeron (separados por coma)
        SustitutoActual      VARCHAR(50)   NULL,       -- sustituto con el tramo abierto hoy (si lo hay)
        MinSustitutoFueraPer INT           NOT NULL,   -- minutos de sustitutos MAS ALLA del fin del periodo del titular
        FechaCalculo         DATETIME      NOT NULL,   -- cuando corrio el SP (hora Argentina)
        CONSTRAINT PK_Z_PeriodosDisponibilidad PRIMARY KEY (IdPeriodo)
    );
    CREATE INDEX IX_Z_PeriodosDisponibilidad_Dominio ON dbo.Z_PeriodosDisponibilidad (Dominio, InicioPeriodo);
END
GO

IF OBJECT_ID('dbo.Z_PeriodosTramos', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Z_PeriodosTramos (
        IdTramo              INT           NOT NULL,   -- Z_Periodos.IdPeriodo de la fila de ese tramo
        IdPeriodo            INT           NOT NULL,   -- periodo al que pertenece (= Z_PeriodosDisponibilidad.IdPeriodo)
        Agrupador            VARCHAR(50)   NULL,
        Dominio              VARCHAR(50)   NOT NULL,   -- dominio que cubrio el tramo
        IdRecurso            INT           NULL,       -- Vehiculo.IdRecurso de ese dominio
        TipoTramo            VARCHAR(10)   NOT NULL,   -- 'Titular' | 'Sustituto'
        DominioSustituye     VARCHAR(50)   NULL,       -- a quien reemplazo este tramo
        Desde                DATETIME      NOT NULL,   -- inicio del tramo
        Hasta                DATETIME      NULL,       -- fin del tramo; NULL = sigue abierto
        Minutos              INT           NOT NULL,   -- duracion del tramo hasta el corte (el del titular, solo dentro de su periodo)
        MinDentroPerTitular  INT           NOT NULL,   -- minutos dentro del periodo del titular
        MinFueraPerTitular   INT           NOT NULL,   -- minutos de un SUSTITUTO mas alla del fin del periodo del titular
        FueraPerTitularDesde DATETIME      NULL,       -- desde cuando (fin del periodo del titular)
        MinFueraPerPropio    INT           NULL,       -- SUSTITUTO: minutos fuera de SUS PROPIOS periodos en Z_Periodos
        FueraPerPropioDesde  DATETIME      NULL,       -- SUSTITUTO: desde cuando esta fuera de sus propios periodos
        EstadoPerPropio      VARCHAR(12)   NULL,       -- 'DENTRO' | 'PARCIAL' | 'FUERA' | 'SIN PERIODO' (NULL en los del titular)
        FechaCalculo         DATETIME      NOT NULL,
        CONSTRAINT PK_Z_PeriodosTramos PRIMARY KEY (IdTramo)
    );
    CREATE INDEX IX_Z_PeriodosTramos_Periodo ON dbo.Z_PeriodosTramos (IdPeriodo);
    CREATE INDEX IX_Z_PeriodosTramos_Dominio ON dbo.Z_PeriodosTramos (Dominio, Desde);
END
GO
