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
  **`Extraer_Viaje_Completo.sql` es el script a usar** (reúne los dos anteriores y agrega estado secundario, indicadores, información
  adicional, incidencias y tablas de reglas/alertas; cambiar `@IdViaje`). `Extraer_Datos_Viaje.sql` y `Extraer_Eventos_y_Estados_Viaje.sql`
  quedan como versiones parciales. Se usó con el viaje 329958 (viaje de prueba).
  `Diagnostico/Consultas/` — consultas **individuales** de solo lectura (una grilla por archivo, para exportar a Excel): `00`–`05` sin viaje (versión desplegada, log, corridas sin fin,
  viajes sin itinerario, viajes sin GPS, control por viaje) y `10`–`20` por viaje (`@IdViaje` arriba de cada una; cabecera, paradas, estados, filas de Z, log, eventos crudos, eventos con geocerca,
  combustible previo, otros viajes de la unidad, km teóricos, cambio de turno). La `21` reprocesa con `@Debug = 1` (**escribe**). Índice en `LEEME.md`. Sin validar en SQL Server (solo `sqlglot`).
- `Operacion/` — scripts operativos que **escriben** datos. `Reprocesar_Itinerario_Viajes.sql` vuelve a ejecutar el SP para los viajes
  finalizados de un rango de fechas (usar después de desplegar un cambio del SP; en SSMS activar "Descartar resultados después de la ejecución").
  `Reprocesar_Itinerario_Viajes_UM.sql` hace lo mismo para los viajes de la consulta del usuario (`Jornada.IdOperacion = 139` y `Viaje.IdEstadoViaje = 99`), uno a uno, con avance y lista de errores al final (`@Maximo` para probar con pocos).
- `Entrega/` — los mismos DDL, SP y reportes **sin comentarios**, numerados en el orden de despliegue (01–08), listos para enviar a implementación.
  Se generan con `python3 Entrega/generar_sin_comentarios.py` (verifica que solo cambien los comentarios); **no se editan a mano**: se regeneran después de tocar `DDL/`, `SP/` o `Reportes/`.
  `09_UPDATE_Reporte_286_Consolidado.sql` carga la consulta del consolidado en la tabla `Reporte` (`UPDATE Reporte SET ConsultaSQL = '...' WHERE IdReporte = 286`, comillas duplicadas; también lo genera el script).
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
3. Volver a ejecutar el SP para los viajes (las columnas nuevas quedan NULL en lo ya procesado): `Operacion/Reprocesar_Itinerario_Viajes.sql`.
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
    `@MinutosTurno`=30, `@TurnoSoloExceso`=0, `@MinutosAtras`=360, `@IdOperacion`=139, `@ImputarPrevioPublicacion`=0). Los nuevos van al final para no romper llamadas posicionales.
  - Base: `UNIGIS_DataRepository_YPF_ARENAS_QA`.
  - Flujo: encabezado → geocercas (`#Zonas`) → eventos GPS (`#Eventos`) → invasión de geocercas →
    novedad por evento → agrupación en tramos (`#Tramos`) → reglas de duración (PASO 7) →
    **PASO 7.e imputación de demoras** → carga de `dbo.Z_ItinerarioViaje` → salidas.
  - Dependencias: `Z_ClasificarParadasViaje` (función), `Z_KmTeoricos`,
    `Z_EstacionesDeServicioYPF`, `Z_CambioTurnoTransporte`, `Viaje`, `Vehiculo`, `Deposito`,
    `Dibujo`, `Evento`, `Log`.
  - Los comentarios del SP están sin tildes (se mantiene así).
  - **Viaje sin eventos GPS válidos** (el vehículo no tiene eventos en la ventana, o todos con coordenadas inválidas): ya no sale con `RETURN` sin cargar nada.
    Borra e inserta **una sola fila** en `Z_ItinerarioViaje` con lo que sí se conoce (encabezado, origen/destino, km teóricos, ventana del viaje) y
    `Novedad`/`TipoSuceso` = `SIN_EVENTOS_GPS`, `Suceso` = `Sin eventos GPS`, `Orden` 1, `CantidadEventos` 0; `KmRecorridos`, `DesvioKm`, tiempos y demoras quedan `NULL`.
    `KmRecorridos` es numérico, así que la leyenda "Sin eventos GPS" va en `Suceso`/`Detalle` y los reportes la muestran en la columna de km GPS.
    Salta a la etiqueta `Salidas:` (`GOTO`) para devolver igual los 3 resultsets. El log pasa de `ERROR` a `AVISO`.
  - **Ventana hacia atrás de la activación** (`@MinutosAtras`=360, `@FechaVentana`): hasta 6 h antes del evento de activación, para ver si el vehículo ya estaba dentro de la geocerca de carga (la tolerancia cuenta
    desde el ingreso) y el **retorno** al depósito de salida. Se acota para no contar dos veces lo de otro viaje (solo viajes de la operación `@IdOperacion`=139, Última Milla; NULL = todas):
    si la unidad finalizó un viaje dentro del tope, la ventana arranca en esa finalización; si hay otro viaje activo al activarse este, no se mira hacia atrás; sin viaje anterior o más viejo que el tope, rige el tope.
    Se recortan los eventos iniciales que sigan dentro de la geocerca de la última parada del viaje anterior y no estén en una zona de este viaje (nunca desde la activación).
    Los eventos previos no pasan por el filtro `IdEvento >= IdEventoActivacion`. Sin evento de activación (viaje sin activar) no se mira hacia atrás. Log `PASO1B`.
    Efectos: el primer tramo, `KmRecorridos` y `% Viaje` incluyen esa ventana; `DiaViaje` nunca es menor que 1; los tramos previos dicen "Retorno previo a la activacion" en `Detalle`.
    Análisis y casos límite en `Recomendaciones/Ventana_Hacia_Atras_y_Retorno.md`. Un viaje finalizado manualmente sin evento de finalización no se ve como viaje anterior.
  - **Detenido antes de publicar el viaje** (`@ImputarPrevioPublicacion`=0): lo detenido fuera de geocerca (o por combustible excedido) antes del primer pase a Publicado (98) o Programado (92) en `EstadoViajeTraceEstado`
    sale como `DETENIDO_SIN_VIAJE` ("Detenido sin viaje asignado"): se muestra, **no se imputa** a nadie y los reportes (que suman `Novedad = 'DETENIDO'`) no lo cuentan. Con 1 se imputa como antes. A confirmar con el cliente.
  - **Salidas y reingresos al depósito (PASO 7.c)**: el fin del proceso de carga lo marca el **primer pase a `En tránsito`** (`EstadoViajeTraceEstado.IdEstadoViajeDestino = 90`, fecha UTC, `@FinCarga`;
    se registra en el log `PASO7C`). Todas las visitas a la geocerca compartida (depósito de salida y de retorno) **anteriores** a ese pase siguen siendo `CARGA`, cada una como fila propia
    (el reporte muestra que salió y volvió a entrar; `Detalle` dice "Reingreso... (visita N)" y "Salio de la geocerca... y volvio a ingresar"); las posteriores toman el rol alterno (`RETORNO`).
    La primera visita siempre es operación. Sin pase a `En tránsito`: regla anterior (primera visita = operación, siguientes = rol alterno). `#Tramos` tiene `NroVisita`/`TotVisitas`.
    La tolerancia y el exceso de YPF suman el tiempo de **todas** las visitas a la parada (el tiempo fuera de la geocerca entre visitas no cuenta; si hay detenido fuera, lo evalúa la regla de detenidos).
    Pendiente de validar con un viaje real con salida y reingreso. Si hay varios pases a `En tránsito` (varias cargas) se usa el primero.
  - **Combustible una vez por día y por unidad, no por viaje** (PASO 7.a.0): antes de numerar las cargas del viaje se recorren los eventos GPS crudos de la unidad desde las 00:00
    local del primer día del viaje hasta el primer evento del viaje (`#EvPrevio`), con la misma regla de un tramo `COMBUSTIBLE` válido (permanencia ≥ `@MinutosMinPermanencia` y al menos un
    evento detenido). Cada una cuenta como carga previa (`@CombPrevios`) y desplaza el número del día (`NroDelDia`): la primera del viaje ya no es la primera del día.
    Se usan eventos crudos y no `Z_ItinerarioViaje`, así no depende del orden en que se procesaron los viajes. **Decisión del usuario (de momento):** una carga entre viajes (sin viaje activo) también consume la excepción; lo conversará con el cliente y avisará si cambia.
    Si la última visita previa es a la misma estación con la que arranca el viaje, es la misma detención y no se cuenta. Se registra en el log (`PASO7A`).
  - **Estación de servicio sin detenerse**: además de pasar a `CARRETEANDO`, el tramo pierde `IdDibujoZona`/`NombreZona`/`IdParada` para que el PASO 7.d lo funda con el carreteando vecino
    (antes quedaba una fila de 1–2 min con el nombre de la estación). **No se aplicó a los pasos fugaces por geocercas de planta/destino** (siguen como fila propia; en el viaje 329958 son 2 filas de 1 min en Planta Añelo): pendiente de decidir.
  - **Hora local**: `FechaHoraDesde/Hasta`, `Periodo`, `Detalle` y la fecha de los logs ya salían en hora argentina (`@OffsetHoras`); `FechaDesdeUTC/FechaHastaUTC` son UTC por diseño.
    `FechaProcesamiento` pasó de `GETUTCDATE()` a hora argentina.
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
Nombres de trabajo acordados con el usuario: **reporte de detalle** = `Reporte_ItinerarioViaje`; **consolidado** = `Reporte_ItinerarioViajeConsolidado`.
- `Reporte_ItinerarioViaje` — detalle cronológico del viaje (los detenidos con minutos, período y
  geoposición del documento). Consulta `Z_ItinerarioViaje` + `Viaje` + `Jornada` + `EstadoViaje`.
  Se agregaron: Responsable Demora, Minutos Imputados, Minutos Exentos, Motivo Exencion, Latitud, Longitud.
  Con fila `SIN_EVENTOS_GPS`, `Kilometros Recorridos GPS` muestra `Sin eventos GPS` (texto).
  - Ojo: el `INNER JOIN` a `Jornada` no aporta columnas; solo excluye viajes sin `IdJornada`.
  - `Latitud`/`Longitud` de la tabla son `MIN(Lat)`/`MIN(Lon)` del tramo (para una detención quieta
    coinciden con el punto real).
- `Reporte_ResumenViajesFinalizados` — una fila por viaje, solo finalizados. Las 14 columnas pedidas
  (en su orden) + 6 del documento al final: tiempo y exceso en origen, tiempo y exceso en destino,
  cantidad de detenidos y tiempo exento.
  - Transporte: `Vehiculo.IdTransporte -> Transporte.RazonSocial` (LEFT JOIN).
  - Tipo de servicio: `Viaje.IdCategoriaViaje -> CategoriaViaje.Descripcion` (LEFT JOIN).
  - Finalizado: `Viaje.IdEventoFinalizacion > 0` (los viajes sin cerrar tienen **0, no NULL**; evidencia: viaje 330113). Fecha y hora de finalización = `FechaHoraEvento`
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
  - Un viaje con fila `SIN_EVENTOS_GPS` sigue con las dos demoras **vacías**: `Filas` cuenta solo las filas distintas de `SIN_EVENTOS_GPS`.
  - `Reporte_ResumenViajesFinalizados` y `Reporte_ParteDemorasPorUnidad` **no se tocaron**: esos viajes ahora aparecen (antes no tenían filas) con tiempos y demoras en `00:00`. Pendiente de decidir si deben salir vacíos.
- `Reporte_ItinerarioViajeConsolidado` — una fila por viaje con los totales (reporte propio del usuario; `original` = la versión que pegó el usuario, en el historial git).
  Columnas: ID, descripción, vehículo, origen, destino, contrato, km teóricos y de ciclo, km GPS, estado, **fecha y hora de finalización (hora argentina)**
  y 3 demoras en HH:MM: `Demoras Responsabilidad YPF` (minutos totales `CARGA`+`DESCARGA`), `Exceso sobre Tolerancia YPF` (suma de `MinutosDemora` con
  responsable YPF) y `Demoras Responsabilidad Transporte` (`DETENIDO` menos `MinutosExentos`).
  - **El SP NO se toca** (decisión del usuario): el flujo es SP → `Z_ItinerarioViaje` (datos crudos) → reportes. Todo lo nuevo se calcula en este reporte a partir de las filas crudas.
  - **Placeholders de fecha: `!!FECHA_DESDE!!` y `!!FECHA_HASTA!!`, formato `dd/mm/aaaa`**, tratados como en el reporte de referencia del usuario (certificación LP):
    `DECLARE @FECHA_DESDE/@FECHA_HASTA`, `CONVERT(DATETIME, CAST('...' AS VARCHAR), 103)` y `@FECHA_HASTA = DATEADD(DAY, 1, @FECHA_HASTA)`.
    Filtro `TE.FechaDescarga BETWEEN @FECHA_DESDE AND @FECHA_HASTA`, con `TE.FechaDescarga` = última transición a estado 99 en `EstadoViajeTraceEstado` **convertida a hora
    argentina** (`DATEADD(HOUR, -3, Fecha)`: las fechas de la base están en UTC). Esa misma fecha se muestra en la columna y se usa en el filtro, así que sirve para verificarlo.
    (A diferencia del reporte de referencia, que filtra sin convertir.)
  - **Finalizado** = existe transición a 99 (criterio del usuario, da la fecha de finalización) **y el estado actual del viaje es 99** (`V.IdEstadoViaje = 99`, `Finalizado -AR`):
    un viaje que llegó a 99 y después volvió a `En tránsito` (90) u otro estado se descarta. **Operación UM** = `Jornada.IdOperacion = 139`. Solo viajes con filas en `Z_ItinerarioViaje`.
  - **Último destino**: la última fila de `Z_ItinerarioViaje` con `Novedad = 'DESCARGA'` (por `FechaHoraDesde`); su nombre sale de `Parada.Descripcion` (vía `Z.IdParada`, el nombre que usa
    `Z_KmTeoricos`, p. ej. `BDTN49`) y, si no hay parada, de `Z.Ubicacion`. Si el viaje no tiene filas `DESCARGA`, se usa `Z.Destino` (el del SP).
  - **Último origen**: la fila `Novedad = 'CARGA'` vigente en el último pase a `En tránsito`: la última que empezó antes de esa transición (si no hay, la primera posterior).
    La transición (UTC) se pasa a hora argentina para compararla con `Z.FechaHoraDesde` (que ya está en hora local). Nombre = `Deposito.Descripcion` de la parada (si no, `Parada.Descripcion`
    o `Z.Ubicacion`). Si el viaje no tiene filas `CARGA` (p. ej. paso fugaz por la planta), se usa `Z.Origen` (el del SP).
  - **Km teóricos y de ciclo**: `Z_KmTeoricos` para el par (último origen, último destino) por nombre (`LTRIM/RTRIM`); con duplicados, el `Id` más nuevo; **vacío si el par no existe**
    (no cae a `Z.KMTeoricos`, que corresponde al par del SP). Los km GPS no cambian.
  - Supuesto a validar con un viaje real con varios pasos a `En tránsito`: `EstadoViajeTraceEstado` no guarda el origen por transición; se infiere con la fila `CARGA` de `Z_ItinerarioViaje`.
  - Un viaje que no se reprocesó con el SP nuevo muestra `00:00` en `Exceso sobre Tolerancia YPF`.
  - **Viaje con fila `SIN_EVENTOS_GPS`**: `Kilometros Recorridos GPS` muestra `Sin eventos GPS` (la columna pasa a texto: `CONVERT(VARCHAR(20), KmRecorridos)`) y las 3 demoras
    salen **vacías** (no `00:00`: no se pueden calcular). Origen/destino salen de `Z.Origen`/`Z.Destino` (no hay filas `CARGA`/`DESCARGA`) y los km teóricos se buscan igual.
  - **Columnas en minutos (pedido del cliente)**, al final y en este orden: `Tiempo Total Origen (min)`, `Tiempo Excedente Origen (min)`, `Tiempo Total Destino (min)`,
    `Tiempo Excedente Destino (min)`, `Demoras Responsabilidad Transporte (min)` y `Tiempo a Reconocer (min)` = excedente origen + excedente destino − demoras del transporte.
    Total = suma de `TiempoMinutos` de las filas `CARGA` (origen) o `DESCARGA` (destino). Excedente = `MAX(0, total − @TOLERANCIA)` (`@TOLERANCIA = 45`, variable al inicio del reporte), **calculado por parada**
    (por `IdDibujo`; las visitas a la misma geocerca se suman antes de restar) y sumado por lado; con una sola parada por lado es el total menos 45. Se calcula a partir de las filas crudas, no de `MinutosDemora`.
    El tiempo a reconocer **no se acota en 0** (puede ser negativo): pendiente de confirmar con el cliente. Las 3 columnas HH:MM anteriores no se tocaron (las dos de YPF son redundantes con las nuevas):
    pendiente de decidir si se reemplazan o convierten a minutos. Con fila `SIN_EVENTOS_GPS` las 6 salen vacías.

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
  atrasados de 90–234 min, en dos lotes). Ahora filtra por la ventana de tiempo (desde `@MinutosAtras` antes de la activación) y `IdEvento >= IdEventoActivacion` desde la activación. Con los 388 eventos el km GPS
  sube de 143,3 a 150,6; la detención de 67 min pasa a 68 min.
- **El SP corre al finalizar el viaje** (confirmado por el usuario), antes de que lleguen los datos atrasados: sin una segunda corrida, el
  cambio de filtro no tiene efecto. Opciones en `Recomendaciones/Datos_Atrasados_y_Momento_de_Ejecucion.md`; **pendiente de decidir, no implementado**.
- **Pendiente:** validar el origen con un viaje real (el usuario espera datos reales esta semana); correr `Extraer_Datos_Viaje.sql` con ese `@IdViaje`.
- **El viaje 329958 es de prueba** (`PruebaFacundo`): los estados del basculero no son reales (carga de 15 s, marcada a 9,3 km de la
  planta). El destino no tiene estados de descarga (sin personal en sitio): ahí solo hay GPS. Para validar el origen hace falta un viaje real.
- Fuentes de estados: `EstadoViajeTraceEstado`, `ParadaTraceEstado`, `BitacoraViaje`. `Z_LPViajeMonitorGeocerca` no se usa en Última Milla.

## Viaje 330113 (ver `Diagnostico/Analisis_Viaje_330113.md`)
- Marcado `FUERA DE TOLERANCIA` porque el SP lo procesó **sin que el viaje hubiera empezado** (`Programado`, `IdEventoActivacion` = `IdEventoFinalizacion` = 0).
  Ventana de respaldo = creación + 72 h → tomó 120 min del camión dentro de BDTN49 (antes del viaje) como `DESCARGA` (+75 min sobre 45).
- Los viajes sin activar/cerrar tienen 0, no NULL. Los filtros de "finalizado" de los reportes y de `Operacion/Reprocesar_Itinerario_Viajes.sql` ya usan `> 0`.
- **Pendiente de decisión, no implementado:** salir sin procesar si no hay activación y/o usar `FechaInicioReal`/`FechaFinReal` como respaldo
  → `Recomendaciones/Viajes_sin_activacion_y_ventana_del_SP.md`. El resultado del SP para este viaje se **reconstruyó** (no se recibió `Z_ItinerarioViaje`).

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

## Ventana hacia atrás y retorno (aplicado)
Pedido del cliente: hasta 6 h antes de la activación, acotadas por el último viaje anterior de la unidad, para capturar el retorno a la planta. Aplicado en el SP (ver "Ventana hacia atrás de la activación"),
solo con viajes de Última Milla por indicación del usuario. Preguntas abiertas y casos límite en `Recomendaciones/Ventana_Hacia_Atras_y_Retorno.md`. Requiere reprocesar los viajes.
Medir con `Diagnostico/Consultas/30_Brechas_entre_Viajes_de_la_Unidad.sql`.
