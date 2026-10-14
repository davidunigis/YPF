USE [UNIGIS_DataRepository_YPF_ARENAS_QA]
GO

IF EXISTS (SELECT 1 FROM sys.columns
           WHERE object_id = OBJECT_ID('dbo.Z_ItinerarioViaje') AND name = 'KmTeoricos'
             AND system_type_id = TYPE_ID('int'))
    ALTER TABLE dbo.Z_ItinerarioViaje ALTER COLUMN KmTeoricos DECIMAL(12,2) NULL;
GO
IF EXISTS (SELECT 1 FROM sys.columns
           WHERE object_id = OBJECT_ID('dbo.Z_ItinerarioViaje') AND name = 'CicloKmTeoricos'
             AND system_type_id = TYPE_ID('int'))
    ALTER TABLE dbo.Z_ItinerarioViaje ALTER COLUMN CicloKmTeoricos DECIMAL(12,2) NULL;
GO
