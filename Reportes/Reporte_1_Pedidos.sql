/*==============================================================================================
  Reporte 1 - Datos de Pedidos  -- DATOS SIMULADOS

  Una fila por PAS y material (16 PAS, 26 materiales).
  Es UNA sola consulta (WITH ... SELECT) y NO lee ninguna tabla real: los datos ficticios estan en los CTE
  Sim... (listas VALUES). Se puede ejecutar en cualquier base. Requiere SQL Server 2008 o superior.
  El archivo esta en UTF-8 con BOM (lleva tildes y el simbolo de grado).

  DEFINICIONES
    Fecha despacho = salida de la geocerca de origen. Fecha / Hora entrega = ingreso a la geocerca destino
    (en un pedido rechazado es la fecha y hora del intento de entrega). Cantidad entregada y rechazada quedan
    vacias mientras el pedido no se entrego (Programado, Pendiente de asignacion, En transito, Cancelado).
    Estados del pedido: Pendiente de asignacion | Programado | En transito | Entregado | Entregado parcial |
    Rechazado | Cancelado.

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
SimPAS AS (
    SELECT NroPAS,
        Prioridad,
        CAST(FechaCreacion AS DATETIME2(0)) AS FechaCreacion,
        CAST(FechaNecesidad AS DATE) AS FechaNecesidad,
        CAST(FechaCompromiso AS DATE) AS FechaCompromiso,
        IdGeocercaDestino,
        ClienteUnidadNegocio,
        CAST(FechaHoraDespacho AS DATETIME2(0)) AS FechaHoraDespacho,
        CAST(FechaHoraEntrega AS DATETIME2(0)) AS FechaHoraEntrega,
        MotivoIncumplimiento,
        EstadoPedido
    FROM (VALUES
            (N'PAS-004512', N'Normal', '2026-10-22T09:14:00', '2026-10-27', '2026-10-27', 108, N'YPF Upstream - UN Loma Campana', '2026-10-27T07:25:00', '2026-10-27T11:05:00', NULL, N'Entregado'),
            (N'PAS-004518', N'Urgente', '2026-10-26T16:40:00', '2026-10-29', '2026-10-29', 109, N'YPF Upstream - UN Loma Campana', '2026-10-29T07:30:00', '2026-10-29T08:25:00', NULL, N'Entregado'),
            (N'PAS-004519', N'Normal', '2026-10-26T16:52:00', '2026-10-29', '2026-10-29', 110, N'YPF Upstream - UN Bajada del Palo', '2026-10-29T07:30:00', '2026-10-29T09:55:00', NULL, N'Entregado parcial'),
            (N'PAS-004521', N'Alta', '2026-10-28T08:05:00', '2026-10-29', '2026-10-29', 111, N'YPF Upstream - UN La Amarga Chica', '2026-10-30T07:45:00', '2026-10-30T09:10:00', N'Falta de unidad disponible', N'Entregado'),
            (N'PAS-004530', N'Normal', '2026-10-30T11:20:00', '2026-11-02', '2026-11-02', 103, N'YPF Upstream - UN Loma Campana', '2026-11-02T14:30:00', '2026-11-02T15:25:00', NULL, N'Entregado'),
            (N'PAS-004533', N'Baja', '2026-10-30T15:00:00', '2026-11-02', '2026-11-02', 105, N'YPF Upstream - Abastecimiento Regional', '2026-11-03T09:15:00', '2026-11-03T10:55:00', N'Demora en preparación de material', N'Entregado'),
            (N'PAS-004536', N'Normal', '2026-11-02T10:30:00', '2026-11-04', '2026-11-04', 105, N'YPF Upstream - Abastecimiento Regional', '2026-11-04T10:25:00', '2026-11-04T12:35:00', NULL, N'Entregado'),
            (N'PAS-004541', N'Normal', '2026-11-03T09:00:00', '2026-11-05', '2026-11-05', 109, N'YPF Upstream - UN Loma Campana', '2026-11-05T08:45:00', '2026-11-05T09:10:00', NULL, N'Entregado'),
            (N'PAS-004544', N'Urgente', '2026-11-03T17:45:00', '2026-11-05', '2026-11-05', 106, N'YPF Upstream - UN Loma Campana', '2026-11-06T07:15:00', '2026-11-06T11:15:00', N'Condiciones climáticas', N'Entregado'),
            (N'PAS-004547', N'Alta', '2026-11-06T12:10:00', '2026-11-09', '2026-11-09', 112, N'Cliente externo - Servicios Petroleros del Sur', '2026-11-09T08:20:00', '2026-11-09T11:15:00', NULL, N'Rechazado'),
            (N'PAS-004550', N'Normal', '2026-11-07T08:30:00', '2026-11-10', '2026-11-10', 109, N'YPF Upstream - UN Loma Campana', '2026-11-10T07:30:00', '2026-11-10T08:20:00', N'Entrega incompleta por faltante de stock', N'Entregado parcial'),
            (N'PAS-004551', N'Alta', '2026-11-07T08:41:00', '2026-11-10', '2026-11-10', 109, N'YPF Upstream - UN Loma Campana', '2026-11-10T07:30:00', '2026-11-10T08:20:00', NULL, N'Entregado'),
            (N'PAS-004556', N'Urgente', '2026-11-10T18:20:00', '2026-11-12', '2026-11-12', 107, N'YPF Upstream - UN Rincón de los Sauces', '2026-11-11T23:05:00', NULL, NULL, N'En tránsito'),
            (N'PAS-004560', N'Normal', '2026-11-10T10:00:00', '2026-11-13', '2026-11-13', 110, N'YPF Upstream - UN Bajada del Palo', NULL, NULL, NULL, N'Programado'),
            (N'PAS-004562', N'Urgente', '2026-11-09T15:30:00', '2026-11-10', '2026-11-11', 106, N'YPF Upstream - UN Loma Campana', NULL, NULL, N'Sin stock en almacén de origen', N'Pendiente de asignación'),
            (N'PAS-004565', N'Baja', '2026-11-05T09:45:00', '2026-11-12', '2026-11-12', 107, N'YPF Upstream - UN Rincón de los Sauces', NULL, NULL, NULL, N'Cancelado')
         ) AS x(NroPAS, Prioridad, FechaCreacion, FechaNecesidad, FechaCompromiso, IdGeocercaDestino, ClienteUnidadNegocio, FechaHoraDespacho, FechaHoraEntrega, MotivoIncumplimiento, EstadoPedido)
),
SimPASItem AS (
    SELECT NroPAS,
        CodigoMaterial,
        DescripcionMaterial,
        CantidadSolicitada,
        CantidadEntregada,
        CantidadRechazada,
        MotivoRechazo
    FROM (VALUES
            (N'PAS-004512', N'10004512', N'Caño casing 9 5/8" P110 x 12 m', 60, 60, 0, NULL),
            (N'PAS-004512', N'10004533', N'Centralizador rígido 9 5/8"', 120, 120, 0, NULL),
            (N'PAS-004518', N'10007801', N'Válvula esclusa 3" 1500 psi', 8, 8, 0, NULL),
            (N'PAS-004518', N'10007815', N'Brida ciega 3" 1500 psi', 16, 16, 0, NULL),
            (N'PAS-004519', N'10009020', N'Cable eléctrico 3x6 mm² (bobina 500 m)', 10, 8, 2, N'Material dañado en transporte'),
            (N'PAS-004519', N'10009044', N'Terminal para cable 6 mm²', 200, 200, 0, NULL),
            (N'PAS-004521', N'10001203', N'Kit de herramientas de montaje', 4, 4, 0, NULL),
            (N'PAS-004521', N'10001260', N'Arnés de seguridad (EPP)', 12, 12, 0, NULL),
            (N'PAS-004530', N'10004512', N'Caño casing 9 5/8" P110 x 12 m', 14, 14, 0, NULL),
            (N'PAS-004533', N'10006650', N'Bomba centrífuga multietapa 60 HP', 2, 2, 0, NULL),
            (N'PAS-004533', N'10006671', N'Kit de sellos mecánicos', 6, 6, 0, NULL),
            (N'PAS-004536', N'10002990', N'Caño reacondicionado 2 7/8" (lote)', 40, 40, 0, NULL),
            (N'PAS-004541', N'10003310', N'Unidad de potencia hidráulica 150 HP', 1, 1, 0, NULL),
            (N'PAS-004541', N'10003322', N'Manguera hidráulica 2" x 15 m', 6, 6, 0, NULL),
            (N'PAS-004544', N'10007801', N'Válvula esclusa 3" 1500 psi', 12, 12, 0, NULL),
            (N'PAS-004544', N'10007890', N'Válvula de retención 4" 900#', 6, 6, 0, NULL),
            (N'PAS-004547', N'10005520', N'Aditivo antiespumante (IBC 1000 L)', 6, 0, 6, N'Documentación incompleta'),
            (N'PAS-004547', N'10005534', N'Biocida para fluidos (tambor 200 L)', 20, 0, 20, N'Documentación incompleta'),
            (N'PAS-004550', N'10008105', N'Tubing 2 7/8" N80 x 9,5 m', 150, 150, 0, NULL),
            (N'PAS-004550', N'10008119', N'Niple de asiento 2 7/8"', 40, 30, 0, NULL),
            (N'PAS-004551', N'10009301', N'Packer de producción 7"', 3, 3, 0, NULL),
            (N'PAS-004556', N'10010045', N'Kit de mantenimiento de compresor (8000 h)', 2, NULL, NULL, NULL),
            (N'PAS-004560', N'10001203', N'Kit de herramientas de montaje', 2, NULL, NULL, NULL),
            (N'PAS-004560', N'10001260', N'Arnés de seguridad (EPP)', 6, NULL, NULL, NULL),
            (N'PAS-004562', N'10006650', N'Bomba centrífuga multietapa 60 HP', 1, NULL, NULL, NULL),
            (N'PAS-004565', N'10002210', N'Cemento Clase G (big bag 1,5 t)', 30, NULL, NULL, NULL)
         ) AS x(NroPAS, CodigoMaterial, DescripcionMaterial, CantidadSolicitada, CantidadEntregada, CantidadRechazada, MotivoRechazo)
)
SELECT
    p.NroPAS                                AS [N° PAS],
    p.Prioridad                             AS [Prioridad],
    p.FechaCreacion                         AS [Fecha creación PAS],
    p.FechaNecesidad                        AS [Fecha necesidad PAS],
    p.FechaCompromiso                       AS [Fecha compromiso],
    g.NombreGeocerca                        AS [Destino],
    p.ClienteUnidadNegocio                  AS [Cliente / Unidad de Negocio],
    i.CodigoMaterial                        AS [Material],
    i.DescripcionMaterial                   AS [Descripción material],
    i.CantidadSolicitada                    AS [Cantidad solicitada],
    i.CantidadEntregada                     AS [Cantidad entregada],
    i.CantidadRechazada                     AS [Cantidad rechazada],
    CAST(p.FechaHoraDespacho AS DATE)       AS [Fecha despacho],
    CAST(p.FechaHoraEntrega  AS DATE)       AS [Fecha entrega],
    CAST(p.FechaHoraEntrega  AS TIME(0))    AS [Hora entrega],
    i.MotivoRechazo                         AS [Motivo de rechazo],
    p.MotivoIncumplimiento                  AS [Motivo de incumplimiento],
    p.EstadoPedido                          AS [Estado del pedido]
FROM SimPAS p
    JOIN SimPASItem  i ON i.NroPAS = p.NroPAS
    JOIN SimGeocerca g ON g.IdGeocerca = p.IdGeocercaDestino
ORDER BY p.FechaCreacion, p.NroPAS, i.CodigoMaterial;
