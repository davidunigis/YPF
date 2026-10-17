/*==============================================================================
  14 - LOG DE LA ULTIMA CORRIDA DEL SP PARA EL VIAJE

  Cambiar @IdViaje. Desde el ultimo INICIO del viaje hasta su FIN (o hasta ahora si
  no hay FIN): pasos, conteos de geocercas, novedades, combustible previo del dia,
  fin de carga y demoras. El Log no guarda el IdViaje en los pasos intermedios,
  asi que si dos corridas se pisaron en el tiempo pueden aparecer lineas de otro viaje.
==============================================================================*/
DECLARE @IdViaje INT = 330178;
DECLARE @Inicio DATETIME, @Fin DATETIME;

SELECT @Inicio = MAX(L.FechaHora)
FROM dbo.[Log] AS L WITH (NOLOCK)
WHERE L.Categoria = 'INICIO'
  AND L.Descripcion = 'Z_SP_ItinerarioViaje | IdViaje: ' + CAST(@IdViaje AS VARCHAR(12));

SELECT @Fin = MIN(L.FechaHora)
FROM dbo.[Log] AS L WITH (NOLOCK)
WHERE L.Categoria = 'FIN'
  AND L.Descripcion = 'Z_SP_ItinerarioViaje finalizado | IdViaje: ' + CAST(@IdViaje AS VARCHAR(12))
  AND L.FechaHora >= @Inicio;

SELECT L.FechaHora, L.Categoria, L.Descripcion
FROM dbo.[Log] AS L WITH (NOLOCK)
WHERE @Inicio IS NOT NULL
  AND L.FechaHora >= @Inicio
  AND L.FechaHora <= ISNULL(@Fin, GETDATE())
ORDER BY L.FechaHora;
