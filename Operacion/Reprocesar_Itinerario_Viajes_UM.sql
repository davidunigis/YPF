/*==============================================================================
  REPROCESAR Z_SP_ItinerarioViaje PARA LOS VIAJES UM FINALIZADOS

  Ejecuta el SP uno a uno solo para los viajes de esta consulta:
      Jornada.IdOperacion = 139 (Ultima Milla) y Viaje.IdEstadoViaje = 99 (Finalizado)

  ESCRIBE datos: por cada viaje borra y vuelve a cargar sus filas en Z_ItinerarioViaje
  y agrega lineas al Log. Usar despues de desplegar el SP nuevo.

  Antes de ejecutar, en SSMS: Herramientas > Opciones > Resultados de la consulta >
  SQL Server > Resultados en cuadricula > "Descartar resultados despues de la
  ejecucion". Sin eso cada viaje abre 3 cuadriculas (el SP devuelve 3 resultados).

  Un viaje con error no corta el proceso: se informa al final con su IdViaje.
  Para probar con pocos viajes, cambiar @Maximo (0 = todos).
==============================================================================*/
USE [UNIGIS_DataRepository_YPF_ARENAS_QA]
GO
SET NOCOUNT ON;

DECLARE @Maximo INT = 0;   -- 0 = todos los viajes de la consulta

DECLARE @Ids TABLE (N INT IDENTITY(1,1) PRIMARY KEY, IdViaje INT NOT NULL);
DECLARE @Errores TABLE (IdViaje INT NOT NULL, Mensaje NVARCHAR(2000) NULL);

INSERT INTO @Ids (IdViaje)
SELECT V.IdViaje
FROM dbo.Viaje AS V WITH (NOLOCK)
INNER JOIN dbo.Jornada AS J WITH (NOLOCK) ON J.IdJornada = V.IdJornada
WHERE J.IdOperacion = 139
  AND V.IdEstadoViaje = 99
ORDER BY V.IdViaje;

DECLARE @N INT = 1, @Total INT, @IdViaje INT, @Ok INT = 0, @Err INT = 0;
SELECT @Total = COUNT(*) FROM @Ids;
IF @Maximo > 0 AND @Total > @Maximo SET @Total = @Maximo;
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
        INSERT INTO @Errores (IdViaje, Mensaje) VALUES (@IdViaje, ERROR_MESSAGE());
    END CATCH;

    IF @N % 25 = 0 OR @N = @Total
        PRINT 'Avance: ' + CAST(@N AS VARCHAR(10)) + ' de ' + CAST(@Total AS VARCHAR(10))
            + ' | ultimo viaje: ' + CAST(@IdViaje AS VARCHAR(12));
    SET @N = @N + 1;
END;

PRINT 'Procesados sin error: ' + CAST(@Ok AS VARCHAR(10)) + ' | con error: ' + CAST(@Err AS VARCHAR(10));

IF @Err > 0
    SELECT IdViaje, Mensaje FROM @Errores ORDER BY IdViaje;
GO
