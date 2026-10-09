# Rama Reportes-Areas — contexto para Claude Code

Repositorio de consultas, SP y reportes de UNIGIS para YPF (SQL Server / T-SQL).
Esta rama agrupa los SP que llenan tablas de **reportes de áreas**.

## Estructura
- `SP/` — un archivo `.sql` por procedimiento, con el nombre exacto del SP
  (ej. `SP/Z_SP_ItinerarioViaje.sql`). Cada archivo contiene el `ALTER PROCEDURE` completo.
- `DDL/` — objetos de soporte (tablas, columnas, funciones) que el SP y los reportes necesitan.
  Scripts re-ejecutables. **Se ejecutan antes de desplegar el SP.**
- `Diagnostico/` — consultas de solo lectura para analizar un viaje (no son reportes de la plataforma).
  `Extraer_Datos_Viaje.sql` junta en un único CSV (Seccion | Parte | Dato JSON) las entradas que usa el SP
  (viaje, paradas, geocercas, eventos GPS con su geocerca y distancia, km teóricos), lo que dejó en
  `Z_ItinerarioViaje`, el log y el código desplegado del SP y de `Z_ClasificarParadasViaje`, para
  recalcular por fuera y comparar. Requiere SQL Server 2016+ (`FOR JSON`).
- `Recomendaciones/` — documentos de recomendaciones para el cliente. Un tema que implica una decisión de
  negocio se documenta acá y **no se implementa hasta que el usuario lo pida**.
- `Reportes/` — consultas de reporte de UNIGIS (un `.sql` por reporte). Se guardan tal cual
  se cargan en la plataforma, con el placeholder `!!ID_VIAJE!!` (lo reemplaza la plataforma;
  no es T-SQL válido por sí solo). Sin comentarios `--` dentro: la plataforma podría aplanarlas.

## Orden de despliegue
1. `DDL/Z_Demoras_Objetos.sql` (tabla `Z_CambioTurnoTransporte`, columnas nuevas de
   `Z_ItinerarioViaje`, función `Z_MinutosAHHMM`) y `DDL/Z_ItinerarioViaje_KmTeoricos_Decimal.sql`
   (`KmTeoricos` y `CicloKmTeoricos` pasan de `INT` a `DECIMAL(12,2)`).
2. `SP/Z_SP_ItinerarioViaje.sql`.
3. Volver a ejecutar el SP para los viajes (las columnas nuevas quedan NULL en lo ya procesado).
4. Reportes de `Reportes/`.
5. Cargar los rangos de cambio de turno por transportista en `Z_CambioTurnoTransporte`.

## SP en alcance
- `Z_SP_ItinerarioViaje` — llena la tabla de reporte `dbo.Z_ItinerarioViaje` (itinerario
  cronológico de un viaje) y devuelve 3 resultsets: resumen de novedades, itinerario y
  métrica de control por parada.
  - Parámetro principal: `@IdViaje INT`. El resto son umbrales con default
    (`@VelocidadDetenido`, `@MinutosDetenido`=15, `@MinutosCombustible`=30,
    `@MinutosTolerancia`=45, `@MinutosMinPermanencia`, `@OffsetHoras`=-3, `@Debug`,
    y nuevos: `@MinutosToleranciaOrigen`/`@MinutosToleranciaDestino` (NULL = `@MinutosTolerancia`),
    `@MinutosTurno`=30, `@TurnoSoloExceso`=0). Los nuevos van al final para no romper llamadas posicionales.
  - Base: `UNIGIS_DataRepository_YPF_ARENAS_QA`.
  - Flujo: encabezado → geocercas (`#Zonas`) → eventos GPS (`#Eventos`) → invasión de geocercas →
    novedad por evento → agrupación en tramos (`#Tramos`) → reglas de duración (PASO 7) →
    **PASO 7.e imputación de demoras** → carga de `dbo.Z_ItinerarioViaje` → salidas.
  - Dependencias: `Z_ClasificarParadasViaje` (función), `Z_KmTeoricos`,
    `Z_EstacionesDeServicioYPF`, `Z_CambioTurnoTransporte`, `Viaje`, `Vehiculo`, `Deposito`,
    `Dibujo`, `Evento`, `Log`.
  - Los comentarios del SP están sin tildes (se mantiene así).
  - Historial: `bc585ed` es la versión original; los cambios van en commits posteriores.
- (agregar aquí los demás SP conforme se vayan subiendo a `SP/`)

## Imputación de demoras (PASO 7.e) — alineada al documento To Be v3
Completa por tramo: `ToleranciaMin`, `Responsable` (`YPF` | `TRANSPORTE` | NULL), `MinutosDemora`,
`MinutosExentos`, `MotivoExencion` (`COMBUSTIBLE` | `CAMBIO_TURNO`). Columnas nuevas equivalentes en
`Z_ItinerarioViaje`: `ToleranciaMinutos`, `ResponsableDemora`, `MinutosDemora`, `MinutosExentos`,
`MotivoExencion`. **No cambia las novedades** (`Novedad`, `Suceso`, etc.).
- `MinutosDemora` es **aditivo**: se puede `SUM` sin contar doble.
- **YPF:** solo hitos de carga y descarga. Exceso sobre la tolerancia de origen (`CARGA`) o de
  destino (`DESCARGA`), por parada (`SUM(Minutos)` de la parada − tolerancia). Se imputa en el
  **último tramo** de la parada; el resto de los tramos de esa parada llevan 0.
- **TRANSPORTE:** detenidos registrables (`DETENIDO`) menos lo exento por cambio de turno.
- **Sin demora para nadie:** `CARRETEANDO`, `RETORNO`, `ESPERA_SIN_TAREA`, la permanencia dentro de la
  tolerancia, y el combustible dentro de la excepción (`MotivoExencion='COMBUSTIBLE'`).
- **Cambio de turno (propuesta propia; el documento no define cómo ni cuándo):**
  - Los rangos se cargan en `dbo.Z_CambioTurnoTransporte` (`IdTransporte`, `HoraDesde` hora local,
    `DuracionMinutos`=60, `Activo`). Un transportista puede tener varios rangos; pueden cruzar la medianoche.
  - Se genera un rango por día del viaje. Por cada rango se suman los minutos de detenidos **que caen
    dentro** (un detenido que cruza el borde aporta solo la parte interior).
  - Suma ≤ `@MinutosTurno` (30) → no se registra ninguno. Suma > 30 → se registra todo
    (`@TurnoSoloExceso=0`, consistente con la regla de combustible) o solo lo que pasa de 30 (`=1`;
    se exentan los primeros 30 min en orden cronológico).
  - Sin rangos activos para el transportista, la excepción no aplica.
  - Limitación: el SP procesa un viaje por vez, así que la suma del rango solo ve los detenidos de ese
    viaje (no los de otro viaje de la misma unidad en el mismo rango).
- `ExcedeTolerancia`, `Observacion` y la salida 3 del SP usan la tolerancia de cada lado
  (`ToleranciaMin`). Con los defaults (45/45) el resultado es el mismo que antes.
- El encabezado `[Excede 45 min]` de la salida 2 sigue escrito fijo.

## Reportes en alcance
- `Reporte_ItinerarioViaje` — detalle cronológico del viaje (los detenidos con minutos, período y
  geoposición del documento). Consulta `Z_ItinerarioViaje` + `Viaje` + `Jornada` + `EstadoViaje`.
  Se agregaron: Responsable Demora, Minutos Imputados, Minutos Exentos, Motivo Exencion, Latitud, Longitud.
  - Ojo: el `INNER JOIN` a `Jornada` no aporta columnas; solo excluye viajes sin `IdJornada`.
  - `Latitud`/`Longitud` de la tabla son `MIN(Lat)`/`MIN(Lon)` del tramo (para una detención quieta
    coinciden con el punto real).
- `Reporte_ResumenViajesFinalizados` — una fila por viaje, solo finalizados. Las 14 columnas pedidas
  (en su orden) + 6 del documento al final: tiempo y exceso en origen, tiempo y exceso en destino,
  cantidad de detenidos y tiempo exento.
  - Transporte: `Vehiculo.IdTransporte -> Transporte.RazonSocial` (LEFT JOIN).
  - Tipo de servicio: `Viaje.IdCategoriaViaje -> CategoriaViaje.Descripcion` (LEFT JOIN).
  - Finalizado: `Viaje.IdEventoFinalizacion IS NOT NULL`. Fecha y hora de finalización = `FechaHoraEvento`
    de ese evento, hora local (UTC-3), `DD/MM/AAAA HH:MM`.
  - `Demoras Responsabilidad YPF` = exceso origen + exceso destino. `Demoras Responsabilidad Transporte` =
    suma de `MinutosDemora` con responsable `TRANSPORTE`. Todo en HH:MM vía `dbo.Z_MinutosAHHMM`.
  - Se quitó el `JOIN` a `Jornada` (filtraba viajes sin jornada en silencio).
- `Reporte_ParteDemorasPorUnidad` — parte por **empresa, unidad y período quincenal** (1–15 y 16–fin de
  mes, según la fecha de finalización local) sobre los viajes finalizados elegidos. Totales de tiempo y
  exceso en origen/destino, demoras YPF, detenidos registrables y demoras del transporte.
- `Reporte_CertificacionViajesUM` — pedido del cliente "Certificar los viajes de UM": tabla de **una fila por viaje**, solo viajes
  finalizados, con exactamente 14 columnas: ID viaje, descripción, vehículo, transporte, contrato, estado del viaje, km teóricos, ciclo km
  teóricos, demoras responsabilidad YPF, demoras responsabilidad Transporte, fecha y hora de finalización, origen, destino, tipo de servicio.
  - **Sin filtros ni `!!ID_VIAJE!!`**: los filtros del pedido (fecha / rango de fechas o día en curso, y contrato) los agrega el usuario con
    placeholders propios. Columnas para filtrar: finalización `EF.FechaHoraEvento` (UTC; hora local = −3 h) y contrato `V.Varchar1`.
    El reporte tampoco filtra por operación UM (en el viaje de prueba `Jornada.IdOperacion` = 139).
  - **Demora YPF = suma total de minutos** de las novedades `CARGA` y `DESCARGA` (en GPS la espera y la operación son un solo tramo).
    **Demora Transporte = suma de minutos de `DETENIDO`**, descontando `MinutosExentos` (cambio de turno); sin rangos de turno cargados
    equivale a la suma bruta. Esto difiere de `Reporte_ResumenViajesFinalizados`, donde YPF es solo el exceso sobre la tolerancia.
  - Parte de `Viaje` (no de `Z_ItinerarioViaje`) para que un viaje finalizado sin itinerario calculado aparezca igual, con las dos demoras
    **vacías** (no en cero). Origen y destino salen de `Z_ItinerarioViaje` y, si no hay, de `Viaje`. Vehículo sin espacios a la derecha.
  - Encabezados sin tildes, como el resto de los reportes.

## Documento de negocio (fuente de reglas)
`YPF_ARENAS_TO_BE_03-06_UNIGIS_V3` (Documento To Be, v3, 04-06-2026). No está en el repo (tiene
datos de contacto); se cita por sección. Lo relevante está en **Tarifación/Certificación →
Certificación Última Milla → Módulo I y Módulo II (Gestión Inteligente de Demoras e Imputaciones)**
y en **Novedades y Alertas Última Milla**.
- Fuentes: parte diario de viajes finalizados, Tabla de Distancias Maestra (Km teóricos) y
  contratos (dato informativo). Corte quincenal: días 1–15 y 16–fin de mes.
- Salida esperada: parte **por empresa de transporte, por unidad y por período**, con detalle de viajes.
- Demoras solo sobre los hitos Espera Carga, Carga, Espera Descarga y Descarga; **las demoras de
  YPF son las únicas sobre esos hitos**. Además se calculan los *detenidos* (responsabilidad contratista).
- YPF: minutos totales de (espera carga + carga) en origen y de (espera descarga + descarga) en
  destino, más el acumulado de minutos que exceden la **tolerancia definida en origen / en destino**.
  Control en origen y destino: > 45 min.
- Contratista: detenidos `d1..dn`, cada uno con minutos + horario + geoposición.
  - Detenido = unidad sin movimiento, con viaje Publicado/Programado/Tránsito, fuera de geocercas de YPF.
  - Excepción combustible: en geocerca de estación de servicio/base operativa solo se registra
    el detenido si supera 30 min; **una vez por día por unidad**; desde la 2.ª vez se registra completo.
  - Excepción cambio de turno: rango horario de 1 h por transportista; dentro de él se suman los
    detenidos y solo se registra si la suma **supera 30 min** (imagen del doc: 12+1+17 = 30 → no registra).
  - Total de detenidos registrables por unidad, período y empresa.
- Espera sin tarea: novedad registrable de la unidad; el documento no la trata como demora.

### Decisiones tomadas al alinear con el documento
- Combustible ≤ 30 min **no es demora de nadie** (antes se había supuesto YPF). Espera sin tarea **no es
  demora** (antes se había supuesto Transporte).
- Umbral de detenido por defecto: **15 min** (el documento fija 15 min para la detención en ruta que
  consume la certificación; antes 5).
- Granularidad: detalle por viaje (itinerario) + resumen por viaje + parte por empresa/unidad/período.

### Supuestos a validar con el cliente
1. **Umbral de detenido = 15 min.** El ejemplo del documento (`d1..dn` = 12, 1, 17, 0, 25) sugiere que
   también se registran detenidos muy cortos; en ese caso `@MinutosDetenido` debería bajar (0).
2. **Demora YPF = solo el exceso** sobre la tolerancia (no el total de minutos). Los totales salen
   en columnas aparte. *(El pedido del cliente para `Reporte_CertificacionViajesUM` define la demora YPF como la suma total de minutos;
   los reportes anteriores siguen con el exceso hasta que el usuario decida alinearlos.)*
3. **Cambio de turno:** todo-o-nada vs solo exceso (el texto dice "registra detenido", la imagen "exceso
   detenido"); los rangos por transportista salen de una tabla nueva que hay que poblar; la suma es por viaje.
4. **Tolerancias:** 45 min en origen y destino (una por lado, no por locación).
5. El tiempo en la geocerca de planta agrupa Espera + Carga (GPS no distingue los estados del basculero),
   que es justo lo que el documento suma para la tolerancia.

## Hallazgos del viaje 329958 (ver `Diagnostico/Analisis_Viaje_329958.md`)
Verificado con datos reales: el SP desplegado = repo, y una réplica en Python reproduce `Z_ItinerarioViaje`.
- **Corregidos en el SP** (verificados con la réplica sobre los eventos reales):
  - `VelocidadPromedio` de las filas fusionadas: ahora promedio ponderado por eventos (antes conservaba el del primer tramo).
  - `KmTeoricos`/`CicloKmTeoricos`: `DECIMAL(12,2)` en el SP y en la tabla (antes `INT`, 130,08 → 130).
  - Paso por una estación de servicio sin detenerse (velocidad mínima > `@VelocidadDetenido`) o con permanencia
    menor a `@MinutosMinPermanencia`: pasa a `CARRETEANDO` y **no consume la excepción diaria de combustible**.
    Un tramo con al menos un evento detenido sigue siendo `COMBUSTIBLE`. Para eso `#Tramos` tiene la columna nueva `VelMin`.
- **Solo documentado, sin cambios de cálculo:** espera en la puerta del destino y origen sin `CARGA`
  → `Recomendaciones/Espera_en_Puerta_y_Geocercas.md`.
- **Corregido por decisión del usuario:** el SP ya no descarta eventos con `IdEvento > IdEventoFinalizacion` (147 de 388 en este viaje: datos
  atrasados de 90–234 min, en dos lotes). Ahora filtra por la ventana de tiempo y `IdEvento >= IdEventoActivacion`. Con los 388 eventos el km GPS
  sube de 143,3 a 150,6; la detención de 67 min pasa a 68 min.
- **El SP corre al finalizar el viaje** (confirmado por el usuario), antes de que lleguen los datos atrasados: sin una segunda corrida, el
  cambio de filtro no tiene efecto. Opciones en `Recomendaciones/Datos_Atrasados_y_Momento_de_Ejecucion.md`; **pendiente de decidir, no implementado**.
- **Pendiente:** validar el origen con un viaje real (el usuario espera datos reales esta semana); correr `Extraer_Datos_Viaje.sql` con ese `@IdViaje`.
- **El viaje 329958 es de prueba** (`PruebaFacundo`): los estados del basculero no son reales (carga de 15 s, marcada a 9,3 km de la
  planta). El destino no tiene estados de descarga (sin personal en sitio): ahí solo hay GPS. Para validar el origen hace falta un viaje real.
- Fuentes de estados: `EstadoViajeTraceEstado`, `ParadaTraceEstado`, `BitacoraViaje`. `Z_LPViajeMonitorGeocerca` no se usa en Última Milla.

## Forma de trabajo
- Antes de modificar un SP, subir primero su versión actual tal cual (commit "original"),
  y luego el cambio en otro commit, para que el diff muestre solo lo agregado.
- No alterar la lógica existente del SP más allá de lo solicitado.
- Comunicación en español.
- No ser proactivo con cambios de reglas de negocio: proponerlos en `Recomendaciones/` y esperar la decisión del usuario.
- Los scripts de `Diagnostico/` usan tablas temporales con nombre propio por script, para poder correrse en la misma sesión de SSMS.
- No hay SQL Server en el entorno de Claude: los cambios se validan con parseo de sintaxis (`sqlglot`,
  que no puede con el procedimiento completo) y con simulaciones de la lógica en SQLite.
  **Probar siempre en la base QA antes de pasar a producción.**
