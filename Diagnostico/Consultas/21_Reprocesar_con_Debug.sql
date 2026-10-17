/*==============================================================================
  21 - REPROCESAR EL VIAJE CON @Debug = 1  (ESCRIBE DATOS)

  ATENCION: ejecuta el SP: borra y vuelve a cargar las filas del viaje en
  Z_ItinerarioViaje y agrega lineas al Log. Usar solo despues de las demas.

  Devuelve 6 grillas, en este orden:
    1 ZONAS    : geocercas que uso el SP
    2 TRAMOS   : tramos finales (despues de las reglas, antes de cargar la tabla)
    3 EVENTOS  : eventos con zona y novedad
    4 a 6      : las 3 salidas normales del SP
  Guardar cada grilla por separado: clic derecho > Guardar resultados como...
==============================================================================*/
DECLARE @IdViaje INT = 330178;

EXEC dbo.Z_SP_ItinerarioViaje @IdViaje = @IdViaje, @Debug = 1;
