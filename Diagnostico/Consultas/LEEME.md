# Consultas de diagnóstico (una por archivo)

Cada archivo es **una sola consulta de solo lectura** que devuelve **una grilla**, pensada para exportar a Excel
(SSMS: clic derecho en la grilla > *Guardar resultados como...* en CSV, o `Ctrl+A` y `Ctrl+Shift+C` para copiar con
encabezados y pegar en Excel). La única que escribe datos es la `21`, y está marcada.

Las consultas por viaje empiezan con `DECLARE @IdViaje INT = 330178;`: cambiar ese número.

## Primero, sin viaje (dónde está el problema)
| Archivo | Responde |
|---|---|
| `00_Version_y_Objetos` | ¿Están desplegados el SP nuevo, las columnas y las funciones? (explica los "Invalid column name" y los SP viejos) |
| `01_Log_Errores_y_Avisos` | Errores y avisos que el SP escribió en el Log |
| `02_Corridas_Sin_Fin` | Corridas que empezaron y no terminaron (el SP falló) y con qué IdViaje |
| `03_Viajes_UM_Finalizados_Sin_Itinerario` | Viajes que el consolidado no muestra porque no tienen filas |
| `04_Viajes_Sin_Eventos_GPS` | Viajes con la fila `SIN_EVENTOS_GPS` y cuántos eventos tenía la unidad |
| `05_Control_Por_Viaje` | Una fila por viaje con km, minutos por novedad y demoras, para detectar valores raros |

## Después, para un viaje en particular
| Archivo | Responde |
|---|---|
| `10_Viaje_Cabecera` | Datos del viaje, ventana de eventos, origen/destino del SP |
| `11_Paradas_y_Clasificacion` | Paradas, cómo las clasifica el SP y si tienen geometría |
| `12_Estados_del_Viaje` | Cambios de estado y el pase a En tránsito que marca el fin de la carga |
| `13_Z_ItinerarioViaje_Filas` | Lo que dejó el SP en la tabla que leen los reportes |
| `14_Log_Ultima_Corrida` | Pasos que registró el SP en la última corrida del viaje |
| `15_Eventos_GPS_Crudos` | Eventos de la unidad y por qué el SP usa o descarta cada uno |
| `16_Eventos_con_Geocerca` | Eventos usados, geocerca, distancia y novedad preliminar (la más útil para entender un tramo) |
| `17_Combustible_Previo_del_Dia` | Cargas de combustible previas del día que consumen la excepción |
| `18_Otros_Viajes_de_la_Unidad` | Otros viajes de la misma unidad y sus cargas de combustible |
| `19_Km_Teoricos_del_Par` | Nombres que busca el SP y filas de `Z_KmTeoricos` que coinciden |
| `20_Cambio_de_Turno_del_Transporte` | Rangos de cambio de turno del transportista |
| `21_Reprocesar_con_Debug` | **Escribe.** Reprocesa el viaje y devuelve zonas, tramos y eventos del SP |

Orden sugerido para un viaje con error: `10`, `13`, `14`, `12`, `16` (y `11`, `19`, `17`, `18` según el caso).
