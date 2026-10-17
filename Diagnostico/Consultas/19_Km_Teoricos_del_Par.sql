/*==============================================================================
  19 - KM TEORICOS: PAR ORIGEN-DESTINO QUE BUSCA EL SP Y LO QUE HAY EN Z_KmTeoricos

  Cambiar @IdViaje. La primera fila (Orden 0) muestra los nombres exactos que busca
  el SP (deposito de salida y ultima parada de descarga, sin espacios a los lados).
  Debajo, las filas de Z_KmTeoricos que coinciden en origen y/o destino. Si
  CoincideOrigen y CoincideDestino no son ambas 1 en ninguna fila, el par no existe
  (o el nombre difiere en alguna letra) y los km teoricos salen vacios.
==============================================================================*/
DECLARE @IdViaje INT = 330178;
DECLARE @Origen VARCHAR(150), @Destino VARCHAR(150);

SELECT @Origen = LTRIM(RTRIM(D.Descripcion))
FROM dbo.Viaje AS V WITH (NOLOCK)
LEFT JOIN dbo.Deposito AS D WITH (NOLOCK) ON D.IdDeposito = V.IdDepositoSalida
WHERE V.IdViaje = @IdViaje;

SELECT TOP 1 @Destino = LTRIM(RTRIM(C.Descripcion))
FROM dbo.Z_ClasificarParadasViaje(@IdViaje) AS C
WHERE C.ClaseParada = 'DESCARGA'
ORDER BY C.Orden DESC;

SELECT 0 AS Orden, CAST(NULL AS INT) AS Id, @Origen AS Origen, @Destino AS Destino,
       CAST(NULL AS DECIMAL(12,2)) AS DistanciaKmTeoricos, CAST(NULL AS DECIMAL(12,2)) AS TiempoEstandar,
       CAST(NULL AS DECIMAL(12,2)) AS CicloKmTeoricos,
       CAST(NULL AS INT) AS CoincideOrigen, CAST(NULL AS INT) AS CoincideDestino,
       'NOMBRES QUE BUSCA EL SP' AS Nota
UNION ALL
SELECT 1, K.Id, K.Origen, K.Destino, K.DistanciaKmTeoricos, K.TiempoEstandar, K.CicloKmTeoricos,
       CASE WHEN LTRIM(RTRIM(K.Origen)) = @Origen THEN 1 ELSE 0 END,
       CASE WHEN LTRIM(RTRIM(K.Destino)) = @Destino THEN 1 ELSE 0 END,
       CASE WHEN LTRIM(RTRIM(K.Origen)) = @Origen AND LTRIM(RTRIM(K.Destino)) = @Destino THEN 'PAR EXACTO' ELSE 'coincide solo un lado' END
FROM dbo.Z_KmTeoricos AS K WITH (NOLOCK)
WHERE LTRIM(RTRIM(K.Origen)) = @Origen OR LTRIM(RTRIM(K.Destino)) = @Destino
ORDER BY Orden, CoincideOrigen DESC, CoincideDestino DESC, Id DESC;
