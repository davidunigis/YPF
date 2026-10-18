# Recomendaciones: ventana hacia atrás de la activación y retorno a la planta

Estado: **análisis y propuesta. No se cambió el SP por este tema** (decisión pendiente).
Origen: reunión con el cliente (la hora previa a la activación no les funciona bien).
Datos reales usados: viaje 329958 (`Diagnostico/Analisis_Viaje_329958.md`). Consulta para medir con datos de la base: `Diagnostico/Consultas/30_Brechas_entre_Viajes_de_la_Unidad.sql`.

## 1. Qué pide el cliente
1. El **retorno del vehículo a la planta o almacén** (el trayecto desde el último destino del viaje anterior hasta el depósito de salida del viaje actual) tiene que aparecer en el análisis. Una hora es poco.
2. Mirar **hasta 6 horas** de eventos GPS antes de la activación, **pero** si dentro de esas 6 horas la unidad finalizó otro viaje, el análisis arranca desde que ese viaje se finalizó y la unidad salió de la geocerca de su última parada, no desde las 6 horas.
3. Les preocupa qué pasa si el viaje anterior fue hace días o si la unidad nunca tuvo viajes.

## 2. Qué hace hoy el SP (y un problema que conviene corregir sí o sí)
Desde la versión con `@MinutosAtras = 60`, la ventana arranca 60 min antes de la activación **sin mirar qué hacía la unidad**.
- **Se pisa con el viaje anterior.** Si el viaje A terminó 30 min antes de que se active el B, la hora previa de B incluye los últimos 30 min de A. Esos eventos están dentro de la geocerca del último destino de A, que **no** es una zona de B: el SP los ve como una parada fuera de geocerca, es decir `DETENIDO` (si pasan de 15 min), y los suma a las demoras del transporte de B. Es la misma espera que ya contó A como descarga: **se cuenta dos veces** y además se le descuenta al transportista.
- Con 6 horas fijas el problema crece (hasta 6 horas de A dentro de B). Por eso la regla "empezar desde la finalización del viaje anterior" que propone el cliente no es un detalle: es lo que evita el doble conteo.
- Cuando el cliente dice que "no funciona de manera correcta", este solape es la primera causa a verificar: la consulta `30` marca con `HoraPreviaPisaAlViajeAnterior = SI` los viajes afectados.

## 3. Por qué el retorno no se captura hoy
En el viaje 329958 el viaje se finalizó a los 5 min de salir del destino (el último tramo es `CARRETEANDO` de 5 min y el cierre lo hace `SYSTEM`). La ventana del viaje A termina ahí, así que **el camino de vuelta al depósito no está en A**. Tampoco está en B más que su última hora. Queda en tierra de nadie.

Se podría extender el final de A (mirar horas **después** de su finalización), pero el SP corre cuando A se finaliza: el retorno todavía no ocurrió y no hay datos (el mismo problema de datos atrasados de `Datos_Atrasados_y_Momento_de_Ejecucion.md`). En cambio, cuando se ejecuta el SP de B, el retorno **ya pasó**. Por eso la propuesta del cliente (asignar el retorno al viaje siguiente, mirando hacia atrás) es la viable técnicamente.

## 4. Viabilidad técnica

### 4.1 Mirar 6 horas (o más)
- **Sí se puede.** El SP ya consulta `Evento` por unidad y rango de fechas; solo cambia el inicio de la ventana.
- **Costo.** En el viaje 329958 hay unos 44 eventos por hora en marcha (hasta ~85 por hora cerca de la planta). El log mostró ~2,7 s para 241 eventos, que es casi todo la intersección con las 1.561 geocercas de estaciones de servicio, o sea unos 11 ms por evento. Estimación: 6 h ≈ 260–500 eventos más ≈ **+3 a +5 s por viaje**; 24 h ≈ +12 a +20 s. Reprocesar 1.000 viajes con 6 h agrega ~1 h; con 24 h, ~4 h. Aceptable; si hiciera falta se acelera descartando de entrada los eventos lejos de toda geocerca.
- **Más de 6 horas no aporta.** El retorno típico de última milla es de pocas horas, y cuanto más atrás se mira más tiempo "parado sin viaje" entra al análisis (punto 5.1). Dejarlo como parámetro (`@MinutosAtras`, hoy 60 → 360) permite subirlo si el cliente lo pide.

### 4.2 Mirar el último viaje anterior finalizado
- **Sí se puede**, con datos crudos (sin depender de `Z_ItinerarioViaje`, así no importa el orden en que se procesen los viajes): `Viaje` de la misma unidad, con `IdEventoFinalizacion > 0`, finalización ≤ activación del viaje actual, el de fecha de finalización más reciente.
- **Cualquier operación.** El viaje anterior puede ser de otra operación (no solo Última Milla 139): la unidad estuvo ocupada igual. Hay que excluir los cancelados.
- **Combustible.** Sigue funcionando: las cargas de A quedan antes del inicio de la ventana de B y el PASO 7.a.0 las cuenta como previas del día.

## 5. Casos límite y cómo se resuelven

| # | Caso | Qué hace la propuesta |
|---|---|---|
| 1 | Viaje anterior finalizado hace menos de 6 h | La ventana arranca en su finalización (y se recortan los eventos iniciales que sigan dentro de la geocerca de su última parada, salvo que esa zona sea también del viaje actual). No hay solape ni doble conteo. |
| 2 | Viaje anterior hace más de 6 h, o hace días | Rige el tope de 6 h. No se mira más atrás. |
| 3 | La unidad nunca tuvo viajes (unidad nueva) | No hay viaje anterior: rige el tope de 6 h. No necesita tratamiento especial. Si la unidad no tiene eventos, sale la fila `Sin eventos GPS` que ya existe. |
| 4 | Hay un viaje activo cuando se activa este (solape de viajes) | No se mira hacia atrás (arranca en la activación) y se deja una línea en el `Log`: esos eventos son del otro viaje. |
| 5 | El viaje anterior terminó en el mismo depósito donde carga el actual (el último destino de A es el depósito de retorno) | Los eventos dentro de la geocerca del depósito son de B (carga y espera): **no** se recortan. Solo se recortan los que estén en la geocerca de A y no en una zona de B. |
| 6 | Finalización manual tardía del viaje anterior (la unidad ya llegó a la planta antes del cierre) | Con "arrancar en la finalización" se pierde la entrada real a la geocerca de carga (y con ella el arranque de la tolerancia). Es el riesgo principal de la regla. Mitigación opcional: si al finalizar A la unidad ya está dentro de la primera geocerca de carga de B, retroceder hasta su entrada. Hay que ver si ocurre con la consulta `30` y el cliente. |
| 7 | Viaje anterior cancelado o sin evento de finalización | No cuenta como viaje anterior. |
| 8 | Dos viajes seguidos de la misma unidad en el mismo día | Las ventanas no se pisan (A termina donde empieza B). La excepción de combustible del día sigue siendo una por día y por unidad. |

## 6. El punto de negocio importante: tiempo parado entre viajes
Cualquier ventana hacia atrás mete en el análisis **tiempo sin viaje asignado**. El documento To Be dice que un detenido solo cuenta "con viaje **Publicado / Programado / Tránsito**". Si la unidad terminó A a las 06:00, se queda estacionada fuera de geocercas hasta las 11:00 y B se activa a las 11:30, la regla simple ("un detenido fuera de geocerca de más de 15 min es del transporte") le carga **5 horas de detenido** al transportista por un tiempo en el que B ni existía. Y como el nuevo "tiempo a reconocer" **resta** las demoras del transporte, ese error le **quita dinero** al transportista.

Opciones:

| | Opción | Efecto |
|---|---|---|
| A | **Lo que pidió el cliente, tal cual**: los detenidos de la ventana previa son del transporte. | Simple, pero con 6 h el error máximo pasa de 60 a 360 min por viaje. |
| B | **Sin responsabilidad antes de que el viaje esté Publicado/Programado** (primer pase a 98 o 92 en `EstadoViajeTraceEstado`). Esos tramos se muestran (retorno) pero no suman a las demoras de nadie. | Respeta el To Be. Cubre el caso de la unidad estacionada. En el viaje 329958: publicado 13:58 UTC, programado 15:06, activado 16:03; la ventana de 6 h arrancaría a las 10:03, antes de que el viaje existiera. |
| C | Que el retorno anterior a la geocerca de carga salga siempre como `RETORNO` (sin responsabilidad, aunque haya paradas). | Es lo más neutral. Pierde el control de paradas largas camino a la planta. |

**Recomendación:** A + B, es decir ventana de 6 h acotada por el viaje anterior (punto 5) y sin imputar detenidos anteriores a que el viaje esté Publicado/Programado.

## 7. Cómo se vería el retorno en el reporte
Hoy el camino a la geocerca de carga sale como `CARRETEANDO`, y las paradas largas fuera de geocerca como `DETENIDO`. El cliente habla de "retorno". Propuesta: **no cambiar los nombres de las novedades**; que los tramos de la ventana previa lleven en `Detalle` la frase "Retorno hacia el depósito de salida (previo a la activación)" para que se distingan. Si prefieren una novedad propia (`RETORNO_PREVIO`), hay que revisar que ningún reporte la tome por error (los reportes filtran por valores concretos de `Novedad`, así que no se contaría en demoras).

## 8. Plan de cambio (cuando se decida)
1. Parámetro nuevo: la ventana pasa a 360 min máximo (`@MinutosAtras = 360`).
2. En el encabezado del SP: buscar el viaje anterior finalizado de la unidad, el inicio efectivo = el mayor entre `activación − 360 min` y su finalización; si hay un viaje activo, inicio = activación.
3. Recortar los eventos iniciales dentro de la geocerca del último destino del viaje anterior que no estén en una zona del viaje actual.
4. Si se elige la opción B: no imputar `DETENIDO` anteriores a la primera publicación/programación.
5. Líneas en el `Log` (`PASO1B`) con el inicio elegido y por qué.
6. Probar en QA con: un viaje con viaje anterior hace 2 h, uno con viaje anterior hace más de 6 h, una unidad sin viajes, un viaje con solape, y el 329958. Reprocesar con `Operacion/Reprocesar_Itinerario_Viajes_UM.sql`.

## 9. Preguntas para el cliente
1. Los detenidos fuera de geocerca durante el retorno, **antes de que el viaje estuviera publicado o programado**, ¿se le cargan al transportista?
2. ¿El viaje anterior puede ser de cualquier operación o solo de Última Milla?
3. ¿Las finalizaciones de los viajes son automáticas (al salir del destino) o hay cierres manuales tardíos? (caso 6)
4. ¿6 horas alcanza como tope o hay retornos más largos?
5. Si el tiempo a reconocer da negativo (las demoras del transporte superan los excedentes), ¿se muestra el valor negativo o se deja en 0?

## 10. Mientras se decide
La hora previa actual (`@MinutosAtras = 60`) puede duplicar tiempo del viaje anterior (punto 2). Si el cliente ya está viendo diferencias, se puede dejar en 0 (`@MinutosAtras = 0`, sin mirar hacia atrás) hasta implementar la regla nueva; no cambia nada más.
