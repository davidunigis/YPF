/* =============================================================================
   Z_ReglaAsignacionVehiculo
   -----------------------------------------------------------------------------
   Parametriza que TIPOS DE VEHICULO se pueden asignar a un viaje, segun el
   tipo de vehiculo con el que el viaje fue creado (el "tipo requerido").

   COMO LEER LA TABLA
     Cada fila responde a una pregunta:
       "Un viaje que pide el tipo X, ¿puede salir con un vehiculo de tipo Y?"
     - IdTipoVehiculoViaje      = X (tipo requerido por el viaje)
     - IdTipoVehiculoHabilitado = Y (tipo de vehiculo que se quiere asignar)
     - Habilitado               = 1 SI se puede / 0 NO se puede

   COMO USARLA (el usuario solo necesita tocar la columna Habilitado)
     - Para ver las reglas con nombres:      SELECT * FROM Z_VW_ReglaAsignacionVehiculo
     - Para ver el resumen estilo Excel:     SELECT * FROM Z_VW_ReglaAsignacionVehiculoResumen
     - Habilitar / deshabilitar una regla:
         UPDATE Z_ReglaAsignacionVehiculo SET Habilitado = 0
         WHERE IdReglaAsignacionVehiculo = <id>
     - Agregar un tipo nuevo: insertar una fila por cada combinacion
       (ver el ejemplo al final de este script).

   CRITERIO CUANDO NO HAY REGLA
     - Si un tipo requerido NO tiene ninguna fila para la operacion, no se
       restringe la asignacion (asi no se bloquean tipos todavia no cargados).
     - Si tiene filas, solo se permiten los tipos con Habilitado = 1.

   NOTA: las reglas se guardan por IdTipoVehiculo y NO por nombre, porque los
   nombres de TipoVehiculo tienen espacios no separables y diferencias de
   escritura (ej. "HG TIIl Liv 5-10 Tn/m").
   ============================================================================= */
USE [UNIGIS_DataRepository_YPF]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

/* ---------------------------------------------------------------------------
   Tabla
   --------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.Z_ReglaAsignacionVehiculo', 'U') IS NULL
BEGIN
	CREATE TABLE dbo.Z_ReglaAsignacionVehiculo (
		IdReglaAsignacionVehiculo INT IDENTITY(1, 1) NOT NULL
		,IdOperacion INT NOT NULL
		,IdTipoVehiculoViaje INT NOT NULL /* Tipo requerido por el viaje */
		,IdTipoVehiculoHabilitado INT NOT NULL /* Tipo de vehiculo que se puede asignar */
		,Habilitado BIT NOT NULL CONSTRAINT DF_Z_ReglaAsignacionVehiculo_Habilitado DEFAULT(1)
		,Observaciones VARCHAR(200) NULL
		,FechaAlta DATETIME NOT NULL CONSTRAINT DF_Z_ReglaAsignacionVehiculo_FechaAlta DEFAULT(GETDATE())
		,CONSTRAINT PK_Z_ReglaAsignacionVehiculo PRIMARY KEY CLUSTERED (IdReglaAsignacionVehiculo)
		,CONSTRAINT UQ_Z_ReglaAsignacionVehiculo UNIQUE (IdOperacion, IdTipoVehiculoViaje, IdTipoVehiculoHabilitado)
		,CONSTRAINT FK_Z_ReglaAsignacionVehiculo_TipoViaje FOREIGN KEY (IdTipoVehiculoViaje) REFERENCES dbo.TipoVehiculo(IdTipoVehiculo)
		,CONSTRAINT FK_Z_ReglaAsignacionVehiculo_TipoHabilitado FOREIGN KEY (IdTipoVehiculoHabilitado) REFERENCES dbo.TipoVehiculo(IdTipoVehiculo)
		)
END
GO

/* ---------------------------------------------------------------------------
   Datos iniciales - Operacion 141
     207 = HG TII  18-20 tn/m
     208 = HG TI   30-35 tn/m
     209 = HG TII Liv 5-10 Tn/m

   REGLA                      HABILITA
     HG TI  30-35             HG TI 30-35 ; HG TII 18-20 ; HG TII Liv 5-10
     HG TII 18-20             HG TII 18-20 ; HG TII Liv 5-10
     HG TII Liv 5-10          HG TII Liv 5-10
   Se carga la matriz completa (3 x 3): las combinaciones que no se permiten
   quedan con Habilitado = 0, asi el usuario solo tiene que cambiar el 0/1.
   --------------------------------------------------------------------------- */
DECLARE @IdOperacion INT = 141;

INSERT dbo.Z_ReglaAsignacionVehiculo (
	IdOperacion
	,IdTipoVehiculoViaje
	,IdTipoVehiculoHabilitado
	,Habilitado
	)
SELECT @IdOperacion
	,v.IdTipoVehiculoViaje
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
		FROM dbo.Z_ReglaAsignacionVehiculo r
		WHERE r.IdOperacion = @IdOperacion
			AND r.IdTipoVehiculoViaje = v.IdTipoVehiculoViaje
			AND r.IdTipoVehiculoHabilitado = v.IdTipoVehiculoHabilitado
		)
GO

/* ---------------------------------------------------------------------------
   Vista 1: una fila por regla, con nombres (para consultar y editar con
   referencia al IdReglaAsignacionVehiculo).
   --------------------------------------------------------------------------- */
CREATE OR ALTER VIEW dbo.Z_VW_ReglaAsignacionVehiculo
AS
SELECT r.IdReglaAsignacionVehiculo
	,r.IdOperacion
	,r.IdTipoVehiculoViaje
	,tv.Descripcion AS TipoVehiculoViaje
	,r.IdTipoVehiculoHabilitado
	,th.Descripcion AS TipoVehiculoHabilitado
	,CASE r.Habilitado
		WHEN 1
			THEN 'SI'
		ELSE 'NO'
		END AS Permite
	,r.Habilitado
	,r.Observaciones
FROM dbo.Z_ReglaAsignacionVehiculo r
INNER JOIN dbo.TipoVehiculo tv ON tv.IdTipoVehiculo = r.IdTipoVehiculoViaje
INNER JOIN dbo.TipoVehiculo th ON th.IdTipoVehiculo = r.IdTipoVehiculoHabilitado
GO

/* ---------------------------------------------------------------------------
   Vista 2: resumen estilo Excel
   (TIPO UNIDAD | UNIDADES QUE HABILITA, separadas por ";").
   --------------------------------------------------------------------------- */
CREATE OR ALTER VIEW dbo.Z_VW_ReglaAsignacionVehiculoResumen
AS
SELECT r.IdOperacion
	,r.IdTipoVehiculoViaje
	,tv.Descripcion AS TipoUnidad
	,STUFF((
			SELECT ';' + th.Descripcion
			FROM dbo.Z_ReglaAsignacionVehiculo r2
			INNER JOIN dbo.TipoVehiculo th ON th.IdTipoVehiculo = r2.IdTipoVehiculoHabilitado
			WHERE r2.IdOperacion = r.IdOperacion
				AND r2.IdTipoVehiculoViaje = r.IdTipoVehiculoViaje
				AND r2.Habilitado = 1
			ORDER BY th.Descripcion
			FOR XML PATH('')
				,TYPE
			).value('.', 'VARCHAR(MAX)'), 1, 1, '') AS UnidadesQueHabilita
FROM dbo.Z_ReglaAsignacionVehiculo r
INNER JOIN dbo.TipoVehiculo tv ON tv.IdTipoVehiculo = r.IdTipoVehiculoViaje
GROUP BY r.IdOperacion
	,r.IdTipoVehiculoViaje
	,tv.Descripcion
GO

/* ---------------------------------------------------------------------------
   Ejemplo: agregar un tipo nuevo (reemplazar <ID_NUEVO> por su IdTipoVehiculo)
   Una fila por cada combinacion; el nuevo tipo solo se habilita a si mismo.

   INSERT Z_ReglaAsignacionVehiculo (IdOperacion, IdTipoVehiculoViaje, IdTipoVehiculoHabilitado, Habilitado)
   VALUES (141, <ID_NUEVO>, <ID_NUEVO>, 1)
         ,(141, <ID_NUEVO>, 207, 0), (141, <ID_NUEVO>, 208, 0), (141, <ID_NUEVO>, 209, 0)
         ,(141, 207, <ID_NUEVO>, 0), (141, 208, <ID_NUEVO>, 0), (141, 209, <ID_NUEVO>, 0)
   --------------------------------------------------------------------------- */
