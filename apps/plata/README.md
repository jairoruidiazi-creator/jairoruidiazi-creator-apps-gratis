# Plata

Finanzas personales gratuitas, sin anuncios, sin cuenta y sin servidor: anota gastos e ingresos en cinco segundos, maneja cuentas, bolsillos, tarjetas de crédito con corte y fecha de pago, presupuestos, programados y quincenas, con todo cifrado en el teléfono. Pensada para Colombia (TRM, Nequi, Daviplata, quincenas, 4×1000, cuotas) y usable en cualquier país.

## Qué trae la v1

| Bloque | Funciones |
|---|---|
| Anotar | Botón + con teclado calculadora (suma, resta, multiplica y divide al escribir) · categoría y subcategoría · cuenta por defecto (la última usada) · fecha y hora · descripción con sugerencias de lo que ya anotaste (rellena categoría y monto) · beneficiario, etiquetas, notas, número de cheque · foto del recibo · división en varias categorías · cuotas en tarjeta de crédito · conciliado · duplicar · guardar como plantilla |
| Favoritos de un toque | Plantillas con monto, cuenta y categoría que se anotan desde Inicio con un toque y se deshacen con otro |
| Cuentas | Efectivo, cuenta bancaria, tarjeta débito (enlazada a su cuenta), tarjeta de crédito (corte, pago y cupo), billetera digital (Nequi, Daviplata…), bolsillos dentro de una cuenta, ahorros, préstamo, inversión · saldo inicial · archivar · ajuste al saldo real · cuentas en otras monedas |
| Tarjetas | Estado de cuenta por ciclo (compras, cuotas facturadas, abonos aplicados), próximo pago y fecha límite, cupo disponible, compras a cuotas con las que faltan, registro del pago como transferencia |
| Transferencias | Entre cuentas, entre monedas (monto recibido), pagos de tarjeta y abonos a préstamos sin contar como gasto |
| Periodo | Mes calendario, mes que empieza el día de pago, o **quincenas** (1–15 y 16–fin); Inicio e Informes usan ese periodo |
| Programados | Arriendo, servicios, salario, cuotas: diario, semanal, mensual, anual o quincenal (15 y último día), con fin opcional · se anotan solos o quedan pendientes para confirmar · recordatorio días antes · anotar ahora / saltar |
| Presupuestos | Por una o varias categorías (o todo el gasto), por cuenta o tarjeta, semanal, quincenal, mensual, anual o por días · arrastre del sobrante · barra de avance, disponible por día y acceso a los movimientos |
| Avisos bancarios (Android) | Lee las notificaciones de Bancolombia, Nequi, Daviplata, Davivienda, BBVA, Banco de Bogotá, Occidente, Colpatria, Lulo, RappiPay, Nu, Ualá y Movii; saca monto, comercio y últimos 4 dígitos y los deja como sugerencia (o los anota solos si coinciden con una cuenta). Nada sale del teléfono; se activa con el permiso "Acceso a notificaciones" |
| Informes | Dona por categoría con detalle de subcategorías y movimientos · tendencia de ingresos y gastos y neto por periodo · tasa de ahorro · presupuestos · entradas y salidas por cuenta · filtro por cuenta · navegación por periodos |
| Movimientos | Lista por día con neto, búsqueda por texto o monto, filtros (tipo, cuentas, categorías, fechas y periodos rápidos, montos, etiquetas, adjuntos, sin categoría, sin conciliar) y calendario mensual con el neto de cada día |
| Monedas | Moneda base y monedas extra · TRM oficial (datos.gov.co) y cruces del Banco Central Europeo, una vez al día si hay internet, o tasa manual · conversión en totales, informes y presupuestos |
| Seguridad | Datos cifrados con ChaCha20-Poly1305 y llave en el Keystore/Llavero · clave de acceso (hash PBKDF2, espera creciente tras 3 fallos) · huella o rostro · bloqueo al salir · ocultar saldos |
| Copias | Copia automática diaria (últimas 7) · exportar copia cifrada con contraseña (.plata) o JSON · restaurar desde archivo · CSV y Excel (XLSX) del periodo o de todo |
| Recordatorios | Aviso diario para anotar · aviso antes de cada programado y de la fecha límite de pago de cada tarjeta |

Interfaz en español e inglés, tema claro y oscuro. La única conexión que hace la app es la descarga de tasas de cambio, y se puede apagar.

## Cuidados

- Las sugerencias de los avisos bancarios no son prueba de nada: se revisan y se confirman. iOS no permite leer notificaciones de otras apps, así que allí no existe esa función.
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
- Código nativo propio en `native/android/` (actividad y lector de avisos); `tools/patch_platforms.py` lo copia a `android/` al generar las plataformas.
- Ícono generado con `tools/gen_plata_assets.py`.
- Decisiones de diseño: `docs/DECISIONES.md`.
