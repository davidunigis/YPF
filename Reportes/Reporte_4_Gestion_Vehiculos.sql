/*==============================================================================================
  Reporte 4 - Gestión de vehículos  -- DATOS SIMULADOS

  Una fila por viaje con Fecha fin (10 viajes). Tiempos en minutos.
  Es UNA sola consulta (WITH ... SELECT) y NO lee ninguna tabla real: los datos ficticios estan en los CTE
  Sim... (listas VALUES). Se puede ejecutar en cualquier base. Requiere SQL Server 2008 o superior.
  El archivo esta en UTF-8 con BOM (lleva tildes y el simbolo de grado).

  DEFINICIONES
    Tiempo en carga    = permanencia en las geocercas de origen del viaje (pick).
    Tiempo en descarga = permanencia en las geocercas de destino del viaje (delivery).
    Tiempo detenido fuera de geocerca = detenciones registradas fuera de toda geocerca.
    Tiempo carreteando = resto del tiempo del viaje fuera de geocercas (en movimiento).
    Los cruces de geocerca sin parada no entran en ninguna de las cuatro mediciones.
    Viaje = desde Fecha inicio (ingreso a la primera geocerca) hasta Fecha fin (egreso de la ultima).

  Para pasar a datos reales: reemplazar cada CTE Sim... por la tabla (o vista) real equivalente, con las mismas
  columnas; el SELECT final no cambia. Las equivalencias estan al final de Reportes_LP_Solidas_Simulado.sql y las
  que faltan confirmar se buscan con Descubrir_Esquema_Reportes.sql.
==============================================================================================*/

WITH
SimVehiculo AS (
    SELECT NumeroVehiculo,
        Patente,
        Transportista
    FROM (VALUES
            (N'SEM-0412', N'AF412KM', N'Transportes Patagonia SA'),
            (N'SEM-0418', N'AG418PL', N'Transportes Patagonia SA'),
            (N'SEM-0731', N'AE731RT', N'Logística Vaca Muerta SRL'),
            (N'SEM-0745', N'AH745TC', N'Logística Vaca Muerta SRL'),
            (N'SEM-0822', N'AD822NB', N'Cargas del Comahue SA'),
            (N'CUA-0108', N'AF108QS', N'Cargas del Comahue SA'),
            (N'CUA-0115', N'AG115VM', N'TransAndes Energía SRL'),
            (N'SEM-0903', N'AH903ZL', N'TransAndes Energía SRL')
         ) AS x(NumeroVehiculo, Patente, Transportista)
),
SimViaje AS (
    SELECT IdViaje,
        NumeroVehiculo,
        CAST(FechaInicio AS DATETIME2(0)) AS FechaInicio,
        CAST(FechaFin AS DATETIME2(0)) AS FechaFin
    FROM (VALUES
            (480201, N'SEM-0412', '2026-10-27T05:40:00', '2026-10-27T12:10:00'),
            (480202, N'SEM-0418', '2026-10-29T06:10:00', '2026-10-29T10:45:00'),
            (480203, N'CUA-0108', '2026-10-30T07:00:00', '2026-10-30T10:40:00'),
            (480204, N'SEM-0731', '2026-11-02T13:20:00', '2026-11-02T16:10:00'),
            (480205, N'SEM-0418', '2026-11-03T08:15:00', '2026-11-03T11:45:00'),
            (480206, N'SEM-0822', '2026-11-04T09:30:00', '2026-11-04T13:15:00'),
            (480207, N'CUA-0115', '2026-11-05T07:45:00', '2026-11-05T10:25:00'),
            (480208, N'SEM-0745', '2026-11-06T06:00:00', '2026-11-06T12:25:00'),
            (480209, N'SEM-0412', '2026-11-09T07:30:00', '2026-11-09T11:50:00'),
            (480210, N'SEM-0731', '2026-11-10T06:20:00', '2026-11-10T09:20:00'),
            (480211, N'SEM-0903', '2026-11-11T21:30:00', NULL),
            (480212, N'CUA-0108', NULL, NULL)
         ) AS x(IdViaje, NumeroVehiculo, FechaInicio, FechaFin)
),
SimParada AS (
    SELECT IdViaje,
        Secuencia,
        TipoParada,
        IdGeocerca,
        NroPAS
    FROM (VALUES
            (480201, 1, N'PICK', 104, N'PAS-004512'),
            (480201, 2, N'DELIVERY', 108, N'PAS-004512'),
            (480202, 1, N'PICK', 103, N'PAS-004518'),
            (480202, 2, N'PICK', 103, N'PAS-004519'),
            (480202, 3, N'DELIVERY', 109, N'PAS-004518'),
            (480202, 4, N'DELIVERY', 110, N'PAS-004519'),
            (480203, 1, N'PICK', 103, N'PAS-004521'),
            (480203, 2, N'DELIVERY', 111, N'PAS-004521'),
            (480204, 1, N'PICK', 108, N'PAS-004530'),
            (480204, 2, N'DELIVERY', 103, N'PAS-004530'),
            (480205, 1, N'PICK', 104, N'PAS-004533'),
            (480205, 2, N'DELIVERY', 105, N'PAS-004533'),
            (480206, 1, N'PICK', 113, N'PAS-004536'),
            (480206, 2, N'DELIVERY', 105, N'PAS-004536'),
            (480207, 1, N'PICK', 108, N'PAS-004541'),
            (480207, 2, N'DELIVERY', 109, N'PAS-004541'),
            (480208, 1, N'PICK', 104, N'PAS-004544'),
            (480208, 2, N'DELIVERY', 106, N'PAS-004544'),
            (480209, 1, N'PICK', 105, N'PAS-004547'),
            (480209, 2, N'DELIVERY', 112, N'PAS-004547'),
            (480210, 1, N'PICK', 103, N'PAS-004550'),
            (480210, 2, N'PICK', 103, N'PAS-004551'),
            (480210, 3, N'DELIVERY', 109, N'PAS-004550'),
            (480210, 4, N'DELIVERY', 109, N'PAS-004551'),
            (480211, 1, N'PICK', 104, N'PAS-004556'),
            (480211, 2, N'DELIVERY', 107, N'PAS-004556'),
            (480212, 1, N'PICK', 103, N'PAS-004560'),
            (480212, 2, N'DELIVERY', 110, N'PAS-004560')
         ) AS x(IdViaje, Secuencia, TipoParada, IdGeocerca, NroPAS)
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
),
SimDetencionFueraGeocerca AS (
    SELECT IdViaje,
        CAST(FechaInicio AS DATETIME2(0)) AS FechaInicio,
        CAST(FechaFin AS DATETIME2(0)) AS FechaFin,
        Motivo
    FROM (VALUES
            (480201, '2026-10-27T08:35:00', '2026-10-27T09:00:00', N'Control vial en ruta'),
            (480202, '2026-10-29T07:55:00', '2026-10-29T08:05:00', N'Descanso del chofer'),
            (480204, '2026-11-02T14:50:00', '2026-11-02T15:05:00', N'Espera por tránsito de equipos'),
            (480206, '2026-11-04T11:05:00', '2026-11-04T11:25:00', N'Cambio de neumático'),
            (480208, '2026-11-06T08:55:00', '2026-11-06T09:35:00', N'Descanso del chofer'),
            (480209, '2026-11-09T09:50:00', '2026-11-09T10:05:00', N'Control de gendarmería')
         ) AS x(IdViaje, FechaInicio, FechaFin, Motivo)
),
-- ---- calculos del reporte ----
RolGeocerca AS (       -- que papel cumple cada geocerca dentro de cada viaje
    SELECT IdViaje, IdGeocerca,
           MAX(CASE WHEN TipoParada = N'PICK'     THEN 1 ELSE 0 END) AS EsPick,
           MAX(CASE WHEN TipoParada = N'DELIVERY' THEN 1 ELSE 0 END) AS EsDelivery
    FROM SimParada
    GROUP BY IdViaje, IdGeocerca
),
Permanencias AS (
    SELECT e.IdViaje,
           SUM(CASE WHEN r.EsPick = 1     AND r.EsDelivery = 0 THEN DATEDIFF(MINUTE, e.FechaIngreso, e.FechaEgreso) ELSE 0 END) AS MinCarga,
           SUM(CASE WHEN r.EsDelivery = 1 AND r.EsPick = 0     THEN DATEDIFF(MINUTE, e.FechaIngreso, e.FechaEgreso) ELSE 0 END) AS MinDescarga,
           SUM(DATEDIFF(MINUTE, e.FechaIngreso, e.FechaEgreso)) AS MinEnGeocercas        -- incluye cruces sin parada
    FROM SimEventoGeocerca e
        LEFT JOIN RolGeocerca r ON r.IdViaje = e.IdViaje AND r.IdGeocerca = e.IdGeocerca
    WHERE e.FechaEgreso IS NOT NULL
    GROUP BY e.IdViaje
),
Detenido AS (
    SELECT IdViaje, SUM(DATEDIFF(MINUTE, FechaInicio, FechaFin)) AS MinDetenido
    FROM SimDetencionFueraGeocerca
    GROUP BY IdViaje
)
SELECT
    v.IdViaje                                   AS [Id de viaje],
    ve.Patente                                  AS [Patente],
    v.NumeroVehiculo                            AS [Número de vehículo],
    p.MinCarga                                  AS [Tiempo en carga (min)],
    p.MinDescarga                               AS [Tiempo en descarga (min)],
    DATEDIFF(MINUTE, v.FechaInicio, v.FechaFin)
        - p.MinEnGeocercas
        - ISNULL(d.MinDetenido, 0)              AS [Tiempo carreteando (min)],
    ISNULL(d.MinDetenido, 0)                    AS [Tiempo detenido fuera de geocerca (min)]
FROM SimViaje v
    JOIN SimVehiculo   ve ON ve.NumeroVehiculo = v.NumeroVehiculo
    JOIN Permanencias  p  ON p.IdViaje = v.IdViaje
    LEFT JOIN Detenido d  ON d.IdViaje = v.IdViaje
WHERE v.FechaFin IS NOT NULL
ORDER BY v.IdViaje;
