USE [UNIGIS_DataRepository_YPF_ARENAS_QA]
GO

IF OBJECT_ID('dbo.Z_CambioTurnoTransporte', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Z_CambioTurnoTransporte
    (
        IdCambioTurno   INT IDENTITY(1,1) NOT NULL
                        CONSTRAINT PK_Z_CambioTurnoTransporte PRIMARY KEY,
        IdTransporte    INT          NOT NULL,
        HoraDesde       TIME(0)      NOT NULL,
        DuracionMinutos INT          NOT NULL
                        CONSTRAINT DF_Z_CambioTurnoTransporte_Dur DEFAULT (60),
        Activo          BIT          NOT NULL
                        CONSTRAINT DF_Z_CambioTurnoTransporte_Act DEFAULT (1),
        Observacion     VARCHAR(200) NULL
    );
    CREATE UNIQUE INDEX UX_Z_CambioTurnoTransporte
        ON dbo.Z_CambioTurnoTransporte (IdTransporte, HoraDesde);
END
GO

IF COL_LENGTH('dbo.Z_ItinerarioViaje', 'ToleranciaMinutos') IS NULL
    ALTER TABLE dbo.Z_ItinerarioViaje ADD ToleranciaMinutos INT NULL;
GO
IF COL_LENGTH('dbo.Z_ItinerarioViaje', 'ResponsableDemora') IS NULL
    ALTER TABLE dbo.Z_ItinerarioViaje ADD ResponsableDemora VARCHAR(12) NULL;
GO
IF COL_LENGTH('dbo.Z_ItinerarioViaje', 'MinutosDemora') IS NULL
    ALTER TABLE dbo.Z_ItinerarioViaje ADD MinutosDemora INT NULL;
GO
IF COL_LENGTH('dbo.Z_ItinerarioViaje', 'MinutosExentos') IS NULL
    ALTER TABLE dbo.Z_ItinerarioViaje ADD MinutosExentos INT NULL;
GO
IF COL_LENGTH('dbo.Z_ItinerarioViaje', 'MotivoExencion') IS NULL
    ALTER TABLE dbo.Z_ItinerarioViaje ADD MotivoExencion VARCHAR(20) NULL;
GO

IF OBJECT_ID('dbo.Z_MinutosAHHMM', 'FN') IS NOT NULL
    DROP FUNCTION dbo.Z_MinutosAHHMM;
GO
CREATE FUNCTION dbo.Z_MinutosAHHMM (@Minutos INT)
RETURNS VARCHAR(12)
AS
BEGIN
    DECLARE @M INT = ISNULL(@Minutos, 0);
    RETURN CASE WHEN @M / 60 < 10 THEN '0' ELSE '' END
         + CAST(@M / 60 AS VARCHAR(10)) + ':'
         + RIGHT('0' + CAST(@M % 60 AS VARCHAR(2)), 2);
END
GO
