# apps-gratis

Aplicaciones gratuitas para Android e iOS, sin anuncios, sin suscripciones y sin cuenta, que dan todo lo que hoy cobran las apps de pago. Hechas con Flutter, con los datos solo en el dispositivo o en la nube del propio usuario.

| App | Carpeta | Qué es | Estado |
| --- | --- | --- | --- |
| Pilas | `apps/pilas` | 26 juegos didácticos para niños de 3 a 11 años: lógica, números, letras, ciencias, arte y emociones; perfiles por niño, informe para padres y modo docente | v1 lista |
| Clave | `apps/clave` | Kit de práctica musical: afinador, metrónomo, bordón y teclado, grabadora y registro de práctica | v1 lista |
| Sello | `apps/sello` | Cámara de campo con sello GPS: coordenadas en UTM, MGRS, Plus Code y proyección oficial de Colombia, norte verdadero, proyectos, galería, mapa y exportación (CSV, KML, KMZ, ZIP, PDF) | v1 lista |
| Finanzas personales | `apps/finanzas` | Gastos, presupuestos, tarjetas y avisos bancarios, todo sin conexión | Pendiente |

## Cómo se compila

Cada app es un proyecto Flutter independiente dentro de `apps/`. La integración continua (`.github/workflows`) analiza, prueba y compila cada app en cada cambio: APK de Android en Linux y compilación de iOS sin firma en macOS.

```bash
cd apps/pilas
flutter pub get
flutter analyze
flutter test
flutter run
```

Las carpetas `android/` e `ios/` de cada app se generan una sola vez con `flutter create` desde el flujo `bootstrap-platforms` y luego se ajustan con `tools/patch_platforms.py`.

## Licencias

- Código: [Apache-2.0](LICENSE).
- Contenido propio de las apps (láminas, cuentos, textos): CC BY 4.0.
- Pictogramas: [Twemoji](https://github.com/jdecked/twemoji), CC BY 4.0 (`docs/LICENSE-twemoji-CC-BY-4.0.txt`).
- Tipografías: Lexend y Andika, SIL Open Font License 1.1 (`docs/`).
- Datos geodésicos de Sello: coeficientes WMM2025 (NOAA/NCEI y BGS) y rejillas EGM96 (NGA), de dominio público.
- Mapas de Sello: © OpenStreetMap contributors (ODbL), con atribución en la app.

## Decisiones

Las decisiones de diseño y producto de cada app están en `apps/<app>/docs/DECISIONES.md`.
