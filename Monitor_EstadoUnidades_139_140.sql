/* ============================================================================
   MONITOR DE ESTADO DE UNIDADES — Operaciones 139 / 140      (v3 - optimizada)
   ----------------------------------------------------------------------------
   - Un solo SELECT (sin DECLARE, sin temp tables) para el portal UNIGIS.
   - Por vehículo se lee UN solo evento GPS confiable (Codigo 209/7/6) y SOLO
     dentro de los últimos 30 minutos. Si no hay evento en la ventana, la unidad
     queda como SIN GPS y no se evalúa ninguna geocerca.
   - Por vehículo se toma un "viaje rector" con prioridad:
       90 En Tránsito > 93 En Proceso de Carga > 92 Programado > 97 Inicial
     (99 Finalizado nunca se considera).

   QUÉ CAMBIÓ RESPECTO A LA v2 (causas de los >20 min):
     1. La cadena pesada (Evento + geocercas) se referenciaba varias veces
        (Tot, Lineas y, sobre todo, Filas -> una ejecución POR CADA línea de
        transporte). Ahora hay UNA sola referencia: todo el HTML se arma en una
        sola pasada, fila a fila, con funciones de ventana para totales y
        encabezados de sección.
     2. Evento: antes se recorría hacia atrás TODO el historial del vehículo
        con key lookup para validar Codigo. Ahora se calcula una sola vez el
        menor IdEvento de la ventana de 30 min (seek en IX_FechaHora) y cada
        vehículo hace seek (IdVehiculo, IdEvento >= MinId): un rango minúsculo.
     3. Geocercas de Parada (depósito / última / intermedia): una sola pasada
        por viaje, sin repetir subconsultas MAX(Orden).
     4. Dibujo IdCondicion=7 con el índice espacial forzado (IX_Geografia) y
        Z_EstacionesDeServicioYPF solo se evalúan si el resultado puede cambiar
        la clasificación.
   ----------------------------------------------------------------------------
   AJUSTAR SI HACE FALTA:
     * Ventana GPS: CTE Ventana, DATEADD(MINUTE,-30,...)
     * Evento.Fecha INT yyyymmdd / Evento.Hora INT hhmmss, guardados en UTC
     * URL del viaje (cloud-test.unigis.com/TCC/...) -> instancia correcta
     * DATEADD(HOUR,-3) -> huso horario de visualización (ART)
     * INDEX(IX_Geografia) en la CTE Zonas2: si el nombre del índice cambia,
       quitar el hint (el resto funciona igual, solo más lento)
   ============================================================================ */
;WITH
/* ----------------------------------------------------------
   0. VENTANA DE TIEMPO GPS (UTC) y límite inferior de IdEvento
   ---------------------------------------------------------- */
Ventana AS (
    SELECT CAST(CONVERT(CHAR(8), W.Desde, 112) AS INT)                      AS FDesde,
           CAST(REPLACE(CONVERT(CHAR(8), W.Desde, 108), ':', '') AS INT)    AS HDesde,
           CAST(CONVERT(CHAR(8), GETUTCDATE(), 112) AS INT)                 AS FHasta
    FROM (SELECT DATEADD(MINUTE, -30, GETUTCDATE()) AS Desde) W
),

/* Menor IdEvento con fecha/hora dentro de la ventana. Solo toca ~30 min de
   eventos (seek por IX_FechaHora). Dos ramas para que cada una sea un seek
   limpio y soporte el cruce de medianoche. */
MinId AS (
    SELECT MIN(X.Id) AS Id
    FROM (
        SELECT MIN(E.IdEvento) AS Id
        FROM Evento E WITH (NOLOCK)
        CROSS JOIN Ventana W
        WHERE E.Fecha = W.FDesde AND E.Hora >= W.HDesde
        UNION ALL
        SELECT MIN(E.IdEvento)
        FROM Evento E WITH (NOLOCK)
        CROSS JOIN Ventana W
        WHERE E.Fecha > W.FDesde AND E.Fecha <= W.FHasta
    ) X
),

/* ----------------------------------------------------------
   1. VIAJE RECTOR por vehículo (uno solo, por prioridad).
      Sustituye a la antigua CTE Flota: un vehículo por fila.
   ---------------------------------------------------------- */
ViajeActivo AS (
    SELECT IdVehiculo, IdViaje, IdEstadoViaje
    FROM (
        SELECT V.IdVehiculo, V.IdViaje, V.IdEstadoViaje,
               ROW_NUMBER() OVER (
                   PARTITION BY V.IdVehiculo
                   ORDER BY CASE V.IdEstadoViaje
                                WHEN 90 THEN 1   -- En Tránsito
                                WHEN 93 THEN 2   -- En Proceso de Carga
                                WHEN 92 THEN 3   -- Programado
                                WHEN 97 THEN 4   -- Inicial
                                ELSE 9 END,
                            V.IdViaje DESC) AS rn
        FROM Jornada J WITH (NOLOCK)
        JOIN Viaje   V WITH (NOLOCK) ON V.IdJornada = J.IdJornada
        WHERE J.IdOperacion IN (139, 140)
          AND V.IdEstadoViaje IN (90, 92, 93, 97)
          AND V.IdVehiculo IS NOT NULL
    ) x
    WHERE rn = 1
),

/* ----------------------------------------------------------
   2. ÚLTIMO EVENTO GPS confiable por vehículo, SOLO si cae en la ventana
   ---------------------------------------------------------- */
UltimoGps AS (
    SELECT VA.IdVehiculo, VA.IdViaje, VA.IdEstadoViaje,
           /* Fecha INT (yyyymmdd) + Hora INT (hhmmss) -> DATETIME (UTC) */
           TRY_CONVERT(DATETIME,
               CAST(G.Fecha AS CHAR(8)) + ' '
               + STUFF(STUFF(RIGHT('000000' + CAST(G.Hora AS VARCHAR(6)), 6), 3, 0, ':'), 6, 0, ':')
           ) AS Fecha,
           CASE WHEN C.Ok = 1 THEN G.Latitud   END                AS Lat,
           CASE WHEN C.Ok = 1 THEN G.Longitud  END                AS Lon,
           CASE WHEN C.Ok = 1 THEN ISNULL(G.Velocidad, 0) END     AS Vel,
           CASE WHEN C.Ok = 1 THEN C.Punto END                    AS Punto,
           CASE WHEN C.Ok = 1 THEN 1 ELSE 0 END                   AS HasGps
    FROM ViajeActivo VA
    CROSS JOIN Ventana W
    CROSS JOIN MinId   M
    OUTER APPLY (
        /* seek IX_Vehiculo (IdVehiculo, IdEvento >= MinId), hacia atrás, TOP 1 */
        SELECT TOP 1 E.IdEvento, E.Fecha, E.Hora, E.Latitud, E.Longitud, E.Velocidad
        FROM Evento E WITH (NOLOCK)
        WHERE E.IdVehiculo = VA.IdVehiculo
          AND E.IdEvento  >= M.Id
          AND E.Codigo IN ('209', '7', '6')
          AND (E.Fecha > W.FDesde OR (E.Fecha = W.FDesde AND E.Hora >= W.HDesde))
        ORDER BY E.IdEvento DESC
    ) G
    OUTER APPLY (
        /* Point nunca recibe NULL ni valores fuera de rango (Msg 6569 / 6522) */
        SELECT CASE WHEN G.Latitud  BETWEEN  -90 AND  90
                     AND G.Longitud BETWEEN -180 AND 180 THEN 1 ELSE 0 END AS Ok,
               geography::Point(CASE WHEN G.Latitud  BETWEEN  -90 AND  90 THEN G.Latitud  ELSE 0 END,
                                CASE WHEN G.Longitud BETWEEN -180 AND 180 THEN G.Longitud ELSE 0 END,
                                4326) AS Punto
    ) C
),

/* ----------------------------------------------------------
   3a. GEOCERCAS DE PARADA (depósito / última / intermedia):
       una sola pasada por viaje, solo con GPS válido.
   ---------------------------------------------------------- */
Zonas AS (
    SELECT U.IdVehiculo, U.IdViaje, U.IdEstadoViaje, U.Fecha, U.Lat, U.Lon, U.Vel, U.Punto, U.HasGps,
           PZ.NumEntregas, PZ.EnDeposito, PZ.EnUltimaParada, PZ.EnParadaIntermedia
    FROM UltimoGps U
    OUTER APPLY (
        SELECT ISNULL(SUM(CASE WHEN H.IdTipoParada = 3 THEN 1 ELSE 0 END), 0)                                AS NumEntregas,
               ISNULL(MAX(CASE WHEN H.IdTipoParada = 1 AND H.Hit = 1 THEN 1 ELSE 0 END), 0)                  AS EnDeposito,
               ISNULL(MAX(CASE WHEN H.IdTipoParada = 3 AND H.Orden  = H.MaxOrd AND H.Hit = 1 THEN 1 ELSE 0 END), 0) AS EnUltimaParada,
               ISNULL(MAX(CASE WHEN H.IdTipoParada = 3 AND H.Orden  < H.MaxOrd AND H.Hit = 1 THEN 1 ELSE 0 END), 0) AS EnParadaIntermedia
        FROM (
            SELECT P.IdTipoParada, P.Orden, P.MaxOrd,
                   /* depósito solo en 92/93; paradas de entrega solo en 90 */
                   CASE WHEN U.HasGps = 1
                         AND ((P.IdTipoParada = 1 AND U.IdEstadoViaje IN (92, 93))
                           OR (P.IdTipoParada = 3 AND U.IdEstadoViaje = 90))
                        THEN D.Geografia.STIntersects(U.Punto)
                        ELSE 0 END AS Hit
            FROM (
                SELECT PA.IdTipoParada, PA.Orden, PA.IdDibujo,
                       MAX(CASE WHEN PA.IdTipoParada = 3 THEN PA.Orden END) OVER () AS MaxOrd
                FROM Parada PA WITH (NOLOCK)
                WHERE PA.IdViaje = U.IdViaje
            ) P
            LEFT JOIN Dibujo D WITH (NOLOCK) ON D.IdDibujo = P.IdDibujo
        ) H
    ) PZ
),

/* ----------------------------------------------------------
   3b. GEOCERCAS "PESADAS" (dibujo cond. 7 y estaciones YPF):
       solo en tránsito y solo si pueden cambiar la clasificación
       (si ya es "Detenido en Parada" no hace falta evaluarlas).
   ---------------------------------------------------------- */
Zonas2 AS (
    SELECT Z.IdVehiculo, Z.IdViaje, Z.IdEstadoViaje, Z.Fecha, Z.Lat, Z.Lon, Z.Vel, Z.HasGps,
           Z.NumEntregas, Z.EnDeposito, Z.EnUltimaParada, Z.EnParadaIntermedia,
           ISNULL(C7.Hit, 0) AS EnCond7,
           ISNULL(ES.Hit, 0) AS EnEstacion
    FROM Zonas Z
    OUTER APPLY (
        SELECT TOP 1 1 AS Hit
        FROM Dibujo D WITH (NOLOCK, INDEX(IX_Geografia))
        WHERE Z.HasGps = 1 AND Z.IdEstadoViaje = 90
          AND NOT (Z.EnUltimaParada = 0 AND Z.EnParadaIntermedia = 1 AND Z.NumEntregas > 1)
          AND D.IdCondicion = 7 AND D.Eliminado = 0
          AND D.Geografia.Filter(Z.Punto) = 1
          AND D.Geografia.STIntersects(Z.Punto) = 1
    ) C7
    OUTER APPLY (
        SELECT TOP 1 1 AS Hit
        FROM Z_EstacionesDeServicioYPF S WITH (NOLOCK)
        WHERE Z.HasGps = 1 AND Z.IdEstadoViaje = 90
          AND Z.EnUltimaParada = 0
          AND NOT (Z.EnParadaIntermedia = 1 AND Z.NumEntregas > 1)
          AND S.Geografia.STIntersects(Z.Punto) = 1      -- tabla SIN índice espacial
    ) ES
),

/* ----------------------------------------------------------
   4. CLASIFICACIÓN DEL ESTADO DE LA UNIDAD
   ---------------------------------------------------------- */
Clasif AS (
    SELECT Z.IdVehiculo, Z.IdViaje, Z.IdEstadoViaje, Z.Fecha, Z.Vel, Z.HasGps,
           LTRIM(RTRIM(V.Dominio))                                   AS Placa,
           UPPER(ISNULL(T.RazonSocial, N'SIN LÍNEA DE TRANSPORTE'))  AS RazonSocial,
           CASE Z.IdEstadoViaje
                WHEN 90 THEN N'En Tránsito'
                WHEN 92 THEN N'Programado'
                WHEN 93 THEN N'En Proceso de Carga'
                WHEN 97 THEN N'Inicial'
                ELSE N'-' END                                         AS EstadoViajeTxt,
           CASE
             WHEN Z.IdViaje IS NULL                                                       THEN 'sinviaje'
             WHEN Z.IdEstadoViaje = 97                                                    THEN 'est'
             WHEN Z.HasGps = 0                                                            THEN 'sgps'
             WHEN Z.IdEstadoViaje = 92 AND Z.EnDeposito = 1                               THEN 'ecar'
             WHEN Z.IdEstadoViaje = 93 AND Z.EnDeposito = 1                               THEN 'car'
             WHEN Z.IdEstadoViaje = 90 AND Z.EnUltimaParada = 1 AND Z.EnCond7 = 1         THEN 'des'
             WHEN Z.IdEstadoViaje = 90 AND Z.EnUltimaParada = 1                           THEN 'edes'
             WHEN Z.IdEstadoViaje = 90 AND Z.EnParadaIntermedia = 1 AND Z.NumEntregas > 1 THEN 'detp'
             WHEN Z.IdEstadoViaje = 90 AND Z.EnEstacion = 0
                                       AND Z.EnCond7 = 0 AND Z.Vel > 0                    THEN 'carr'
             WHEN Z.IdEstadoViaje = 90 AND Z.EnEstacion = 0
                                       AND Z.EnCond7 = 0                                  THEN 'det'
             ELSE 'otro'
           END                                                        AS K,
           /* detalle de ubicación para la columna informativa */
           CASE WHEN Z.HasGps = 0 THEN N'Sin posición'
                ELSE STUFF(
                     CASE WHEN Z.EnDeposito         = 1 THEN N' · Depósito origen'   ELSE N'' END
                   + CASE WHEN Z.EnUltimaParada     = 1 THEN N' · Última parada'     ELSE N'' END
                   + CASE WHEN Z.EnParadaIntermedia = 1 THEN N' · Parada intermedia' ELSE N'' END
                   + CASE WHEN Z.EnEstacion         = 1 THEN N' · Estación YPF'      ELSE N'' END
                   + CASE WHEN Z.EnCond7            = 1 THEN N' · Dibujo cond. 7'    ELSE N'' END
                   , 1, 3, N'')
           END                                                        AS Ubicacion
    FROM Zonas2 Z
    JOIN      Vehiculo   V WITH (NOLOCK) ON V.IdVehiculo   = Z.IdVehiculo
    LEFT JOIN Transporte T WITH (NOLOCK) ON T.IdTransporte = V.IdTransporte
),

Datos AS (
    SELECT C.IdVehiculo, C.IdViaje, C.Placa, C.RazonSocial, C.EstadoViajeTxt, C.K, C.HasGps, C.Vel,
           CASE C.K
                WHEN 'carr'     THEN N'CARRETEANDO'
                WHEN 'det'      THEN N'DETENIDO'
                WHEN 'est'      THEN N'ESPERA SIN TAREA'
                WHEN 'ecar'     THEN N'ESPERA CARGA'
                WHEN 'car'      THEN N'CARGA'
                WHEN 'detp'     THEN N'DETENIDO EN PARADA'
                WHEN 'edes'     THEN N'ESPERA DESCARGA'
                WHEN 'des'      THEN N'DESCARGA'
                WHEN 'sgps'     THEN N'SIN GPS'
                WHEN 'sinviaje' THEN N'SIN VIAJE ACTIVO'
                ELSE N'FUERA DE REGLA' END                                   AS Estado,
           ISNULL(NULLIF(C.Ubicacion, N''), N'Fuera de geocercas')           AS UbicacionTxt,
           CASE WHEN C.Fecha IS NULL THEN N'-'
                ELSE CONVERT(NVARCHAR(16), DATEADD(HOUR, -3, C.Fecha), 120) END AS UltReporte,
           DATEDIFF(MINUTE, C.Fecha, GETUTCDATE())                          AS MinAgo,
           CASE WHEN C.Fecha IS NULL THEN N'-'
                WHEN DATEDIFF(MINUTE, C.Fecha, GETUTCDATE()) < 60
                     THEN CAST(DATEDIFF(MINUTE, C.Fecha, GETUTCDATE()) AS NVARCHAR(10)) + N' min'
                ELSE CAST(DATEDIFF(MINUTE, C.Fecha, GETUTCDATE()) / 60 AS NVARCHAR(10)) + N' h' END AS HaceTxt
    FROM Clasif C
),

/* ----------------------------------------------------------
   5. TOTALES con funciones de ventana: Datos se referencia UNA sola vez
   ---------------------------------------------------------- */
R1 AS (
    SELECT D.*,
           COUNT(*) OVER (PARTITION BY D.RazonSocial)                                                    AS LTotal,
           SUM(CASE WHEN D.K IN ('carr','det','detp','edes','des','car','ecar') THEN 1 ELSE 0 END)
               OVER (PARTITION BY D.RazonSocial)                                                         AS LActivas,
           SUM(CASE WHEN D.K = 'sgps' THEN 1 ELSE 0 END) OVER (PARTITION BY D.RazonSocial)               AS LSinGps,
           ROW_NUMBER() OVER (PARTITION BY D.RazonSocial
                              ORDER BY CASE D.K WHEN 'sgps' THEN 0 WHEN 'otro' THEN 1 ELSE 2 END,
                                       D.Estado, D.Placa, D.IdVehiculo)                                  AS rnL,
           DENSE_RANK() OVER (ORDER BY D.RazonSocial)                                                    AS dr,
           COUNT(*)                                        OVER () AS gTot,
           SUM(CASE WHEN D.K = 'carr'     THEN 1 ELSE 0 END) OVER () AS gCarr,
           SUM(CASE WHEN D.K = 'det'      THEN 1 ELSE 0 END) OVER () AS gDet,
           SUM(CASE WHEN D.K = 'est'      THEN 1 ELSE 0 END) OVER () AS gEst,
           SUM(CASE WHEN D.K = 'ecar'     THEN 1 ELSE 0 END) OVER () AS gEcar,
           SUM(CASE WHEN D.K = 'car'      THEN 1 ELSE 0 END) OVER () AS gCar,
           SUM(CASE WHEN D.K = 'detp'     THEN 1 ELSE 0 END) OVER () AS gDetp,
           SUM(CASE WHEN D.K = 'edes'     THEN 1 ELSE 0 END) OVER () AS gEdes,
           SUM(CASE WHEN D.K = 'des'      THEN 1 ELSE 0 END) OVER () AS gDes,
           SUM(CASE WHEN D.K = 'sgps'     THEN 1 ELSE 0 END) OVER () AS gSgps,
           SUM(CASE WHEN D.K = 'sinviaje' THEN 1 ELSE 0 END) OVER () AS gSinv,
           SUM(CASE WHEN D.K = 'otro'     THEN 1 ELSE 0 END) OVER () AS gOtro
    FROM Datos D
),

R2 AS (
    SELECT R.*,
           ROW_NUMBER() OVER (ORDER BY R.LTotal DESC, R.RazonSocial, R.rnL) AS gOrd,
           MAX(R.dr) OVER ()                                                AS gLineas
    FROM R1 R
)

/* ----------------------------------------------------------
   6. SALIDA: se arma el HTML fila a fila (la primera fila trae el encabezado,
      la primera de cada línea abre la sección, la última de cada línea la
      cierra y la última global cierra el documento).
   ---------------------------------------------------------- */
SELECT ISNULL(
(
  SELECT CAST(N'' AS NVARCHAR(MAX))
  /* ===================== ENCABEZADO (solo 1ª fila) ===================== */
  + CASE WHEN R.gOrd = 1 THEN
N'<div id="um">
<style>
@import url(https://fonts.googleapis.com/css2?family=Outfit:wght@500;600;700&family=Inter:wght@400;500;600&family=JetBrains+Mono:wght@400;500;600&display=swap);
.uni_cont_all{width:100%!important;max-width:none!important;height:auto!important;min-height:0!important;overflow:visible!important;}
#um{width:100%;padding:22px 24px;box-sizing:border-box;font-family:"Inter",sans-serif;color:#e2e8f0;
  background:radial-gradient(1200px 500px at 10% -10%,rgba(56,189,248,.10),transparent 60%),
             radial-gradient(900px 400px at 100% 0%,rgba(167,139,250,.08),transparent 60%),#0b1220;
  border-radius:16px;border:1px solid rgba(148,163,184,.12);position:relative;overflow:hidden;
  box-shadow:0 10px 40px rgba(0,0,0,.45)}
#um *{box-sizing:border-box}
#um a{color:inherit}
/* ---- pantalla completa (API nativa o modo fijo) ---- */
#um:fullscreen,#um.um-fs{position:fixed;inset:0;z-index:2147483000;width:100vw;height:100vh;max-width:none;
  border-radius:0;border:none;overflow-y:auto;padding:28px 36px}
#um:fullscreen .um-h,#um.um-fs .um-h{position:sticky;top:-28px;background:#0b1220;z-index:5;padding-top:6px;margin-top:-6px}
/* HEADER */
.um-h{display:flex;align-items:center;justify-content:space-between;gap:18px;padding-bottom:16px;margin-bottom:16px;
  border-bottom:1px solid rgba(148,163,184,.12);flex-wrap:wrap}
.um-t{font-family:"Outfit",sans-serif;font-size:21px;font-weight:700;color:#f8fafc;letter-spacing:.2px}
.um-t small{display:block;font-family:"Inter",sans-serif;font-size:11px;letter-spacing:.8px;color:#64748b;font-weight:500;margin-top:5px;text-transform:uppercase}
.um-right{display:flex;align-items:center;gap:10px;flex-wrap:wrap}
.um-kpis{display:flex;gap:10px;flex-wrap:wrap}
.kpi{padding:9px 18px;border-radius:12px;background:rgba(30,41,59,.65);border:1px solid rgba(148,163,184,.14);
  display:flex;flex-direction:column;align-items:center;min-width:96px;position:relative;overflow:hidden}
.kpi::before{content:"";position:absolute;left:0;right:0;top:0;height:2px;background:var(--c,#38bdf8);opacity:.8}
.kpi b{font-family:"Outfit",sans-serif;font-size:24px;font-weight:600;line-height:1;color:#f8fafc;font-variant-numeric:tabular-nums}
.kpi span{font-size:10px;letter-spacing:.9px;color:#64748b;font-weight:500;margin-top:5px;text-transform:uppercase}
.live{display:flex;align-items:center;gap:7px;font-size:10px;font-weight:600;letter-spacing:1.4px;color:#38bdf8;
  padding:8px 14px;border-radius:10px;border:1px solid rgba(56,189,248,.3);background:rgba(56,189,248,.08)}
.live i{width:7px;height:7px;border-radius:50%;background:#38bdf8;box-shadow:0 0 8px #38bdf8;animation:umblink 1.4s ease-in-out infinite}
@keyframes umblink{0%,100%{opacity:1}50%{opacity:.15}}
.fsbtn{display:flex;align-items:center;gap:8px;padding:8px 14px;border-radius:10px;cursor:pointer;
  border:1px solid rgba(148,163,184,.2);background:rgba(30,41,59,.75);color:#e2e8f0;
  font-family:"Inter",sans-serif;font-size:11px;font-weight:600;letter-spacing:.6px;transition:background .15s,border-color .15s}
.fsbtn:hover{background:#1e293b;border-color:#38bdf8}
.fsbtn svg{width:14px;height:14px;stroke:currentColor;fill:none;stroke-width:2;stroke-linecap:round;stroke-linejoin:round}
.fsbtn .ico-x{display:none}
#um:fullscreen .fsbtn .ico-x,#um.um-fs .fsbtn .ico-x{display:block}
#um:fullscreen .fsbtn .ico-fs,#um.um-fs .fsbtn .ico-fs{display:none}
#um:fullscreen .fsbtn,#um.um-fs .fsbtn{border-color:rgba(248,113,113,.45);color:#fca5a5}
/* CHIPS DE ESTADO (filtros) */
.chips{display:grid;grid-template-columns:repeat(auto-fill,minmax(158px,1fr));gap:10px;margin-bottom:16px}
.chip{cursor:pointer;padding:12px 14px 12px 16px;border-radius:12px;border:1px solid rgba(148,163,184,.14);background:rgba(30,41,59,.55);
  position:relative;overflow:hidden;transition:transform .15s,background .15s,border-color .15s;user-select:none;min-height:66px;
  display:flex;flex-direction:column;justify-content:space-between;gap:6px}
.chip::before{content:"";position:absolute;left:0;top:0;bottom:0;width:3px;background:var(--c);opacity:.9}
.chip:hover{transform:translateY(-2px);background:rgba(30,41,59,.9)}
.chip.on{border-color:var(--c);background:color-mix(in srgb,var(--c) 12%,rgba(30,41,59,.9));
  box-shadow:0 0 0 1px var(--c),0 6px 20px color-mix(in srgb,var(--c) 25%,transparent)}
.chip span{font-size:10.5px;letter-spacing:.5px;font-weight:600;color:#94a3b8;text-transform:uppercase;line-height:1.25;white-space:normal}
.chip.on span{color:#e2e8f0}
.chip b{font-family:"Outfit",sans-serif;font-size:24px;font-weight:600;color:#f8fafc;line-height:1;font-variant-numeric:tabular-nums;
  display:flex;align-items:center;gap:8px}
.chip b i{width:9px;height:9px;border-radius:50%;background:var(--c);box-shadow:0 0 8px var(--c);flex-shrink:0}
/* BARRA DE HERRAMIENTAS */
.tools{display:flex;gap:10px;align-items:center;margin-bottom:14px;flex-wrap:wrap}
.srch{flex:1;min-width:220px;padding:10px 14px 10px 38px;border-radius:10px;border:1px solid rgba(148,163,184,.18);background:#111a2c;color:#f1f5f9;
  font-family:"Inter",sans-serif;font-size:13px;outline:none;
  background-image:url("data:image/svg+xml,%3Csvg xmlns=%27http://www.w3.org/2000/svg%27 viewBox=%270 0 24 24%27 fill=%27none%27 stroke=%27%2364748b%27 stroke-width=%272%27 stroke-linecap=%27round%27%3E%3Ccircle cx=%2711%27 cy=%2711%27 r=%278%27/%3E%3Cpath d=%27m21 21-4.3-4.3%27/%3E%3C/svg%3E");
  background-repeat:no-repeat;background-position:12px center;background-size:16px}
.srch::placeholder{color:#64748b}
.srch:focus{border-color:#38bdf8;box-shadow:0 0 0 3px rgba(56,189,248,.15)}
.tbtn{padding:10px 14px;border-radius:10px;border:1px solid rgba(148,163,184,.18);background:#111a2c;color:#cbd5e1;cursor:pointer;
  font-family:"Inter",sans-serif;font-size:11px;font-weight:600;letter-spacing:.6px}
.tbtn:hover{background:#1e293b}
.vis{font-size:11px;letter-spacing:.5px;color:#64748b;font-weight:500;margin-left:auto}
/* SECCIONES POR TRANSPORTE */
.tsec{border-radius:14px;border:1px solid rgba(148,163,184,.14);background:rgba(17,26,44,.85);margin-bottom:12px;overflow:hidden}
.tsec-h{display:flex;align-items:center;gap:12px;padding:13px 18px;cursor:pointer;user-select:none;
  background:linear-gradient(90deg,rgba(56,189,248,.10),rgba(56,189,248,0) 60%)}
.tsec-h:hover{background:linear-gradient(90deg,rgba(56,189,248,.16),rgba(56,189,248,0) 60%)}
.tsec-arrow{color:#38bdf8;font-size:13px;transition:transform .2s;width:14px;text-align:center}
.tsec.col .tsec-arrow{transform:rotate(-90deg)}
.tsec.col .tsec-b{display:none}
.tsec-name{font-family:"Outfit",sans-serif;font-size:15px;font-weight:600;color:#f8fafc;flex:1;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.tsec-mini{font-size:12px;color:#94a3b8;white-space:nowrap;display:flex;gap:6px;align-items:center}
.tsec-mini b{color:#f8fafc;font-family:"Outfit",sans-serif;font-size:14px;font-weight:600;font-variant-numeric:tabular-nums}
.tsec-mini .c-act{color:#4ade80} .tsec-mini .c-sgps{color:#f87171}
.tsec-b{overflow-x:auto}
.tb{width:100%;border-collapse:collapse;min-width:820px}
.tb th{padding:10px 14px;font-size:10px;font-weight:600;letter-spacing:.8px;color:#64748b;text-align:left;white-space:nowrap;
  border-top:1px solid rgba(148,163,184,.1);border-bottom:1px solid rgba(148,163,184,.1);background:#0f172a}
.tb td{padding:9px 14px;font-size:13px;font-weight:400;color:#e2e8f0;border-bottom:1px solid rgba(148,163,184,.06);white-space:nowrap;vertical-align:middle}
.tb td:last-child{white-space:normal;min-width:180px;color:#94a3b8}
.tb tbody tr:nth-child(even) td{background:rgba(148,163,184,.025)}
.tb tbody tr:hover td{background:rgba(56,189,248,.06)}
.td-placa{font-family:"JetBrains Mono","Outfit",monospace;font-size:13px;font-weight:600;letter-spacing:.5px;color:#f8fafc}
.td-dim{color:#94a3b8}
.td-mono{font-family:"JetBrains Mono",monospace;font-size:12px;color:#cbd5e1;font-variant-numeric:tabular-nums}
.td-late{color:#f87171!important;font-weight:600} .td-ok{color:#4ade80!important;font-weight:600}
.lnk{color:#38bdf8!important;font-weight:600;text-decoration:none}
.lnk:hover{text-decoration:underline}
/* BADGES */
.bd{display:inline-flex;align-items:center;gap:7px;padding:4px 11px 4px 9px;border-radius:999px;font-size:11px;font-weight:600;letter-spacing:.4px;
  white-space:nowrap;border:1px solid color-mix(in srgb,var(--c) 45%,transparent);background:color-mix(in srgb,var(--c) 14%,transparent);color:var(--c)}
.bd::before{content:"";width:7px;height:7px;border-radius:50%;background:var(--c);box-shadow:0 0 6px var(--c)}
.bd-carr,.c-carr{--c:#22c55e} .bd-det,.c-det{--c:#f59e0b} .bd-est,.c-est{--c:#94a3b8}
.bd-ecar,.c-ecar{--c:#3b82f6} .bd-car,.c-car{--c:#06b6d4} .bd-detp,.c-detp{--c:#f97316}
.bd-edes,.c-edes{--c:#a78bfa} .bd-des,.c-des{--c:#e879f9} .bd-sgps,.c-sgps{--c:#ef4444}
.bd-sinviaje,.c-sinviaje{--c:#475569} .bd-otro,.c-otro{--c:#64748b} .c-all{--c:#38bdf8}
.empty{padding:36px;text-align:center;color:#475569;letter-spacing:.5px;font-weight:500;display:none}
</style>

<!-- HEADER -->
<div class="um-h">
  <div class="um-t">Estado de Unidades<small>Operaciones 139 &middot; 140 &nbsp;|&nbsp; GPS &uacute;ltimos 30 min &nbsp;|&nbsp; Actualizado ' + CONVERT(NVARCHAR(16), DATEADD(HOUR,-3,GETUTCDATE()), 120) + N'</small></div>
  <div class="um-right">
    <div class="um-kpis">
      <div class="kpi"><b>' + CAST(R.gTot    AS NVARCHAR(10)) + N'</b><span>Unidades</span></div>
      <div class="kpi" style="--c:#a78bfa"><b>' + CAST(R.gLineas AS NVARCHAR(10)) + N'</b><span>L&#237;neas</span></div>
      <div class="kpi" style="--c:#ef4444"><b style="color:#f87171">' + CAST(R.gSgps AS NVARCHAR(10)) + N'</b><span>Sin GPS</span></div>
    </div>
    <div class="live"><i></i>EN VIVO</div>
    <button class="fsbtn" id="um-fsbtn" onclick="umFs()" title="Pantalla completa">
      <svg class="ico-fs" viewBox="0 0 24 24"><path d="M8 3H5a2 2 0 0 0-2 2v3M21 8V5a2 2 0 0 0-2-2h-3M3 16v3a2 2 0 0 0 2 2h3M16 21h3a2 2 0 0 0 2-2v-3"/></svg>
      <svg class="ico-x" viewBox="0 0 24 24"><path d="M18 6 6 18M6 6l12 12"/></svg>
      <span id="um-fslbl">PANTALLA COMPLETA</span>
    </button>
  </div>
</div>

<!-- CHIPS / FILTROS -->
<div class="chips">
  <div class="chip c-all on" data-k="all" onclick="umFil(this)"><span>Todas</span><b><i></i>' + CAST(R.gTot  AS NVARCHAR(10)) + N'</b></div>
  <div class="chip c-carr" data-k="carr" onclick="umFil(this)"><span>Carreteando</span><b><i></i>' + CAST(R.gCarr AS NVARCHAR(10)) + N'</b></div>
  <div class="chip c-det" data-k="det" onclick="umFil(this)"><span>Detenido</span><b><i></i>' + CAST(R.gDet  AS NVARCHAR(10)) + N'</b></div>
  <div class="chip c-detp" data-k="detp" onclick="umFil(this)"><span>Detenido en Parada</span><b><i></i>' + CAST(R.gDetp AS NVARCHAR(10)) + N'</b></div>
  <div class="chip c-ecar" data-k="ecar" onclick="umFil(this)"><span>Espera Carga</span><b><i></i>' + CAST(R.gEcar AS NVARCHAR(10)) + N'</b></div>
  <div class="chip c-car" data-k="car" onclick="umFil(this)"><span>Carga</span><b><i></i>' + CAST(R.gCar  AS NVARCHAR(10)) + N'</b></div>
  <div class="chip c-edes" data-k="edes" onclick="umFil(this)"><span>Espera Descarga</span><b><i></i>' + CAST(R.gEdes AS NVARCHAR(10)) + N'</b></div>
  <div class="chip c-des" data-k="des" onclick="umFil(this)"><span>Descarga</span><b><i></i>' + CAST(R.gDes  AS NVARCHAR(10)) + N'</b></div>
  <div class="chip c-est" data-k="est" onclick="umFil(this)"><span>Espera sin Tarea</span><b><i></i>' + CAST(R.gEst  AS NVARCHAR(10)) + N'</b></div>
  <div class="chip c-sgps" data-k="sgps" onclick="umFil(this)"><span>Sin GPS (30 min)</span><b><i></i>' + CAST(R.gSgps AS NVARCHAR(10)) + N'</b></div>
  <div class="chip c-sinviaje" data-k="sinviaje" onclick="umFil(this)"><span>Sin Viaje Activo</span><b><i></i>' + CAST(R.gSinv AS NVARCHAR(10)) + N'</b></div>
  <div class="chip c-otro" data-k="otro" onclick="umFil(this)"><span>Fuera de Regla</span><b><i></i>' + CAST(R.gOtro AS NVARCHAR(10)) + N'</b></div>
</div>

<!-- HERRAMIENTAS -->
<div class="tools">
  <input class="srch" id="um-q" placeholder="Buscar placa" oninput="umApply()">
  <button class="tbtn" onclick="umAll(false)">EXPANDIR</button>
  <button class="tbtn" onclick="umAll(true)">COLAPSAR</button>
  <span class="vis" id="um-vis"></span>
</div>

<!-- SECCIONES -->
<div id="um-secs">'
     ELSE N'' END

  /* ============ APERTURA DE SECCIÓN POR LÍNEA (1ª fila de la línea) ============ */
  + CASE WHEN R.rnL = 1 THEN
        N'<div class="tsec">'
      + N'<div class="tsec-h" onclick="umTog(this)">'
      + N'<span class="tsec-arrow">&#9662;</span>'
      + N'<span class="tsec-name">' + REPLACE(REPLACE(R.RazonSocial, N'&', N'&amp;'), N'<', N'&lt;') + N'</span>'
      + N'<span class="tsec-mini"><b class="tcount">' + CAST(R.LTotal AS NVARCHAR(10)) + N'</b> unidades'
      + N' &middot; <b class="c-act">' + CAST(R.LActivas AS NVARCHAR(10)) + N'</b> activas'
      + CASE WHEN R.LSinGps > 0 THEN N' &middot; <b class="c-sgps">' + CAST(R.LSinGps AS NVARCHAR(10)) + N'</b> sin GPS' ELSE N'' END
      + N'</span></div>'
      + N'<div class="tsec-b"><table class="tb"><thead><tr>'
      + N'<th>PLACA</th><th>ESTADO UNIDAD</th><th>VIAJE</th><th>ESTADO VIAJE</th>'
      + N'<th>&#218;LTIMO REPORTE</th><th>HACE</th><th>VELOCIDAD</th><th>UBICACI&#211;N</th>'
      + N'</tr></thead><tbody>'
    ELSE N'' END

  /* ============================ FILA DE LA UNIDAD ============================ */
  + N'<tr data-k="' + R.K + N'" data-p="' + ISNULL(R.Placa, N'') + N'">'
  + N'<td class="td-placa">' + ISNULL(R.Placa, N'-') + N'</td>'
  + N'<td><span class="bd bd-' + R.K + N'">' + R.Estado + N'</span></td>'
  + N'<td>' + CASE WHEN R.IdViaje IS NULL THEN N'-'
                   ELSE N'<a class="lnk" target="_blank" href="https://cloud-test.unigis.com/TCC/tracking/Shipment/index?id='
                        + CAST(R.IdViaje AS NVARCHAR(20)) + N'">' + CAST(R.IdViaje AS NVARCHAR(20)) + N'</a>' END + N'</td>'
  + N'<td class="td-dim">' + R.EstadoViajeTxt + N'</td>'
  + N'<td class="td-mono">' + R.UltReporte + N'</td>'
  + N'<td class="td-mono ' + CASE WHEN R.MinAgo > 30 THEN N'td-late' ELSE N'td-ok' END + N'">' + R.HaceTxt + N'</td>'
  + N'<td class="td-mono">' + CASE WHEN R.HasGps = 0 THEN N'-' ELSE CAST(CAST(R.Vel AS INT) AS NVARCHAR(10)) + N' km/h' END + N'</td>'
  + N'<td class="td-dim">' + R.UbicacionTxt + N'</td>'
  + N'</tr>'

  /* ============ CIERRE DE SECCIÓN POR LÍNEA (última fila de la línea) ============ */
  + CASE WHEN R.rnL = R.LTotal THEN N'</tbody></table></div></div>' ELSE N'' END

  /* ===================== CIERRE + JS (última fila global) ===================== */
  + CASE WHEN R.gOrd = R.gTot THEN
N'</div>
<div class="empty" id="um-empty">Sin unidades para el filtro seleccionado</div>
</div>

<script>
(function(){
  function fix(){
    var el=document.getElementById("um"); if(!el)return;
    var p=el.parentElement,s=0;
    while(p&&s<12){
      p.style.setProperty("height","auto","important");
      p.style.setProperty("max-height","none","important");
      p.style.setProperty("min-height","0","important");
      p.style.setProperty("overflow","visible","important");
      p.style.setProperty("width","100%","important");
      p.style.setProperty("max-width","none","important");
      p=p.parentElement;s++;
    }
  }
  fix();setTimeout(fix,200);setTimeout(fix,600);setTimeout(fix,1500);
  if(window.ResizeObserver)new ResizeObserver(fix).observe(document.getElementById("um"));

  var cur="all";
  window.umApply=function(){
    var q=(document.getElementById("um-q").value||"").toUpperCase().trim();
    var vis=0;
    var rows=document.querySelectorAll("#um-secs tbody tr");
    for(var i=0;i<rows.length;i++){
      var r=rows[i];
      var ok=(cur==="all"||r.getAttribute("data-k")===cur)&&(!q||(r.getAttribute("data-p")||"").toUpperCase().indexOf(q)>-1);
      r.style.display=ok?"":"none"; if(ok)vis++;
    }
    var secs=document.querySelectorAll("#um-secs .tsec");
    for(var j=0;j<secs.length;j++){
      var s=secs[j], n=0, tr=s.querySelectorAll("tbody tr");
      for(var k=0;k<tr.length;k++){ if(tr[k].style.display!=="none")n++; }
      s.querySelector(".tcount").textContent=n;
      s.style.display=n?"":"none";
    }
    document.getElementById("um-vis").textContent=vis+" unidades visibles";
    document.getElementById("um-empty").style.display=vis?"none":"block";
  };
  window.umFil=function(ch){
    cur=ch.getAttribute("data-k");
    var cs=document.querySelectorAll("#um .chip");
    for(var i=0;i<cs.length;i++)cs[i].className=cs[i].className.replace(" on","");
    ch.className+=" on";
    umAll(false); umApply();
  };
  window.umTog=function(h){ var s=h.parentElement; s.className=(s.className.indexOf(" col")>-1)?s.className.replace(" col",""):s.className+" col"; };
  window.umAll=function(col){
    var secs=document.querySelectorAll("#um-secs .tsec");
    for(var i=0;i<secs.length;i++){ secs[i].className="tsec"+(col?" col":""); }
  };
  umApply();

  /* ---- Pantalla completa: API nativa; si el portal la bloquea, modo fijo ---- */
  var um=document.getElementById("um");
  function fsOn(){ return !!(document.fullscreenElement||document.webkitFullscreenElement)||um.className.indexOf("um-fs")>-1; }
  function lbl(){ document.getElementById("um-fslbl").textContent=fsOn()?"SALIR":"PANTALLA COMPLETA"; }
  window.umFs=function(){
    if(fsOn()){
      if(document.fullscreenElement&&document.exitFullscreen)document.exitFullscreen();
      else if(document.webkitFullscreenElement&&document.webkitExitFullscreen)document.webkitExitFullscreen();
      um.className=um.className.replace(" um-fs","");
      document.body.style.overflow="";
      lbl(); return;
    }
    var req=um.requestFullscreen||um.webkitRequestFullscreen;
    var p=null;
    try{ p=req?req.call(um):null; }catch(e){ p=null; }
    if(p&&p.then){ p.then(lbl).catch(function(){ um.className+=" um-fs"; document.body.style.overflow="hidden"; lbl(); }); }
    else if(!req){ um.className+=" um-fs"; document.body.style.overflow="hidden"; lbl(); }
    else{ setTimeout(lbl,150); }
  };
  document.addEventListener("fullscreenchange",lbl);
  document.addEventListener("webkitfullscreenchange",lbl);
  document.addEventListener("keydown",function(e){
    if(e.key==="Escape"&&um.className.indexOf("um-fs")>-1){ um.className=um.className.replace(" um-fs",""); document.body.style.overflow=""; lbl(); }
  });

  /* Auto-refresh cada 10 min */
  setTimeout(function(){ location.reload(); }, 600000);
})();
</script>'
     ELSE N'' END
  FROM R2 R
  ORDER BY R.gOrd
  FOR XML PATH(''), TYPE
).value('.', 'NVARCHAR(MAX)'),
/* sin unidades con viaje activo: mensaje mínimo + auto-refresh */
N'<div style="padding:24px;font-family:sans-serif;color:#94a3b8">Sin unidades con viaje activo en las operaciones 139 / 140.</div><script>setTimeout(function(){location.reload()},600000)</script>'
) AS [ ]
;
