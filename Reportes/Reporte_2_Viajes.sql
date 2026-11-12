/*==============================================================================================
  Reporte 2 - Datos de Viajes  -- DATOS SIMULADOS

  Una fila por viaje (12 viajes: 7 certificados, 3 finalizados, 1 en curso, 1 asignado).
  Es UNA sola consulta (WITH ... SELECT) y NO lee ninguna tabla real: los datos ficticios estan en los CTE
  Sim... (listas VALUES). Se puede ejecutar en cualquier base. Requiere SQL Server 2017 o superior (STRING_AGG).
  El archivo esta en UTF-8 con BOM (lleva tildes y el simbolo de grado).

  DEFINICIONES
    Fecha inicio / Fecha fin = ingreso a la primera geocerca / egreso de la ultima. Fecha finalizacion viaje =
    cierre del viaje en el sistema (posterior a la Fecha fin). KM liquidados, Costo del viaje y Fecha de
    certificacion solo existen en viajes Certificados. Costos en pesos (ARS). Origen / Destino: si hay varios se
    separan con " / ". Cada PAS genera un pick (origen) y un delivery (destino): "Cantidad de pick y delivery" se
    devuelve en dos columnas. Cuadrilla solo se completa en viajes de tipo Cuadrilla.
    Tipo de viaje: Cuadrilla | Semi. Tipo de operacion: Salida | Devolucion | Entre pozos | Entre almacenes |
    Recoleccion. Tipo de tarifa: Por km | Por viaje | Por hora | Diaria.

  Para pasar a datos reales: reemplazar cada CTE Sim... por la tabla (o vista) real equivalente, con las mismas
  columnas; el SELECT final no cambia. Las equivalencias estan al final de Reportes_LP_Solidas_Simulado.sql y las
  que faltan confirmar se buscan con Descubrir_Esquema_Reportes.sql.
==============================================================================================*/

WITH
SimGeocerca AS (
    SELECT IdGeocerca,
        NombreGeocerca
    FROM (VALUES
            (101, N'Base Neuquén Capital'),
            (102, N'Base Añelo'),
            (103, N'Almacén Añelo Central'),
            (104, N'Almacén Neuquén Parque Industrial'),
            (105, N'Almacén Plaza Huincul'),
            (106, N'Planta Loma Campana'),
            (107, N'Planta Rincón de los Sauces'),
            (108, N'Pozo LCa-1023'),
            (109, N'Pozo LCa-1187'),
            (110, N'Pozo BA-0412'),
            (111, N'Pozo AChi-0215'),
            (112, N'Cliente Servicios Petroleros del Sur'),
            (113, N'Cliente Metalúrgica del Valle')
         ) AS x(IdGeocerca, NombreGeocerca)
),
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
        TipoViaje,
        TipoOperacion,
        NumeroVehiculo,
        Chofer,
        Cuadrilla,
        EstadoViaje,
        CAST(FechaInicio AS DATETIME2(0)) AS FechaInicio,
        CAST(FechaFin AS DATETIME2(0)) AS FechaFin,
        KmPlanificados,
        KmLiquidados,
        TipoTarifa,
        CAST(CostoViaje AS DECIMAL(14,2)) AS CostoViaje,
        CAST(FechaCreacion AS DATETIME2(0)) AS FechaCreacion,
        CAST(FechaAsignacion AS DATETIME2(0)) AS FechaAsignacion,
        CAST(FechaFinalizacion AS DATETIME2(0)) AS FechaFinalizacion,
        CAST(FechaCertificacion AS DATETIME2(0)) AS FechaCertificacion
    FROM (VALUES
            (480201, N'Semi', N'Salida', N'SEM-0412', N'Marcelo Quiroga', NULL, N'Certificado', '2026-10-27T05:40:00', '2026-10-27T12:10:00', 152, 157, N'Por km', 525950, '2026-10-24T15:20:00', '2026-10-26T10:05:00', '2026-10-27T12:50:00', '2026-10-30T11:30:00'),
            (480202, N'Semi', N'Salida', N'SEM-0418', N'Héctor Almonacid', NULL, N'Certificado', '2026-10-29T06:10:00', '2026-10-29T10:45:00', 58, 61, N'Por km', 204350, '2026-10-27T09:10:00', '2026-10-28T11:45:00', '2026-10-29T11:10:00', '2026-11-03T10:20:00'),
            (480203, N'Cuadrilla', N'Salida', N'CUA-0108', N'Nahuel Cárdenas', N'Cuadrilla Montaje 01', N'Certificado', '2026-10-30T07:00:00', '2026-10-30T10:40:00', 62, 64, N'Diaria', 690000, '2026-10-28T13:00:00', '2026-10-29T15:30:00', '2026-10-30T11:35:00', '2026-11-03T10:20:00'),
            (480204, N'Semi', N'Devolución', N'SEM-0731', N'Sergio Painemil', NULL, N'Certificado', '2026-11-02T13:20:00', '2026-11-02T16:10:00', 34, 36, N'Por km', 120600, '2026-10-30T16:45:00', '2026-11-01T09:15:00', '2026-11-02T16:40:00', '2026-11-06T09:40:00'),
            (480205, N'Semi', N'Entre almacenes', N'SEM-0418', N'Diego Fuentealba', NULL, N'Certificado', '2026-11-03T08:15:00', '2026-11-03T11:45:00', 98, 100, N'Por viaje', 285000, '2026-11-01T10:20:00', '2026-11-02T08:05:00', '2026-11-03T12:05:00', '2026-11-06T09:40:00'),
            (480206, N'Semi', N'Recolección', N'SEM-0822', N'Raúl Sepúlveda', NULL, N'Certificado', '2026-11-04T09:30:00', '2026-11-04T13:15:00', 92, 95, N'Por hora', 296000, '2026-11-02T12:00:00', '2026-11-03T14:10:00', '2026-11-04T14:15:00', '2026-11-09T10:05:00'),
            (480207, N'Cuadrilla', N'Entre pozos', N'CUA-0115', N'Gustavo Millaqueo', N'Cuadrilla Izaje 03', N'Certificado', '2026-11-05T07:45:00', '2026-11-05T10:25:00', 9, 10, N'Diaria', 690000, '2026-11-03T14:30:00', '2026-11-04T10:00:00', '2026-11-05T11:10:00', '2026-11-09T10:05:00'),
            (480208, N'Semi', N'Salida', N'SEM-0745', N'Ariel Pereyra', NULL, N'Finalizado', '2026-11-06T06:00:00', '2026-11-06T12:25:00', 168, NULL, N'Por km', NULL, '2026-11-04T11:15:00', '2026-11-05T09:30:00', '2026-11-06T13:00:00', NULL),
            (480209, N'Semi', N'Salida', N'SEM-0412', N'Marcelo Quiroga', NULL, N'Finalizado', '2026-11-09T07:30:00', '2026-11-09T11:50:00', 128, NULL, N'Por km', NULL, '2026-11-06T13:40:00', '2026-11-07T12:25:00', '2026-11-09T12:40:00', NULL),
            (480210, N'Semi', N'Salida', N'SEM-0731', N'Sergio Painemil', NULL, N'Finalizado', '2026-11-10T06:20:00', '2026-11-10T09:20:00', 31, NULL, N'Por km', NULL, '2026-11-07T09:00:00', '2026-11-09T08:40:00', '2026-11-10T09:50:00', NULL),
            (480211, N'Semi', N'Salida', N'SEM-0903', N'Claudio Huenchumil', NULL, N'En curso', '2026-11-11T21:30:00', NULL, 334, NULL, N'Por km', NULL, '2026-11-10T19:00:00', '2026-11-11T10:30:00', NULL, NULL),
            (480212, N'Cuadrilla', N'Salida', N'CUA-0108', N'Nahuel Cárdenas', N'Cuadrilla Mantenimiento 05', N'Asignado', NULL, NULL, 29, NULL, N'Diaria', NULL, '2026-11-11T14:05:00', '2026-11-11T16:20:00', NULL, NULL)
         ) AS x(IdViaje, TipoViaje, TipoOperacion, NumeroVehiculo, Chofer, Cuadrilla, EstadoViaje, FechaInicio, FechaFin, KmPlanificados, KmLiquidados, TipoTarifa, CostoViaje, FechaCreacion, FechaAsignacion, FechaFinalizacion, FechaCertificacion)
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
-- ---- calculos del reporte ----
Tramos AS (            -- geocercas distintas de cada viaje, por tipo de parada y orden de aparicion
    SELECT IdViaje, TipoParada, IdGeocerca, MIN(Secuencia) AS Sec
    FROM SimParada
    GROUP BY IdViaje, TipoParada, IdGeocerca
),
TramoOrigen AS (
    SELECT t.IdViaje, STRING_AGG(g.NombreGeocerca, N' / ') WITHIN GROUP (ORDER BY t.Sec) AS Origen
    FROM Tramos t
        JOIN SimGeocerca g ON g.IdGeocerca = t.IdGeocerca
    WHERE t.TipoParada = N'PICK'
    GROUP BY t.IdViaje
),
TramoDestino AS (
    SELECT t.IdViaje, STRING_AGG(g.NombreGeocerca, N' / ') WITHIN GROUP (ORDER BY t.Sec) AS Destino
    FROM Tramos t
        JOIN SimGeocerca g ON g.IdGeocerca = t.IdGeocerca
    WHERE t.TipoParada = N'DELIVERY'
    GROUP BY t.IdViaje
),
Pedidos AS (
    SELECT IdViaje,
           STRING_AGG(NroPAS, N', ') WITHIN GROUP (ORDER BY NroPAS) AS PedidosAsociados
    FROM (SELECT DISTINCT IdViaje, NroPAS FROM SimParada) x
    GROUP BY IdViaje
),
Conteo AS (
    SELECT IdViaje,
           SUM(CASE WHEN TipoParada = N'PICK'     THEN 1 ELSE 0 END) AS CantPick,
           SUM(CASE WHEN TipoParada = N'DELIVERY' THEN 1 ELSE 0 END) AS CantDelivery
    FROM SimParada
    GROUP BY IdViaje
)
SELECT
    v.IdViaje                   AS [ID Viaje],
    v.TipoViaje                 AS [Tipo de viaje],
    v.TipoOperacion             AS [Tipo de operación],
    v.FechaInicio               AS [Fecha inicio],
    v.FechaFin                  AS [Fecha fin],
    o.Origen                    AS [Origen],
    d.Destino                   AS [Destino],
    ve.Transportista            AS [Transportista],
    v.NumeroVehiculo            AS [Vehículo],
    ve.Patente                  AS [Patente],
    v.Chofer                    AS [Chofer],
    v.Cuadrilla                 AS [Cuadrilla],
    v.EstadoViaje               AS [Estado viaje],
    pe.PedidosAsociados         AS [Pedidos asociados],
    v.KmLiquidados              AS [KM liquidados],
    v.KmPlanificados            AS [KM planificados],
    c.CantPick                  AS [Cantidad de pick],
    c.CantDelivery              AS [Cantidad de delivery],
    v.CostoViaje                AS [Costo del viaje asociado],
    v.TipoTarifa                AS [Tipo de tarifa],
    v.FechaCreacion             AS [Fecha de creación del viaje],
    v.FechaAsignacion           AS [Fecha de asignación del viaje],
    v.FechaFinalizacion         AS [Fecha finalización viaje],
    v.FechaCertificacion        AS [Fecha de certificación de viaje]
FROM SimViaje v
    JOIN SimVehiculo      ve ON ve.NumeroVehiculo = v.NumeroVehiculo
    LEFT JOIN TramoOrigen   o  ON o.IdViaje  = v.IdViaje
    LEFT JOIN TramoDestino  d  ON d.IdViaje  = v.IdViaje
    LEFT JOIN Pedidos       pe ON pe.IdViaje = v.IdViaje
    LEFT JOIN Conteo        c  ON c.IdViaje  = v.IdViaje
ORDER BY v.IdViaje;
