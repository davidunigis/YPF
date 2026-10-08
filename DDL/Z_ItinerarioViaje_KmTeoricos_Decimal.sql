USE [UNIGIS_DataRepository_YPF_ARENAS_QA]
GO
/*==============================================================================
  Z_ItinerarioViaje.KmTeoricos y CicloKmTeoricos eran INT y truncaban lo que viene
  de Z_KmTeoricos (DECIMAL): 130,08 / 260,16 quedaban 130 / 260.
  Pasan a DECIMAL(12,2), igual que el SP. Es re-ejecutable: solo cambia las columnas
  que todavia son INT. Los valores ya guardados no se recuperan: hay que volver a
  ejecutar el SP para los viajes.
  Si falla por un indice, default o constraint que dependa de la columna, avisar.
==============================================================================*/
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
