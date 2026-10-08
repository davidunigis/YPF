# Recomendaciones: espera en la puerta de los sitios y geocercas

Estado: **documento de recomendaciones. No se cambió ningún cálculo por este tema.**
Origen: análisis del viaje 329958 (`Diagnostico/Analisis_Viaje_329958.md`, hallazgos 1 y 3).

## 1. Qué pasa
El SP decide si un vehículo está en una parada solo por geometría: el evento GPS cae **dentro** del polígono de la
geocerca o no. Un camión que espera en la cola, aunque sea a metros de la puerta, queda **fuera** y su tiempo se
clasifica como `DETENIDO` (responsabilidad del transporte). Si hubiera estado adentro, ese mismo tiempo sería
espera de descarga y, pasada la tolerancia, demora de YPF.

## 2. Evidencia (viaje 329958, destino BDTN49; horas locales)
| Hora | Velocidad | Distancia a la geocerca | Clasificación hoy |
|---|---|---|---|
| 16:51 | 0 km/h | 84 m | `CARRETEANDO` (parada corta) |
| 16:54 | 3,7 km/h | 8 m | `CARRETEANDO` |
| 16:55 → 17:45 | 0 km/h | 8 m → 2 m | **`DETENIDO` (67 min, transporte)** |
| 18:02 | 11 km/h | 0 m (entra) | `DESCARGA` |
| 18:31 | 11 km/h | 1 m (sale) | `CARRETEANDO` |

El camión esperó **a 2–8 m del borde**, dentro del error normal de un GPS. Con un margen de 10 m en la geocerca
el resultado cambia por completo:

| Margen | YPF (min) | Transporte (min) | Estadía en destino |
|---|---|---|---|
| 0 m (hoy) | 0 | 67 | 29 min |
| 10 / 25 / 50 m | 57 | 0 | 102 min |
| 100 / 150 m | 60 | 0 | 105 min |

En el origen ocurre algo parecido: la geocerca de Planta Añelo tiene 10 puntos y el camión da vueltas a 0–130 m
durante unos 37 min sin registrar ninguna `CARGA`.

## 3. Opciones

| | Opción | A favor | En contra |
|---|---|---|---|
| A | **Redibujar las geocercas** de planta y destino incluyendo la zona de ingreso y espera | No requiere código. Es lo que el documento supone ("ingreso a la geocerca"). Se ve y se audita en el mapa. | Hay que relevar cada locación. Puede incluir calles de paso. Las geocercas también se usan para **cerrar viajes** y para alertas: agrandarlas puede adelantar un cierre. |
| B | **Parámetro de margen en metros** en el SP (por defecto 0 = comportamiento actual), solo para las paradas del viaje, no para estaciones de servicio | Rápido y uniforme. Con 0 no cambia nada hasta que se decida. Absorbe el error del GPS. | Un solo valor para todos los sitios. No cubre colas largas. Un margen grande genera falsos positivos (camiones que pasan por calles cercanas). |
| C | **Dejarlo como está** y formalizarlo: espera fuera de la geocerca = detenido del transporte | Coincide literalmente con el documento. | La cola de descarga, que depende de YPF, se imputa al transporte: riesgo de disputas. |
| D | **Usar los estados de la plataforma** (llegada, atraque, inicio y fin de carga/descarga) en vez del GPS | Es lo que describe el documento (el basculero cambia estados). No depende del ruido GPS. | Depende de que se registren. No aplica a destinos sin personal en sitio. Falta revisar qué tablas lo guardan (`ParadaTraceEstado`, `EstadoViajeTraceEstado`, `Z_LPViajeMonitorGeocerca`). |
| E | **Señalizar sin cambiar los números**: una observación en cada `DETENIDO` que está a menos de N m de una parada ("detenido a 8 m de la geocerca X") | Transparencia y auditoría sin tocar la imputación. | No resuelve la imputación. Requiere código. |

## 4. Recomendación
1. **Cuantificar primero**: medir en un período cuántos viajes y minutos de `DETENIDO` están a pocos metros de una
   parada. Hoy hay un solo viaje de prueba; no alcanza para elegir un valor.
2. **Decidir el criterio de negocio**: ¿la espera en la puerta cuenta como espera de carga/descarga (YPF)?
3. Si la respuesta es sí: **A como solución de fondo** y **B como complemento** (con un margen chico, 10–25 m, que
   solo absorba el error del GPS). Mientras tanto, **E** da visibilidad sin cambiar los resultados.
4. Si la respuesta es no: **C**, dejándolo escrito como regla.
5. En paralelo, revisar **D**: si la plataforma ya registra los estados, es la fuente más fiable.

## 5. Preguntas para el cliente
- ¿Existe una zona de espera o cola reconocida en cada planta y destino? ¿Dónde está?
- ¿Quién responde por el tiempo de cola antes de entrar al predio?
- ¿Se puede usar el registro de estados (basculero) como fuente oficial?
- ¿Qué efecto tendría agrandar las geocercas sobre el cierre automático de viajes y las alertas?
- ¿Dónde carga realmente el camión en Planta Añelo? La geocerca actual no lo captura.

## 6. Qué no se hizo
No se agregó ningún margen al SP ni se modificó ninguna geocerca. Los números de los reportes siguen
calculándose con el polígono exacto.
