USE [UNIGIS_DataRepository_YPF]
GO
/****** Objeto: StoredProcedure [dbo].[Z_Solidas-AtributosViaje] Fecha de script: 22/10/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[Z_Solidas-AtributosViaje]
    @IdViaje BIGINT
AS
BEGIN
    /*
    Creado: 22/10/2026
    Objetivo: se ejecuta para un viaje (recibe el IdViaje) y le asigna sus atributos de Solidas.
    Valores por defecto de Solidas:  Conductor 12173 | Transporte 163 | Vehiculo 19052

    1) Si el viaje TIENE ruta (Viaje.IdRutaFK distinto de NULL y de 0):
         - Seguimiento del viaje (Seguimiento.IdSeguimiento = Viaje.IdSeguimiento):
               IdTransporte = 163 e IdVehiculo = 19052.
         - Viaje: IdVehiculo = 19052 e IdConductor = 12173.
         - Viaje.IdTipoVehiculo y Viaje.Float1 = Ruta.IdTipoVehiculo (Ruta.IdRuta = Viaje.IdRutaFK).
           Si la ruta no tiene tipo de vehiculo, esos dos campos no se tocan.
    2) Si el viaje NO tiene ruta (IdRutaFK NULL o 0):
         - Se toman los pedidos de sus paradas (Parada.IdViaje = Viaje.IdViaje, Parada.IdPedido = Pedido.IdPedido).
         - Del pedido se obtiene el tipo de vehiculo a partir de Pedido.IdTipoCanal
               (1 -> 207, 2 -> 208, 3 -> 209, la misma equivalencia de Z_SP_YPF_ValidaVehiculoPedido)
           y se asigna en Viaje.IdTipoVehiculo y Viaje.Float1.
         - Los pedidos de las paradas deben dar el mismo tipo de vehiculo: si dan tipos distintos, o ninguna
           parada tiene pedido con canal 1, 2 o 3, no se asigna nada (queda anotado en Log).
         - En este caso NO se asignan conductor, vehiculo ni transporte por defecto.
    Modificado: 22/10/2026 - la categoria de Log pasa a 'SolidasAtribViaje': Log.Categoria admite solo 20
              caracteres y 'Solidas-AtributosViaje' (22) lo superaba (error de datos truncados). El INSERT en Log va
              protegido: si falla, no rompe el SP ni se informa como error.
    Llamada desde la plataforma:  EXEC [dbo].[Z_Solidas-AtributosViaje] [Viaje.IdViaje]
    Notas:
      - Solo escribe si algun valor cambia.
      - Un viaje que no existe no hace nada ni inserta en Log.
      - Como el resto de los SP del repo, registra el resultado en Log y no relanza el error.
    */
    SET NOCOUNT ON;

    -- Salida inmediata si el viaje no existe
    IF NOT EXISTS (SELECT 1 FROM Viaje WITH (NOLOCK) WHERE IdViaje = @IdViaje)
        RETURN 0;

    BEGIN TRY
        /*Valores por defecto de Solidas*/
        DECLARE @IdConductorDef  INT = 12173;
        DECLARE @IdTransporteDef INT = 163;
        DECLARE @IdVehiculoDef   INT = 19052;

        DECLARE @IdRutaFK       BIGINT;
        DECLARE @IdSeguimiento  BIGINT;
        DECLARE @IdTipoVehiculo INT;
        DECLARE @TiposDistintos INT = 0;
        DECLARE @Detalle        VARCHAR(200);

        SELECT @IdRutaFK      = IdRutaFK,
               @IdSeguimiento = IdSeguimiento
        FROM Viaje WITH (NOLOCK)
        WHERE IdViaje = @IdViaje;

        IF ISNULL(@IdRutaFK, 0) <> 0
        BEGIN
            /*1) Viaje con ruta*/
            SELECT @IdTipoVehiculo = IdTipoVehiculo
            FROM Ruta WITH (NOLOCK)
            WHERE IdRuta = @IdRutaFK;

            UPDATE Seguimiento
            SET IdTransporte = @IdTransporteDef,
                IdVehiculo   = @IdVehiculoDef
            WHERE IdSeguimiento = @IdSeguimiento
              AND (ISNULL(IdTransporte, -1) <> @IdTransporteDef
                   OR ISNULL(IdVehiculo, -1) <> @IdVehiculoDef);

            UPDATE Viaje
            SET IdVehiculo     = @IdVehiculoDef,
                IdConductor    = @IdConductorDef,
                IdTipoVehiculo = ISNULL(@IdTipoVehiculo, IdTipoVehiculo),
                Float1         = ISNULL(@IdTipoVehiculo, Float1)
            WHERE IdViaje = @IdViaje
              AND (ISNULL(IdVehiculo, -1) <> @IdVehiculoDef
                   OR ISNULL(IdConductor, -1) <> @IdConductorDef
                   OR (@IdTipoVehiculo IS NOT NULL
                       AND (ISNULL(IdTipoVehiculo, -1) <> @IdTipoVehiculo
                            OR ISNULL(Float1, -1) <> @IdTipoVehiculo)));

            SET @Detalle = 'Ruta=' + CONVERT(VARCHAR(20), @IdRutaFK)
                         + ' TipoVehiculo=' + ISNULL(CONVERT(VARCHAR(20), @IdTipoVehiculo), '-');
        END
        ELSE
        BEGIN
            /*2) Viaje sin ruta: tipo de vehiculo del pedido de sus paradas.
                 Para tomar el tipo de otra columna del pedido, cambiar solo la expresion CASE de abajo.*/
            SELECT @TiposDistintos = COUNT(DISTINCT t.Tipo),
                   @IdTipoVehiculo = MIN(t.Tipo)
            FROM (SELECT CASE pe.IdTipoCanal WHEN 1 THEN 207 WHEN 2 THEN 208 WHEN 3 THEN 209 END AS Tipo
                  FROM Parada pa WITH (NOLOCK)
                      JOIN Pedido pe WITH (NOLOCK) ON pe.IdPedido = pa.IdPedido
                  WHERE pa.IdViaje = @IdViaje) t
            WHERE t.Tipo IS NOT NULL;

            IF @TiposDistintos = 1
            BEGIN
                UPDATE Viaje
                SET IdTipoVehiculo = @IdTipoVehiculo,
                    Float1         = @IdTipoVehiculo
                WHERE IdViaje = @IdViaje
                  AND (ISNULL(IdTipoVehiculo, -1) <> @IdTipoVehiculo
                       OR ISNULL(Float1, -1) <> @IdTipoVehiculo);

                SET @Detalle = 'SinRuta TipoVehiculo=' + CONVERT(VARCHAR(20), @IdTipoVehiculo);
            END
            ELSE IF @TiposDistintos > 1
                SET @Detalle = 'SinRuta NO se asigna: los pedidos de las paradas tienen tipos de vehiculo distintos';
            ELSE
                SET @Detalle = 'SinRuta NO se asigna: ninguna parada tiene pedido con canal 1, 2 o 3';
        END

        BEGIN TRY   -- el Log nunca debe hacer fallar el SP
            INSERT Log (Categoria, Descripcion, FechaHora)
            VALUES ('SolidasAtribViaje',
                    'OK IdViaje=' + CONVERT(VARCHAR(20), @IdViaje) + ' ' + @Detalle,
                    GETUTCDATE());
        END TRY
        BEGIN CATCH
        END CATCH
    END TRY
    BEGIN CATCH
        BEGIN TRY   -- el Log nunca debe hacer fallar el SP
            INSERT Log (Categoria, Descripcion, FechaHora)
            VALUES ('SolidasAtribViaje',
                    'IdViaje=' + CONVERT(VARCHAR(20), @IdViaje) + ' Error :' + ERROR_MESSAGE(),
                    GETUTCDATE());
        END TRY
        BEGIN CATCH
        END CATCH
    END CATCH
END
