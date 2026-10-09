# Análisis del viaje 330113 (Planta Añelo → BDTN49), marcado "fuera de regla"

Fuente: `Results.csv` de `Extraer_Eventos_y_Estados_Viaje.sql` para el viaje 330113 (no se recibió la salida de
`Z_ItinerarioViaje`; el resultado del SP se **reconstruyó** con la réplica de sus reglas sobre los eventos reales).
Viaje de prueba (`PruebaFacundoNQN`), transporte 126, vehículo 15876.

## Conclusión
El viaje **no empezó**: su último estado es `Programado` (12:39 UTC). No tiene evento de activación ni de cierre
(`IdEventoActivacion` = 0 e `IdEventoFinalizacion` = 0), no hubo `En proceso de carga` ni `En tránsito`.
Como no hay eventos de referencia, el SP usa la ventana de respaldo: desde la **creación del viaje** (11:23:37 UTC) hasta +72 h.
En esa ventana el camión estaba **dentro de la geocerca de BDTN49** (que es también el destino de este viaje), parado o a
velocidad mínima, desde el primer evento (11:23:46) hasta las 13:23:21 UTC. El SP lo toma como la descarga de este viaje.

| Parada | Novedad | Tiempo | Tolerancia | Desvío | Marca |
|---|---|---|---|---|---|
| BDTN49 | `DESCARGA` | **120 min** (08:23–10:23 local) | 45 min | **+75 min** | `FUERA DE TOLERANCIA` |

- Demora YPF según el SP: 75 min. `ExcedeTolerancia` = 1 y la observación dice "excede la tolerancia de 45 min".
- Después el camión viaja hacia la planta (10:23–12:31 local), pasa por la estación de servicio (12:31, 3 min: `COMBUSTIBLE`
  dentro de la excepción) y a las 15:49 UTC está a 4 km de la planta, todavía sin cargar.
- La marca "fuera de regla" es **real para el cálculo, pero no corresponde al viaje**: son las 2 horas que el camión pasó en el
  destino **antes** de que el viaje empezara.

## Por qué ocurre
- El SP está pensado para correr al finalizar el viaje (ahí existen activación y cierre). Corrido sobre un viaje sin
  activación toma como ventana la creación del viaje más 72 horas.
- Los viajes sin activar ni cerrar tienen `IdEventoActivacion` e `IdEventoFinalizacion` en **0, no NULL**.
- El SP ya trata el 0 de forma coherente en la ventana (cae al respaldo), pero el respaldo no tiene sentido para un viaje sin empezar.

## Defecto corregido en los reportes
`Viaje.IdEventoFinalizacion IS NOT NULL` dejaba pasar a este viaje como "finalizado" (0 no es NULL). Los reportes
`Reporte_ResumenViajesFinalizados`, `Reporte_ParteDemorasPorUnidad`, `Reporte_CertificacionViajesUM` y el script
`Operacion/Reprocesar_Itinerario_Viajes.sql` ahora usan `IdEventoFinalizacion > 0`.

## Pendiente de decisión
Ver `Recomendaciones/Viajes_sin_activacion_y_ventana_del_SP.md`.
