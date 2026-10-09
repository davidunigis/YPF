# Recomendaciones: viajes sin activación y ventana de eventos del SP

Estado: **documento de recomendaciones. No se cambió el SP por este tema.**
Origen: viaje 330113 (`Diagnostico/Analisis_Viaje_330113.md`).

## 1. Situación
- Si el viaje no tiene evento de activación o de cierre (valen 0), `Z_SP_ItinerarioViaje` usa como ventana
  `Viaje.FechaCreacion` hasta +72 h.
- En el viaje 330113 (estado `Programado`, sin empezar) eso tomó 2 horas de permanencia del camión en el destino,
  anteriores al viaje, como si fueran la descarga: 120 min contra 45 de tolerancia → `FUERA DE TOLERANCIA` y 75 min de demora de YPF.
- El problema aplica a **cualquier viaje al que se ejecute el SP antes de activarse** y, por la misma ventana de respaldo, a los
  viajes **finalizados sin evento GPS** (cierre manual), cuya ventana también sería creación + 72 h.

## 2. Opciones

| | Opción | A favor | En contra |
|---|---|---|---|
| A | **Salir sin procesar** si `IdEventoActivacion` es NULL o 0 (con una línea en el `Log` explicando el motivo) | Un viaje sin empezar nunca genera filas. Es lo que ya ocurre en la práctica, porque la plataforma corre el SP al finalizar. | Los viajes finalizados sin evento de activación tampoco se procesan, salvo que se combine con B. |
| B | **Usar `Viaje.FechaInicioReal` y `FechaFinReal`** como ventana de respaldo cuando faltan los eventos | Cubre los cierres manuales con una ventana acotada (en el viaje 329958 coinciden con los eventos: 16:04:00 y 21:38:05). | Hay que validar que esos campos se llenen siempre; un viaje sin ellos seguiría sin ventana. |
| C | **Dejarlo como está** y evitar corridas manuales sobre viajes sin finalizar | Sin cambios. | Cualquier ejecución manual o reproceso sobre un viaje sin cerrar deja filas engañosas en `Z_ItinerarioViaje`. |

## 3. Recomendación
**A y B juntas**: salir sin procesar si el viaje no está activado, y usar `FechaInicioReal`/`FechaFinReal` para los finalizados sin
evento GPS. Antes de B, confirmar con un viaje real finalizado manualmente que esas dos fechas existen.

## 4. Preguntas
- ¿Hay viajes de Última Milla que se finalicen manualmente, sin evento GPS de cierre? ¿Deben entrar en la certificación?
- ¿Alguien ejecuta el SP a mano sobre viajes sin finalizar?

## 5. Limpieza puntual
El viaje 330113 quedó con filas en `Z_ItinerarioViaje`. Se pueden borrar, y se recalcularán cuando el viaje se cierre:
```sql
DELETE FROM dbo.Z_ItinerarioViaje WHERE IdViaje = 330113;
```
