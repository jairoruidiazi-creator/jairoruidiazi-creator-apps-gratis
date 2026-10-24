import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/ledger.dart';
import '../../model/models.dart';
import '../../model/money.dart';
import 'amount_keypad.dart';
import 'icons.dart';

/// Formato de dinero con las preferencias del usuario (centavos, ocultar e
/// idioma).
String money(BuildContext context, int minor, String currency, {bool compact = false, bool withSymbol = true}) {
  final Services s = AppScope.of(context);
  if (s.settings.hideBalances) {
    return '${Money.info(currency).symbol} ••••';
  }
  return Money.format(minor, currency, showCents: s.settings.showCents, compact: compact, withSymbol: withSymbol, spanish: s.settings.spanish);
}

/// Color de gastos (rojo), ingresos (verde) y transferencias. En tema oscuro
/// se usan tonos claros: el rojo y el verde de siempre quedan por debajo de
/// 4,5:1 de contraste sobre fondos oscuros.
Color kindColor(BuildContext context, TxKind k) {
  final bool dark = Theme.of(context).brightness == Brightness.dark;
  switch (k) {
    case TxKind.expense:
      return dark ? const Color(0xFFEF9A9A) : const Color(0xFFC62828);
    case TxKind.income:
      return dark ? const Color(0xFF81C784) : const Color(0xFF2E7D32);
    case TxKind.transfer:
      return Theme.of(context).colorScheme.primary;
  }
}

/// Tarjetas y préstamos: su saldo es deuda.
bool isDebtAccount(Account a) => a.isCredit || a.type == AccountType.loan;

/// Saldo como se muestra: en tarjetas y préstamos, lo que se debe (positivo);
/// en el resto, el saldo. Una sola regla para Inicio y Cuentas.
int shownBalance(Account a, int balance) => isDebtAccount(a) ? -balance : balance;

/// Texto del saldo: una deuda se muestra en positivo, sin signo, y un saldo a
/// favor en una tarjeta o un préstamo también, pero en verde (ver
/// [balanceColor]) y con «a favor» en la línea de abajo.
String balanceText(BuildContext context, Account a, int balance) {
  final int v = shownBalance(a, balance);
  return money(context, isDebtAccount(a) ? v.abs() : v, a.currency);
}

/// Color del saldo: rojo si una cuenta está en negativo, verde si una deuda
/// quedó con saldo a favor; si no, el normal.
Color? balanceColor(BuildContext context, Account a, int balance) {
  final int v = shownBalance(a, balance);
  if (isDebtAccount(a)) {
    return v < 0 ? kindColor(context, TxKind.income) : null;
  }
  return v < 0 ? kindColor(context, TxKind.expense) : null;
}

/// Fecha corta en el formato del idioma: «lun 07 dic 2026» / «Mon Dec 07
/// 2026» (el día de la semana y el año, si se piden). Un solo formato por
/// idioma en toda la pantalla de tarjetas.
String dayText(BuildContext context, DateTime d, {bool weekday = false, bool year = false}) {
  final bool es = AppScope.of(context).settings.spanish;
  final String base = es ? 'dd MMM' : 'MMM dd';
  final String pattern = '${weekday ? 'EEE ' : ''}$base${year ? ' yyyy' : ''}';
  return formatDate(d, pattern, spanish: es);
}

/// Fecha límite de un pago de tarjeta: la real y, si se corrió porque la
/// nominal no es hábil, cuál era: «lun 07 dic (el sáb 05 no es hábil)».
String payDateText(BuildContext context, Ledger l, Account card, DateTime nominal, {bool year = false}) {
  final DateTime real = l.effectivePayDate(card, nominal);
  final String shown = dayText(context, real, weekday: true, year: year);
  if (real == dateOnly(nominal)) {
    return shown;
  }
  return '$shown ${t(context, '(el ${dayText(context, nominal, weekday: true)} no es hábil)', '(${dayText(context, nominal, weekday: true)} is not a business day)')}';
}

/// «Vencido desde el 05 oct» / «Overdue since Oct 05».
String overdueLabel(BuildContext context, DateTime since) {
  final bool es = AppScope.of(context).settings.spanish;
  return es ? 'Vencido desde el ${formatDate(since, 'dd MMM', spanish: true)}' : 'Overdue since ${formatDate(since, 'MMM dd', spanish: false)}';
}

/// Día del mes como se dice: «15» en español, «15th» en inglés.
String dayOfMonth(BuildContext context, int d) {
  if (AppScope.of(context).settings.spanish) {
    return '$d';
  }
  final int r100 = d % 100;
  final String suffix = r100 >= 11 && r100 <= 13 ? 'th' : (d % 10 == 1 ? 'st' : (d % 10 == 2 ? 'nd' : (d % 10 == 3 ? 'rd' : 'th')));
  return '$d$suffix';
}

/// Ámbar de "casi en el tope" con contraste suficiente en los dos temas.
Color warnColor(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? const Color(0xFFFFB74D) : const Color(0xFF9A5B00);

/// Explica por qué no se pudo guardar un movimiento.
String txProblemText(BuildContext context, TxRejected e) {
  switch (e.problem) {
    case TxProblem.amount:
      return t(context, 'Escribe un monto mayor que cero.', 'Enter an amount greater than zero.');
    case TxProblem.account:
      return t(context, 'Elige la cuenta.', 'Choose the account.');
    case TxProblem.destination:
      return t(context, 'Elige la cuenta de destino.', 'Choose the destination account.');
    case TxProblem.sameAccount:
      return t(context, 'El origen y el destino son la misma cuenta.', 'Source and destination are the same account.');
    case TxProblem.missingRate:
      final String c = e.currency ?? '';
      return t(context, 'No hay tasa de cambio para $c, así que no se puede calcular cuánto llega. Escribe el monto recibido o pon la tasa en Más › Monedas.', 'There is no exchange rate for $c, so the amount received cannot be worked out. Type the amount received or set the rate under More › Currencies.');
  }
}

String kindName(BuildContext context, TxKind k) {
  switch (k) {
    case TxKind.expense:
      return t(context, 'Gasto', 'Expense');
    case TxKind.income:
      return t(context, 'Ingreso', 'Income');
    case TxKind.transfer:
      return t(context, 'Transferencia', 'Transfer');
  }
}

String accountTypeName(BuildContext context, AccountType type) {
  switch (type) {
    case AccountType.cash:
      return t(context, 'Efectivo', 'Cash');
    case AccountType.bank:
      return t(context, 'Cuenta bancaria', 'Bank account');
    case AccountType.debit:
      return t(context, 'Tarjeta débito', 'Debit card');
    case AccountType.credit:
      return t(context, 'Tarjeta de crédito', 'Credit card');
    case AccountType.wallet:
      return t(context, 'Billetera digital', 'Digital wallet');
    case AccountType.pocket:
      return t(context, 'Bolsillo', 'Pocket');
    case AccountType.savings:
      return t(context, 'Ahorros', 'Savings');
    case AccountType.loan:
      return t(context, 'Préstamo', 'Loan');
    case AccountType.investment:
      return t(context, 'Inversión', 'Investment');
    case AccountType.other:
      return t(context, 'Otra', 'Other');
  }
}

/// Avatar redondo con icono y color.
class IconBadge extends StatelessWidget {
  const IconBadge({super.key, required this.icon, required this.color, this.size = 40});

  final String icon;
  final int color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final Color c = Color(color);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c.withValues(alpha: 0.18), shape: BoxShape.circle),
      child: Icon(AppIcons.of(icon), color: c, size: size * 0.55),
    );
  }
}

/// Hoja para elegir una cuenta.
Future<Account?> pickAccount(BuildContext context, {String? exclude, String? title, bool includeArchived = false, bool Function(Account a)? where}) {
  final Ledger l = AppScope.of(context).ledger;
  return showModalBottomSheet<Account>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext context) {
      final List<Account> list = (includeArchived ? l.accounts : l.activeAccounts).where((Account a) => a.id != exclude && (where == null || where(a))).toList();
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text(title ?? t(context, 'Cuenta', 'Account'), style: Theme.of(context).textTheme.titleMedium)),
            for (final Account a in list)
              ListTile(
                leading: IconBadge(icon: a.icon, color: a.color),
                title: Text(a.name),
                subtitle: Text('${accountTypeName(context, a.type)} · ${money(context, l.balanceMinor(a.id), a.currency)}'),
                onTap: () => Navigator.pop(context, a),
              ),
            if (list.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(t(context, 'No hay cuentas. Crea una en Más › Cuentas.', 'No accounts yet. Create one in More › Accounts.'))),
          ],
        ),
      );
    },
  );
}

/// Hoja para elegir una categoría (raíces y subcategorías).
Future<Category?> pickCategory(BuildContext context, CategoryKind kind, {String? current}) {
  final Ledger l = AppScope.of(context).ledger;
  return showModalBottomSheet<Category>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext context) {
      final List<Category> roots = l.roots(kind);
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (BuildContext context, ScrollController sc) => ListView(
          controller: sc,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          children: <Widget>[
            Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 8), child: Text(kind == CategoryKind.expense ? t(context, 'Categoría del gasto', 'Expense category') : t(context, 'Categoría del ingreso', 'Income category'), style: Theme.of(context).textTheme.titleMedium)),
            for (final Category r in roots) ...<Widget>[
              _CategoryRow(category: r, selected: current == r.id, onTap: () => Navigator.pop(context, r)),
              if (l.children(r.id).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 44, bottom: 6),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: <Widget>[
                      for (final Category c in l.children(r.id))
                        ChoiceChip(
                          avatar: Icon(AppIcons.of(c.icon), size: 16, color: Color(c.color)),
                          label: Text(c.name),
                          selected: current == c.id,
                          onSelected: (_) => Navigator.pop(context, c),
                        ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      );
    },
  );
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.category, required this.selected, required this.onTap});

  final Category category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: IconBadge(icon: category.icon, color: category.color, size: 34),
      title: Text(category.name, style: TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
      trailing: selected ? const Icon(Icons.check) : null,
      onTap: onTap,
    );
  }
}

/// Selector de icono y color para cuentas, categorías y plantillas.
class IconColorPicker extends StatelessWidget {
  const IconColorPicker({super.key, required this.icon, required this.color, required this.onIcon, required this.onColor});

  final String icon;
  final int color;
  final ValueChanged<String> onIcon;
  final ValueChanged<int> onColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 2,
          runSpacing: 2,
          children: <Widget>[
            for (int i = 0; i < AppIcons.palette.length; i++)
              Semantics(
                button: true,
                selected: color == AppIcons.palette[i],
                label: 'Color ${AppIcons.colorNames[i][AppScope.of(context).settings.spanish ? 0 : 1]}',
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => onColor(AppIcons.palette[i]),
                  // Área de toque de 44 × 44 alrededor de la muestra de 30.
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(color: Color(AppIcons.palette[i]), shape: BoxShape.circle, border: Border.all(color: color == AppIcons.palette[i] ? Theme.of(context).colorScheme.onSurface : Colors.transparent, width: 3)),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        // Celdas de al menos 48 dp, como pide la guía de accesibilidad.
        SizedBox(
          height: 176,
          child: GridView.extent(
            maxCrossAxisExtent: 56,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            children: <Widget>[
              for (final MapEntry<String, IconData> e in AppIcons.all.entries)
                Semantics(
                  button: true,
                  selected: icon == e.key,
                  label: '${t(context, 'Ícono', 'Icon')} ${AppIcons.nameOf(e.key, spanish: AppScope.of(context).settings.spanish)}',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => onIcon(e.key),
                    child: Container(
                      decoration: BoxDecoration(color: icon == e.key ? Color(color).withValues(alpha: 0.2) : null, borderRadius: BorderRadius.circular(8)),
                      child: Icon(e.value, size: 22, color: icon == e.key ? Color(color) : null),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Diálogo de una línea de texto.
Future<String?> askText(BuildContext context, String title, {String? initial, String? hint, TextInputType? keyboard}) async {
  final TextEditingController ctrl = TextEditingController(text: initial ?? '');
  final String? v = await showDialog<String>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(title),
      content: TextField(controller: ctrl, autofocus: true, keyboardType: keyboard, decoration: InputDecoration(hintText: hint), textCapitalization: TextCapitalization.sentences, onSubmitted: (String s) => Navigator.pop(context, s)),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t(context, 'Cancelar', 'Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(context, ctrl.text), child: Text(t(context, 'Aceptar', 'OK'))),
      ],
    ),
  );
  disposeLater(<ChangeNotifier>[ctrl]);
  return v;
}

/// Pide una contraseña sin mostrarla, sin autocorrección ni sugerencias (el
/// teclado no la aprende) y, con [repeat], escrita dos veces.
Future<String?> askSecret(BuildContext context, String title, {String? help, bool repeat = false, int minLength = 0}) async {
  final TextEditingController first = TextEditingController();
  final TextEditingController second = TextEditingController();
  bool show = false;
  String? error;
  final String? v = await showDialog<String>(
    context: context,
    builder: (BuildContext context) => StatefulBuilder(
      builder: (BuildContext context, StateSetter setState) {
        void submit() {
          if (first.text.length < minLength) {
            setState(() => error = t(context, 'Usa al menos $minLength caracteres.', 'Use at least $minLength characters.'));
            return;
          }
          if (repeat && first.text != second.text) {
            setState(() => error = t(context, 'Las contraseñas no coinciden.', 'The passwords do not match.'));
            return;
          }
          Navigator.pop(context, first.text);
        }

        Widget field(TextEditingController c, String label, {bool autofocus = false, bool last = false}) => TextField(
              controller: c,
              autofocus: autofocus,
              obscureText: !show,
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              keyboardType: TextInputType.visiblePassword,
              textCapitalization: TextCapitalization.none,
              textInputAction: last ? TextInputAction.done : TextInputAction.next,
              decoration: InputDecoration(
                labelText: label,
                suffixIcon: IconButton(
                  tooltip: show ? t(context, 'Ocultar', 'Hide') : t(context, 'Mostrar', 'Show'),
                  icon: Icon(show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  onPressed: () => setState(() => show = !show),
                ),
              ),
              onSubmitted: last ? (_) => submit() : null,
            );

        return AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (help != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(help)),
                field(first, t(context, 'Contraseña', 'Password'), autofocus: true, last: !repeat),
                if (repeat) ...<Widget>[const SizedBox(height: 8), field(second, t(context, 'Repite la contraseña', 'Repeat the password'), last: true)],
                if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(context), child: Text(t(context, 'Cancelar', 'Cancel'))),
            FilledButton(onPressed: submit, child: Text(t(context, 'Aceptar', 'OK'))),
          ],
        );
      },
    ),
  );
  disposeLater(<ChangeNotifier>[first, second]);
  return v;
}

Future<bool> confirm(BuildContext context, String title, String body, {String? yes, String? no, bool barrierDismissible = true}) async {
  final bool? ok = await showDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (BuildContext context) => PopScope(
      // Sin cierre por fuera, tampoco con el botón Atrás: hay que contestar.
      canPop: barrierDismissible,
      child: AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(no ?? t(context, 'Cancelar', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(yes ?? t(context, 'Aceptar', 'OK'))),
        ],
      ),
    ),
  );
  return ok ?? false;
}

/// Pide el permiso de notificaciones en el momento en que hace falta (un
/// programado con aviso, una tarjeta con día de pago, un recordatorio que se
/// enciende), con una línea que dice para qué. Si ya está concedido no
/// pregunta nada. Fuera de Ajustes ([force] falso) se pregunta una sola vez:
/// después solo se recuerda, con un botón, que están apagadas. Devuelve si
/// quedó concedido.
Future<bool> ensureNotifications(BuildContext context, {required String why, bool force = false}) async {
  final Services s = AppScope.of(context);
  // Desde Flutter 3.38 un aviso con acción no se cierra solo; aquí se cierra a
  // los 8 s, salvo con lector de pantalla, donde se queda hasta que se atienda.
  final bool keep = MediaQuery.accessibleNavigationOf(context);
  final bool? status = await s.notifier.permissionStatus();
  s.settings.setNotificationsAllowed(status);
  if (status == true) {
    return true;
  }
  if (!context.mounted) {
    return false;
  }
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final SnackBar off = SnackBar(
    content: Text(t(context, 'Las notificaciones están apagadas: los recordatorios no aparecerán. Puedes activarlas en Más › Ajustes.', 'Notifications are off: reminders will not show. You can turn them on under More › Settings.')),
    action: SnackBarAction(label: t(context, 'Activar', 'Turn on'), onPressed: () => s.notifier.openSettings()),
    duration: const Duration(seconds: 8),
    persist: keep,
  );
  if (s.settings.notificationsAsked && !force) {
    messenger.showSnackBar(off);
    return false;
  }
  s.settings.notificationsAsked = true;
  await s.settings.save();
  if (!context.mounted) {
    return false;
  }
  final bool ok = await confirm(context, t(context, 'Activar las notificaciones', 'Turn on notifications'), why, yes: t(context, 'Permitir', 'Allow'));
  if (!ok) {
    messenger.showSnackBar(off);
    return false;
  }
  final bool granted = await s.notifier.requestPermission();
  s.settings.setNotificationsAllowed(granted);
  if (!granted) {
    messenger.showSnackBar(off);
  }
  return granted;
}

/// Campo de monto que abre el teclado calculadora.
class AmountTile extends StatelessWidget {
  const AmountTile({super.key, required this.minor, required this.currency, required this.onTap, this.color, this.label});

  final int minor;
  final String currency;
  final VoidCallback onTap;
  final Color? color;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label ?? t(context, 'Monto', 'Amount'), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            Text(Money.format(minor, currency, showCents: AppScope.of(context).settings.showCents, spanish: AppScope.of(context).settings.spanish), style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: color ?? cs.onSurface, fontFeatures: const <FontFeature>[FontFeature.tabularFigures()])),
          ],
        ),
      ),
    );
  }
}

/// Hoja con la calculadora para pedir un monto. Devuelve centavos o null.
Future<int?> pickAmount(BuildContext context, {int initialMinor = 0, String currency = 'COP', String? title}) {
  return showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext context) => _AmountSheet(initialMinor: initialMinor, currency: currency, title: title),
  );
}

class _AmountSheet extends StatefulWidget {
  const _AmountSheet({required this.initialMinor, required this.currency, this.title});

  final int initialMinor;
  final String currency;
  final String? title;

  @override
  State<_AmountSheet> createState() => _AmountSheetState();
}

class _AmountSheetState extends State<_AmountSheet> {
  late final Calc _calc = Calc(initialMinor: widget.initialMinor);

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool cents = Money.info(widget.currency).decimals > 0 || AppScope.of(context).settings.showCents;
    _calc.spanish = AppScope.of(context).settings.spanish;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Row(
              children: <Widget>[
                Expanded(child: Text(widget.title ?? t(context, 'Monto', 'Amount'), style: Theme.of(context).textTheme.titleMedium)),
                Text(Money.info(widget.currency).symbol, style: TextStyle(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(_calc.expression.isEmpty ? '0' : _calc.expression, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, fontFeatures: <FontFeature>[FontFeature.tabularFigures()]), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          AmountKeypad(
            showDecimal: cents,
            spanish: _calc.spanish,
            doneLabel: t(context, 'Listo', 'Done'),
            deleteLabel: t(context, 'Borrar', 'Delete'),
            onKey: (String k) => setState(() => _calc.press(k)),
            onDone: () {
              if (_calc.hasPendingOp) {
                setState(() => _calc.press('='));
                return;
              }
              final int v = _calc.valueMinor;
              // Sin decimales en pantalla (pesos sin centavos), una división
              // queda en el peso más cercano.
              Navigator.pop(context, cents ? v : (v / 100).round() * 100);
            },
          ),
        ],
      ),
    );
  }
}
