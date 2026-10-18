# Rutinas

Hábitos con racha, recordatorios que insisten y temporizador de intervalos en una sola app gratuita, sin anuncios, sin cuenta y sin internet. Junta lo que hoy se paga en Streaks, Due, Seconds Pro y (Not Boring) Habits.

## Qué trae la v1

| Parte | Funciones |
|---|---|
| Hábitos | Ilimitados, cada uno con ícono (61 de Material) y color · frecuencias: todos los días, días concretos de la semana, cada N días, N veces por semana o por mes · de sí o no, varias veces al día con meta y unidad (8 vasos), con tiempo y temporizador integrado (meditar 10 min) y "dejar de…" que cuenta los días sin recaer · nota en cada día · racha actual y mejor racha que no rompen los días que no tocan, los saltados a propósito ni el día de hoy sin terminar · calendario del mes con el estado de cada día · avisos a las horas elegidas que pueden insistir cada 1 a 60 min hasta marcarlo · archivar y recuperar |
| Recordatorios | Una vez, cada N días, días de la semana, cada mes (un día fijo, el 31 cae el último día de los meses cortos, o el último día) y cada año (el 29 de febrero cae el 28 en los años no bisiestos) · insistencia cada 1 a 60 min hasta marcarlo hecho · cuentas regresivas "avísame en 5, 10, 15, 30, 60 min u otro" que suenan hasta apagarlas · Hecho, Posponer 10 min y Sumar 1 desde la notificación · posponer 5 min a 3 h o hasta mañana · deshacer |
| Temporizador | Plantillas HIIT, Tabata, circuito y propia · bloques que se repiten, anidados hasta tres niveles, con nombre de la vuelta y opción de omitir el último descanso · color por intervalo · pantalla grande con intervalo actual y siguiente, ronda, total restante y avance · voz del sistema en el idioma de la app que anuncia cada intervalo y cuenta 3, 2, 1 · sonidos propios (pitido, campana, bocina y gong) · sigue con la pantalla apagada o en otra app (notificaciones programadas con sonido para cada cambio, alarmas exactas si se conceden) · pantalla encendida mientras se entrena · candado contra pausas accidentales (se quita manteniendo presionado) · cronómetro con vueltas (la más rápida y la más lenta resaltadas) · cuentas atrás con preajustes guardados · historial de entrenamientos |
| Resumen | Semana, mes y año: cumplimiento global y por hábito, días hechos, mejor día, día de la semana más constante, minutos de los hábitos con tiempo, entrenamientos hechos y tiempo entrenado, barras por día o por mes |
| General | Sin cuenta y sin internet (la app no tiene ese permiso) · tema claro, oscuro o del sistema y ocho colores de acento · TalkBack y VoiceOver, texto hasta ×2 sin desbordes y botones de 48 dp · copia de seguridad en JSON por la hoja de compartir y restauración desde archivo · español e inglés (al abrir, el idioma del teléfono) |

Los datos quedan en el dispositivo, en archivos JSON con escritura atómica.

- Código: Apache-2.0. Sonidos sintetizados con `tools/gen_rutinas_sounds.py` (sin muestras de terceros); voz del sistema con `flutter_tts`.
- Decisiones de diseño: `docs/DECISIONES.md`.
- Respuestas para las tiendas: `store/COMPLIANCE.md`; fichas en `fastlane/metadata/`.
- Ícono generado con `tools/gen_rutinas_assets.py`.

```bash
flutter pub get
flutter analyze
flutter test
flutter test --tags screenshots   # capturas de tienda
flutter run
```
