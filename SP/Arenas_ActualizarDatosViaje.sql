USE [UNIGIS_DataRepository_YPF]
GO
/****** Objeto: StoredProcedure [dbo].[Arenas_ActualizarDatosViaje] Fecha de script: 07/10/2026 02:08:18 p. m. ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[Arenas_ActualizarDatosViaje]
    @IdViaje INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TotalPeso INT; 
    DECLARE @Origen INT; -- IdDeposito correspondiente
    DECLARE @DescripcionOrigen VARCHAR(255); -- Guardará la descripción del depósito

    -- 1. Obtener el IdDeposito y la Descripción buscando desde la tabla Viaje
    SELECT TOP 1 
        @Origen = D.IdDeposito,
        @DescripcionOrigen = D.Descripcion
    FROM Viaje V WITH(NOLOCK)
    INNER JOIN Deposito D WITH(NOLOCK) ON D.Descripcion = V.Varchar4 
    WHERE V.IdViaje = @IdViaje;

    -- 2. Seleccionar el peso de la parada con IdTipoParada = 3 y el orden más alto
    SELECT TOP 1 @TotalPeso = CAST(P.Peso AS INT)
    FROM Parada P WITH(NOLOCK)
    WHERE P.IdViaje = @IdViaje 
      AND P.IdTipoParada = 3
    ORDER BY P.Orden DESC;

    -- 3. Actualizar la tabla Viaje con los datos obtenidos
    UPDATE Viaje
    SET IdDepositoSalida  = ISNULL(@Origen, IdDepositoSalida),
        IdDepositoLlegada = ISNULL(@Origen, IdDepositoLlegada),
        Origen            = ISNULL(@DescripcionOrigen, Origen),
        Peso              = ISNULL(@TotalPeso, Peso)
    WHERE IdViaje = @IdViaje;
END
