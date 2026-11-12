/*==============================================================================================
  Reporte 3.1 - Eventos de geocercas  -- DATOS SIMULADOS

  Una fila por ingreso / egreso de un vehiculo a una geocerca durante un viaje (23 eventos, 11 viajes).
  Es UNA sola consulta (WITH ... SELECT) y NO lee ninguna tabla real: los datos ficticios estan en los CTE
  Sim... (listas VALUES). Se puede ejecutar en cualquier base. Requiere SQL Server 2008 o superior.
  El archivo esta en UTF-8 con BOM (lleva tildes y el simbolo de grado).

  DEFINICIONES
    Incluye las paradas y tambien cruces de geocercas sin parada (ej. Base Anelo en el viaje 480208).
    Vehiculo = numero de vehiculo (el mismo del reporte de viajes y de gestion de vehiculos).
    ID de geocerca se corresponde con el Reporte 3.

  Para pasar a datos reales: reemplazar cada CTE Sim... por la tabla (o vista) real equivalente, con las mismas
  columnas; el SELECT final no cambia. Las equivalencias estan al final de Reportes_LP_Solidas_Simulado.sql y las
  que faltan confirmar se buscan con Descubrir_Esquema_Reportes.sql.
==============================================================================================*/

WITH
SimViaje AS (
    SELECT IdViaje,
        NumeroVehiculo
    FROM (VALUES
            (480201, N'SEM-0412'),
            (480202, N'SEM-0418'),
            (480203, N'CUA-0108'),
            (480204, N'SEM-0731'),
            (480205, N'SEM-0418'),
            (480206, N'SEM-0822'),
            (480207, N'CUA-0115'),
            (480208, N'SEM-0745'),
            (480209, N'SEM-0412'),
            (480210, N'SEM-0731'),
            (480211, N'SEM-0903'),
            (480212, N'CUA-0108')
         ) AS x(IdViaje, NumeroVehiculo)
),
SimEventoGeocerca AS (
    SELECT IdEvento,
        IdViaje,
        IdGeocerca,
        CAST(FechaIngreso AS DATETIME2(0)) AS FechaIngreso,
        CAST(FechaEgreso AS DATETIME2(0)) AS FechaEgreso
    FROM (VALUES
            (9001, 480201, 104, '2026-10-27T05:40:00', '2026-10-27T07:25:00'),
            (9002, 480201, 108, '2026-10-27T11:05:00', '2026-10-27T12:10:00'),
            (9003, 480202, 103, '2026-10-29T06:10:00', '2026-10-29T07:30:00'),
            (9004, 480202, 109, '2026-10-29T08:25:00', '2026-10-29T09:20:00'),
            (9005, 480202, 110, '2026-10-29T09:55:00', '2026-10-29T10:45:00'),
            (9006, 480203, 103, '2026-10-30T07:00:00', '2026-10-30T07:45:00'),
            (9007, 480203, 111, '2026-10-30T09:10:00', '2026-10-30T10:40:00'),
            (9008, 480204, 108, '2026-11-02T13:20:00', '2026-11-02T14:30:00'),
            (9009, 480204, 103, '2026-11-02T15:25:00', '2026-11-02T16:10:00'),
            (9010, 480205, 104, '2026-11-03T08:15:00', '2026-11-03T09:15:00'),
            (9011, 480205, 105, '2026-11-03T10:55:00', '2026-11-03T11:45:00'),
            (9012, 480206, 113, '2026-11-04T09:30:00', '2026-11-04T10:25:00'),
            (9013, 480206, 105, '2026-11-04T12:35:00', '2026-11-04T13:15:00'),
            (9014, 480207, 108, '2026-11-05T07:45:00', '2026-11-05T08:45:00'),
            (9015, 480207, 109, '2026-11-05T09:10:00', '2026-11-05T10:25:00'),
            (9016, 480208, 104, '2026-11-06T06:00:00', '2026-11-06T07:15:00'),
            (9017, 480208, 102, '2026-11-06T09:55:00', '2026-11-06T10:03:00'),
            (9018, 480208, 106, '2026-11-06T11:15:00', '2026-11-06T12:25:00'),
            (9019, 480209, 105, '2026-11-09T07:30:00', '2026-11-09T08:20:00'),
            (9020, 480209, 112, '2026-11-09T11:15:00', '2026-11-09T11:50:00'),
            (9021, 480210, 103, '2026-11-10T06:20:00', '2026-11-10T07:30:00'),
            (9022, 480210, 109, '2026-11-10T08:20:00', '2026-11-10T09:20:00'),
            (9023, 480211, 104, '2026-11-11T21:30:00', '2026-11-11T23:05:00')
         ) AS x(IdEvento, IdViaje, IdGeocerca, FechaIngreso, FechaEgreso)
)
SELECT
    e.IdViaje           AS [ID de viaje],
    e.FechaIngreso      AS [Fecha ingreso],
    e.FechaEgreso       AS [Fecha egreso],
    v.NumeroVehiculo    AS [Vehículo],
    e.IdGeocerca        AS [ID de geocerca]
FROM SimEventoGeocerca e
    JOIN SimViaje v ON v.IdViaje = e.IdViaje
ORDER BY e.IdViaje, e.FechaIngreso;
