USE [UNIGIS_DataRepository_YPF]
GO
/*==============================================================================================
  Descubrir_Esquema_Reportes.sql

  SOLO LECTURA (consulta INFORMATION_SCHEMA, no modifica nada).

  Sirve para armar la version con datos reales de Reportes_LP_Solidas_Simulado.sql. En el repositorio
  no figuran las tablas de geocercas, eventos de geocerca, tarifas, costos, KM liquidados, cuadrillas,
  patente / numero de vehiculo, ni los campos de prioridad, fecha compromiso y motivos del pedido.
  Este script los busca por nombre en la base real.

  COMO USARLO
    Correr en UNIGIS_DataRepository_YPF y guardar los 3 resultados (por ejemplo, copiar a Excel).
    Con eso se completa la columna "ver" de las equivalencias que estan al final del script simulado.

    1) Tablas cuyo nombre sugiere lo que falta.
    2) Columnas (de cualquier tabla) cuyo nombre sugiere los campos pedidos.
    3) Todas las columnas de las tablas base que ya usan los SP del repositorio.
==============================================================================================*/
SET NOCOUNT ON;

-- 1) Tablas candidatas ---------------------------------------------------------------------
SELECT t.TABLE_SCHEMA AS Esquema,
       t.TABLE_NAME   AS Tabla
FROM INFORMATION_SCHEMA.TABLES t
WHERE t.TABLE_TYPE = 'BASE TABLE'
  AND (   t.TABLE_NAME LIKE '%geocerc%'  OR t.TABLE_NAME LIKE '%geofence%' OR t.TABLE_NAME LIKE '%evento%'
       OR t.TABLE_NAME LIKE '%tarifa%'   OR t.TABLE_NAME LIKE '%costo%'    OR t.TABLE_NAME LIKE '%valoriz%'
       OR t.TABLE_NAME LIKE '%liquid%'   OR t.TABLE_NAME LIKE '%certific%' OR t.TABLE_NAME LIKE '%cuadrilla%'
       OR t.TABLE_NAME LIKE '%transport%' OR t.TABLE_NAME LIKE '%vehiculo%' OR t.TABLE_NAME LIKE '%conductor%'
       OR t.TABLE_NAME LIKE '%posicion%' OR t.TABLE_NAME LIKE '%telemetr%' OR t.TABLE_NAME LIKE '%motivo%'
       OR t.TABLE_NAME LIKE '%estadia%'  OR t.TABLE_NAME LIKE '%[_]Dyn')
ORDER BY t.TABLE_NAME;

-- 2) Columnas candidatas (cualquier tabla) -------------------------------------------------
SELECT c.TABLE_NAME  AS Tabla,
       c.COLUMN_NAME AS Columna,
       c.DATA_TYPE   AS Tipo,
       c.CHARACTER_MAXIMUM_LENGTH AS Largo
FROM INFORMATION_SCHEMA.COLUMNS c
    JOIN INFORMATION_SCHEMA.TABLES t
        ON t.TABLE_SCHEMA = c.TABLE_SCHEMA AND t.TABLE_NAME = c.TABLE_NAME AND t.TABLE_TYPE = 'BASE TABLE'
WHERE c.COLUMN_NAME LIKE '%geocerc%'  OR c.COLUMN_NAME LIKE '%latitud%'   OR c.COLUMN_NAME LIKE '%longitud%'
   OR c.COLUMN_NAME LIKE '%radio%'    OR c.COLUMN_NAME LIKE '%km%'        OR c.COLUMN_NAME LIKE '%kilom%'
   OR c.COLUMN_NAME LIKE '%costo%'    OR c.COLUMN_NAME LIKE '%tarifa%'    OR c.COLUMN_NAME LIKE '%patente%'
   OR c.COLUMN_NAME LIKE '%cuadrilla%' OR c.COLUMN_NAME LIKE '%certific%' OR c.COLUMN_NAME LIKE '%prioridad%'
   OR c.COLUMN_NAME LIKE '%compromiso%' OR c.COLUMN_NAME LIKE '%necesidad%' OR c.COLUMN_NAME LIKE '%rechaz%'
   OR c.COLUMN_NAME LIKE '%incumpl%'  OR c.COLUMN_NAME LIKE '%motivo%'    OR c.COLUMN_NAME LIKE '%asign%'
   OR c.COLUMN_NAME LIKE '%ingreso%'  OR c.COLUMN_NAME LIKE '%egreso%'    OR c.COLUMN_NAME LIKE '%despacho%'
   OR c.COLUMN_NAME LIKE '%entrega%'  OR c.COLUMN_NAME LIKE '%numero%veh%' OR c.COLUMN_NAME LIKE '%interno%'
ORDER BY c.TABLE_NAME, c.ORDINAL_POSITION;

-- 3) Columnas de las tablas base que ya usan los SP del repositorio ------------------------
SELECT c.TABLE_NAME       AS Tabla,
       c.ORDINAL_POSITION AS Pos,
       c.COLUMN_NAME      AS Columna,
       c.DATA_TYPE        AS Tipo,
       c.CHARACTER_MAXIMUM_LENGTH AS Largo
FROM INFORMATION_SCHEMA.COLUMNS c
WHERE c.TABLE_NAME IN ('Pedido', 'Pedido_Dyn', 'PedidoItem', 'PedidoItem_Dyn', 'Orden', 'OrdenItem',
                       'Viaje', 'Parada', 'ParadaItem', 'Seguimiento', 'Vehiculo', 'Jornada', 'Deposito',
                       'EstadiaParada', 'GuiaViaje', 'ConceptoValorizadoGuia')
ORDER BY c.TABLE_NAME, c.ORDINAL_POSITION;
