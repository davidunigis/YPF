/*==============================================================================================
  Reporte 3 - Datos de Geocercas cargadas  -- DATOS SIMULADOS

  Una fila por geocerca (13 geocercas).
  Es UNA sola consulta (WITH ... SELECT) y NO lee ninguna tabla real: los datos ficticios estan en los CTE
  Sim... (listas VALUES). Se puede ejecutar en cualquier base. Requiere SQL Server 2008 o superior.
  El archivo esta en UTF-8 con BOM (lleva tildes y el simbolo de grado).

  DEFINICIONES
    Tipo geocerca: Base | Almacén | Pozo | Cliente | Planta. Radio en metros. Nombres y coordenadas ficticios
    (zona de Neuquen).

  Para pasar a datos reales: reemplazar cada CTE Sim... por la tabla (o vista) real equivalente, con las mismas
  columnas; el SELECT final no cambia. Las equivalencias estan al final de Reportes_LP_Solidas_Simulado.sql y las
  que faltan confirmar se buscan con Descubrir_Esquema_Reportes.sql.
==============================================================================================*/

WITH
SimGeocerca AS (
    SELECT IdGeocerca,
        NombreGeocerca,
        TipoGeocerca,
        CAST(Latitud AS DECIMAL(9,6)) AS Latitud,
        CAST(Longitud AS DECIMAL(9,6)) AS Longitud,
        RadioMetros
    FROM (VALUES
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
            (113, N'Cliente Metalúrgica del Valle', N'Cliente', -38.960000, -68.230000, 200)
         ) AS x(IdGeocerca, NombreGeocerca, TipoGeocerca, Latitud, Longitud, RadioMetros)
)
SELECT
    g.IdGeocerca        AS [ID Geocerca],
    g.NombreGeocerca    AS [Nombre geocerca],
    g.TipoGeocerca      AS [Tipo geocerca],
    g.Latitud           AS [Latitud],
    g.Longitud          AS [Longitud],
    g.RadioMetros       AS [Radio (m)]
FROM SimGeocerca g
ORDER BY g.IdGeocerca;
