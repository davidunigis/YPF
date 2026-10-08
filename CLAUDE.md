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
  - Demoras por responsabilidad (HH:MM, se suman minutos y recién al final se formatea).
    Se calculan **en el reporte** a partir de `Z_ItinerarioViaje`, sin tocar el SP ni la tabla:
    - **YPF** = `COMBUSTIBLE` con `AplicoExcepcionCombustible=1` (primera carga del día ≤ 30 min)
      + exceso sobre 45 min en `CARGA`/`DESCARGA` (`MAX(MinutosOperacion) - 45` por parada,
      agrupando por `IdViaje, IdDibujo` porque `MinutosOperacion` se repite en cada fila de la parada).
    - **Transporte** = `DETENIDO` (incluye la primera carga del día que excedió 30 min, tramo
      completo) + `ESPERA_SIN_TAREA`.
    - No cuentan: `CARRETEANDO`, `RETORNO`, `COMBUSTIBLE` sin excepción, ni la permanencia dentro de la tolerancia.
    - Limitación: la tolerancia de 45 min está escrita fija en el reporte (en el SP es el parámetro
      `@MinutosTolerancia`); si se cambia el default hay que cambiarla también en el reporte.
    - Alternativa futura (punto pendiente): agregar columnas de minutos de demora por responsable
      a `Z_ItinerarioViaje` y calcularlas en el SP.
  - No lleva comentarios `--` dentro de la consulta: la plataforma podría aplanarla a una línea.

## Reglas del cliente: PRESERVAR (no modificar la lógica de `Z_SP_ItinerarioViaje`)
Las reglas de duración del SP (PASO 7) son reglas establecidas por el cliente. Cualquier
cálculo nuevo (p. ej. demoras por responsabilidad) se construye **encima** de ellas, sin
cambiarlas.
- **Combustible:** el vehículo solo puede hacer **una carga por día**, de **hasta 30 min**
  (`@MinutosCombustible`) en estación de servicio.
  - Primera del día y ≤ 30 min → queda `COMBUSTIBLE`; esa detención **la paga YPF**
    (criterio indicado por el usuario; el documento To Be NO lo dice, ver "Diferencias abiertas").
  - Primera del día y > 30 min → **todo el tramo** pasa a `DETENIDO` (no solo el exceso);
    **la paga la línea de transporte**.
  - Siguientes del día: > 5 min (`@MinutosDetenido`) → `DETENIDO`; si no, `COMBUSTIBLE`.
  - En la tabla: `Novedad='COMBUSTIBLE'` + `AplicoExcepcionCombustible=1` = YPF;
    `Novedad='DETENIDO'` + `AplicoExcepcionCombustible=1` = excedió los 30 min (transporte).
- **Tolerancia en carga y descarga:** 45 min (`@MinutosTolerancia`) sobre la permanencia
  total por parada (`MinutosOperacion`).
- **Detención fuera de geocerca:** menos de 5 min no es novedad (es `CARRETEANDO`).
- **Responsable de la demora (confirmado):**

  | Concepto | Responsable |
  |---|---|
  | Primera carga de combustible del día ≤ 30 min | YPF |
  | Exceso sobre 45 min en `CARGA`/`DESCARGA` | YPF |
  | `DETENIDO` (incluye combustible que excedió la regla) | Transporte |
  | `ESPERA_SIN_TAREA` | Transporte |

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
  destino, más el acumulado de minutos que exceden la **tolerancia definida en origen / en destino**
  (columnas separadas de diferencia contra cada tolerancia). Control en origen y destino: > 45 min.
- Contratista: detenidos `d1..dn`, cada uno con minutos + horario + geoposición.
  - Detenido = unidad sin movimiento, con viaje Publicado/Programado/Tránsito, fuera de geocercas de YPF.
  - Excepción combustible: en geocerca de estación de servicio/base operativa solo se registra
    el detenido si supera 30 min; **una vez por día por unidad**; desde la 2.ª vez se registra completo.
  - Excepción cambio de turno: cada transportista tiene un rango horario de 1 h; dentro de él se
    suman los detenidos y solo se registra detenido si la suma **supera 30 min**.
  - Total de detenidos registrables por unidad, período y empresa.
- Espera sin tarea: novedad registrable de la unidad (sin viajes Publicado/Programado/En Tránsito);
  el documento no le asigna responsabilidad de demora.

### Diferencias abiertas (documento vs. SP / reporte actual) — pendientes de decidir
1. **Combustible ≤ 30 min:** el documento dice que no se registra detenido; no dice que lo pague
   YPF (y las demoras de YPF serían solo las de los 4 hitos). El reporte hoy lo suma a YPF.
2. **`ESPERA_SIN_TAREA`:** el documento no la trata como demora. El reporte hoy la suma a Transporte.
3. **Cambio de turno:** no está implementado en el SP; hoy todo `DETENIDO` cuenta completo.
4. **YPF origen / destino:** el documento pide columnas separadas por origen y destino, con minutos
   totales y exceso contra la tolerancia de cada locación. El reporte hoy suma un solo número
   (solo exceso, con 45 fijo).
5. **Umbral de detenido:** el documento habla de alerta a los 15 min fuera de geocerca; el SP usa
   `@MinutosDetenido = 5`.
6. **Granularidad:** el documento pide parte por empresa/unidad/período y detenidos `d1..dn`;
   el reporte actual es una fila por viaje.

## Forma de trabajo
- Antes de modificar un SP, subir primero su versión actual tal cual (commit "original"),
  y luego el cambio en otro commit, para que el diff muestre solo lo agregado.
- No alterar la lógica existente del SP más allá de lo solicitado.
- Comunicación en español.
