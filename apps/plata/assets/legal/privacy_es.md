# Política de privacidad de Plata

Vigente desde el 18 de octubre de 2026.

## En pocas palabras

Plata no recoge datos de nadie. No tiene cuentas, ni anuncios, ni herramientas de analítica o rastreo, y no tenemos servidores. Tus cuentas, movimientos y presupuestos se guardan cifrados solo en tu teléfono. La app solo se conecta a internet para descargar tasas de cambio, y solo si usas otras monedas además de la principal.

## Quién publica la app

Plata es una app gratuita y de código abierto publicada por el equipo de apps-gratis, con el nombre de desarrollador que aparece en su ficha de Google Play y de la App Store. El código está en github.com/jairoruidiazi-creator/jairoruidiazi-creator-apps-gratis.

## Qué información maneja la app y dónde queda

- **Tus finanzas:** cuentas, saldos, movimientos, categorías, presupuestos, programados, plantillas y notas.
- **Fotos de recibos** que adjuntes a un movimiento, tomadas con la cámara o elegidas de tus fotos.
- **Avisos bancarios (solo Android y solo si los activas):** el título y el texto de las notificaciones de estas apps de bancos y billeteras, para sugerirte el movimiento: Mi Bancolombia, Nequi, Daviplata, Davivienda, BBVA, Banco de Bogotá, Banco de Occidente, DAVIbank (antes Scotiabank Colpatria), Lulo Bank, Nu y MOVii.
- **Ajustes** de la app, la clave de acceso (guardada como huella criptográfica, nunca en claro) y las copias automáticas.

Todo vive en tu teléfono, en la carpeta privada de la app. Los datos y las fotos de recibos se guardan cifrados con ChaCha20-Poly1305 y una llave que guarda el sistema (Keystore de Android o Llavero de iOS); si al instalar la app el teléfono no ofrece ese almacén seguro, la llave queda en la carpeta privada de la app, protegida por el sistema y no por hardware. Esa carpeta no entra en las copias de seguridad de Google o de iCloud ni en el traspaso a un teléfono nuevo, porque la llave no viaja con ella: para llevar tus datos a otro teléfono usa la copia cifrada con contraseña. Los avisos bancarios que llegan con la app cerrada esperan cifrados (AES-GCM, con una llave del Keystore de Android) en la carpeta privada de la app hasta que la abres y Plata los procesa; si apagas los avisos, se borran. En iPhone el Llavero conserva sus claves aunque desinstales una app, así que la primera vez que Plata se abre tras instalarse borra lo que hubiera dejado una instalación anterior, como una clave de acceso. Nosotros no recibimos nada de esto, no lo vemos y no lo podemos recuperar.

## Permisos

- **Acceso a notificaciones (Android, opcional):** solo si activas los avisos bancarios. Plata lee únicamente las notificaciones de las apps de bancos y billeteras de su lista e ignora las demás; lo que lee se usa en el teléfono. Si apagas los avisos en Plata, deja de leer aunque el permiso siga concedido; puedes quitar el permiso cuando quieras en los ajustes del sistema.
- **Cámara y fotos (opcional):** para adjuntar la foto de un recibo.
- **Huella o rostro (opcional):** para desbloquear la app; la verificación la hace el sistema y Plata no recibe tus datos biométricos.
- **Notificaciones:** para tus recordatorios de anotar y de pagos, que se programan en el teléfono. Plata pide el permiso la primera vez que hace falta (al guardar un programado con recordatorio o una tarjeta con día de pago, o al encender un recordatorio) y te dice para qué; en Más › Ajustes ves si está concedido y lo puedes dar, y lo quitas cuando quieras en los ajustes del sistema.
- **Internet:** solo para las tasas de cambio (ver abajo).

## Qué sale del teléfono y a quién

Si usas otras monedas además de la principal y dejas activada la actualización de tasas, Plata consulta una vez al día la Tasa Representativa del Mercado en datos.gov.co (Gobierno de Colombia), los cambios de referencia del Banco Central Europeo a través de api.frankfurter.dev y, para las monedas que el Banco Central Europeo no publica, open.er-api.com (ExchangeRate-API). Estas consultas no llevan ningún dato tuyo: esos servicios solo ven la dirección IP desde la que se hace la consulta, como cualquier sitio web. Se apaga en Más › Monedas.

Los enlaces de la guía (código fuente y reportar un problema) abren el navegador solo si los tocas.

## Compartir y exportar

Tú decides cuándo exportar un CSV o un Excel, o hacer una copia de seguridad (Más › Copias de seguridad). La copia cifrada queda protegida con la contraseña que elijas; la copia en JSON (la app te lo advierte antes) y los archivos CSV y Excel no van cifrados. Las copias guardan tus datos, no las fotos de recibos. Todo se comparte con la hoja de compartir del sistema y queda sujeto a las condiciones de quien lo recibe; la app borra su propio ejemplar del archivo, y la copia que la hoja de compartir de Android deja en la caché de la app, la siguiente vez que la abres y al borrar todo. Al restaurar, la copia temporal del archivo que eliges se borra apenas se lee.

## Niños

Plata es una herramienta de finanzas personales para adultos. No está dirigida a niños.

## Seguridad

Además del cifrado, puedes poner una clave de acceso y desbloquear con huella o rostro; tras varios intentos fallidos la espera entre intentos crece, aunque cierres la app. Con la clave puesta, Plata se tapa al salir de ella, para que no se vea en las apps recientes, y Android no deja tomar capturas de pantalla de la app. Con la clave puesta o con los saldos ocultos, los recordatorios no muestran montos y Android los oculta en la pantalla de bloqueo. Nadie puede recuperar la clave: si la olvidas, en la pantalla de bloqueo puedes borrar todo lo de Plata en el teléfono y empezar de nuevo. Recomendamos proteger el teléfono con bloqueo de pantalla y guardar copias cifradas en un lugar seguro: si pierdes el teléfono o la clave, nosotros no podemos recuperar tus datos.

## Conservación y borrado

Tus datos permanecen en el teléfono hasta que los borres. Puedes borrar movimientos y cuentas desde la app; las copias automáticas en Más › Copias de seguridad › Borrar las copias automáticas; y todo en Más › Ajustes › Borrar todos los datos o con «¿Olvidaste la clave?» en la pantalla de bloqueo, que quitan datos, fotos, copias automáticas, avisos pendientes, la clave y la llave de cifrado; o desinstalarla o limpiar sus datos en los ajustes del sistema. Las copias que hayas exportado fuera de la app las borras tú donde las guardaste. Como no guardamos copias, no hay nada más que borrar de nuestro lado.

## Tus derechos

Como no recogemos ni guardamos datos personales, no tenemos información tuya que consultar, corregir o eliminar; tú la controlas directamente en el teléfono. Esto aplica también a lo previsto en la Ley 1581 de 2012 de Colombia y en normas similares de otros países.

## Cambios a esta política

Si la app cambia la forma en que maneja la información, actualizaremos esta política y su fecha de vigencia antes de publicar la nueva versión. Las versiones anteriores quedan en el historial del repositorio.

## Contacto

Para cualquier consulta, también las privadas, usa la página de soporte: github.com/jairoruidiazi-creator/jairoruidiazi-creator-apps-gratis/blob/main/docs/SOPORTE.md. Allí se explica cómo abrir un reporte en github.com/jairoruidiazi-creator/jairoruidiazi-creator-apps-gratis/issues y cómo pedir un contacto privado sin publicar datos personales.
