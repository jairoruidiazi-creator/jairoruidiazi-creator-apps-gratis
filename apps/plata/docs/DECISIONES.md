# Plata: decisiones de diseño y producto

Registro de las decisiones tomadas durante el desarrollo, con su razón.

## Producto

- **Nombre de trabajo: Plata.** Es como se dice "dinero" en Colombia, corto y en español. Identificador de paquete `co.appsgratis.plata`. La carpeta pasó de `apps/finanzas` (nombre provisional del estudio) a `apps/plata`.
- **Colombia primero, útil en cualquier país.** Trae de serie lo que las apps extranjeras no tienen: quincenas como periodo y como frecuencia, TRM oficial, Nequi y Daviplata como tipos de cuenta, categorías con Administración, Prima y cesantías o 4×1000, avisos de los bancos colombianos, y tarjetas de crédito con corte, fecha de pago y cuotas tal como las facturan los bancos del país. Nada de eso estorba en otro país: la moneda base, las categorías y los bancos se cambian.
- **Sin cuenta, sin anuncios, sin servidor.** Los datos viven cifrados en el teléfono. La única conexión es la descarga de tasas de cambio (TRM de datos.gov.co y Banco Central Europeo), opcional y una vez al día. Esto es lo que el estudio marcaba como la ventaja frente a las apps de pago (que cobran por la nube o por la sincronización bancaria) y lo que da privacidad real.
- **Qué entró en la v1 además de lo que el estudio pedía:** tasa de ahorro, división de un movimiento en varias categorías, cuotas con estado de cuenta por ciclo, ajuste de saldo real, Excel propio sin dependencias, copia cifrada portátil con contraseña, calendario de movimientos, "favoritos de un toque" con deshacer. **Quedan para la v1.1:** importación de CSV/OFX de los bancos, widgets de pantalla de inicio, Wear OS/watchOS, metas de ahorro con fecha, informes PDF, reglas automáticas de categorización por comercio (hoy son sugerencias por descripción), modo pareja/familia por archivo compartido, y lectura de SMS (se descartó para la v1 por las políticas de Google Play; las notificaciones cubren lo mismo sin ese permiso).

## Datos y seguridad

- **Libro completo en un JSON cifrado en vez de SQLite/SQLCipher.** El estudio sugería Drift con SQLCipher. Se eligió un modelo en memoria (cuentas, categorías, movimientos, programados, presupuestos, plantillas, avisos, tasas) que se serializa a un archivo cifrado con **ChaCha20-Poly1305** (paquete `cryptography`, puro Dart, probado en la CI). Razones: un hogar genera unos pocos miles de movimientos al año, que caben de sobra en memoria y se consultan en microsegundos; no hay generación de código ni librerías nativas de cifrado por plataforma; las pruebas corren sin dispositivo; y el respaldo es un solo archivo. El guardado es diferido (400 ms) y atómico (archivo temporal + renombrado), con `flush` al pasar a segundo plano.
- **La llave vive en el Keystore de Android / Llavero de iOS** (`flutter_secure_storage`, accesible tras el primer desbloqueo y sin copia a otros dispositivos). Si el llavero falla (ROM rara), hay un respaldo en archivo privado para que la app no quede inutilizable.
- **Clave de acceso con PBKDF2-HMAC-SHA256 (60 000 iteraciones) y sal**, nunca en claro; tras 3 fallos la espera empieza en 30 s y se duplica. La biometría usa la pantalla del sistema (`local_auth`) y la clave sigue siendo el respaldo. Se guarda el largo de la clave para enviarla sola al completarla.
- **Copia portátil cifrada con contraseña** (PBKDF2 120 000 iteraciones + la misma caja ChaCha20-Poly1305, cabecera `PLATA-BK1` + sal), además del JSON abierto para migrar. Las copias automáticas locales (7 días) usan la llave del dispositivo y se pierden al desinstalar: el texto de la pantalla lo dice.
- **Montos en enteros de centavos** (`int`), nunca en `double`; el formato colombiano (punto de miles, coma decimal, sin centavos en pesos) y el extranjero se reconocen al escribir o pegar. Las conversiones entre monedas guardan la tasa usada en cada movimiento para que los informes históricos no cambien cuando cambia la TRM.

## Tarjetas, periodos y programados

- **Estado de cuenta como lo factura el banco.** Compras y cuotas por fecha dentro del ciclo (corte anterior, corte]; la cuota k de una compra diferida cae en el ciclo k-ésimo después del de la compra; los abonos se aplican a la ventana entre fechas de pago consecutivas, que es como los bancos los acreditan. El "próximo pago" que se muestra en Inicio es el del ciclo ya cerrado mientras su fecha de pago no haya pasado; después, el del ciclo en curso. El recordatorio de pago usa la misma regla.
- **Quincena real colombiana:** el 15 y el último día del mes (no "cada 14 días"), tanto como frecuencia de programados como periodo de la app (1–15 y 16–fin). El mes también puede empezar el día de pago (1–28).
- **Programados manuales no se saltan solos:** quedan vencidos hasta que el usuario los anota o los salta; los automáticos se anotan al abrir la app con la fecha que tocaba (al mediodía, para no caer en el día anterior por zona horaria). Las series mensuales conservan el día ancla en meses cortos (31 → 28 → 31).
- **Presupuestos con arrastre opcional** (sobrante o déficit pasa al siguiente periodo) y reembolsos: un ingreso anotado en una categoría de gasto descuenta del presupuesto de esa categoría.

## Avisos bancarios

- **Lector propio de notificaciones en Kotlin en vez del plugin sugerido.** `notification_listener_service` no se mantiene y no permite filtrar por paquete ni funcionar con la app cerrada. El servicio propio (`BankNoticeListener`) solo mira una lista fija de paquetes de bancos y billeteras, guarda título y texto en un archivo privado (tope 300 KB) y, si la app está abierta, los envía en vivo por un `EventChannel`. Al abrir la app se procesan los pendientes.
- **Las reglas de lectura son texto plano** (`BankRules`): monto con `$`/COP/USD o "por valor de", comercio tras "en/a/de", últimos 4 dígitos, ingreso o gasto por la primera palabra clave, descarte duro de rechazos, códigos y claves dinámicas y descarte blando de publicidad. Se validaron con 17 mensajes reales de los bancos más usados. Lo que no se entiende no se anota: va a una bandeja para revisar, y el anotado automático es opcional y solo cuando el banco o los últimos 4 dígitos coinciden con una cuenta.
- **Sin SMS.** Google Play restringe `READ_SMS` a apps cuya función principal sea la mensajería; la lectura de notificaciones logra lo mismo con un permiso que el usuario activa a conciencia y puede revocar. En iOS la función no existe y la pantalla lo explica.

## Interfaz

- **Cinco pestañas (Inicio, Movimientos, Presupuestos, Informes, Más) y el botón + siempre a mano**, con el teclado calculadora abierto al entrar porque el 90 % de los usos es anotar un monto. Las sugerencias por descripción rellenan categoría y monto del último movimiento igual.
- **Gráficas propias** (dona, barras, línea) con `CustomPainter`: pesan nada, se prueban en la CI y evitan una dependencia grande para tres dibujos.
- **Excel propio.** El XLSX se escribe como OOXML mínimo (cadenas en línea, números con formato, dos hojas) con el paquete `archive`; no hacía falta una librería de hojas de cálculo. El CSV lleva BOM para que Excel abra las tildes.
- **Recordatorios con alarmas inexactas** (`inexactAllowWhileIdle`) para no pedir el permiso de alarmas exactas de Android 14; unos minutos de diferencia no importan en un recordatorio de pago. La zona horaria se fija por el desfase actual del dispositivo, suficiente para Colombia (sin horario de verano).
- **Textos en español neutro con vocabulario colombiano** (plata, bolsillo, quincena, corrientazo en los ejemplos) y traducción al inglés completa.
