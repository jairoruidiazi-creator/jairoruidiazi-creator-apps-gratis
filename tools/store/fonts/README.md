# Fuentes de las capturas de tienda

Instancias estáticas (Regular, Medium, SemiBold, Bold y ExtraBold) creadas con
`fontTools.varLib.instancer` a partir de las fuentes variables del repositorio
[google/fonts](https://github.com/google/fonts). Todas usan la licencia SIL Open
Font License 1.1 (archivos `OFL-*.txt`).

- **Roboto**: texto de las capturas de Android (la fuente del sistema en Android).
- **Inter**: reemplaza a San Francisco en las capturas de iOS, que no se puede
  redistribuir; se registra con los nombres `CupertinoSystemText` y
  `CupertinoSystemDisplay` que usa Flutter en iOS.
- **Lexend**: titulares de las capturas compuestas.

Se usan en las pruebas de capturas y en `tools/store/compose_screenshots.py`.
Sello además incluye Roboto Medium, Bold y ExtraBold (familia `SelloSans`) para
dibujar el sello con la misma letra en Android y en iOS.
