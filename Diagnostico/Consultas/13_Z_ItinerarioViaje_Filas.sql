/*==============================================================================
  13 - LO QUE DEJO EL SP EN Z_ItinerarioViaje PARA EL VIAJE (todas las columnas)

  Cambiar @IdViaje. Es la tabla de la que leen los reportes, fila por fila.
==============================================================================*/
DECLARE @IdViaje INT = 330178;

SELECT Z.*
FROM dbo.Z_ItinerarioViaje AS Z WITH (NOLOCK)
WHERE Z.IdViaje = @IdViaje
ORDER BY Z.Orden;
