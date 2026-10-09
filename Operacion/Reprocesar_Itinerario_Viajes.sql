/*==============================================================================
  REPROCESAR Z_SP_ItinerarioViaje PARA VIAJES YA FINALIZADOS

  ESCRIBE datos: por cada viaje borra y vuelve a cargar sus filas en Z_ItinerarioViaje
  y agrega lineas al Log. Usar despues de desplegar el SP nuevo.

  Antes de ejecutar, en SSMS: Herramientas > Opciones > Resultados de la consulta >
  SQL Server > Resultados en cuadricula > "Descartar resultados despues de la
  ejecucion". Sin eso cada viaje abre 3 cuadriculas (el SP devuelve 3 resultados).

  Elegir los viajes: por rango de fechas de finalizacion (hora LOCAL) y, opcionalmente,
  una lista de IdViaje (descomentar la linea).
==============================================================================*/
USE [UNIGIS_DataRepository_YPF_ARENAS_QA]
GO
SET NOCOUNT ON;

DECLARE @Desde  DATETIME = '2026-10-01 00:00:00';   -- hora local de finalizacion
DECLARE @Hasta  DATETIME = '2026-10-31 23:59:59';
DECLARE @Offset INT      = -3;                      -- igual que @OffsetHoras del SP

DECLARE @Ids TABLE (N INT IDENTITY(1,1) PRIMARY KEY, IdViaje INT NOT NULL);

INSERT INTO @Ids (IdViaje)
SELECT V.IdViaje
FROM dbo.Viaje V WITH (NOLOCK)
INNER JOIN dbo.Evento EF WITH (NOLOCK) ON EF.IdEvento = V.IdEventoFinalizacion
WHERE V.IdEventoFinalizacion > 0
  AND DATEADD(HOUR, @Offset, EF.FechaHoraEvento) >= @Desde
  AND DATEADD(HOUR, @Offset, EF.FechaHoraEvento) <= @Hasta
  -- AND V.IdViaje IN (329958)
ORDER BY EF.FechaHoraEvento;

DECLARE @N INT = 1, @Total INT, @IdViaje INT, @Ok INT = 0, @Err INT = 0;
SELECT @Total = COUNT(*) FROM @Ids;
PRINT 'Viajes a reprocesar: ' + CAST(@Total AS VARCHAR(10));

WHILE @N <= @Total
BEGIN
    SELECT @IdViaje = IdViaje FROM @Ids WHERE N = @N;
    BEGIN TRY
        EXEC dbo.Z_SP_ItinerarioViaje @IdViaje = @IdViaje;
        SET @Ok = @Ok + 1;
    END TRY
    BEGIN CATCH
        SET @Err = @Err + 1;
        PRINT 'Viaje ' + CAST(@IdViaje AS VARCHAR(12)) + ' con error: ' + ERROR_MESSAGE();
    END CATCH;
    SET @N = @N + 1;
END;

PRINT 'Procesados sin error: ' + CAST(@Ok AS VARCHAR(10)) + ' | con error: ' + CAST(@Err AS VARCHAR(10));
