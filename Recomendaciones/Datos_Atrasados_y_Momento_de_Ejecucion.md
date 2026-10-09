# Recomendaciones: datos GPS atrasados y momento de ejecución del SP

Estado: **documento de recomendaciones.** Lo único que se cambió es el filtro del SP (ver sección 6).
Origen: análisis del viaje 329958 (`Diagnostico/Analisis_Viaje_329958.md`, hallazgo 2).

## 1. Situación
- `Z_SP_ItinerarioViaje` se ejecuta **al finalizar el viaje** (confirmado).
- Los reportes GPS de un vehículo pueden llegar mucho después de haber ocurrido (el equipo los guarda y los envía cuando
  recupera cobertura). El `IdEvento` se asigna al recibirlos.
- En el viaje 329958, el estado `Finalizado` se registró a las 21:38:05 UTC y la certificación de la plataforma corrió
  en el mismo segundo. Los datos atrasados llegaron **después**.

## 2. Evidencia (viaje 329958)
| | Valor |
|---|---|
| Eventos de la ventana del viaje | 388 |
| Disponibles al cierre (21:38 UTC) | 241 (62 %) |
| Llegaron después | 147 (38 %), en dos lotes: 21:42–21:44 y 22:53–23:05 UTC |
| Atraso de los que llegaron tarde | 90 a 234 min (mediana 170) |
| Km GPS con lo disponible al cierre / con todo | 143,3 / 150,6 (+5 %) |
| Entre 19:00 y 21:00 UTC (detención y descarga) | 13 eventos al cierre contra 101 en total |

Las duraciones de este viaje casi no cambian con los datos completos (`DETENIDO` 67 → 68 min, `DESCARGA` 29 → 29 min),
porque los tiempos se calculan entre eventos y la detención era larga y estable. Pero **el kilometraje sí cambia**, y en
otros viajes un hueco que cubra una entrada o salida de geocerca puede mover un tiempo decenas de minutos.

## 3. Qué ya está resuelto
El SP descartaba cualquier evento con `IdEvento` mayor al del cierre, aunque su hora estuviera dentro del viaje. Se
quitó ese tope: ahora filtra por la ventana de tiempo (y `IdEvento >= IdEventoActivacion`). **Una segunda corrida
posterior ya usaría los datos atrasados.** Pero hoy esa segunda corrida no existe.

## 4. Opciones

| | Opción | A favor | En contra |
|---|---|---|---|
| A | **Segunda corrida diferida** a horas fijas tras el cierre (por ejemplo +6 h y +24 h), con un proceso programado de la plataforma o un job de SQL Agent | Simple. El SP se puede volver a ejecutar (borra y recarga el viaje). | Los valores cambian después de publicados. Hay que definir cuándo son "definitivos". Si algo consume la tabla al cierre, ve valores provisorios. |
| B | **Corrida cuando llegan datos nuevos**: cada hora, revisar los viajes finalizados de las últimas 24–48 h y volver a ejecutar el SP solo si hoy hay más eventos válidos en la ventana que los usados (`SUM(CantidadEventos)` de `Z_ItinerarioViaje`) | Corre solo cuando hace falta. No depende de un atraso fijo. | Más piezas: el proceso de revisión. Una consulta repetida sobre `Evento`, que es una tabla grande. |
| C | **No hacer nada** y aceptar los datos disponibles al cierre | Sin cambios. | El resultado de cada viaje depende de la cobertura del vehículo: dos viajes iguales pueden dar km y tiempos distintos. |
| D | **Retrasar la primera corrida** (por ejemplo 6 h después del cierre) | Todos los consumidores ven datos casi completos desde el principio. | El reporte tarda en estar disponible. Si la certificación necesita los datos al cierre, no sirve. |

## 5. Recomendación
1. **Medir antes de fijar plazos.** Con un solo viaje de prueba (atraso máximo de 234 min) no hay base para elegir "+6 h".
   La consulta de abajo mide cuántos reportes llegan tarde y cuánto en los vehículos del transporte de Última Milla.
2. Como punto de partida, **B**; **A** si se prefiere algo más simple de operar (con el plazo definido según la medición).
3. Decidir con el cliente qué valores son "definitivos" y quién los consume (certificación incluida) antes de agregar
   la segunda corrida.

Consulta de medición (solo lectura; ajustar el filtro de transportes y el rango de fechas):
```sql
SELECT E.IdVehiculo,
       COUNT(*)                                                                              AS Eventos,
       SUM(CASE WHEN DATEDIFF(MINUTE, E.FechaHoraEvento, E.FechaHoraRecepcion) > 10  THEN 1 ELSE 0 END) AS Atrasados_10min,
       SUM(CASE WHEN DATEDIFF(MINUTE, E.FechaHoraEvento, E.FechaHoraRecepcion) > 60  THEN 1 ELSE 0 END) AS Atrasados_60min,
       MAX(DATEDIFF(MINUTE, E.FechaHoraEvento, E.FechaHoraRecepcion))                        AS MaxDemoraMin
FROM dbo.Evento E WITH (NOLOCK)
WHERE E.FechaHoraEvento >= DATEADD(DAY, -7, GETUTCDATE())
  AND E.IdVehiculo IN (SELECT V.IdVehiculo FROM dbo.Vehiculo V WHERE V.IdTransporte = 126)
GROUP BY E.IdVehiculo
ORDER BY Atrasados_60min DESC;
```

## 6. Preguntas para el cliente
- ¿Qué procesos leen `Z_ItinerarioViaje` y en qué momento? ¿La certificación (`ARENAS_EJECUCION_CERTIFICACIONUM`) la usa al cierre?
- ¿Es aceptable que los valores de un viaje cambien después del cierre? ¿Hasta cuándo?
- ¿Qué proceso de la plataforma invoca hoy el SP, y se le puede agregar una segunda invocación?

## 7. Qué se hizo y qué no
- Hecho: se quitó el tope superior por `IdEvento` en `SP/Z_SP_ItinerarioViaje.sql`.
- No hecho: ninguna segunda corrida, proceso programado ni job. El resultado al cierre sigue siendo el mismo que antes.
