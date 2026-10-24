# Plata

Finanzas personales gratuitas, sin anuncios, sin cuenta y sin servidor: anota gastos e ingresos en cinco segundos, maneja cuentas, bolsillos, tarjetas de crédito con corte y fecha de pago, presupuestos, programados y quincenas, con todo cifrado en el teléfono. Pensada para Colombia (TRM, Nequi, Daviplata, quincenas, 4×1000, cuotas) y usable en cualquier país.

## Qué trae la v1

| Bloque | Funciones |
|---|---|
| Anotar | Botón + con teclado calculadora (suma, resta, multiplica y divide al escribir) · categoría y subcategoría · cuenta por defecto (la última usada) · fecha y hora · descripción con sugerencias de lo que ya anotaste (rellena categoría y monto) · beneficiario, etiquetas, notas, número de cheque · foto del recibo · división en varias categorías · cuotas en tarjeta de crédito · conciliado · duplicar · guardar como plantilla |
| Favoritos de un toque | Plantillas con monto, cuenta y categoría que se anotan desde Inicio con un toque y se deshacen con otro |
| Cuentas | Efectivo, cuenta bancaria, tarjeta débito (enlazada a su cuenta), tarjeta de crédito (corte, pago y cupo), billetera digital (Nequi, Daviplata…), bolsillos dentro de una cuenta, ahorros, préstamo, inversión · saldo inicial (en tarjetas y préstamos, la deuda) · archivar (pausa sus programados) · ajuste al saldo real, que no cuenta como gasto ni ingreso · cuentas en otras monedas |
| Tarjetas | Estado de cuenta **estimado** por ciclo: saldo anterior sin pagar, compras, avances (también a cuotas), cuotas (la primera en el primer corte después de la compra) y abonos aplicados · próximo pago y fecha límite (corrida al siguiente día hábil si cae en sábado, domingo o festivo, y un pago hasta ese día cuenta para ese extracto) · al anotar un pago mínimo, «¿Ya lo pagaste?»: «Ya lo pagué» marca el extracto como pagado (se deshace con «Deshacer» o «Desmarcar», y el pago que registres después lo reemplaza, sin contarlo dos veces) · «vencido» solo contra el pago mínimo que anotas del extracto; si no, lo que falta según lo anotado se informa sin hablar de mora · cupo disponible · compras a cuotas con lo que falta · pago como transferencia desde una cuenta en la moneda de la tarjeta. Es capital estimado, sin intereses ni cuota de manejo: el valor exacto es el del extracto del banco |
| Transferencias | Entre cuentas, pagos de tarjeta y abonos a préstamos sin contar como gasto · entre monedas, con el monto recibido calculado con la tasa guardada o escrito a mano (sin tasa no se anota y se explica qué falta); igual en programados y favoritos |
| Periodo | Mes calendario, mes que empieza el día de pago, o **quincenas** (1–15 y 16–fin); Inicio e Informes usan ese periodo |
| Programados | Arriendo, servicios, salario, cuotas: diario, semanal, mensual, anual o quincenal (15 y último día), con fin opcional · se anotan solos o quedan pendientes para confirmar · recordatorio días antes · anotar ahora / saltar |
| Presupuestos | Por una o varias categorías (o todo el gasto), por cuenta o tarjeta, semanal, quincenal, mensual, anual o por días · arrastre del sobrante · barra de avance, disponible por día y acceso a los movimientos |
| Avisos bancarios (Android) | Lee las notificaciones de Mi Bancolombia, Nequi, Daviplata, Davivienda, BBVA, Banco de Bogotá, Banco de Occidente, DAVIbank (antes Scotiabank Colpatria), Lulo Bank, Nu y MOVii (paquetes comprobados en Google Play, ver `docs/DECISIONES.md`); saca monto, moneda, comercio y últimos 4 dígitos y los deja como sugerencia. Pagos de tarjeta, retiros y movimientos entre cuentas propias se sugieren como transferencias. "Anotar sin preguntar" solo anota gastos e ingresos cuya cuenta se reconoce sin dudas. Lo que llega con la app cerrada espera cifrado; al apagar la lectura, el servicio deja de leer y lo pendiente se borra. Nada sale del teléfono; se activa con el permiso "Acceso a notificaciones" |
| Informes | Dona por categoría con detalle de subcategorías y movimientos · tendencia de ingresos y gastos y neto por periodo · tasa de ahorro · presupuestos · entradas y salidas por cuenta · filtro por cuenta · navegación por periodos |
| Movimientos | Lista por día con neto, búsqueda por texto o monto, filtros (tipo, cuentas, categorías, fechas y periodos rápidos, montos, etiquetas, adjuntos, sin categoría, sin conciliar) y calendario mensual con el neto de cada día |
| Monedas | Moneda base y monedas extra · TRM oficial (datos.gov.co), Banco Central Europeo (vía Frankfurter) y ExchangeRate-API para las que el BCE no publica, una vez al día si hay internet, con la fuente de cada tasa y la atribución que pide ExchangeRate-API · tasa manual con todos sus decimales · conversión en totales, informes, presupuestos y compromisos · cambio de moneda base que convierte tasas, movimientos y presupuestos |
| Seguridad | Datos cifrados con ChaCha20-Poly1305 y llave en el Keystore/Llavero (con reintentos; nunca una llave nueva sobre datos existentes) · escritura atómica y modo de recuperación si los datos no abren · clave de acceso (hash PBKDF2, espera creciente tras 3 fallos que sobrevive al cierre) · huella o rostro (sin el PIN del teléfono) · bloqueo al salir · con clave, sin capturas en Android y cubierta en el selector de apps · lo de atrás del candado no se lee ni se toca · "¿Olvidaste la clave?" borra todo y deja empezar de nuevo · en iOS, la primera apertura tras instalar limpia el Llavero · ocultar saldos |
| Copias | Copia automática diaria (últimas 7) y una copia antes de cada restauración, que no pisa ninguna otra (últimas 5) · exportar copia cifrada con contraseña (.plata, oculta, mínimo 8 caracteres y confirmada) o JSON · restaurar desde archivo, validada antes de reemplazar · CSV (protegido contra fórmulas) y Excel (XLSX) del periodo o de todo |
| Recordatorios | Aviso diario para anotar · aviso antes de las próximas 3 ocurrencias de cada programado (hasta 120 días) y de las próximas 3 fechas límite de cada tarjeta con deuda, sin pasar de 60 agendados (iOS guarda solo los 64 más próximos) · un programado manual vencido se recuerda 3 días · se reprograman solos con cada cambio y al abrir la app |

Interfaz en español e inglés (arranca en el idioma del teléfono), tema claro y oscuro, gráficas descritas para TalkBack y VoiceOver y pantallas probadas con texto grande. La única conexión que hace la app es la descarga de tasas de cambio, y se puede apagar.

## Cuidados

- Las sugerencias de los avisos bancarios no son prueba de nada: se revisan y se confirman. iOS no permite leer notificaciones de otras apps, así que allí no existe esa función.
- El estado de cuenta de las tarjetas es capital estimado: no incluye intereses, cuota de manejo ni seguros. El valor exacto a pagar es el del extracto del banco.
- Sin copias de seguridad, al perder o cambiar de teléfono se pierden los datos: la app no tiene nube. Exporta una copia cifrada con contraseña y guárdala donde quieras.
- No es asesoría financiera: muestra tus números, no decide por ti.

## Desarrollo

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

- Código: Apache-2.0. Sin paquetes GPL.
- Código nativo propio en `native/`: en Android la actividad (canales de avisos y de privacidad, `FLAG_SECURE`), el lector de avisos, los temas AppCompat de la actividad (`styles.xml` y `styles-night.xml`, que exige la huella de local_auth) y el ícono de las notificaciones (`ic_stat_plata.xml`, con `keep.xml`); en iOS el `AppDelegate` (carpeta fuera de iCloud, canal de privacidad y cubierta del selector de apps). `tools/patch_platforms.py` los copia a `android/` e `ios/` al generar las plataformas.
- Pruebas: `test/money_test.dart`, `test/ledger_test.dart`, `test/storage_test.dart`, `test/notices_test.dart`, `test/reminders_test.dart`, `test/ui_test.dart` (cada una nombra los hallazgos de auditoría que cubre), además de `core_test`, `app_test`, `legal_document_test` y las capturas de tienda (`--tags screenshots`).
- Ícono generado con `tools/gen_plata_assets.py`.
- Decisiones de diseño: `docs/DECISIONES.md`.
