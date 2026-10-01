/* =============================================================================
   REGLA DE ASIGNACION DE VEHICULOS
   -----------------------------------------------------------------------------
   Define que tipos de vehiculo se pueden asignar a un viaje, segun el tipo de
   vehiculo con el que el viaje fue creado.

   QUE TOCA EL USUARIO  ->  MatrizAsignacionVehiculo  (vista: una matriz con "x")
   QUE USA EL SP        ->  ReglaAsignacionVehiculo    (tabla; no se edita a mano)

   COMO SE LEE LA MATRIZ
       SELECT * FROM MatrizAsignacionVehiculo

       Id  | Si el viaje es de tipo | HG TI  30-35 | HG TII  18-20 | HG TII Liv 5-10
       ----+------------------------+--------------+---------------+-----------------
       208 | HG TI  30-35 tn/m      |      x       |       x       |       x
       207 | HG TII  18-20 tn/m     |              |       x       |       x
       209 | HG TII Liv 5-10 Tn/m   |              |               |       x

     - Cada FILA es el tipo de vehiculo con el que se creo el viaje.
     - Cada COLUMNA es un tipo de vehiculo que se le quiere asignar.
     - "x" = se puede asignar.  Vacio = NO se puede asignar.
     - Id es el IdTipoVehiculo de la fila. Es solo informativo: no se usa y, como
       la matriz no tiene registros nuevos, no hace falta mantenerlo.

   COMO SE EDITA
     - En SSMS: clic derecho sobre la vista > "Edit Top 200 Rows" y escribir o
       borrar la "x" en la celda. Solo se editan las celdas de las columnas de
       tipos de vehiculo (no Id ni "Si el viaje es de tipo").
     - Por SQL:
         UPDATE MatrizAsignacionVehiculo
         SET [HG TII Liv 5-10 Tn/m] = 'x'
         WHERE [Si el viaje es de tipo] = 'HG TII  18-20 tn/m'
     - Solo se admite "x" o vacio; cualquier otro valor se rechaza.

   CRITERIO PARA TIPOS QUE NO ESTAN EN LA MATRIZ
     Un tipo de vehiculo que no aparece como fila de la matriz no se restringe
     (asi no se bloquean tipos que todavia no se parametrizaron).

   COMO AGREGAR UN TIPO NUEVO A LA MATRIZ (ej. Cuadrilla)
     1) Cargar sus filas en ReglaAsignacionVehiculo (ver el ejemplo al final).
     2) Agregarlo en MatrizAsignacionVehiculo y en su trigger
        (una columna mas y una linea mas en cada lista; ver marcas "TIPOS").
   ============================================================================= */
USE [UNIGIS_DataRepository_YPF]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

/* ---------------------------------------------------------------------------
   Limpieza de versiones anteriores de este script (objetos con prefijo Z_).
   Solo actua si esos objetos existen. Las reglas ya editadas se migran a la
   tabla nueva (ver "Migracion" mas abajo) antes de borrar la tabla vieja.
   --------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.Z_VW_ReglaAsignacionVehiculoResumen', 'V') IS NOT NULL
	DROP VIEW dbo.Z_VW_ReglaAsignacionVehiculoResumen

IF OBJECT_ID('dbo.Z_VW_ReglaAsignacionVehiculo', 'V') IS NOT NULL
	DROP VIEW dbo.Z_VW_ReglaAsignacionVehiculo

/* Al borrar la vista tambien se borra su trigger Z_TR_MatrizAsignacionVehiculo_Update */
IF OBJECT_ID('dbo.Z_VW_MatrizAsignacionVehiculo', 'V') IS NOT NULL
	DROP VIEW dbo.Z_VW_MatrizAsignacionVehiculo

/* Primera version de la tabla (tenia IdOperacion): solo traia datos de ejemplo */
IF OBJECT_ID('dbo.Z_ReglaAsignacionVehiculo', 'U') IS NOT NULL
	AND COL_LENGTH('dbo.Z_ReglaAsignacionVehiculo', 'IdOperacion') IS NOT NULL
	DROP TABLE dbo.Z_ReglaAsignacionVehiculo
GO

/* ---------------------------------------------------------------------------
   Tabla (la usa el SP). Una fila por combinacion:
     "un viaje del tipo IdTipoVehiculoViaje, ¿puede llevar un vehiculo del tipo
      IdTipoVehiculoHabilitado?"  ->  Habilitado = 1 (si) / 0 (no)
   --------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.ReglaAsignacionVehiculo', 'U') IS NULL
BEGIN
	CREATE TABLE dbo.ReglaAsignacionVehiculo (
		IdTipoVehiculoViaje INT NOT NULL /* Tipo con el que se creo el viaje */
		,IdTipoVehiculoHabilitado INT NOT NULL /* Tipo de vehiculo que se puede asignar */
		,Habilitado BIT NOT NULL CONSTRAINT DF_ReglaAsignacionVehiculo_Habilitado DEFAULT(1)
		,CONSTRAINT PK_ReglaAsignacionVehiculo PRIMARY KEY CLUSTERED (IdTipoVehiculoViaje, IdTipoVehiculoHabilitado)
		,CONSTRAINT FK_ReglaAsignacionVehiculo_Viaje FOREIGN KEY (IdTipoVehiculoViaje) REFERENCES dbo.TipoVehiculo(IdTipoVehiculo)
		,CONSTRAINT FK_ReglaAsignacionVehiculo_Habilitado FOREIGN KEY (IdTipoVehiculoHabilitado) REFERENCES dbo.TipoVehiculo(IdTipoVehiculo)
		)
END
GO

/* ---------------------------------------------------------------------------
   Migracion: si existe la tabla anterior Z_ReglaAsignacionVehiculo (misma
   estructura, solo cambia el nombre), se copian sus reglas y se borra.
   --------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.Z_ReglaAsignacionVehiculo', 'U') IS NOT NULL
BEGIN
	INSERT dbo.ReglaAsignacionVehiculo (
		IdTipoVehiculoViaje
		,IdTipoVehiculoHabilitado
		,Habilitado
		)
	SELECT o.IdTipoVehiculoViaje
		,o.IdTipoVehiculoHabilitado
		,o.Habilitado
	FROM dbo.Z_ReglaAsignacionVehiculo o
	WHERE NOT EXISTS (
			SELECT 1
			FROM dbo.ReglaAsignacionVehiculo r
			WHERE r.IdTipoVehiculoViaje = o.IdTipoVehiculoViaje
				AND r.IdTipoVehiculoHabilitado = o.IdTipoVehiculoHabilitado
			)

	DROP TABLE dbo.Z_ReglaAsignacionVehiculo
END
GO

/* ---------------------------------------------------------------------------
   Datos iniciales
     207 = HG TII  18-20 tn/m
     208 = HG TI   30-35 tn/m
     209 = HG TII Liv 5-10 Tn/m

   TIPO DEL VIAJE         HABILITA
     HG TI  30-35         HG TI 30-35 ; HG TII 18-20 ; HG TII Liv 5-10
     HG TII 18-20         HG TII 18-20 ; HG TII Liv 5-10
     HG TII Liv 5-10      HG TII Liv 5-10
   --------------------------------------------------------------------------- */
INSERT dbo.ReglaAsignacionVehiculo (
	IdTipoVehiculoViaje
	,IdTipoVehiculoHabilitado
	,Habilitado
	)
SELECT v.IdTipoVehiculoViaje
	,v.IdTipoVehiculoHabilitado
	,v.Habilitado
FROM (
	VALUES
		 (208, 208, 1), (208, 207, 1), (208, 209, 1)
		,(207, 208, 0), (207, 207, 1), (207, 209, 1)
		,(209, 208, 0), (209, 207, 0), (209, 209, 1)
	) v(IdTipoVehiculoViaje, IdTipoVehiculoHabilitado, Habilitado)
WHERE NOT EXISTS (
		SELECT 1
		FROM dbo.ReglaAsignacionVehiculo r
		WHERE r.IdTipoVehiculoViaje = v.IdTipoVehiculoViaje
			AND r.IdTipoVehiculoHabilitado = v.IdTipoVehiculoHabilitado
		)
GO

/* ---------------------------------------------------------------------------
   La vista se borra y se vuelve a crear en cada ejecucion. Al borrarla SQL
   Server elimina tambien los triggers que tenga, con cualquier nombre (por ej.
   Z_TR_MatrizAsignacionVehiculo_Update de una ejecucion anterior). Es necesario
   porque una vista admite un solo trigger INSTEAD OF UPDATE (error 2111).
   --------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.MatrizAsignacionVehiculo', 'V') IS NOT NULL
	DROP VIEW dbo.MatrizAsignacionVehiculo
GO

/* ---------------------------------------------------------------------------
   Matriz que ve y edita el usuario.
   TIPOS: la lista VALUES de filas y las columnas se mantienen iguales en la
   vista y en el trigger de abajo.
   --------------------------------------------------------------------------- */
CREATE VIEW dbo.MatrizAsignacionVehiculo
AS
SELECT t.IdTipoVehiculo AS Id /* IdTipoVehiculo de la fila; informativo, no se usa */
	,t.Nombre AS [Si el viaje es de tipo]
	,CAST(MAX(CASE WHEN r.IdTipoVehiculoHabilitado = 208 AND r.Habilitado = 1 THEN 'x' ELSE '' END) AS VARCHAR(10)) AS [HG TI  30-35 tn/m]
	,CAST(MAX(CASE WHEN r.IdTipoVehiculoHabilitado = 207 AND r.Habilitado = 1 THEN 'x' ELSE '' END) AS VARCHAR(10)) AS [HG TII  18-20 tn/m]
	,CAST(MAX(CASE WHEN r.IdTipoVehiculoHabilitado = 209 AND r.Habilitado = 1 THEN 'x' ELSE '' END) AS VARCHAR(10)) AS [HG TII Liv 5-10 Tn/m]
FROM (
	VALUES
		 (208, 'HG TI  30-35 tn/m')
		,(207, 'HG TII  18-20 tn/m')
		,(209, 'HG TII Liv 5-10 Tn/m')
	) t(IdTipoVehiculo, Nombre)
INNER JOIN dbo.ReglaAsignacionVehiculo r ON r.IdTipoVehiculoViaje = t.IdTipoVehiculo
GROUP BY t.IdTipoVehiculo
	,t.Nombre
GO

/* ---------------------------------------------------------------------------
   Trigger: traduce lo que el usuario escribe en la matriz ("x" / vacio) a
   Habilitado = 1 / 0 en ReglaAsignacionVehiculo.
   --------------------------------------------------------------------------- */
CREATE OR ALTER TRIGGER dbo.TR_MatrizAsignacionVehiculo_Update ON dbo.MatrizAsignacionVehiculo
INSTEAD OF UPDATE
AS
BEGIN
	SET NOCOUNT ON;

	/* Solo se admite "x" o vacio en las celdas */
	IF EXISTS (
			SELECT 1
			FROM inserted i
			WHERE UPPER(LTRIM(RTRIM(ISNULL(i.[HG TI  30-35 tn/m], '')))) NOT IN ('', 'X')
				OR UPPER(LTRIM(RTRIM(ISNULL(i.[HG TII  18-20 tn/m], '')))) NOT IN ('', 'X')
				OR UPPER(LTRIM(RTRIM(ISNULL(i.[HG TII Liv 5-10 Tn/m], '')))) NOT IN ('', 'X')
			)
	BEGIN
		RAISERROR ('Solo se admite "x" (se puede asignar) o vacio (no se puede asignar).', 16, 1);

		RETURN;
	END

	/* La columna "Si el viaje es de tipo" identifica la fila y no se puede modificar */
	IF EXISTS (
			SELECT 1
			FROM inserted i
			WHERE i.[Si el viaje es de tipo] NOT IN (
					'HG TI  30-35 tn/m'
					,'HG TII  18-20 tn/m'
					,'HG TII Liv 5-10 Tn/m'
					)
			)
	BEGIN
		RAISERROR ('No se puede modificar el tipo de viaje (columna "Si el viaje es de tipo"). Solo marque o borre las "x".', 16, 1);

		RETURN;
	END

	DECLARE @Cambios TABLE (
		IdTipoVehiculoViaje INT NOT NULL
		,IdTipoVehiculoHabilitado INT NOT NULL
		,Habilitado BIT NOT NULL
		);

	INSERT @Cambios (
		IdTipoVehiculoViaje
		,IdTipoVehiculoHabilitado
		,Habilitado
		)
	SELECT t.IdTipoVehiculo
		,v.IdTipoVehiculoHabilitado
		,v.Habilitado
	FROM inserted i
	INNER JOIN (
		VALUES
			 (208, 'HG TI  30-35 tn/m')
			,(207, 'HG TII  18-20 tn/m')
			,(209, 'HG TII Liv 5-10 Tn/m')
		) t(IdTipoVehiculo, Nombre) ON t.Nombre = i.[Si el viaje es de tipo]
	CROSS APPLY (
		VALUES
			 (208, CASE WHEN UPPER(LTRIM(RTRIM(ISNULL(i.[HG TI  30-35 tn/m], '')))) = 'X' THEN 1 ELSE 0 END)
			,(207, CASE WHEN UPPER(LTRIM(RTRIM(ISNULL(i.[HG TII  18-20 tn/m], '')))) = 'X' THEN 1 ELSE 0 END)
			,(209, CASE WHEN UPPER(LTRIM(RTRIM(ISNULL(i.[HG TII Liv 5-10 Tn/m], '')))) = 'X' THEN 1 ELSE 0 END)
		) v(IdTipoVehiculoHabilitado, Habilitado);

	UPDATE r
	SET r.Habilitado = c.Habilitado
	FROM dbo.ReglaAsignacionVehiculo r
	INNER JOIN @Cambios c ON c.IdTipoVehiculoViaje = r.IdTipoVehiculoViaje
		AND c.IdTipoVehiculoHabilitado = r.IdTipoVehiculoHabilitado
	WHERE r.Habilitado <> c.Habilitado;

	INSERT dbo.ReglaAsignacionVehiculo (
		IdTipoVehiculoViaje
		,IdTipoVehiculoHabilitado
		,Habilitado
		)
	SELECT c.IdTipoVehiculoViaje
		,c.IdTipoVehiculoHabilitado
		,c.Habilitado
	FROM @Cambios c
	WHERE NOT EXISTS (
			SELECT 1
			FROM dbo.ReglaAsignacionVehiculo r
			WHERE r.IdTipoVehiculoViaje = c.IdTipoVehiculoViaje
				AND r.IdTipoVehiculoHabilitado = c.IdTipoVehiculoHabilitado
			)
END
GO

/* ---------------------------------------------------------------------------
   Ejemplo: cargar un tipo nuevo (reemplazar <ID> por su IdTipoVehiculo).
   Se habilita solo con si mismo y con ningun otro tipo, y ningun otro tipo lo
   habilita a el. (Para Cuadrilla: asi un viaje de cuadrilla solo recibe
   vehiculos de cuadrilla.)

   INSERT ReglaAsignacionVehiculo (IdTipoVehiculoViaje, IdTipoVehiculoHabilitado, Habilitado)
   VALUES (<ID>, <ID>, 1)
         ,(<ID>, 207, 0), (<ID>, 208, 0), (<ID>, 209, 0)
         ,(207, <ID>, 0), (208, <ID>, 0), (209, <ID>, 0)

   Luego agregarlo en la vista y en el trigger (marcas TIPOS).
   --------------------------------------------------------------------------- */
