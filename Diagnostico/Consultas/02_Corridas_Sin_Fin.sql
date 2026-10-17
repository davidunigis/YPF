/*==============================================================================
  02 - CORRIDAS DEL SP QUE EMPEZARON Y NO TERMINARON (solo lectura, sin viaje)

  El SP escribe INICIO al arrancar y FIN al terminar. Una corrida con INICIO y sin
  FIN abortó por un error (o sigue corriendo). Las primeras filas son las que
  fallaron. Pasarme las filas con Estado = 'SIN FIN' y el IdViaje de cada una.
==============================================================================*/
DECLARE @Dias INT = 7;

;WITH Ini AS (
    SELECT L.FechaHora AS Inicio,
           TRY_CAST(LTRIM(RTRIM(SUBSTRING(L.Descripcion, CHARINDEX('IdViaje:', L.Descripcion) + 8, 20))) AS INT) AS IdViaje
    FROM dbo.[Log] AS L WITH (NOLOCK)
    WHERE L.Categoria = 'INICIO'
      AND L.Descripcion LIKE 'Z_SP_ItinerarioViaje | IdViaje:%'
      AND L.FechaHora >= DATEADD(DAY, -@Dias, GETDATE())
),
Fin AS (
    SELECT L.FechaHora AS Fin,
           TRY_CAST(LTRIM(RTRIM(SUBSTRING(L.Descripcion, CHARINDEX('IdViaje:', L.Descripcion) + 8, 20))) AS INT) AS IdViaje
    FROM dbo.[Log] AS L WITH (NOLOCK)
    WHERE L.Categoria = 'FIN'
      AND L.Descripcion LIKE 'Z_SP_ItinerarioViaje finalizado | IdViaje:%'
      AND L.FechaHora >= DATEADD(DAY, -@Dias, GETDATE())
)
SELECT I.IdViaje,
       I.Inicio,
       F.Fin,
       CASE WHEN F.Fin IS NULL THEN 'SIN FIN' ELSE 'OK' END AS Estado,
       DATEDIFF(SECOND, I.Inicio, F.Fin) AS SegundosDeCorrida,
       (SELECT COUNT(*) FROM dbo.Z_ItinerarioViaje AS Z WITH (NOLOCK) WHERE Z.IdViaje = I.IdViaje) AS FilasEnZ
FROM Ini AS I
OUTER APPLY (SELECT MIN(X.Fin) AS Fin FROM Fin AS X WHERE X.IdViaje = I.IdViaje AND X.Fin >= I.Inicio) AS F
ORDER BY CASE WHEN F.Fin IS NULL THEN 0 ELSE 1 END, I.Inicio DESC;
