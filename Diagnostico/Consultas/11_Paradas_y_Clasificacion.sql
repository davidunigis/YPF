/*==============================================================================
  11 - PARADAS DEL VIAJE Y COMO LAS CLASIFICA EL SP

  Cambiar @IdViaje. Una fila por parada con la salida de Z_ClasificarParadasViaje
  (ClaseParada / TipoOperacion) y si la geocerca (Dibujo) tiene geometria.
  Una parada sin geometria nunca se detecta por GPS.
==============================================================================*/
DECLARE @IdViaje INT = 330178;

SELECT C.Orden, C.IdParada, C.IdTipoParada, C.ClaseParada, C.TipoOperacion,
       C.Descripcion, C.IdDeposito, C.IdPedido, C.IdDibujo,
       DB.Nombre AS NombreDibujo,
       CASE WHEN C.IdDibujo IS NULL THEN 'SIN DIBUJO'
            WHEN DB.Geografia IS NULL THEN 'SIN GEOMETRIA' ELSE 'OK' END AS Geometria,
       CASE WHEN DB.Geografia IS NULL THEN NULL ELSE DB.Geografia.STArea() END AS AreaM2
FROM dbo.Z_ClasificarParadasViaje(@IdViaje) AS C
LEFT JOIN dbo.Dibujo AS DB WITH (NOLOCK) ON DB.IdDibujo = C.IdDibujo
ORDER BY C.Orden;
