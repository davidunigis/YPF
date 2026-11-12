/*==============================================================================================
  Reportes_LP_Solidas_Simulado.sql

  Reportes de LP Solidas con DATOS SIMULADOS, para la presentacion.
  Devuelve 5 resultados, con las columnas pedidas, en este orden:
     1)   Datos de Pedidos                      (una fila por PAS y material)
     2)   Datos de Viajes                       (una fila por viaje)
     3)   Datos de Geocercas cargadas           (una fila por geocerca)
     3.1) Eventos de geocercas                  (una fila por ingreso/egreso de un vehiculo a una geocerca)
     4)   Gestion de vehiculos                  (una fila por viaje finalizado)

  COMO USARLO
    Ejecutar el script completo (F5 en SSMS). Solo crea tablas temporales (#...): NO lee ni modifica
    ninguna tabla real y se puede correr en cualquier base. Se puede volver a correr las veces que haga
    falta (borra y recrea las temporales). Requiere SQL Server 2017 o superior (STRING_AGG).
    El archivo esta en UTF-8 con BOM (lleva tildes y el simbolo de grado).

  DATOS SIMULADOS
    16 PAS (26 materiales), 12 viajes, 13 geocercas, 8 vehiculos. Los datos son ficticios pero coherentes
    entre si: la fecha de despacho/entrega de cada PAS sale de los eventos de geocerca de su viaje, y los
    tiempos de la gestion de vehiculos se calculan a partir de esos mismos eventos. Hay casos de entrega
    completa, parcial, con rechazo, con incumplimiento de fecha compromiso, en transito, programado,
    pendiente y cancelado. Hoy simulado: 12/11/2026. Importes en pesos (ARS).

  DEFINICIONES USADAS (ajustar si el cliente las entiende distinto)
    - Pedidos: Fecha despacho = salida de la geocerca de origen; Fecha/Hora entrega = ingreso a la
      geocerca destino (en un pedido rechazado es la fecha/hora del intento de entrega).
    - Viajes: Fecha inicio / Fecha fin = ingreso a la primera geocerca / egreso de la ultima.
      Fecha finalizacion viaje = cierre del viaje en el sistema (posterior a la Fecha fin).
      KM liquidados, Costo del viaje y Fecha de certificacion solo existen en viajes Certificados.
      Origen / Destino: si hay varios, se separan con " / ".
      "Cantidad de pick y delivery" se devuelve en dos columnas: Cantidad de pick y Cantidad de delivery.
      Cada PAS genera un pick (en el origen) y un delivery (en el destino).
      Cuadrilla solo se completa en los viajes de tipo Cuadrilla.
    - Eventos de geocerca: incluye las paradas y tambien cruces de geocercas sin parada (ej. Base Anelo).
      Vehiculo = numero de vehiculo (el mismo del reporte de viajes y de la gestion de vehiculos).
    - Gestion de vehiculos (en minutos, solo viajes con Fecha fin):
        Tiempo en carga    = permanencia en geocercas de origen (pick)
        Tiempo en descarga = permanencia en geocercas de destino (delivery)
        Tiempo detenido fuera de geocerca = detenciones registradas fuera de toda geocerca
        Tiempo carreteando = resto del tiempo fuera de geocercas (en movimiento)
      Los cruces sin parada no entran en ninguna de las cuatro mediciones.
==============================================================================================*/
SET NOCOUNT ON;


-- ============================================================================================
-- 1) DATOS SIMULADOS (tablas temporales)
-- ============================================================================================
DROP TABLE IF EXISTS #DetencionFueraGeocerca;
DROP TABLE IF EXISTS #EventoGeocerca;
DROP TABLE IF EXISTS #Parada;
DROP TABLE IF EXISTS #Viaje;
DROP TABLE IF EXISTS #PASItem;
DROP TABLE IF EXISTS #PAS;
DROP TABLE IF EXISTS #Vehiculo;
DROP TABLE IF EXISTS #Geocerca;

CREATE TABLE #Geocerca (
    IdGeocerca      INT           NOT NULL PRIMARY KEY,
    NombreGeocerca  NVARCHAR(100) NOT NULL,
    TipoGeocerca    NVARCHAR(20)  NOT NULL,   -- Base | Almacén | Pozo | Cliente | Planta
    Latitud         DECIMAL(9,6)  NOT NULL,
    Longitud        DECIMAL(9,6)  NOT NULL,
    RadioMetros     INT           NOT NULL
);

CREATE TABLE #Vehiculo (
    NumeroVehiculo  NVARCHAR(20)  NOT NULL PRIMARY KEY,
    Patente         NVARCHAR(10)  NOT NULL,
    Transportista   NVARCHAR(100) NOT NULL
);

CREATE TABLE #PAS (                            -- cabecera del pedido
    NroPAS               NVARCHAR(20)  NOT NULL PRIMARY KEY,
    Prioridad            NVARCHAR(20)  NOT NULL,   -- Urgente | Alta | Normal | Baja
    FechaCreacion        DATETIME2(0)  NOT NULL,
    FechaNecesidad       DATE          NOT NULL,
    FechaCompromiso      DATE          NOT NULL,
    IdGeocercaDestino    INT           NOT NULL,
    ClienteUnidadNegocio NVARCHAR(100) NOT NULL,
    FechaHoraDespacho    DATETIME2(0)  NULL,
    FechaHoraEntrega     DATETIME2(0)  NULL,
    MotivoIncumplimiento NVARCHAR(100) NULL,
    EstadoPedido         NVARCHAR(30)  NOT NULL
);

CREATE TABLE #PASItem (                        -- materiales del pedido
    NroPAS               NVARCHAR(20)  NOT NULL,
    CodigoMaterial       NVARCHAR(20)  NOT NULL,
    DescripcionMaterial  NVARCHAR(120) NOT NULL,
    CantidadSolicitada   INT           NOT NULL,
    CantidadEntregada    INT           NULL,
    CantidadRechazada    INT           NULL,
    MotivoRechazo        NVARCHAR(100) NULL,
    PRIMARY KEY (NroPAS, CodigoMaterial)
);

CREATE TABLE #Viaje (
    IdViaje            INT           NOT NULL PRIMARY KEY,
    TipoViaje          NVARCHAR(20)  NOT NULL,   -- Cuadrilla | Semi
    TipoOperacion      NVARCHAR(30)  NOT NULL,   -- Salida | Devolución | Entre pozos | Entre almacenes | Recolección
    NumeroVehiculo     NVARCHAR(20)  NOT NULL,
    Chofer             NVARCHAR(100) NOT NULL,
    Cuadrilla          NVARCHAR(100) NULL,
    EstadoViaje        NVARCHAR(20)  NOT NULL,   -- Asignado | En curso | Finalizado | Certificado
    FechaInicio        DATETIME2(0)  NULL,
    FechaFin           DATETIME2(0)  NULL,
    KmPlanificados     INT           NOT NULL,
    KmLiquidados       INT           NULL,
    TipoTarifa         NVARCHAR(20)  NOT NULL,   -- Por km | Por viaje | Por hora | Diaria
    CostoViaje         DECIMAL(14,2) NULL,
    FechaCreacion      DATETIME2(0)  NOT NULL,
    FechaAsignacion    DATETIME2(0)  NOT NULL,
    FechaFinalizacion  DATETIME2(0)  NULL,
    FechaCertificacion DATETIME2(0)  NULL
);

CREATE TABLE #Parada (                         -- un pick y un delivery por cada PAS del viaje
    IdViaje       INT          NOT NULL,
    Secuencia     INT          NOT NULL,
    TipoParada    NVARCHAR(10) NOT NULL,         -- PICK | DELIVERY
    IdGeocerca    INT          NOT NULL,
    NroPAS        NVARCHAR(20) NOT NULL,
    PRIMARY KEY (IdViaje, Secuencia)
);

CREATE TABLE #EventoGeocerca (
    IdEvento      INT          NOT NULL PRIMARY KEY,
    IdViaje       INT          NOT NULL,
    IdGeocerca    INT          NOT NULL,
    FechaIngreso  DATETIME2(0) NOT NULL,
    FechaEgreso   DATETIME2(0) NULL
);

CREATE TABLE #DetencionFueraGeocerca (
    IdViaje       INT           NOT NULL,
    FechaInicio   DATETIME2(0)  NOT NULL,
    FechaFin      DATETIME2(0)  NOT NULL,
    Motivo        NVARCHAR(100) NULL
);

INSERT INTO #Geocerca (IdGeocerca, NombreGeocerca, TipoGeocerca, Latitud, Longitud, RadioMetros) VALUES
    (101, N'Base Neuquén Capital', N'Base', -38.951600, -68.059100, 300),
    (102, N'Base Añelo', N'Base', -38.353500, -68.790300, 400),
    (103, N'Almacén Añelo Central', N'Almacén', -38.360100, -68.785200, 250),
    (104, N'Almacén Neuquén Parque Industrial', N'Almacén', -38.929800, -68.124500, 300),
    (105, N'Almacén Plaza Huincul', N'Almacén', -38.933000, -69.206000, 250),
    (106, N'Planta Loma Campana', N'Planta', -38.470000, -68.940000, 600),
    (107, N'Planta Rincón de los Sauces', N'Planta', -37.406000, -68.933000, 500),
    (108, N'Pozo LCa-1023', N'Pozo', -38.512000, -68.901000, 150),
    (109, N'Pozo LCa-1187', N'Pozo', -38.523000, -68.875000, 150),
    (110, N'Pozo BA-0412', N'Pozo', -38.445000, -68.965000, 150),
    (111, N'Pozo AChi-0215', N'Pozo', -38.248000, -69.042000, 150),
    (112, N'Cliente Servicios Petroleros del Sur', N'Cliente', -38.358000, -68.799000, 200),
    (113, N'Cliente Metalúrgica del Valle', N'Cliente', -38.960000, -68.230000, 200);

INSERT INTO #Vehiculo (NumeroVehiculo, Patente, Transportista) VALUES
    (N'SEM-0412', N'AF412KM', N'Transportes Patagonia SA'),
    (N'SEM-0418', N'AG418PL', N'Transportes Patagonia SA'),
    (N'SEM-0731', N'AE731RT', N'Logística Vaca Muerta SRL'),
    (N'SEM-0745', N'AH745TC', N'Logística Vaca Muerta SRL'),
    (N'SEM-0822', N'AD822NB', N'Cargas del Comahue SA'),
    (N'CUA-0108', N'AF108QS', N'Cargas del Comahue SA'),
    (N'CUA-0115', N'AG115VM', N'TransAndes Energía SRL'),
    (N'SEM-0903', N'AH903ZL', N'TransAndes Energía SRL');

INSERT INTO #PAS (NroPAS, Prioridad, FechaCreacion, FechaNecesidad, FechaCompromiso, IdGeocercaDestino,
                  ClienteUnidadNegocio, FechaHoraDespacho, FechaHoraEntrega, MotivoIncumplimiento, EstadoPedido) VALUES
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
    (N'PAS-004565', N'Baja', '2026-11-05T09:45:00', '2026-11-12', '2026-11-12', 107, N'YPF Upstream - UN Rincón de los Sauces', NULL, NULL, NULL, N'Cancelado');

INSERT INTO #PASItem (NroPAS, CodigoMaterial, DescripcionMaterial, CantidadSolicitada, CantidadEntregada,
                      CantidadRechazada, MotivoRechazo) VALUES
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
    (N'PAS-004565', N'10002210', N'Cemento Clase G (big bag 1,5 t)', 30, NULL, NULL, NULL);

INSERT INTO #Viaje (IdViaje, TipoViaje, TipoOperacion, NumeroVehiculo, Chofer, Cuadrilla, EstadoViaje, FechaInicio, FechaFin,
                    KmPlanificados, KmLiquidados, TipoTarifa, CostoViaje, FechaCreacion, FechaAsignacion,
                    FechaFinalizacion, FechaCertificacion) VALUES
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
    (480212, N'Cuadrilla', N'Salida', N'CUA-0108', N'Nahuel Cárdenas', N'Cuadrilla Mantenimiento 05', N'Asignado', NULL, NULL, 29, NULL, N'Diaria', NULL, '2026-11-11T14:05:00', '2026-11-11T16:20:00', NULL, NULL);

INSERT INTO #Parada (IdViaje, Secuencia, TipoParada, IdGeocerca, NroPAS) VALUES
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
    (480212, 2, N'DELIVERY', 110, N'PAS-004560');

INSERT INTO #EventoGeocerca (IdEvento, IdViaje, IdGeocerca, FechaIngreso, FechaEgreso) VALUES
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
    (9023, 480211, 104, '2026-11-11T21:30:00', '2026-11-11T23:05:00');

INSERT INTO #DetencionFueraGeocerca (IdViaje, FechaInicio, FechaFin, Motivo) VALUES
    (480201, '2026-10-27T08:35:00', '2026-10-27T09:00:00', N'Control vial en ruta'),
    (480202, '2026-10-29T07:55:00', '2026-10-29T08:05:00', N'Descanso del chofer'),
    (480204, '2026-11-02T14:50:00', '2026-11-02T15:05:00', N'Espera por tránsito de equipos'),
    (480206, '2026-11-04T11:05:00', '2026-11-04T11:25:00', N'Cambio de neumático'),
    (480208, '2026-11-06T08:55:00', '2026-11-06T09:35:00', N'Descanso del chofer'),
    (480209, '2026-11-09T09:50:00', '2026-11-09T10:05:00', N'Control de gendarmería');


-- ============================================================================================
-- 2) REPORTES
-- ============================================================================================

-- --------------------------------------------------------------------------------------------
-- 1. DATOS DE PEDIDOS  (una fila por PAS y material)
-- --------------------------------------------------------------------------------------------
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
FROM #PAS p
    JOIN #PASItem  i ON i.NroPAS = p.NroPAS
    JOIN #Geocerca g ON g.IdGeocerca = p.IdGeocercaDestino
ORDER BY p.FechaCreacion, p.NroPAS, i.CodigoMaterial;

-- --------------------------------------------------------------------------------------------
-- 2. DATOS DE VIAJES  (una fila por viaje)
-- --------------------------------------------------------------------------------------------
WITH Tramos AS (            -- geocercas distintas de cada viaje, por tipo de parada y orden de aparicion
    SELECT IdViaje, TipoParada, IdGeocerca, MIN(Secuencia) AS Sec
    FROM #Parada
    GROUP BY IdViaje, TipoParada, IdGeocerca
),
TramoOrigen AS (
    SELECT t.IdViaje, STRING_AGG(g.NombreGeocerca, N' / ') WITHIN GROUP (ORDER BY t.Sec) AS Origen
    FROM Tramos t
        JOIN #Geocerca g ON g.IdGeocerca = t.IdGeocerca
    WHERE t.TipoParada = N'PICK'
    GROUP BY t.IdViaje
),
TramoDestino AS (
    SELECT t.IdViaje, STRING_AGG(g.NombreGeocerca, N' / ') WITHIN GROUP (ORDER BY t.Sec) AS Destino
    FROM Tramos t
        JOIN #Geocerca g ON g.IdGeocerca = t.IdGeocerca
    WHERE t.TipoParada = N'DELIVERY'
    GROUP BY t.IdViaje
),
Pedidos AS (
    SELECT IdViaje,
           STRING_AGG(NroPAS, N', ') WITHIN GROUP (ORDER BY NroPAS) AS PedidosAsociados
    FROM (SELECT DISTINCT IdViaje, NroPAS FROM #Parada) x
    GROUP BY IdViaje
),
Conteo AS (
    SELECT IdViaje,
           SUM(CASE WHEN TipoParada = N'PICK'     THEN 1 ELSE 0 END) AS CantPick,
           SUM(CASE WHEN TipoParada = N'DELIVERY' THEN 1 ELSE 0 END) AS CantDelivery
    FROM #Parada
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
FROM #Viaje v
    JOIN #Vehiculo      ve ON ve.NumeroVehiculo = v.NumeroVehiculo
    LEFT JOIN TramoOrigen   o  ON o.IdViaje  = v.IdViaje
    LEFT JOIN TramoDestino  d  ON d.IdViaje  = v.IdViaje
    LEFT JOIN Pedidos       pe ON pe.IdViaje = v.IdViaje
    LEFT JOIN Conteo        c  ON c.IdViaje  = v.IdViaje
ORDER BY v.IdViaje;

-- --------------------------------------------------------------------------------------------
-- 3. DATOS DE GEOCERCAS CARGADAS
-- --------------------------------------------------------------------------------------------
SELECT
    g.IdGeocerca        AS [ID Geocerca],
    g.NombreGeocerca    AS [Nombre geocerca],
    g.TipoGeocerca      AS [Tipo geocerca],
    g.Latitud           AS [Latitud],
    g.Longitud          AS [Longitud],
    g.RadioMetros       AS [Radio (m)]
FROM #Geocerca g
ORDER BY g.IdGeocerca;

-- --------------------------------------------------------------------------------------------
-- 3.1 EVENTOS DE GEOCERCAS
-- --------------------------------------------------------------------------------------------
SELECT
    e.IdViaje           AS [ID de viaje],
    e.FechaIngreso      AS [Fecha ingreso],
    e.FechaEgreso       AS [Fecha egreso],
    v.NumeroVehiculo    AS [Vehículo],
    e.IdGeocerca        AS [ID de geocerca]
FROM #EventoGeocerca e
    JOIN #Viaje v ON v.IdViaje = e.IdViaje
ORDER BY e.IdViaje, e.FechaIngreso;

-- --------------------------------------------------------------------------------------------
-- 4. GESTIÓN DE VEHÍCULOS  (una fila por viaje con Fecha fin; tiempos en minutos)
-- --------------------------------------------------------------------------------------------
WITH RolGeocerca AS (       -- que papel cumple cada geocerca dentro de cada viaje
    SELECT IdViaje, IdGeocerca,
           MAX(CASE WHEN TipoParada = N'PICK'     THEN 1 ELSE 0 END) AS EsPick,
           MAX(CASE WHEN TipoParada = N'DELIVERY' THEN 1 ELSE 0 END) AS EsDelivery
    FROM #Parada
    GROUP BY IdViaje, IdGeocerca
),
Permanencias AS (
    SELECT e.IdViaje,
           SUM(CASE WHEN r.EsPick = 1     AND r.EsDelivery = 0 THEN DATEDIFF(MINUTE, e.FechaIngreso, e.FechaEgreso) ELSE 0 END) AS MinCarga,
           SUM(CASE WHEN r.EsDelivery = 1 AND r.EsPick = 0     THEN DATEDIFF(MINUTE, e.FechaIngreso, e.FechaEgreso) ELSE 0 END) AS MinDescarga,
           SUM(DATEDIFF(MINUTE, e.FechaIngreso, e.FechaEgreso)) AS MinEnGeocercas        -- incluye cruces sin parada
    FROM #EventoGeocerca e
        LEFT JOIN RolGeocerca r ON r.IdViaje = e.IdViaje AND r.IdGeocerca = e.IdGeocerca
    WHERE e.FechaEgreso IS NOT NULL
    GROUP BY e.IdViaje
),
Detenido AS (
    SELECT IdViaje, SUM(DATEDIFF(MINUTE, FechaInicio, FechaFin)) AS MinDetenido
    FROM #DetencionFueraGeocerca
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
FROM #Viaje v
    JOIN #Vehiculo     ve ON ve.NumeroVehiculo = v.NumeroVehiculo
    JOIN Permanencias  p  ON p.IdViaje = v.IdViaje
    LEFT JOIN Detenido d  ON d.IdViaje = v.IdViaje
WHERE v.FechaFin IS NOT NULL
ORDER BY v.IdViaje;


/*==============================================================================================
  EQUIVALENCIAS CON LA BASE REAL (UNIGIS_DataRepository_YPF)  -- para pasar estos reportes a datos reales

  Las tablas #... reemplazan a estas. Lo marcado "ver" no aparece en los SP de este repositorio y hay que
  confirmarlo en la base (Reportes/Descubrir_Esquema_Reportes.sql lista las tablas y columnas candidatas).

    #PAS / #PASItem      -> Pedido / PedidoItem (y OrdenItem para el material). N° PAS: ver (tal vez Pedido.ReferenciaOT).
                            Prioridad, fechas de necesidad y compromiso, motivos de rechazo e incumplimiento: ver
                            (posiblemente en Pedido_Dyn / PedidoItem_Dyn). Estado: Pedido.IdEstadoPedido.
    #Viaje / #Parada     -> Viaje (IdViaje, IdJornada, IdVehiculo, IdConductor, IdSeguimiento, IdRutaFK) y
                            Parada (IdViaje, IdTipoParada, IdPedido, Orden). Transportista: Seguimiento.IdTransporte.
                            Tipo de viaje, tipo de operacion, cuadrilla, KM liquidados, costo, tarifa y fechas de
                            asignacion / certificacion: ver.
    #Vehiculo            -> Vehiculo (IdVehiculo, IdTransporte). Patente y numero de vehiculo: ver.
    #Geocerca            -> ver (no aparece en el repositorio).
    #EventoGeocerca      -> ver (eventos de la plataforma / posiciones). Hay que decidir de donde salen ingreso y egreso.
    #DetencionFueraGeocerca -> ver (telemetria; EstadiaParada solo cubre estadias en paradas).
==============================================================================================*/
