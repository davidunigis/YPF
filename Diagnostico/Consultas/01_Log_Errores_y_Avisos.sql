/*==============================================================================
  01 - ERRORES Y AVISOS DEL SP EN EL LOG (solo lectura, sin viaje)

  Muestra lo que el SP escribio como ERROR o AVISO (viaje no encontrado, viaje sin
  eventos GPS validos). Un error de SQL que aborta el SP NO queda en el Log: para
  eso usar la consulta 02 (corridas que empezaron y no terminaron).
==============================================================================*/
DECLARE @Dias INT = 7;

SELECT TOP (1000) L.FechaHora, L.Categoria, L.Descripcion
FROM dbo.[Log] AS L WITH (NOLOCK)
WHERE L.FechaHora >= DATEADD(DAY, -@Dias, GETDATE())
  AND L.Categoria IN ('ERROR', 'AVISO')
  AND (L.Descripcion LIKE 'Viaje % sin eventos GPS%'
    OR L.Descripcion LIKE 'Viaje % no encontrado%'
    OR L.Descripcion LIKE '%Z_SP_ItinerarioViaje%')
ORDER BY L.FechaHora DESC;
