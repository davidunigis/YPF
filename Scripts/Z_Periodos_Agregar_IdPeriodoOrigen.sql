USE [UNIGIS_DataRepository_YPF]
GO
/*
Creado: 02/11/2026
Objetivo: agregar a Z_Periodos la columna IdPeriodoOrigen, que usa Z_SP_YPF_SustituyeDominioPeriodo.

Z_Periodos.IdPeriodo es IDENTITY, asi que no se puede copiar a los tramos nuevos (error "Cannot insert explicit
value for identity column"). En su lugar, cada tramo nuevo (sustituto o titular que vuelve) recibe su propio
IdPeriodo y guarda en IdPeriodoOrigen el IdPeriodo de la fila ORIGINAL del periodo. Todos los tramos de un mismo
periodo comparten ese valor: COALESCE(IdPeriodoOrigen, IdPeriodo).

- Es una columna que admite NULL y sin valor por defecto: las filas existentes no cambian (NULL = fila original).
- No hay que tocar nada mas. Se puede ejecutar mas de una vez.
- Ejecutar ANTES de crear/actualizar el SP Z_SP_YPF_SustituyeDominioPeriodo.
*/
IF COL_LENGTH('dbo.Z_Periodos', 'IdPeriodoOrigen') IS NULL
    ALTER TABLE dbo.Z_Periodos ADD IdPeriodoOrigen INT NULL;
GO
