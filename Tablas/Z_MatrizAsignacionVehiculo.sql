/* =============================================================================
   REGLA DE ASIGNACION DE VEHICULOS
   -----------------------------------------------------------------------------
   Define que tipos de vehiculo se pueden asignar a un viaje, segun el tipo de
   vehiculo con el que el viaje fue creado.

   QUE TOCA EL USUARIO  ->  Z_MatrizAsignacionVehiculo  (TABLA; se edita en el catalogo)
   QUE USA EL SP        ->  ReglaAsignacionVehiculo     (vista de solo lectura)

   Z_MatrizAsignacionVehiculo es una tabla fisica con la misma forma que
   Z_KMSSolidas (Id INT NOT NULL + columnas simples) para poder listarla en el
   catalogo dinamico: no hay vistas, triggers ni nombres con espacios.

   COMO SE LEE LA TABLA
       SELECT * FROM Z_MatrizAsignacionVehiculo

       Id  | TipoViaje              | HG_TI_30_35 | HG_TII_18_20 | HG_TII_Liv_5_10
       ----+------------------------+-------------+--------------+----------------
       208 | HG TI  30-35 tn/m      |      x      |      x       |       x
       207 | HG TII  18-20 tn/m     |             |      x       |       x
       209 | HG TII Liv 5-10 Tn/m   |             |              |       x

     - Cada FILA es el tipo de vehiculo con el que se creo el viaje (TipoViaje).
     - Cada COLUMNA HG_... es un tipo de vehiculo que se le quiere asignar:
         HG_TI_30_35     = HG TI  30-35 tn/m
         HG_TII_18_20    = HG TII  18-20 tn/m
         HG_TII_Liv_5_10 = HG TII Liv 5-10 Tn/m
     - "x" = se puede asignar.  Vacio = NO se puede asignar.
     - Solo se admite "x" o vacio (lo controla la propia tabla).
     - Id es el IdTipoVehiculo de la fila y es lo que usa el SP: NO se cambia.
       TipoViaje es solo la descripcion para que el usuario se ubique.

   CRITERIO PARA TIPOS QUE NO ESTAN EN LA TABLA
     Un tipo de vehiculo sin fila en esta tabla no se restringe (asi no se
     bloquean tipos que todavia no se parametrizaron). Una fila con todas las
     celdas vacias no permite ninguna asignacion.

   COMO SE LE AGREGA UN TIPO NUEVO (ej. Cuadrilla) - ver ejemplo al final
     1) Una columna nueva en Z_MatrizAsignacionVehiculo.
     2) Una fila nueva (Id = IdTipoVehiculo del tipo nuevo).
     3) Una linea en la vista ReglaAsignacionVehiculo.
   ============================================================================= */
USE [UNIGIS_DataRepository_YPF]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

/* ---------------------------------------------------------------------------
   Limpieza de versiones anteriores de este diseno (vistas y triggers).
   Al borrar una vista se borran tambien sus triggers, con cualquier nombre.
   --------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.Z_VW_ReglaAsignacionVehiculoResumen', 'V') IS NOT NULL
	DROP VIEW dbo.Z_VW_ReglaAsignacionVehiculoResumen

IF OBJECT_ID('dbo.Z_VW_ReglaAsignacionVehiculo', 'V') IS NOT NULL
	DROP VIEW dbo.Z_VW_ReglaAsignacionVehiculo

IF OBJECT_ID('dbo.Z_VW_MatrizAsignacionVehiculo', 'V') IS NOT NULL
	DROP VIEW dbo.Z_VW_MatrizAsignacionVehiculo

/* La matriz como vista (ya no se usa: el catalogo dinamico no lista vistas) */
IF OBJECT_ID('dbo.MatrizAsignacionVehiculo', 'V') IS NOT NULL
	DROP VIEW dbo.MatrizAsignacionVehiculo
GO

/* ---------------------------------------------------------------------------
   Tabla que edita el usuario.
   Una fila por tipo de vehiculo del viaje; una columna por tipo asignable.
   Las celdas aceptan vacio (NULL) para poder quitar una "x" desde el catalogo.
   --------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.Z_MatrizAsignacionVehiculo', 'U') IS NULL
BEGIN
	CREATE TABLE dbo.Z_MatrizAsignacionVehiculo (
		Id INT NOT NULL /* IdTipoVehiculo del tipo con el que se creo el viaje */
		,TipoViaje VARCHAR(100) NOT NULL /* Descripcion para el usuario */
		,HG_TI_30_35 VARCHAR(10) NULL CONSTRAINT CK_Z_MatrizAsignacionVehiculo_HG_TI_30_35 CHECK (UPPER(LTRIM(RTRIM(ISNULL(HG_TI_30_35, '')))) IN ('', 'X'))
		,HG_TII_18_20 VARCHAR(10) NULL CONSTRAINT CK_Z_MatrizAsignacionVehiculo_HG_TII_18_20 CHECK (UPPER(LTRIM(RTRIM(ISNULL(HG_TII_18_20, '')))) IN ('', 'X'))
		,HG_TII_Liv_5_10 VARCHAR(10) NULL CONSTRAINT CK_Z_MatrizAsignacionVehiculo_HG_TII_Liv_5_10 CHECK (UPPER(LTRIM(RTRIM(ISNULL(HG_TII_Liv_5_10, '')))) IN ('', 'X'))
		,CONSTRAINT PK_Z_MatrizAsignacionVehiculo PRIMARY KEY CLUSTERED (Id)
		,CONSTRAINT FK_Z_MatrizAsignacionVehiculo_TipoVehiculo FOREIGN KEY (Id) REFERENCES dbo.TipoVehiculo(IdTipoVehiculo)
		)
END
GO

/* ---------------------------------------------------------------------------
   Datos iniciales
     208 = HG TI  30-35 tn/m        -> HG TI ; HG TII ; HG TII Liv
     207 = HG TII  18-20 tn/m       -> HG TII ; HG TII Liv
     209 = HG TII Liv 5-10 Tn/m     -> HG TII Liv
   Solo se insertan las filas que todavia no existen.
   --------------------------------------------------------------------------- */
INSERT dbo.Z_MatrizAsignacionVehiculo (
	Id
	,TipoViaje
	,HG_TI_30_35
	,HG_TII_18_20
	,HG_TII_Liv_5_10
	)
SELECT v.Id
	,v.TipoViaje
	,v.HG_TI_30_35
	,v.HG_TII_18_20
	,v.HG_TII_Liv_5_10
FROM (
	VALUES
		 (208, 'HG TI  30-35 tn/m', 'x', 'x', 'x')
		,(207, 'HG TII  18-20 tn/m', NULL, 'x', 'x')
		,(209, 'HG TII Liv 5-10 Tn/m', NULL, NULL, 'x')
	) v(Id, TipoViaje, HG_TI_30_35, HG_TII_18_20, HG_TII_Liv_5_10)
WHERE NOT EXISTS (
		SELECT 1
		FROM dbo.Z_MatrizAsignacionVehiculo m
		WHERE m.Id = v.Id
		)
GO

/* ---------------------------------------------------------------------------
   Migracion: si existe la tabla anterior (ReglaAsignacionVehiculo o, mas
   vieja, Z_ReglaAsignacionVehiculo), sus reglas se pasan a la matriz y la
   tabla vieja se elimina. Si no existen, no hace nada.
   --------------------------------------------------------------------------- */
DECLARE @Anteriores TABLE (
	IdTipoVehiculoViaje INT NOT NULL
	,IdTipoVehiculoHabilitado INT NOT NULL
	,Habilitado BIT NOT NULL
	);

IF OBJECT_ID('dbo.ReglaAsignacionVehiculo', 'U') IS NOT NULL
	INSERT @Anteriores (IdTipoVehiculoViaje, IdTipoVehiculoHabilitado, Habilitado)
	SELECT IdTipoVehiculoViaje
		,IdTipoVehiculoHabilitado
		,Habilitado
	FROM dbo.ReglaAsignacionVehiculo
ELSE IF OBJECT_ID('dbo.Z_ReglaAsignacionVehiculo', 'U') IS NOT NULL
	INSERT @Anteriores (IdTipoVehiculoViaje, IdTipoVehiculoHabilitado, Habilitado)
	SELECT IdTipoVehiculoViaje
		,IdTipoVehiculoHabilitado
		,Habilitado
	FROM dbo.Z_ReglaAsignacionVehiculo;

WITH a
AS (
	SELECT IdTipoVehiculoViaje
		,MAX(CASE WHEN IdTipoVehiculoHabilitado = 208 THEN CAST(Habilitado AS INT) END) AS HG_TI_30_35
		,MAX(CASE WHEN IdTipoVehiculoHabilitado = 207 THEN CAST(Habilitado AS INT) END) AS HG_TII_18_20
		,MAX(CASE WHEN IdTipoVehiculoHabilitado = 209 THEN CAST(Habilitado AS INT) END) AS HG_TII_Liv_5_10
	FROM @Anteriores
	GROUP BY IdTipoVehiculoViaje
	)
UPDATE m
SET m.HG_TI_30_35 = CASE WHEN a.HG_TI_30_35 = 1 THEN 'x' END
	,m.HG_TII_18_20 = CASE WHEN a.HG_TII_18_20 = 1 THEN 'x' END
	,m.HG_TII_Liv_5_10 = CASE WHEN a.HG_TII_Liv_5_10 = 1 THEN 'x' END
FROM dbo.Z_MatrizAsignacionVehiculo m
INNER JOIN a ON a.IdTipoVehiculoViaje = m.Id;

IF OBJECT_ID('dbo.ReglaAsignacionVehiculo', 'U') IS NOT NULL
	DROP TABLE dbo.ReglaAsignacionVehiculo

IF OBJECT_ID('dbo.Z_ReglaAsignacionVehiculo', 'U') IS NOT NULL
	DROP TABLE dbo.Z_ReglaAsignacionVehiculo
GO

/* ---------------------------------------------------------------------------
   Vista que usa el SP (solo lectura): convierte la matriz en una fila por
   combinacion
     "un viaje del tipo IdTipoVehiculoViaje, ¿puede llevar un vehiculo del tipo
      IdTipoVehiculoHabilitado?"  ->  Habilitado = 1 (si) / 0 (no)
   Aqui se relaciona cada columna de la matriz con su IdTipoVehiculo:
     208 = HG_TI_30_35 ; 207 = HG_TII_18_20 ; 209 = HG_TII_Liv_5_10
   --------------------------------------------------------------------------- */
CREATE OR ALTER VIEW dbo.ReglaAsignacionVehiculo
AS
SELECT m.Id AS IdTipoVehiculoViaje
	,c.IdTipoVehiculoHabilitado
	,CAST(CASE WHEN UPPER(LTRIM(RTRIM(ISNULL(c.Marca, '')))) = 'X' THEN 1 ELSE 0 END AS BIT) AS Habilitado
FROM dbo.Z_MatrizAsignacionVehiculo m
CROSS APPLY (
	VALUES
		 (208, m.HG_TI_30_35)
		,(207, m.HG_TII_18_20)
		,(209, m.HG_TII_Liv_5_10)
	) c(IdTipoVehiculoHabilitado, Marca)
GO

/* ---------------------------------------------------------------------------
   Ejemplo: agregar Cuadrilla (reemplazar <ID> por su IdTipoVehiculo).
   Cuadrilla solo se habilita con cuadrilla, y ningun HG la habilita a ella.

   -- 1) Columna nueva (con el mismo control "x" o vacio)
   ALTER TABLE Z_MatrizAsignacionVehiculo ADD Cuadrilla VARCHAR(10) NULL
       CONSTRAINT CK_Z_MatrizAsignacionVehiculo_Cuadrilla
       CHECK (UPPER(LTRIM(RTRIM(ISNULL(Cuadrilla, '')))) IN ('', 'X'))

   -- 2) Fila nueva (solo se habilita con si misma)
   INSERT Z_MatrizAsignacionVehiculo (Id, TipoViaje, Cuadrilla) VALUES (<ID>, 'Cuadrilla', 'x')

   -- 3) Agregar "(<ID>, m.Cuadrilla)" a la lista VALUES de la vista
   --    ReglaAsignacionVehiculo (CREATE OR ALTER VIEW de arriba).
   --------------------------------------------------------------------------- */
