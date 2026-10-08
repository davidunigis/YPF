USE [UNIGIS_DataRepository_YPF_ARENAS_QA]
GO
/*==============================================================================
  Objetos de soporte para la imputacion de demoras (Z_SP_ItinerarioViaje).
  Ejecutar ANTES de desplegar el SP modificado. Es re-ejecutable (idempotente).

  1) Z_CambioTurnoTransporte : rangos de cambio de turno por transportista.
  2) Columnas nuevas en Z_ItinerarioViaje.
  3) Z_MinutosAHHMM          : formato HH:MM para los reportes.
==============================================================================*/

/* 1) Rangos de cambio de turno.
      Un transportista puede tener 1..n filas (una por turno). Horas en hora LOCAL
      (la misma base que @OffsetHoras del SP). El rango puede cruzar la medianoche
      (ej. 23:30 con 60 min => 23:30 a 00:30). Sin filas activas para un transportista
      no se aplica la excepcion. */
IF OBJECT_ID('dbo.Z_CambioTurnoTransporte', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Z_CambioTurnoTransporte
    (
        IdCambioTurno   INT IDENTITY(1,1) NOT NULL
                        CONSTRAINT PK_Z_CambioTurnoTransporte PRIMARY KEY,
        IdTransporte    INT          NOT NULL,   -- Transporte.IdTransporte
        HoraDesde       TIME(0)      NOT NULL,   -- inicio del rango, hora local
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

/* Ejemplo de carga (descomentar y ajustar):
INSERT INTO dbo.Z_CambioTurnoTransporte (IdTransporte, HoraDesde, DuracionMinutos, Observacion)
VALUES (123, '06:00', 60, 'Cambio de turno manana'),
       (123, '18:00', 60, 'Cambio de turno tarde');
*/

/* 2) Columnas nuevas en la tabla del reporte */
IF COL_LENGTH('dbo.Z_ItinerarioViaje', 'ToleranciaMinutos') IS NULL
    ALTER TABLE dbo.Z_ItinerarioViaje ADD ToleranciaMinutos INT NULL;      -- tolerancia aplicada a la parada
GO
IF COL_LENGTH('dbo.Z_ItinerarioViaje', 'ResponsableDemora') IS NULL
    ALTER TABLE dbo.Z_ItinerarioViaje ADD ResponsableDemora VARCHAR(12) NULL;   -- YPF | TRANSPORTE | NULL
GO
IF COL_LENGTH('dbo.Z_ItinerarioViaje', 'MinutosDemora') IS NULL
    ALTER TABLE dbo.Z_ItinerarioViaje ADD MinutosDemora INT NULL;          -- minutos imputados (aditivo: se puede sumar)
GO
IF COL_LENGTH('dbo.Z_ItinerarioViaje', 'MinutosExentos') IS NULL
    ALTER TABLE dbo.Z_ItinerarioViaje ADD MinutosExentos INT NULL;         -- minutos no imputados por excepcion
GO
IF COL_LENGTH('dbo.Z_ItinerarioViaje', 'MotivoExencion') IS NULL
    ALTER TABLE dbo.Z_ItinerarioViaje ADD MotivoExencion VARCHAR(20) NULL; -- COMBUSTIBLE | CAMBIO_TURNO
GO

/* 3) Formato HH:MM (horas sin tope de 24: 27:05 es valido) */
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
