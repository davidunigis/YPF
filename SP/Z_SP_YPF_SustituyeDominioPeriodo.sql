USE [UNIGIS_DataRepository_YPF]
GO
/****** Objeto: StoredProcedure [dbo].[Z_SP_YPF_SustituyeDominioPeriodo] Fecha de script: 02/11/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[Z_SP_YPF_SustituyeDominioPeriodo]
    @IdRecurso INT
AS
BEGIN
    /*
    Creado: 02/11/2026
    Objetivo: llevar en Z_Periodos la traza de cuando un vehiculo deja de estar disponible, quien lo sustituye
              y cuando vuelve. Se ejecuta cuando el Recurso del vehiculo recibe un cambio de estado.

    Llamada desde la plataforma (placeholder a confirmar):  EXEC [dbo].[Z_SP_YPF_SustituyeDominioPeriodo] [Recurso.IdRecurso]

    Lee el ULTIMO cambio de estado del recurso (RecursoTraceEstado, el de mayor IdRecursoTraceEstado) y el dominio
    del vehiculo del recurso (Vehiculo.IdRecurso = @IdRecurso). Si el recurso no tiene vehiculo con dominio, o si el
    cambio no es de los dos de abajo, sale sin hacer nada ni escribir en Log.

    Modelo: cada fila de Z_Periodos es un TRAMO del periodo.
      - La fila ABIERTA (FechaNodisponible IS NULL) es el vehiculo que cubre el periodo hoy.
      - FechaNodisponible = momento (hora Argentina) en que ese dominio dejo de cubrir el periodo.
      - DominioSustituye = a quien reemplaza esa fila (NULL en las filas originales).
      - FechaRegistroPeriodo = momento (hora Argentina) desde el que rige el tramo, en las filas que crea este SP.
      - Los tramos de un mismo periodo se reconocen por IdPeriodo + Agrupador + InicioPeriodo + FinPeriodo (iguales).
      - Solo se consideran periodos VIGENTES: InicioPeriodo <= hoy (Argentina) <= FinPeriodo.

    1) BAJA - el recurso pasa a IdEstadoRecursoDestino = 3 (cualquiera sea el origen):
         El dominio sustituto es el texto de RecursoTraceEstado.Observaciones (se limpia de espacios y saltos de linea).
         a) Al dominio del vehiculo (A), en cada tramo ABIERTO vigente de Z_Periodos, se le pone
            FechaNodisponible = ahora (hora Argentina).
         b) Por cada tramo cerrado se inserta una fila nueva para el sustituto (B): IdPeriodo, Agrupador,
            InicioPeriodo y FinPeriodo copiados, Dominio = B, DominioSustituye = A, FechaRegistroPeriodo = ahora.
         Si A no tiene tramo abierto vigente, o Observaciones viene vacia / no es un dominio (mas de 50 caracteres)
         / es el mismo dominio, no se cambia nada y queda un Aviso en Log.

    2) RETORNO - transicion IdEstadoRecursoOrigen = 3 -> IdEstadoRecursoDestino = 2:
         a) Se busca, en los periodos donde A dejo un tramo cerrado y no tiene tramo abierto, el tramo ABIERTO
            de quien lo sustituyo (DominioSustituye = A) y se le pone FechaNodisponible = ahora.
         b) Se inserta una fila nueva para A (copiando IdPeriodo, Agrupador, InicioPeriodo, FinPeriodo) con
            DominioSustituye = el dominio sustituto y FechaRegistroPeriodo = ahora: A vuelve a reemplazar a quien
            lo habia reemplazado.
         Limite: solo encuentra al sustituto DIRECTO. Si el sustituto tambien dejo de estar disponible y lo
         reemplazo otro dominio antes de que A vuelva, no hay tramo abierto con DominioSustituye = A: no se
         cambia nada y queda un Aviso en Log.

    Ejemplo (A deja de estar disponible, lo reemplaza B, y despues A vuelve):
         A  Inicio..Fin  FechaNodisponible = t1                                  <- A se fue
         B  Inicio..Fin  DominioSustituye = A  Registro = t1  FechaNodisponible = t2   <- B cubre de t1 a t2
         A  Inicio..Fin  DominioSustituye = B  Registro = t2                     <- A volvio y reemplaza a B

    Notas:
      - Es idempotente: si se ejecuta dos veces para el mismo cambio, la segunda no encuentra tramos y no duplica filas.
      - Hora Argentina = GETUTCDATE() menos 3 horas (sin horario de verano), igual que el resto de los SP.
        FechaNodisponible y FechaRegistroPeriodo son DATE en la tabla: hoy guardan solo la fecha. Si se
        pasan a DATETIME, el SP guarda la hora sin cambios (probado).
      - Las altas/bajas se hacen en una transaccion: o se cierra el tramo y se inserta el nuevo, o ninguno.
      - Registra el resultado en Log (categoria SustituyeDominio, 20 caracteres como maximo) y no relanza el error.
    */
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @IdTrace   INT;
    DECLARE @Origen    INT;
    DECLARE @Destino   INT;
    DECLARE @Observ    VARCHAR(MAX);
    DECLARE @DomActual VARCHAR(50);      -- dominio del vehiculo que cambia de estado (A)
    DECLARE @DomNuevo  VARCHAR(51);      -- dominio sustituto (B); 51 para poder detectar el que supera 50
    DECLARE @Ahora     DATETIME = DATEADD(HOUR, -3, GETUTCDATE());   -- hora Argentina
    DECLARE @Hoy       DATE     = CAST(@Ahora AS DATE);
    DECLARE @Filas     INT;
    DECLARE @Resultado VARCHAR(10);
    DECLARE @Detalle   VARCHAR(300);

    DECLARE @Tramos TABLE (
        IdPeriodo     INT,
        Agrupador     VARCHAR(50),
        InicioPeriodo DATE,
        FinPeriodo    DATE,
        Dominio       VARCHAR(50)
    );

    -- Ultimo cambio de estado del recurso
    SELECT TOP 1
           @IdTrace = IdRecursoTraceEstado,
           @Origen  = IdEstadoRecursoOrigen,
           @Destino = IdEstadoRecursoDestino,
           @Observ  = CONVERT(VARCHAR(MAX), Observaciones)
    FROM RecursoTraceEstado WITH (NOLOCK)
    WHERE IdRecurso = @IdRecurso
    ORDER BY IdRecursoTraceEstado DESC;

    -- Solo interesan: cualquier cambio hacia 3 (baja) y 3 -> 2 (retorno)
    IF @IdTrace IS NULL OR NOT (@Destino = 3 OR (@Origen = 3 AND @Destino = 2))
        RETURN 0;

    -- Dominio del vehiculo del recurso
    SELECT TOP 1 @DomActual = LTRIM(RTRIM(Dominio))
    FROM Vehiculo WITH (NOLOCK)
    WHERE IdRecurso = @IdRecurso
    ORDER BY IdVehiculo;

    IF ISNULL(@DomActual, '') = ''
        RETURN 0;   -- el recurso no es un vehiculo con dominio

    BEGIN TRY
        IF @Destino = 3
        BEGIN
            ------------------------------------------------------------------
            -- BAJA: el vehiculo deja de estar disponible y lo sustituye el dominio de Observaciones
            ------------------------------------------------------------------
            SET @DomNuevo = LEFT(LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(ISNULL(@Observ, ''), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''))), 51);

            IF @DomNuevo = ''
                SELECT @Resultado = 'Aviso', @Detalle = 'Baja sin dominio sustituto en Observaciones';
            ELSE IF LEN(@DomNuevo) > 50
                SELECT @Resultado = 'Aviso', @Detalle = 'Baja: Observaciones no es un dominio (mas de 50 caracteres)';
            ELSE IF @DomNuevo = @DomActual
                SELECT @Resultado = 'Aviso', @Detalle = 'Baja: el dominio sustituto es el mismo dominio';
            ELSE IF NOT EXISTS (SELECT 1 FROM Z_Periodos WITH (NOLOCK) WHERE Dominio = @DomActual)
                SELECT @Resultado = 'Aviso', @Detalle = 'Baja: el dominio no existe en Z_Periodos';
            ELSE
            BEGIN
                BEGIN TRAN;

                -- a) cerrar el tramo abierto vigente del vehiculo que se va
                UPDATE Z_Periodos
                SET FechaNodisponible = @Ahora
                OUTPUT inserted.IdPeriodo, inserted.Agrupador, inserted.InicioPeriodo, inserted.FinPeriodo
                INTO @Tramos (IdPeriodo, Agrupador, InicioPeriodo, FinPeriodo)
                WHERE Dominio = @DomActual
                  AND FechaNodisponible IS NULL
                  AND @Hoy BETWEEN InicioPeriodo AND FinPeriodo;

                -- b) tramo nuevo del sustituto, copiado del que se cerro
                INSERT Z_Periodos (IdPeriodo, Agrupador, Dominio, InicioPeriodo, FinPeriodo, FechaRegistroPeriodo, DominioSustituye)
                SELECT IdPeriodo, Agrupador, @DomNuevo, InicioPeriodo, FinPeriodo, @Ahora, @DomActual
                FROM @Tramos;

                SELECT @Filas = COUNT(*) FROM @Tramos;

                COMMIT TRAN;

                IF @Filas = 0
                    SELECT @Resultado = 'Aviso', @Detalle = 'Baja: sin periodo vigente abierto para el dominio';
                ELSE
                    SELECT @Resultado = 'OK',
                           @Detalle   = 'Baja: sustituido por ' + @DomNuevo + ', tramos=' + CONVERT(VARCHAR(10), @Filas);
            END
        END
        ELSE
        BEGIN
            ------------------------------------------------------------------
            -- RETORNO (3 -> 2): el vehiculo vuelve y reemplaza a quien lo habia sustituido
            ------------------------------------------------------------------
            BEGIN TRAN;

            -- a) cerrar el tramo abierto de quien lo sustituyo (solo en periodos donde el titular dejo un tramo cerrado)
            UPDATE s
            SET FechaNodisponible = @Ahora
            OUTPUT inserted.IdPeriodo, inserted.Agrupador, inserted.InicioPeriodo, inserted.FinPeriodo, inserted.Dominio
            INTO @Tramos (IdPeriodo, Agrupador, InicioPeriodo, FinPeriodo, Dominio)
            FROM Z_Periodos s
            WHERE s.DominioSustituye = @DomActual
              AND s.FechaNodisponible IS NULL
              AND @Hoy BETWEEN s.InicioPeriodo AND s.FinPeriodo
              AND EXISTS (SELECT 1 FROM Z_Periodos a
                          WHERE a.Dominio = @DomActual
                            AND a.FechaNodisponible IS NOT NULL
                            AND a.IdPeriodo = s.IdPeriodo
                            AND ISNULL(a.Agrupador, '') = ISNULL(s.Agrupador, '')
                            AND a.InicioPeriodo = s.InicioPeriodo
                            AND a.FinPeriodo = s.FinPeriodo)
              AND NOT EXISTS (SELECT 1 FROM Z_Periodos a
                              WHERE a.Dominio = @DomActual
                                AND a.FechaNodisponible IS NULL
                                AND a.IdPeriodo = s.IdPeriodo
                                AND ISNULL(a.Agrupador, '') = ISNULL(s.Agrupador, '')
                                AND a.InicioPeriodo = s.InicioPeriodo
                                AND a.FinPeriodo = s.FinPeriodo);

            -- b) tramo nuevo del titular, que vuelve a reemplazar al sustituto
            INSERT Z_Periodos (IdPeriodo, Agrupador, Dominio, InicioPeriodo, FinPeriodo, FechaRegistroPeriodo, DominioSustituye)
            SELECT IdPeriodo, Agrupador, @DomActual, InicioPeriodo, FinPeriodo, @Ahora, RTRIM(Dominio)
            FROM @Tramos;

            SELECT @Filas = COUNT(*) FROM @Tramos;

            COMMIT TRAN;

            IF @Filas = 0
                SELECT @Resultado = 'Aviso', @Detalle = 'Retorno: no hay tramo abierto de un sustituto directo (ya retomado, o el sustituto tambien se fue)';
            ELSE
                SELECT @Resultado = 'OK', @Detalle = 'Retorno: vuelve a reemplazar al sustituto, tramos=' + CONVERT(VARCHAR(10), @Filas);
        END
    END TRY

    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRAN;

        SELECT @Resultado = 'Error', @Detalle = ERROR_MESSAGE();
    END CATCH

    IF @Resultado IS NOT NULL
    BEGIN
        BEGIN TRY   -- el Log nunca debe hacer fallar el SP
            INSERT Log (Categoria, Descripcion, FechaHora)
            VALUES ('SustituyeDominio',
                    @Resultado + ' IdRecurso=' + CONVERT(VARCHAR(20), @IdRecurso) + ' Dominio=' + @DomActual + ' ' + @Detalle,
                    GETUTCDATE());
        END TRY
        BEGIN CATCH
        END CATCH
    END
END
