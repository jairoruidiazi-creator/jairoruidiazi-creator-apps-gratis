import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_scope.dart';
import '../widgets/adaptive.dart';

/// Guía de uso y acerca de.
class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  static const String version = '1.0.0';
  static const String repo = 'https://github.com/jairoruidiazi-creator/jairoruidiazi-creator-apps-gratis';

  @override
  Widget build(BuildContext context) {
    final bool es = AppScope.of(context).settings.spanish;
    final List<_Section> sections = es ? _es : _en;
    return ReadableScaffold(
      appBar: AppBar(title: Text(t(context, 'Guía', 'Guide'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          for (final _Section sec in sections)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 12),
              leading: Icon(sec.icon),
              title: Text(sec.title, style: const TextStyle(fontWeight: FontWeight.w600)),
              children: <Widget>[Align(alignment: Alignment.centerLeft, child: Text(sec.body))],
            ),
          const Divider(height: 32),
          Text(t(context, 'Acerca de Plata', 'About Plata'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(t(
            context,
            'Versión $version. Gratis, sin anuncios, sin cuenta y sin servidores: tus datos viven cifrados solo en tu teléfono. La única conexión que hace la app es descargar la tasa de cambio (TRM de datos.gov.co y Banco Central Europeo), y puedes apagarla.',
            'Version $version. Free, no ads, no account and no servers: your data lives encrypted only on your phone. The only connection the app makes is to download exchange rates (TRM from datos.gov.co and the European Central Bank), and you can turn it off.',
          )),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: <Widget>[
              OutlinedButton.icon(onPressed: () => launchUrl(Uri.parse(repo), mode: LaunchMode.externalApplication), icon: const Icon(Icons.code), label: Text(t(context, 'Código fuente', 'Source code'))),
              OutlinedButton.icon(onPressed: () => launchUrl(Uri.parse('$repo/issues'), mode: LaunchMode.externalApplication), icon: const Icon(Icons.bug_report_outlined), label: Text(t(context, 'Reportar un problema', 'Report a problem'))),
            ],
          ),
        ],
      ),
    );
  }
}

class _Section {
  const _Section(this.icon, this.title, this.body);

  final IconData icon;
  final String title;
  final String body;
}

const List<_Section> _es = <_Section>[
  _Section(Icons.add_circle_outline, 'Anotar un gasto en 5 segundos', 'Toca el botón + : escribe el monto (la calculadora suma y resta, útil para dividir cuentas), elige categoría y listo. La cuenta por defecto es la última que usaste. Si algo se repite (bus, tinto, almuerzo), guárdalo como plantilla desde el menú ⋮ del editor y anótalo con un toque desde Inicio.'),
  _Section(Icons.account_balance_wallet_outlined, 'Cuentas, bolsillos y tarjetas', 'Crea una cuenta por cada sitio donde tengas plata: efectivo, cuenta de ahorros, Nequi, Daviplata, tarjeta de crédito, préstamo, CDT. Los bolsillos cuelgan de una cuenta madre y se suman a ella. Una tarjeta débito se enlaza a su cuenta: lo que pagues con ella se descuenta de la cuenta. En las tarjetas de crédito pon el día de corte y el de pago para ver el estado de cuenta, las cuotas y cuánto pagar.'),
  _Section(Icons.swap_horiz, 'Transferencias y pagos de tarjeta', 'Mover plata entre cuentas (retiro, pasar a Nequi, pagar la tarjeta, abonar al préstamo) es una transferencia: no es gasto ni ingreso. Si las cuentas tienen monedas distintas puedes escribir el monto que llegó.'),
  _Section(Icons.calendar_month_outlined, 'Quincenas y periodo', 'En Ajustes eliges si tu mes empieza el día 1, el día de pago o si manejas quincenas (1–15 y 16–fin). Inicio e Informes usan ese periodo. Los programados pueden repetirse "quincenal", que cae el 15 y el último día de cada mes.'),
  _Section(Icons.event_repeat, 'Programados', 'Arriendo, administración, servicios, salario, cuotas: se anotan solos el día que toca (o quedan pendientes si prefieres confirmarlos) y te avisan antes con una notificación.'),
  _Section(Icons.savings_outlined, 'Presupuestos', 'Ponle un tope a una o varias categorías, a todo el gasto, o a una tarjeta. Puedes arrastrar el sobrante al periodo siguiente. Inicio muestra los tres más ajustados.'),
  _Section(Icons.notifications_active_outlined, 'Avisos bancarios (Android)', 'Si lo activas, Plata lee las notificaciones de las apps de bancos (Bancolombia, Nequi, Daviplata, Davivienda, BBVA…) y te sugiere el movimiento con monto y comercio. Nada sale del teléfono. Tú confirmas o descartas; también puedes dejar que se anoten solos cuando el banco o los últimos 4 dígitos coinciden con una cuenta.'),
  _Section(Icons.bar_chart_outlined, 'Informes y exportar', 'Informes muestra la dona por categoría (toca una para ver subcategorías y movimientos), la tendencia de los últimos periodos, presupuestos y el flujo por cuenta. Exporta CSV o Excel desde el icono de compartir.'),
  _Section(Icons.lock_outline, 'Seguridad y copias', 'Pon una clave (y huella) en Seguridad. Todo se guarda cifrado en el teléfono. Haz copias cifradas con contraseña desde Copias de seguridad y guárdalas en tu Drive o correo: sin ellas, al perder o cambiar de teléfono se pierden los datos.'),
  _Section(Icons.search, 'Buscar y filtrar', 'En Movimientos busca por texto o monto y filtra por cuenta, categoría, fechas, montos, etiquetas o adjuntos. El calendario muestra el neto de cada día.'),
];

const List<_Section> _en = <_Section>[
  _Section(Icons.add_circle_outline, 'Log an expense in 5 seconds', 'Tap + : type the amount (the calculator adds and subtracts, handy for splitting bills), pick a category and done. The default account is the last one you used. If something repeats, save it as a template from the editor ⋮ menu and log it with one tap from Home.'),
  _Section(Icons.account_balance_wallet_outlined, 'Accounts, pockets and cards', 'Create an account for every place you keep money: cash, savings, wallets, credit card, loan, investments. Pockets hang from a parent account and add to it. A debit card links to its account: what you pay with it is taken from the account. For credit cards set the statement and payment days to see the statement, installments and what to pay.'),
  _Section(Icons.swap_horiz, 'Transfers and card payments', 'Moving money between accounts (withdrawals, paying the card, paying down a loan) is a transfer: neither expense nor income. If the accounts use different currencies you can type the amount that arrived.'),
  _Section(Icons.calendar_month_outlined, 'Fortnights and period', 'In Settings choose whether your month starts on the 1st, on payday, or whether you run fortnights (1–15 and 16–end). Home and Reports use that period. Scheduled items can repeat "twice a month", on the 15th and the last day.'),
  _Section(Icons.event_repeat, 'Scheduled', 'Rent, utilities, salary, installments: they are logged automatically when due (or wait for confirmation if you prefer) and remind you beforehand with a notification.'),
  _Section(Icons.savings_outlined, 'Budgets', 'Cap one or more categories, all spending, or one card. Leftovers can roll over to the next period. Home shows the three tightest.'),
  _Section(Icons.notifications_active_outlined, 'Bank notices (Android)', 'If enabled, Plata reads notifications from bank apps and suggests the transaction with amount and merchant. Nothing leaves the phone. You confirm or dismiss; you can also let them be logged automatically when the bank or last 4 digits match an account.'),
  _Section(Icons.bar_chart_outlined, 'Reports and export', 'Reports shows the category donut (tap one for subcategories and transactions), the trend over recent periods, budgets and cash flow per account. Export CSV or Excel from the share icon.'),
  _Section(Icons.lock_outline, 'Security and backups', 'Set a passcode (and biometrics) under Security. Everything is stored encrypted on the phone. Make password-protected backups from Backups and keep them in your Drive or email: without them, losing or changing phones loses the data.'),
  _Section(Icons.search, 'Search and filter', 'In Transactions search by text or amount and filter by account, category, dates, amounts, tags or attachments. The calendar shows each day net.'),
];
