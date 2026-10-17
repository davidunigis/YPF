/*==============================================================================
  00 - VERSION DESPLEGADA Y OBJETOS REQUERIDOS (solo lectura, sin viaje)

  Responde: el SP, las columnas y las funciones que usan los reportes, estan
  desplegados y en la version nueva? Un "Invalid column name" o un SP viejo
  se ve aca. Exportar la grilla completa a Excel.
==============================================================================*/
SELECT T.Orden, T.Chequeo, T.Esperado, T.Encontrado, T.Estado
FROM (
    SELECT 1 AS Orden, CAST('Base de datos' AS VARCHAR(80)) AS Chequeo,
           CAST('UNIGIS_DataRepository_YPF_ARENAS_QA' AS NVARCHAR(300)) AS Esperado,
           CAST(DB_NAME() AS NVARCHAR(300)) AS Encontrado,
           CASE WHEN DB_NAME() = 'UNIGIS_DataRepository_YPF_ARENAS_QA' THEN 'OK' ELSE 'REVISAR' END AS Estado
    UNION ALL
    SELECT 2, 'Hora del servidor (local) / UTC', 'la hora local debe ser UTC-3',
           CONVERT(NVARCHAR(30), GETDATE(), 120) + ' / ' + CONVERT(NVARCHAR(30), GETUTCDATE(), 120), 'INFO'
    UNION ALL
    SELECT 3, 'SP Z_SP_ItinerarioViaje', 'existe',
           CASE WHEN OBJECT_ID('dbo.Z_SP_ItinerarioViaje', 'P') IS NOT NULL THEN 'existe' ELSE 'NO EXISTE' END,
           CASE WHEN OBJECT_ID('dbo.Z_SP_ItinerarioViaje', 'P') IS NOT NULL THEN 'OK' ELSE 'FALTA' END
    UNION ALL
    SELECT 4, 'SP modificado por ultima vez', 'fecha del despliegue',
           CONVERT(NVARCHAR(30), (SELECT O.modify_date FROM sys.objects O WHERE O.object_id = OBJECT_ID('dbo.Z_SP_ItinerarioViaje')), 120), 'INFO'
    UNION ALL
    SELECT 10 + M.N, 'SP contiene: ' + M.Marca, M.Funcion,
           CASE WHEN CHARINDEX(M.Marca, ISNULL(OBJECT_DEFINITION(OBJECT_ID('dbo.Z_SP_ItinerarioViaje')), '')) > 0 THEN 'si' ELSE 'NO' END,
           CASE WHEN CHARINDEX(M.Marca, ISNULL(OBJECT_DEFINITION(OBJECT_ID('dbo.Z_SP_ItinerarioViaje')), '')) > 0 THEN 'OK' ELSE 'VERSION VIEJA' END
    FROM (VALUES
            (1, '@MinutosToleranciaOrigen', 'tolerancia por origen / destino'),
            (2, 'MinutosDemora',            'imputacion de demoras (PASO 7.e)'),
            (3, 'VelMin',                   'estacion de servicio sin detenerse'),
            (4, 'IdDibujoZona = NULL',      'estacion sin detenerse se funde con el carreteando'),
            (5, '@MinutosAtras',            'hora previa a la activacion'),
            (6, '@CombPrevios',             'combustible una vez por dia y por unidad'),
            (7, '@FinCarga',                'visitas al deposito segun el pase a En transito'),
            (8, 'SIN_EVENTOS_GPS',          'fila para viajes sin eventos GPS')
         ) M (N, Marca, Funcion)
    UNION ALL
    SELECT 30 + X.N, 'Z_ItinerarioViaje.' + X.Col, X.Tipo,
           ISNULL(TYPE_NAME(C.user_type_id)
                  + CASE WHEN TYPE_NAME(C.user_type_id) IN ('decimal', 'numeric')
                         THEN '(' + CAST(C.precision AS VARCHAR(5)) + ',' + CAST(C.scale AS VARCHAR(5)) + ')' ELSE '' END,
                  'NO EXISTE'),
           CASE WHEN C.column_id IS NULL THEN 'FALTA'
                WHEN TYPE_NAME(C.user_type_id) = X.TipoBase THEN 'OK' ELSE 'TIPO DISTINTO' END
    FROM (VALUES
            (1, 'KmTeoricos',        'decimal(12,2)', 'decimal'),
            (2, 'CicloKmTeoricos',   'decimal(12,2)', 'decimal'),
            (3, 'ToleranciaMinutos', 'int',           'int'),
            (4, 'ResponsableDemora', 'varchar',       'varchar'),
            (5, 'MinutosDemora',     'int',           'int'),
            (6, 'MinutosExentos',    'int',           'int'),
            (7, 'MotivoExencion',    'varchar',       'varchar'),
            (8, 'Novedad',           'varchar',       'varchar'),
            (9, 'KmRecorridos',      'decimal',       'decimal')
         ) X (N, Col, Tipo, TipoBase)
    LEFT JOIN sys.columns C ON C.object_id = OBJECT_ID('dbo.Z_ItinerarioViaje') AND C.name = X.Col
    UNION ALL
    SELECT 50 + O.N, 'Objeto ' + O.Nombre, 'existe',
           CASE WHEN OBJECT_ID(O.Nombre) IS NOT NULL THEN 'existe' ELSE 'NO EXISTE' END,
           CASE WHEN OBJECT_ID(O.Nombre) IS NOT NULL THEN 'OK' ELSE 'FALTA' END
    FROM (VALUES
            (1, 'dbo.Z_MinutosAHHMM'),
            (2, 'dbo.Z_ClasificarParadasViaje'),
            (3, 'dbo.Z_CambioTurnoTransporte'),
            (4, 'dbo.Z_KmTeoricos'),
            (5, 'dbo.Z_EstacionesDeServicioYPF'),
            (6, 'dbo.Z_ItinerarioViaje')
         ) O (N, Nombre)
    UNION ALL
    SELECT 70, 'Rangos de cambio de turno activos', 'cargados por transportista',
           CAST((SELECT COUNT(*) FROM dbo.Z_CambioTurnoTransporte WITH (NOLOCK) WHERE Activo = 1) AS NVARCHAR(30)), 'INFO'
    UNION ALL
    SELECT 71, 'Z_ItinerarioViaje: filas / viajes distintos', 'informativo',
           CAST((SELECT COUNT(*) FROM dbo.Z_ItinerarioViaje WITH (NOLOCK)) AS NVARCHAR(30)) + ' / '
         + CAST((SELECT COUNT(DISTINCT IdViaje) FROM dbo.Z_ItinerarioViaje WITH (NOLOCK)) AS NVARCHAR(30)), 'INFO'
    UNION ALL
    SELECT 72, 'Z_ItinerarioViaje: viajes con fila SIN_EVENTOS_GPS', 'informativo',
           CAST((SELECT COUNT(DISTINCT IdViaje) FROM dbo.Z_ItinerarioViaje WITH (NOLOCK) WHERE Novedad = 'SIN_EVENTOS_GPS') AS NVARCHAR(30)), 'INFO'
) T
ORDER BY T.Orden;
