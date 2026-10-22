USE [UNIGIS_DataRepository_YPF]
GO
/****** Objeto: StoredProcedure [dbo].[Z_SP_YPF_ValidaVehiculoPedido] Fecha de script: 22/10/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[Z_SP_YPF_ValidaVehiculoPedido]
    @IdPedido BIGINT
AS
BEGIN
    /*
    Creado: 22/10/2026
    Objetivo: validacion del pedido. El vehiculo requerido se indica en el campo Canal del pedido
              (Pedido.IdTipoCanal).
      - Si IdTipoCanal viene NULL: devuelve un mensaje pidiendo ingresar el vehiculo.
      - Si no viene NULL: devuelve 'OK' y ademas asigna en Pedido.IdTipoVehiculo y Pedido.Int1:
            IdTipoCanal 1 -> 207
            IdTipoCanal 2 -> 208
            IdTipoCanal 3 -> 209
        Con cualquier otro valor no se asigna nada (igualmente devuelve 'OK').
    Resultado: un unico SELECT con las columnas [Resultado] y [Mensaje]
               (Resultado = 'OK' y Mensaje = NULL; o Resultado = NULL y Mensaje = texto a mostrar).
    El UPDATE es transparente: no inserta en Log ni devuelve nada, y solo escribe si el valor cambia.
    Llamada desde la plataforma:  EXEC [dbo].[Z_SP_YPF_ValidaVehiculoPedido] [Pedido.IdPedido]
    */
    SET NOCOUNT ON;

    BEGIN TRY
        DECLARE @IdTipoCanal    BIGINT;
        DECLARE @IdTipoVehiculo INT;

        /*Icono Unicode (U+26D4)*/
        DECLARE @Icono NVARCHAR(10) = NCHAR(9940) + N' ';

        SELECT @IdTipoCanal = IdTipoCanal
        FROM Pedido WITH (NOLOCK)
        WHERE IdPedido = @IdPedido;

        /*Sin canal: se pide ingresar el vehiculo (NCHAR(237) = i con tilde, para no depender de la codificacion del archivo)*/
        IF @IdTipoCanal IS NULL
        BEGIN
            SELECT NULL [Resultado],
                   @Icono + N'Favor de ingresar el veh' + NCHAR(237) + N'culo requerido en el campo Canal del pedido' [Mensaje];
            RETURN;
        END

        /*Con canal: se asigna el tipo de vehiculo correspondiente*/
        SET @IdTipoVehiculo = CASE @IdTipoCanal
                                  WHEN 1 THEN 207
                                  WHEN 2 THEN 208
                                  WHEN 3 THEN 209
                              END;

        IF @IdTipoVehiculo IS NOT NULL
            UPDATE Pedido
            SET IdTipoVehiculo = @IdTipoVehiculo,
                Int1           = @IdTipoVehiculo
            WHERE IdPedido = @IdPedido
              AND (ISNULL(IdTipoVehiculo, -1) <> @IdTipoVehiculo
                   OR ISNULL(Int1, -1) <> @IdTipoVehiculo);

        SELECT 'OK' [Resultado], NULL [Mensaje];
    END TRY

    BEGIN CATCH
        SELECT NULL [Resultado], N'Error al validar el veh' + NCHAR(237) + N'culo del pedido: ' + ERROR_MESSAGE() [Mensaje];
    END CATCH
END
