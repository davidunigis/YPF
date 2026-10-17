/*==============================================================================
  20 - RANGOS DE CAMBIO DE TURNO DEL TRANSPORTE DEL VIAJE

  Cambiar @IdViaje. Rangos cargados en Z_CambioTurnoTransporte para el transportista
  del vehiculo. Sin filas = la excepcion de cambio de turno no se aplica a este viaje.
==============================================================================*/
DECLARE @IdViaje INT = 330178;

SELECT CT.IdCambioTurno, CT.IdTransporte, T.RazonSocial AS Transporte,
       CT.HoraDesde, CT.DuracionMinutos, CT.Activo, CT.Observacion
FROM dbo.Z_CambioTurnoTransporte AS CT WITH (NOLOCK)
LEFT JOIN dbo.Transporte AS T WITH (NOLOCK) ON T.IdTransporte = CT.IdTransporte
WHERE CT.IdTransporte = (SELECT VH.IdTransporte
                         FROM dbo.Viaje AS V WITH (NOLOCK)
                         INNER JOIN dbo.Vehiculo AS VH WITH (NOLOCK) ON VH.IdVehiculo = V.IdVehiculo
                         WHERE V.IdViaje = @IdViaje)
ORDER BY CT.HoraDesde;
