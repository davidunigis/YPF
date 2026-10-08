# Rama Reportes-Areas — contexto para Claude Code

Repositorio de consultas, SP y reportes de UNIGIS para YPF (SQL Server / T-SQL).
Esta rama agrupa los SP que llenan tablas de **reportes de áreas**.

## Estructura
- `SP/` — un archivo `.sql` por procedimiento, con el nombre exacto del SP
  (ej. `SP/Z_SP_ItinerarioViaje.sql`). Cada archivo contiene el `ALTER PROCEDURE` completo.
- `Reportes/` — consultas de reporte de UNIGIS (un `.sql` por reporte). Se guardan tal cual
  se cargan en la plataforma, con el placeholder `!!ID_VIAJE!!` (lo reemplaza la plataforma;
  no es T-SQL válido por sí solo).

## SP en alcance
- `Z_SP_ItinerarioViaje` — llena la tabla de reporte `dbo.Z_ItinerarioViaje` (itinerario
  cronológico de un viaje) y devuelve 3 resultsets: resumen de novedades, itinerario y
  métrica de control por parada.
  - Parámetro principal: `@IdViaje INT`. El resto son umbrales con default
    (`@VelocidadDetenido`, `@MinutosDetenido`, `@MinutosCombustible`, `@MinutosTolerancia`,
    `@MinutosMinPermanencia`, `@OffsetHoras`, `@Debug`).
  - Base: `UNIGIS_DataRepository_YPF_ARENAS_QA`.
  - Flujo en 9 pasos: encabezado → geocercas (`#Zonas`) → eventos GPS (`#Eventos`) →
    invasión de geocercas → novedad por evento → agrupación en tramos (`#Tramos`) →
    reglas de duración → carga de `dbo.Z_ItinerarioViaje` → salidas.
  - Dependencias: `Z_ClasificarParadasViaje` (función), `Z_KmTeoricos`,
    `Z_EstacionesDeServicioYPF`, `Viaje`, `Vehiculo`, `Deposito`, `Dibujo`, `Evento`, `Log`.
  - Los comentarios del SP están sin tildes (se mantiene así).
- (agregar aquí los demás SP conforme se vayan subiendo a `SP/`)

## Reportes en alcance
- `Reporte_ItinerarioViaje` — consulta `dbo.Z_ItinerarioViaje` (la tabla que llena
  `Z_SP_ItinerarioViaje`) con `Viaje`, `Jornada` y `EstadoViaje`, filtrada por
  `Z.IdViaje IN (!!ID_VIAJE!!)` y ordenada por `FechaHoraDesde`. Columnas: viaje, vehículo,
  origen/destino, contrato (`Viaje.Varchar1`), km teóricos y recorridos, evento, ubicación,
  período, duración, velocidades, detalle y estado del viaje.
  - Ojo: el `INNER JOIN` a `Jornada` no aporta columnas; solo excluye viajes sin `IdJornada`.
- `Reporte_ResumenViajesFinalizados` — una fila por viaje (resumen), solo viajes finalizados.
  Columnas pedidas: ID viaje, descripción, vehículo, transporte, contrato, estado del viaje,
  km teóricos, ciclo km teóricos, demoras responsabilidad YPF, demoras responsabilidad
  Transporte, fecha y hora de finalización, origen, destino, tipo de servicio.
  - Transporte: `Vehiculo.IdTransporte -> Transporte.RazonSocial`.
  - Tipo de servicio: `Viaje.IdCategoriaViaje -> CategoriaViaje.Descripcion`.
  - Viaje finalizado: `Viaje.IdEventoFinalizacion IS NOT NULL` (la plataforma asigna ahí el
    evento GPS que finalizó el viaje). Fecha y hora de finalización = `FechaHoraEvento` de ese
    evento, en hora local (UTC-3), formato `DD/MM/AAAA HH:MM`.
  - **Pendiente:** las 2 columnas de demoras por responsabilidad (YPF / Transporte). Requieren
    redefinir los cálculos del SP; se tratan en la siguiente solicitud.
  - No lleva comentarios `--` dentro de la consulta: la plataforma podría aplanarla a una línea.

## Reglas del cliente: PRESERVAR (no modificar la lógica de `Z_SP_ItinerarioViaje`)
Las reglas de duración del SP (PASO 7) son reglas establecidas por el cliente. Cualquier
cálculo nuevo (p. ej. demoras por responsabilidad) se construye **encima** de ellas, sin
cambiarlas.
- **Combustible:** el vehículo solo puede hacer **una carga por día**, de **hasta 30 min**
  (`@MinutosCombustible`) en estación de servicio.
  - Primera del día y ≤ 30 min → queda `COMBUSTIBLE`; esa detención **la paga YPF**.
  - Primera del día y > 30 min → **todo el tramo** pasa a `DETENIDO` (no solo el exceso);
    **la paga la línea de transporte**.
  - Siguientes del día: > 5 min (`@MinutosDetenido`) → `DETENIDO`; si no, `COMBUSTIBLE`.
  - En la tabla: `Novedad='COMBUSTIBLE'` + `AplicoExcepcionCombustible=1` = YPF;
    `Novedad='DETENIDO'` + `AplicoExcepcionCombustible=1` = excedió los 30 min (transporte).
- **Tolerancia en carga y descarga:** 45 min (`@MinutosTolerancia`) sobre la permanencia
  total por parada (`MinutosOperacion`).
- **Detención fuera de geocerca:** menos de 5 min no es novedad (es `CARRETEANDO`).
- **Pendiente de definir con el cliente** (responsable de la demora): exceso de tolerancia en
  carga/descarga y `ESPERA_SIN_TAREA`.

## Forma de trabajo
- Antes de modificar un SP, subir primero su versión actual tal cual (commit "original"),
  y luego el cambio en otro commit, para que el diff muestre solo lo agregado.
- No alterar la lógica existente del SP más allá de lo solicitado.
- Comunicación en español.
