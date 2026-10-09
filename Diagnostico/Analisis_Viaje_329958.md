# Análisis del viaje 329958 (Planta Añelo → BDTN49)

Fuente: `RESULTADO.csv` generado con `Extraer_Datos_Viaje.sql` en `UNIGIS_DataRepository_YPF_ARENAS_QA`
(SQL Server 2019, nivel de compatibilidad 150). Viaje de prueba (`07102026-UM-PruebaFacundo-0040`),
transporte `TRANSPORTE JOSE BERALDI - Arenas - UM`, vehículo AG782BW, operación 139, categoría Arena.

## Verificación del SP
- El SP desplegado es **idéntico** al de `SP/Z_SP_ItinerarioViaje.sql` (0 líneas distintas).
- Una réplica independiente en Python (mismas reglas, mismos 241 eventos y geocercas) reproduce las 10 filas
  de `Z_ItinerarioViaje` en novedad, minutos y cantidad de eventos, y la línea `PASO7E` del log
  (YPF 0 min, Transporte 67 min, exentos 2 min). **El SP hace lo que dice el código.**
- El km recalculado (143,34) coincide con `KmRecorridos`.
- Lo que sigue son problemas de **resultado de negocio** o defectos puntuales, no de ejecución.

## Estado de los hallazgos
- 1 y 3: solo documentados, sin cambios de cálculo (`Recomendaciones/Espera_en_Puerta_y_Geocercas.md`).
- 2: **confirmado y corregido en el SP** (se quitó el tope de `IdEvento`). Como el SP corre al cierre, falta decidir una segunda
  corrida: `Recomendaciones/Datos_Atrasados_y_Momento_de_Ejecucion.md`.
- 3: el viaje es de prueba y los estados de la plataforma no son reales; se reinterpreta abajo.
- 4, 5 y 6: **corregidos en el SP** (y `DDL/Z_ItinerarioViaje_KmTeoricos_Decimal.sql` para el 5).

## Hallazgos (por impacto)

### 1. Los 67 min de `DETENIDO` son la cola en la puerta del destino
El camión estuvo parado entre 19:54 y 21:02 UTC (16:54–18:02 local) a **8 m y luego 2 m por fuera** de la
geocerca `LOC-BDTN-49 1` (119 puntos). Entró a las 21:02:37 y descargó hasta las 21:31:22.
- Hoy: `DESCARGA` 29 min (dentro de tolerancia) → **YPF 0 min, Transporte 67 min**.
- Con un margen de 10 m en la geocerca: `DESCARGA` ≈ 102 min → **YPF 57 min, Transporte 0**.
- Margen 10, 25, 50 m dan el mismo resultado; 100 y 150 m, 60 min. El resultado cambia por completo con
  un margen menor que el error normal de un GPS.
- Decisión de negocio: ¿la espera en la puerta cuenta como espera de descarga (YPF)? El documento arranca
  la espera al ingresar a la geocerca, así que la solución puede ser de diseño (dibujar la geocerca incluyendo
  la cola) o un parámetro de margen en el SP.

### 2. El SP descarta 147 de los 388 eventos de la ventana
`EVENTOS_RESUMEN`: 388 eventos del vehículo entre el primer y el último evento del viaje, **todos válidos**;
el SP usó 241. Como `Valido` es verdadero en todos y `MinIdEvento = IdEventoActivacion`, los 147 restantes
quedan afuera solo por el filtro `IdEvento <= IdEventoFinalizacion` (`MaxIdEvento` 173557111 > 173430834).
Son eventos con hora anterior al cierre pero que **llegaron después** (el `IdEvento` es posterior).
- Es plausible que llenen los huecos: entre 18:49 y 19:55 UTC hay eventos cada 5–13 min y un hueco de
  50 min (19:55 → 20:45) dentro de la detención.
- **Confirmado** (ver "Segunda extracción"): son datos atrasados que llegaron en dos lotes.

### 3. El origen no tiene `CARGA`
La planta (geocerca de **10 puntos**) registra 4 eventos en 2 visitas de 1 minuto (13:24 y 13:56 local), menores
al mínimo de 2 min, así que pasan a `CARRETEANDO`. En el itinerario aparecen dos filas "CARRETEANDO" con
ubicación "Planta Añelo". Entre 16:23 y 17:00 UTC el camión da vueltas a 0–130 m de la geocerca y a baja velocidad.
- Con margen de 150 m se verían dos `CARGA` de 8 y 6 min (siguen bajo tolerancia).
- Dónde carga realmente el camión es dato operativo; el reporte hoy no muestra ninguna carga.
- **Matiz tras la segunda extracción:** es un viaje de prueba. El basculero marcó la carga y la salida a las 16:04 UTC,
  desde un punto a 9,3 km de la planta, y el camión recién entra a la geocerca a las 16:24. Para validar el origen
  hace falta un viaje real.

### 4. `VelocidadPromedio` es incorrecta en las filas fusionadas (bug del SP original)
La consolidación (PASO 7) recalcula `FechaHasta`, `Kms`, `Eventos`, `VelMax` y `Minutos`, pero **no `VelProm`**:
la fila fusionada conserva el promedio del primer tramo.
| Fila | Tabla | Promedio real |
|---|---|---|
| 1 | 54,62 | 34,25 |
| 3 | 7,32 | 5,71 |
| 5 | 7,32 | **24,27** |
| 7 | 51,61 | 50,62 |
La fila 5 dice "16,68 km en 00:35 hs (promedio 7 km/h)". Afecta también al texto de `Detalle`.

### 5. `KmTeoricos` y `CicloKmTeoricos` se truncan a entero
`Z_KmTeoricos`: 130,08 / 260,16. `Z_ItinerarioViaje` (columnas `int`) y las variables del SP (`INT`): 130 / 260.
`DesvioKm` queda 13,34 en vez de 13,26. En rutas cortas el error llega al 3–5 % (20,65 → 20; 15,48 → 15).

### 6. El paso por la estación de servicio consume la excepción diaria de combustible
Los 2 eventos en la estación van a 14,64 y 21,96 km/h: el camión pasó, no cargó. Aun así quedó como
`COMBUSTIBLE` (2 min, `AplicoExcepcion = 1`), y una carga real posterior ese día se trataría como "segunda del día"
(detención completa). El filtro de pasos fugaces (PASO 6) solo contempla `CARGA`, `DESCARGA` y `RETORNO`.

## Menores
- `KmAcumulado` suma los km de todas las filas, pero la columna `Km Tramo` muestra 0 para las que no son
  `CARRETEANDO`: el acumulado final (143,33) supera en 0,6 km la suma de lo mostrado.
- `Dominio` es `char(50)`: el reporte muestra el dominio con espacios a la derecha.
- La plataforma guarda `Viaje.KmsRecorridos = 128,89` (el SP calcula 143,34; teórico 130,08; plan 126,14).
  No sé qué método usa cada uno.
- En este viaje de prueba `FechaInicioCarga`/`FechaFinCarga` valen 2026-10-09 03:00/03:01, posteriores al cierre.
  No sirven como referencia de tiempos.
- Sin filas de cambio de turno para el transportista 126 (`TURNO = NULL`): la excepción no se aplicó.

## Qué mostrarían hoy los reportes para este viaje
Demora YPF 00:00, Transporte 01:07, tiempo en origen 00:00, tiempo en destino 00:29, 1 detenido, exento 00:02.

## Segunda extracción (`Extraer_Eventos_y_Estados_Viaje.sql`)

### Hallazgo 2 confirmado: datos que llegan tarde
- 464 eventos del vehículo con ±30 min de margen; 388 en la ventana del viaje; el SP usó 241. Los **147 descartados**
  tienen `IdEvento` mayor al de cierre (173438154–173557111 contra 173430834) y todos son válidos.
- Recibieron **90 a 234 min** después de ocurrir (mediana 170). Llegaron en dos lotes: 18 eventos entre 21:42 y 21:44 UTC
  y 129 entre 22:53 y 23:05 UTC. El evento de cierre se recibió a las 21:37:47 y el estado `Finalizado` se registró a las 21:38:05.
- Los 147 se concentran donde el SP veía poco: entre las 19:00 y las 21:00 UTC el SP usó 13 eventos y descartó 88.
- Los eventos usados también traen atrasos de hasta 181 min (llegaron antes del cierre).

Resultado de recalcular con los 388 eventos (misma lógica del SP):
| | 241 eventos (SP) | 388 eventos |
|---|---|---|
| Km GPS | 143,3 | **150,6** |
| `DETENIDO` | 67 min, 5 eventos | **68 min, 33 eventos** |
| `DESCARGA` | 29 min | 29 min |
| YPF / Transporte | 0 / 67 min | 0 / 68 min |

- **La detención en la puerta es real**: con los eventos faltantes son 33 reportes en el mismo punto (0,01 km), no
  un hueco de cobertura. La conclusión del hallazgo 1 no cambia.
- El km sube 7,3 km porque los tramos con pocos eventos se medían con cuerdas más cortas que el recorrido.
- La plataforma guarda `Viaje.KmsRecorridos` = 128,89: sigue sin explicarse la diferencia con 143,3 y con 150,6.
- Si el SP corre al finalizar el viaje (21:38 UTC) los datos atrasados todavía no existen, aunque se quite el filtro de
  `IdEvento`. Hay que saber **cuándo** corre el SP en la plataforma.
- Nota de método: mi réplica con la geocerca en plano difiere de SQL en 1 de los 241 eventos (a 1 m del borde). No cambia las conclusiones.

### Estados de la plataforma (horas en UTC)
| Hora | Qué registró la plataforma |
|---|---|
| 13:58 | `Publicado Manual` (PROGRAMADOR_ARENAS) |
| 15:06 | `Programado` (el transporte confirma el viaje) |
| 16:04:16 | `En proceso de carga` (Basculero_Anelo_Despacho) |
| 16:04:31 | `En tránsito`: **la carga duró 15 s** |
| 21:38:05 | `Finalizado` (SYSTEM, por GPS, posición a 1,1 km del destino) |
| 21:38:09 | proceso `ARENAS_EJECUCION_CERTIFICACIONUM` (3 s) |

- **Es un viaje de prueba** (`PruebaFacundo`): el basculero cambió los estados a 9,3 km de la planta, a las 16:04, cuando el camión
  iba a 73 km/h; recién llegó a la planta a las 16:24. Los estados del origen no sirven como referencia en este viaje.
- **El destino no tiene estados**: de `En tránsito` pasa directo a `Finalizado` (sin `En proceso de descarga`). Es el caso del
  documento, destinos sin personal en sitio. Ahí la única fuente de tiempos es la geocerca, y la calidad del polígono es decisiva.
- `Z_LPViajeMonitorGeocerca` no tiene filas para este viaje; no se usa en Última Milla.
- Fuentes de estados confirmadas: `EstadoViajeTraceEstado` (viaje), `ParadaTraceEstado` (parada, con posición del cambio) y `BitacoraViaje`.
- El proceso de certificación de la plataforma corre en el mismo segundo del cierre: indica el momento en que se dispone de los datos.
