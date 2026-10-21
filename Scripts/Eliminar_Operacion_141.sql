/*==============================================================================================
  Eliminar_Operacion_141.sql

  Borra Jornadas, Viajes, Paradas, Ordenes y Pedidos de una operacion (@IdOperacion) y TODAS las
  filas que dependen de ellos. NO borra la operacion en si (su registro). Con @BorrarJornadas = 0
  las Jornadas se conservan y solo se usan para ubicar los viajes (Viaje.IdJornada -> Jornada.IdOperacion).
  Las tablas dependientes no se listan a mano: se descubren solas
  recorriendo las foreign keys de la base (sys.foreign_keys), nivel por nivel, y se borran de las
  hojas hacia las raices.

  COMO USARLO
    1) Dejar @Ejecutar = 0 y correr el script completo. Hace TODO dentro de una transaccion y al
       final hace ROLLBACK: no queda ningun cambio. Devuelve:
         - el plan (las sentencias que va a ejecutar),
         - las posibles dependencias SIN foreign key (tablas que el script no puede descubrir),
         - el resumen de filas que se borrarian por tabla.
    2) Revisar el resumen. Si una tabla no debe borrarse, usar los AJUSTES MANUALES de abajo.
    3) Con @Ejecutar = 1 se repite el mismo proceso y se hace COMMIT.

  SEGURIDAD
    - Si hay filas de OTRAS operaciones que dependen de lo que se va a borrar (ej. una orden de
      otra operacion dentro de una jornada o asociada a un viaje de la 141), el script se cancela sin tocar nada y
      muestra cuales son.
    - Un Pedido que tambien tiene ordenes de otras operaciones NO se borra (se conserva).
    - Cualquier error (FK, trigger, bloqueo) hace ROLLBACK de todo.

  LIMITES (leer)
    - Solo ve las FK declaradas. Si una tabla apunta a Viaje/Orden/etc. sin FK, el script la
      informa en "posibles dependencias SIN foreign key" pero no la borra salvo que se declare en
      #AristaManual.
    - Una tabla maestra con FK opcional hacia lo borrado (ej. un vehiculo con "viaje actual")
      aparece en el resumen con Revisar = 'FK opcional'. Si no se debe borrar, declararla en
      #Excepcion: ahi se pone NULL la referencia en lugar de borrar la fila.
    - Todo corre en UNA transaccion: con muchos millones de filas puede crecer mucho el log y
      bloquear tablas. Correr en ventana de mantenimiento, idealmente con la plataforma detenida.
    - Los triggers de DELETE de las tablas siguen disparandose.
    - Probar siempre primero en una copia (restore) de la base.
==============================================================================================*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;   -- requerido por los metodos XML (.value); sqlcmd lo trae en OFF
SET ANSI_NULLS ON;

------------------------------------------------------------------------------------------
-- PARAMETROS
------------------------------------------------------------------------------------------
DECLARE @IdOperacion INT = 141;
DECLARE @Ejecutar    BIT = 0;   -- 0 = simulacion (ROLLBACK al final) | 1 = borrado real (COMMIT)
DECLARE @BorrarJornadas BIT = 1;   -- 1 = borrar tambien las Jornadas de la operacion | 0 = conservarlas
DECLARE @BuscarSinFK BIT = 1;   -- 1 = buscar tablas con columnas IdViaje/IdOrden/... sin FK declarada

------------------------------------------------------------------------------------------
-- Estructuras de trabajo (se recrean en cada corrida)
------------------------------------------------------------------------------------------
DECLARE @Pref sysname = N'##K' + CAST(@@SPID AS NVARCHAR(10)) + N'_';   -- tablas de claves a borrar
DECLARE @sql  NVARCHAR(MAX) = N'';
DECLARE @msg  NVARCHAR(2048);

SELECT @sql += N'DROP TABLE ' + QUOTENAME(name) + N';'
FROM tempdb.sys.tables WHERE name LIKE REPLACE(@Pref, N'_', N'[_]') + N'%';
IF @sql <> N'' EXEC (@sql);

IF OBJECT_ID('tempdb..#SemJornada') IS NOT NULL DROP TABLE #SemJornada;
IF OBJECT_ID('tempdb..#SemViaje')   IS NOT NULL DROP TABLE #SemViaje;
IF OBJECT_ID('tempdb..#SemParada')  IS NOT NULL DROP TABLE #SemParada;
IF OBJECT_ID('tempdb..#SemOrden')   IS NOT NULL DROP TABLE #SemOrden;
IF OBJECT_ID('tempdb..#SemPedido')  IS NOT NULL DROP TABLE #SemPedido;
IF OBJECT_ID('tempdb..#Raiz')       IS NOT NULL DROP TABLE #Raiz;
IF OBJECT_ID('tempdb..#Nodo')       IS NOT NULL DROP TABLE #Nodo;
IF OBJECT_ID('tempdb..#Arista')     IS NOT NULL DROP TABLE #Arista;
IF OBJECT_ID('tempdb..#AristaCol')  IS NOT NULL DROP TABLE #AristaCol;
IF OBJECT_ID('tempdb..#AristaManual') IS NOT NULL DROP TABLE #AristaManual;
IF OBJECT_ID('tempdb..#Excepcion')  IS NOT NULL DROP TABLE #Excepcion;
IF OBJECT_ID('tempdb..#Plan')       IS NOT NULL DROP TABLE #Plan;
IF OBJECT_ID('tempdb..#Cand')       IS NOT NULL DROP TABLE #Cand;

CREATE TABLE #SemJornada (Id BIGINT NOT NULL PRIMARY KEY);   -- ids a borrar, uno por tabla raiz
CREATE TABLE #SemViaje   (Id BIGINT NOT NULL PRIMARY KEY);
CREATE TABLE #SemParada  (Id BIGINT NOT NULL PRIMARY KEY);
CREATE TABLE #SemOrden   (Id BIGINT NOT NULL PRIMARY KEY);
CREATE TABLE #SemPedido  (Id BIGINT NOT NULL PRIMARY KEY);

CREATE TABLE #Raiz (Ord INT, Esq SYSNAME, Tabla SYSNAME, Sem SYSNAME, Filtro NVARCHAR(MAX), Borrar BIT NOT NULL, ColId SYSNAME NULL);

CREATE TABLE #Nodo (
    Id INT IDENTITY(1,1) PRIMARY KEY, ObjectId INT NOT NULL, Esq SYSNAME, Tabla SYSNAME,
    EsRaiz BIT NOT NULL, Sem SYSNAME NULL, ColId SYSNAME NULL, Nivel INT NOT NULL DEFAULT 0,
    KTabla SYSNAME NULL, KCols NVARCHAR(MAX) NULL, Miembro NVARCHAR(MAX) NULL,
    Via NVARCHAR(MAX) NULL, Revisar VARCHAR(20) NULL);

CREATE TABLE #Arista (   -- relacion hijo (H) -> padre (P)
    IdArista INT PRIMARY KEY, Origen VARCHAR(10), Nombre SYSNAME, ObjH INT, ObjP INT,
    Cruce NVARCHAR(MAX) NULL, ColsH NVARCHAR(MAX) NULL, SetNull NVARCHAR(MAX) NULL, Obligatoria BIT NULL);
CREATE TABLE #AristaCol (IdArista INT, Ord INT, ColH SYSNAME, ColP SYSNAME);

CREATE TABLE #Plan (
    Seq INT IDENTITY(1,1) PRIMARY KEY, Fase TINYINT, Nivel INT, NodoId INT NULL,
    Esq SYSNAME, Tabla SYSNAME, Tipo VARCHAR(10), Detalle NVARCHAR(MAX) NULL,
    Sql NVARCHAR(MAX), Muestra NVARCHAR(MAX) NULL);

DECLARE @Log TABLE (Seq INT, Fase TINYINT, NodoId INT, Tabla NVARCHAR(300), Tipo VARCHAR(10), Filas BIGINT);

------------------------------------------------------------------------------------------
-- AJUSTES MANUALES (opcional; completar despues de revisar la simulacion)
------------------------------------------------------------------------------------------
-- Tablas que apuntan a lo que se borra pero NO tienen foreign key declarada.
-- Se las trata como si la tuvieran: se borran sus filas que apunten a lo borrado.
CREATE TABLE #AristaManual (Id INT IDENTITY(1,1), EsqH SYSNAME, TblH SYSNAME, ColH SYSNAME,
                                                  EsqP SYSNAME, TblP SYSNAME, ColP SYSNAME);
-- INSERT #AristaManual (EsqH, TblH, ColH, EsqP, TblP, ColP) VALUES (N'dbo', N'OrdenLog', N'IdOrden', N'dbo', N'Orden', N'IdOrden');

-- Tablas que NO deben borrarse: en lugar de borrar la fila se pone NULL la columna que apunta a
-- lo borrado (la columna debe aceptar NULL). Tampoco se sigue bajando por sus dependientes.
CREATE TABLE #Excepcion (Esq SYSNAME, Tabla SYSNAME, Obj INT NULL);
-- INSERT #Excepcion (Esq, Tabla) VALUES (N'dbo', N'Vehiculo');

-- Tablas raiz y como se decide que filas se borran (T = la tabla raiz).
--   Jornada/Orden: por IdOperacion.  Viaje: las de esas jornadas.  Parada: las de esos viajes.
--   Pedido: los de esas ordenes (y los que tengan Pedido.IdOperacion = @IdOperacion, si existe la columna).
--   Borrar = 0 (Jornada con @BorrarJornadas = 0): se calcula la lista pero la tabla no se borra.
INSERT #Raiz (Ord, Esq, Tabla, Sem, Filtro, Borrar) VALUES
 (1, N'dbo', N'Jornada', N'#SemJornada', N'T.IdOperacion = @IdOperacion', @BorrarJornadas),
 (2, N'dbo', N'Viaje',   N'#SemViaje',   N'T.IdJornada IN (SELECT Id FROM #SemJornada)', 1),
 (3, N'dbo', N'Parada',  N'#SemParada',  N'T.IdViaje IN (SELECT Id FROM #SemViaje)', 1),
 (4, N'dbo', N'Orden',   N'#SemOrden',   N'T.IdOperacion = @IdOperacion', 1),
 (5, N'dbo', N'Pedido',  N'#SemPedido',  N'T.IdPedido IN (SELECT o.IdPedido FROM dbo.Orden o WHERE o.IdPedido IS NOT NULL AND o.IdOperacion = @IdOperacion)', 1);

IF COL_LENGTH(N'dbo.Pedido', N'IdOperacion') IS NOT NULL
    UPDATE #Raiz SET Filtro = Filtro + N' OR T.IdOperacion = @IdOperacion' WHERE Tabla = N'Pedido';

------------------------------------------------------------------------------------------
-- PROCESO
------------------------------------------------------------------------------------------
DECLARE @Seq INT = 0, @Fase TINYINT, @Niv INT, @NodoId INT, @Tabla NVARCHAR(300), @Tipo VARCHAR(10),
        @Muestra NVARCHAR(MAX), @n BIGINT, @Conflictos INT = 0, @PedidosConservados INT = 0,
        @Ord INT = 0, @Esq SYSNAME, @Tbl SYSNAME, @Sem SYSNAME, @Filtro NVARCHAR(MAX), @Col SYSNAME;

BEGIN TRY
    ----- 1. Raices: clave primaria (una sola columna) y filas a borrar -----
    UPDATE r SET ColId = pk.Col
    FROM #Raiz r
    CROSS APPLY (SELECT MIN(c.name) AS Col, COUNT(*) AS N
                 FROM sys.indexes i
                 JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
                 JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
                 WHERE i.object_id = OBJECT_ID(QUOTENAME(r.Esq) + N'.' + QUOTENAME(r.Tabla))
                   AND i.is_primary_key = 1) pk
    WHERE pk.N = 1;

    IF EXISTS (SELECT 1 FROM #Raiz WHERE ColId IS NULL)
    BEGIN
        SELECT @msg = N'No se encontro la tabla o su clave primaria (de una sola columna): '
                    + STUFF((SELECT N', ' + Tabla FROM #Raiz WHERE ColId IS NULL FOR XML PATH(N'')), 1, 2, N'');
        THROW 50001, @msg, 1;
    END

    WHILE 1 = 1
    BEGIN
        SELECT TOP (1) @Ord = Ord, @Esq = Esq, @Tbl = Tabla, @Sem = Sem, @Filtro = Filtro, @Col = ColId
        FROM #Raiz WHERE Ord > @Ord ORDER BY Ord;
        IF @@ROWCOUNT = 0 BREAK;

        SET @sql = N'INSERT ' + @Sem + N' (Id) SELECT T.' + QUOTENAME(@Col) + N' FROM '
                 + QUOTENAME(@Esq) + N'.' + QUOTENAME(@Tbl) + N' AS T WHERE ' + @Filtro + N';';
        EXEC sp_executesql @sql, N'@IdOperacion INT', @IdOperacion = @IdOperacion;
    END

    -- un pedido compartido con ordenes de otras operaciones se conserva
    DELETE s FROM #SemPedido s
    WHERE EXISTS (SELECT 1 FROM dbo.Orden o
                  WHERE o.IdPedido = s.Id
                    AND NOT EXISTS (SELECT 1 FROM #SemOrden so WHERE so.Id = o.IdOrden));
    SET @PedidosConservados = @@ROWCOUNT;

    ----- 2. Relaciones (FK + manuales) -----
    INSERT #Arista (IdArista, Origen, Nombre, ObjH, ObjP)
    SELECT fk.object_id, 'FK', fk.name, fk.parent_object_id, fk.referenced_object_id
    FROM sys.foreign_keys fk
    WHERE fk.parent_object_id <> fk.referenced_object_id;      -- las auto-referencias no se usan

    INSERT #AristaCol (IdArista, Ord, ColH, ColP)
    SELECT fkc.constraint_object_id, fkc.constraint_column_id,
           COL_NAME(fkc.parent_object_id, fkc.parent_column_id),
           COL_NAME(fkc.referenced_object_id, fkc.referenced_column_id)
    FROM sys.foreign_key_columns fkc
    JOIN #Arista a ON a.IdArista = fkc.constraint_object_id;

    IF EXISTS (SELECT 1 FROM #AristaManual m
               WHERE COL_LENGTH(QUOTENAME(m.EsqH) + N'.' + QUOTENAME(m.TblH), m.ColH) IS NULL
                  OR COL_LENGTH(QUOTENAME(m.EsqP) + N'.' + QUOTENAME(m.TblP), m.ColP) IS NULL)
        THROW 50002, N'#AristaManual: hay tablas o columnas que no existen.', 1;

    INSERT #Arista (IdArista, Origen, Nombre, ObjH, ObjP)
    SELECT -m.Id, 'MANUAL', m.TblH + N'.' + m.ColH,
           OBJECT_ID(QUOTENAME(m.EsqH) + N'.' + QUOTENAME(m.TblH)),
           OBJECT_ID(QUOTENAME(m.EsqP) + N'.' + QUOTENAME(m.TblP))
    FROM #AristaManual m;
    INSERT #AristaCol (IdArista, Ord, ColH, ColP) SELECT -Id, 1, ColH, ColP FROM #AristaManual;

    UPDATE e SET Obj = OBJECT_ID(QUOTENAME(e.Esq) + N'.' + QUOTENAME(e.Tabla)) FROM #Excepcion e;
    IF EXISTS (SELECT 1 FROM #Excepcion WHERE Obj IS NULL)
        THROW 50002, N'#Excepcion: hay tablas que no existen.', 1;

    ----- 3. Tablas alcanzadas: se parte de las raices y se baja por las FK -----
    INSERT #Nodo (ObjectId, Esq, Tabla, EsRaiz, Sem, ColId)
    SELECT OBJECT_ID(QUOTENAME(Esq) + N'.' + QUOTENAME(Tabla)), Esq, Tabla, 1, Sem, ColId FROM #Raiz WHERE Borrar = 1 ORDER BY Ord;

    WHILE 1 = 1
    BEGIN
        INSERT #Nodo (ObjectId, Esq, Tabla, EsRaiz)
        SELECT DISTINCT a.ObjH, OBJECT_SCHEMA_NAME(a.ObjH), OBJECT_NAME(a.ObjH), 0
        FROM #Arista a
        WHERE EXISTS (SELECT 1 FROM #Nodo p WHERE p.ObjectId = a.ObjP)
          AND NOT EXISTS (SELECT 1 FROM #Nodo h WHERE h.ObjectId = a.ObjH)
          AND NOT EXISTS (SELECT 1 FROM #Excepcion e WHERE e.Obj = a.ObjH);
        IF @@ROWCOUNT = 0 BREAK;
    END

    DELETE a FROM #Arista a
    WHERE NOT EXISTS (SELECT 1 FROM #Nodo n WHERE n.ObjectId = a.ObjP)
       OR (NOT EXISTS (SELECT 1 FROM #Nodo n WHERE n.ObjectId = a.ObjH)
           AND NOT EXISTS (SELECT 1 FROM #Excepcion e WHERE e.Obj = a.ObjH));
    DELETE c FROM #AristaCol c WHERE NOT EXISTS (SELECT 1 FROM #Arista a WHERE a.IdArista = c.IdArista);

    -- nivel = distancia maxima a una raiz; los padres siempre tienen nivel menor que sus hijos
    DECLARE @Iter INT = 0, @Cambios INT = 1;
    WHILE @Cambios > 0
    BEGIN
        UPDATE h SET Nivel = x.Nv
        FROM #Nodo h
        CROSS APPLY (SELECT MAX(p.Nivel) + 1 AS Nv
                     FROM #Arista a JOIN #Nodo p ON p.ObjectId = a.ObjP
                     WHERE a.ObjH = h.ObjectId) x
        WHERE x.Nv > h.Nivel;
        SET @Cambios = @@ROWCOUNT;
        SET @Iter += 1;
        IF @Iter > (SELECT COUNT(*) FROM #Nodo) + 1
            THROW 50003, N'Hay dependencias circulares entre las tablas alcanzadas; no se puede ordenar el borrado.', 1;
    END

    ----- 4. Predicados (T = tabla borrada, K = claves del padre) -----
    UPDATE #Nodo SET KTabla = @Pref + CAST(Id AS NVARCHAR(10));

    UPDATE a SET
        Cruce   = STUFF((SELECT N' AND T.' + QUOTENAME(c.ColH) + N' = K.' + QUOTENAME(c.ColP)
                         FROM #AristaCol c WHERE c.IdArista = a.IdArista ORDER BY c.Ord
                         FOR XML PATH(N''), TYPE).value(N'.', N'NVARCHAR(MAX)'), 1, 5, N''),
        ColsH   = STUFF((SELECT N', ' + c.ColH
                         FROM #AristaCol c WHERE c.IdArista = a.IdArista ORDER BY c.Ord
                         FOR XML PATH(N''), TYPE).value(N'.', N'NVARCHAR(MAX)'), 1, 2, N''),
        SetNull = STUFF((SELECT N', ' + QUOTENAME(c.ColH) + N' = NULL'
                         FROM #AristaCol c WHERE c.IdArista = a.IdArista ORDER BY c.Ord
                         FOR XML PATH(N''), TYPE).value(N'.', N'NVARCHAR(MAX)'), 1, 2, N''),
        Obligatoria = CASE WHEN EXISTS (SELECT 1 FROM #AristaCol c
                                        JOIN sys.columns sc ON sc.object_id = a.ObjH AND sc.name = c.ColH
                                        WHERE c.IdArista = a.IdArista AND sc.is_nullable = 1) THEN 0 ELSE 1 END
    FROM #Arista a;

    UPDATE n SET KCols = STUFF((SELECT DISTINCT N', ' + QUOTENAME(c.ColP)
                                FROM #Arista a JOIN #AristaCol c ON c.IdArista = a.IdArista
                                WHERE a.ObjP = n.ObjectId
                                FOR XML PATH(N''), TYPE).value(N'.', N'NVARCHAR(MAX)'), 1, 2, N'')
    FROM #Nodo n;

    UPDATE #Nodo SET Miembro = N'T.' + QUOTENAME(ColId) + N' IN (SELECT Id FROM ' + Sem + N')' WHERE EsRaiz = 1;

    UPDATE n SET
        Miembro = STUFF((SELECT N' OR EXISTS (SELECT 1 FROM ' + p.KTabla + N' AS K WHERE ' + a.Cruce + N')'
                         FROM #Arista a JOIN #Nodo p ON p.ObjectId = a.ObjP
                         WHERE a.ObjH = n.ObjectId
                         FOR XML PATH(N''), TYPE).value(N'.', N'NVARCHAR(MAX)'), 1, 4, N''),
        Via     = STUFF((SELECT N'; ' + OBJECT_NAME(a.ObjP) + N' (' + a.ColsH + N')'
                         FROM #Arista a WHERE a.ObjH = n.ObjectId
                         FOR XML PATH(N''), TYPE).value(N'.', N'NVARCHAR(MAX)'), 1, 2, N''),
        Revisar = CASE WHEN EXISTS (SELECT 1 FROM #Arista a WHERE a.ObjH = n.ObjectId AND a.Obligatoria = 1)
                       THEN NULL ELSE 'FK opcional' END
    FROM #Nodo n
    WHERE n.EsRaiz = 0;

    -- una tabla en #Excepcion necesita que la(s) columna(s) acepten NULL
    IF EXISTS (SELECT 1 FROM #Arista a WHERE a.Obligatoria = 1
                 AND EXISTS (SELECT 1 FROM #Excepcion e WHERE e.Obj = a.ObjH))
    BEGIN
        SELECT @msg = N'#Excepcion: la columna no acepta NULL en: '
                    + STUFF((SELECT DISTINCT N', ' + OBJECT_NAME(a.ObjH)
                             FROM #Arista a JOIN #Excepcion e ON e.Obj = a.ObjH WHERE a.Obligatoria = 1
                             FOR XML PATH(N'')), 1, 2, N'');
        THROW 50005, @msg, 1;
    END

    ----- 5. Plan de ejecucion -----
    -- Fase 1: guardar las claves de lo que se va a borrar, de arriba hacia abajo
    INSERT #Plan (Fase, Nivel, NodoId, Esq, Tabla, Tipo, Sql)
    SELECT 1, Nivel, Id, Esq, Tabla, 'CLAVES',
           N'SELECT DISTINCT ' + KCols + N' INTO ' + KTabla + N' FROM ' + QUOTENAME(Esq) + N'.' + QUOTENAME(Tabla)
         + N' AS T WHERE ' + Miembro
    FROM #Nodo WHERE KCols IS NOT NULL ORDER BY Nivel, Id;

    -- Fase 2: filas de una tabla raiz que NO estan en la lista y dependen de algo que se borra
    INSERT #Plan (Fase, Nivel, NodoId, Esq, Tabla, Tipo, Detalle, Sql, Muestra)
    SELECT 2, h.Nivel, h.Id, h.Esq, h.Tabla, 'CONFLICTO', a.Nombre + N' -> ' + p.Tabla,
           N'SELECT @n = COUNT_BIG(*) FROM ' + QUOTENAME(h.Esq) + N'.' + QUOTENAME(h.Tabla) + N' AS T WHERE EXISTS (SELECT 1 FROM '
         + p.KTabla + N' AS K WHERE ' + a.Cruce + N') AND NOT (' + h.Miembro + N')',
           N'SELECT TOP (50) T.* FROM ' + QUOTENAME(h.Esq) + N'.' + QUOTENAME(h.Tabla) + N' AS T WHERE EXISTS (SELECT 1 FROM '
         + p.KTabla + N' AS K WHERE ' + a.Cruce + N') AND NOT (' + h.Miembro + N')'
    FROM #Arista a
    JOIN #Nodo h ON h.ObjectId = a.ObjH AND h.EsRaiz = 1
    JOIN #Nodo p ON p.ObjectId = a.ObjP
    ORDER BY h.Nivel, h.Id;

    -- Fase 3: tablas en #Excepcion -> poner NULL la referencia
    INSERT #Plan (Fase, Nivel, Esq, Tabla, Tipo, Detalle, Sql)
    SELECT 3, 0, OBJECT_SCHEMA_NAME(a.ObjH), OBJECT_NAME(a.ObjH), 'ANULAR', a.ColsH + N' -> ' + p.Tabla,
           N'UPDATE T SET ' + a.SetNull + N' FROM ' + QUOTENAME(OBJECT_SCHEMA_NAME(a.ObjH)) + N'.' + QUOTENAME(OBJECT_NAME(a.ObjH))
         + N' AS T WHERE EXISTS (SELECT 1 FROM ' + p.KTabla + N' AS K WHERE ' + a.Cruce + N')'
    FROM #Arista a
    JOIN #Nodo p ON p.ObjectId = a.ObjP
    WHERE EXISTS (SELECT 1 FROM #Excepcion e WHERE e.Obj = a.ObjH);

    -- Fase 4: borrar, de las hojas hacia las raices
    INSERT #Plan (Fase, Nivel, NodoId, Esq, Tabla, Tipo, Detalle, Sql)
    SELECT 4, Nivel, Id, Esq, Tabla, 'BORRAR', Via,
           N'DELETE T FROM ' + QUOTENAME(Esq) + N'.' + QUOTENAME(Tabla) + N' AS T WHERE ' + Miembro
    FROM #Nodo ORDER BY Nivel DESC, Id;

    SELECT Seq, Fase, Tipo, Nivel, Tabla = Esq + N'.' + Tabla, Detalle, Sql FROM #Plan ORDER BY Seq;   -- plan a revisar

    ----- 6. Dependencias que el script no ve (sin FK declarada) -----
    IF @BuscarSinFK = 1
    BEGIN
        CREATE TABLE #Cand (Tabla NVARCHAR(300), Columna SYSNAME, ApuntaA SYSNAME, Filas BIGINT NULL, Sql NVARCHAR(MAX));

        INSERT #Cand (Tabla, Columna, ApuntaA, Sql)
        SELECT OBJECT_SCHEMA_NAME(t.object_id) + N'.' + t.name, c.name, r.Tabla,
               N'SELECT @n = COUNT_BIG(*) FROM ' + QUOTENAME(OBJECT_SCHEMA_NAME(t.object_id)) + N'.' + QUOTENAME(t.name)
             + N' AS T WHERE T.' + QUOTENAME(c.name) + N' IN (SELECT Id FROM ' + r.Sem + N')'
             + ISNULL(N' AND NOT (' + h.Miembro + N')', N'')          -- si es raiz, solo las filas que NO se borran
        FROM sys.tables t
        JOIN sys.columns c ON c.object_id = t.object_id
        JOIN #Nodo r ON r.EsRaiz = 1 AND r.ColId = c.name AND r.ObjectId <> t.object_id
        LEFT JOIN #Nodo h ON h.ObjectId = t.object_id AND h.EsRaiz = 1
        WHERE t.is_ms_shipped = 0
          AND NOT EXISTS (SELECT 1 FROM #Nodo n WHERE n.ObjectId = t.object_id AND n.EsRaiz = 0)
          AND NOT EXISTS (SELECT 1 FROM #Arista a JOIN #AristaCol ac ON ac.IdArista = a.IdArista
                          WHERE a.ObjH = t.object_id AND a.ObjP = r.ObjectId AND ac.ColH = c.name)
          AND NOT EXISTS (SELECT 1 FROM #Excepcion e WHERE e.Obj = t.object_id);

        DECLARE @CandTabla NVARCHAR(300), @CandCol SYSNAME;
        DECLARE cur CURSOR LOCAL FAST_FORWARD FOR SELECT Tabla, Columna, Sql FROM #Cand;
        OPEN cur;
        FETCH NEXT FROM cur INTO @CandTabla, @CandCol, @sql;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @n = NULL;
            EXEC sp_executesql @sql, N'@n BIGINT OUTPUT', @n OUTPUT;
            UPDATE #Cand SET Filas = @n WHERE Tabla = @CandTabla AND Columna = @CandCol;
            FETCH NEXT FROM cur INTO @CandTabla, @CandCol, @sql;
        END
        CLOSE cur; DEALLOCATE cur;

        IF EXISTS (SELECT 1 FROM #Cand WHERE Filas > 0)
        BEGIN
            PRINT N'*** ATENCION: hay tablas SIN foreign key con filas que apuntan a lo que se va a borrar (resultado "Posibles dependencias SIN FK").';
            PRINT N'    Si corresponde borrarlas, declararlas en #AristaManual. Si no, quedarian huerfanas.';
            SELECT [Posibles dependencias SIN FK] = Tabla, Columna, ApuntaA, Filas FROM #Cand WHERE Filas > 0 ORDER BY Filas DESC;
        END
        ELSE PRINT N'No se detectaron dependencias sin FK (por nombre de columna).';
    END

    ----- 7. Ejecucion dentro de una transaccion -----
    BEGIN TRAN;

    WHILE 1 = 1
    BEGIN
        SELECT TOP (1) @Seq = Seq, @Fase = Fase, @Niv = Nivel, @NodoId = NodoId, @Tabla = Esq + N'.' + Tabla,
                       @Tipo = Tipo, @sql = Sql, @Muestra = Muestra
        FROM #Plan WHERE Seq > @Seq ORDER BY Seq;
        IF @@ROWCOUNT = 0 BREAK;

        IF @Fase >= 3 AND @Conflictos > 0
        BEGIN
            SET @msg = N'CANCELADO: hay ' + CAST(@Conflictos AS NVARCHAR(10))
                     + N' tabla(s) raiz con filas de otras operaciones que dependen de lo que se va a borrar. No se borro nada.';
            SELECT @Tipo = 'CONFLICTO', @Tabla = N'(validacion previa al borrado)';
            THROW 50004, @msg, 1;
        END

        SET @n = NULL;
        IF @Tipo = 'CONFLICTO'
            EXEC sp_executesql @sql, N'@n BIGINT OUTPUT', @n OUTPUT;
        ELSE
        BEGIN
            EXEC sp_executesql @sql;
            SET @n = @@ROWCOUNT;
        END

        INSERT @Log (Seq, Fase, NodoId, Tabla, Tipo, Filas) VALUES (@Seq, @Fase, @NodoId, @Tabla, @Tipo, @n);

        IF @Tipo = 'CONFLICTO' AND @n > 0
        BEGIN
            SET @Conflictos += 1;
            PRINT N'CONFLICTO: ' + @Tabla + N' tiene ' + CAST(@n AS NVARCHAR(20)) + N' fila(s) que NO son de la operacion y dependen de lo que se borra.';
            EXEC sp_executesql @Muestra;
        END
    END

    IF @Ejecutar = 1
    BEGIN
        COMMIT TRAN;
        PRINT N'*** EJECUTADO: cambios confirmados (COMMIT). ***';
    END
    ELSE
    BEGIN
        ROLLBACK TRAN;
        PRINT N'*** SIMULACION: se hizo ROLLBACK, no se modifico nada. Poner @Ejecutar = 1 para borrar de verdad. ***';
    END

    IF @PedidosConservados > 0
        PRINT N'Pedidos conservados por tener ordenes de otras operaciones: ' + CAST(@PedidosConservados AS NVARCHAR(10));

    ----- 8. Resumen -----
    SELECT Nivel = n.Nivel, Tabla = n.Esq + N'.' + n.Tabla, Tipo = CASE WHEN n.EsRaiz = 1 THEN 'RAIZ' ELSE 'dependiente' END,
           [Llego por] = n.Via, n.Revisar, Filas = l.Filas
    FROM #Nodo n JOIN @Log l ON l.NodoId = n.Id AND l.Tipo = 'BORRAR'
    WHERE l.Filas > 0
    ORDER BY n.Nivel, n.Tabla;

    SELECT [Referencias puestas en NULL] = Tabla, Filas FROM @Log WHERE Tipo = 'ANULAR' AND Filas > 0;
    SELECT [Total filas borradas] = ISNULL(SUM(Filas), 0) FROM @Log WHERE Tipo = 'BORRAR';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRAN;
    PRINT N'*** CANCELADO, se hizo ROLLBACK (no se modifico nada).'
        + ISNULL(N' Ultimo paso: ' + @Tipo + N' ' + @Tabla, N'');
    THROW;
END CATCH

SET @sql = N'';
SELECT @sql += N'DROP TABLE ' + QUOTENAME(name) + N';'
FROM tempdb.sys.tables WHERE name LIKE REPLACE(@Pref, N'_', N'[_]') + N'%';
IF @sql <> N'' EXEC (@sql);
