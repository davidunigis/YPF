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

## Forma de trabajo
- Antes de modificar un SP, subir primero su versión actual tal cual (commit "original"),
  y luego el cambio en otro commit, para que el diff muestre solo lo agregado.
- No alterar la lógica existente del SP más allá de lo solicitado.
- Comunicación en español.
