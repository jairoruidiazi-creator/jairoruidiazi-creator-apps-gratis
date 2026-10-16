import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/ledger.dart';
import '../../model/models.dart';
import '../../model/money.dart';
import 'amount_keypad.dart';
import 'icons.dart';

/// Formato de dinero con las preferencias del usuario (centavos, ocultar).
String money(BuildContext context, int minor, String currency, {bool compact = false, bool withSymbol = true}) {
  final Services s = AppScope.of(context);
  if (s.settings.hideBalances) {
    return '${Money.info(currency).symbol} ••••';
  }
  return Money.format(minor, currency, showCents: s.settings.showCents, compact: compact, withSymbol: withSymbol);
}

Color kindColor(BuildContext context, TxKind k) {
  switch (k) {
    case TxKind.expense:
      return const Color(0xFFC62828);
    case TxKind.income:
      return const Color(0xFF2E7D32);
    case TxKind.transfer:
      return Theme.of(context).colorScheme.primary;
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
Future<Account?> pickAccount(BuildContext context, {String? exclude, String? title, bool includeArchived = false}) {
  final Ledger l = AppScope.of(context).ledger;
  return showModalBottomSheet<Account>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext context) {
      final List<Account> list = (includeArchived ? l.accounts : l.activeAccounts).where((Account a) => a.id != exclude).toList();
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
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final int c in AppIcons.palette)
              GestureDetector(
                onTap: () => onColor(c),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(color: Color(c), shape: BoxShape.circle, border: Border.all(color: color == c ? Theme.of(context).colorScheme.onSurface : Colors.transparent, width: 3)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 150,
          child: GridView.count(
            crossAxisCount: 8,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            children: <Widget>[
              for (final MapEntry<String, IconData> e in AppIcons.all.entries)
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onIcon(e.key),
                  child: Container(
                    decoration: BoxDecoration(color: icon == e.key ? Color(color).withValues(alpha: 0.2) : null, borderRadius: BorderRadius.circular(8)),
                    child: Icon(e.value, size: 22, color: icon == e.key ? Color(color) : null),
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

Future<bool> confirm(BuildContext context, String title, String body, {String? yes}) async {
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t(context, 'Cancelar', 'Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(yes ?? t(context, 'Aceptar', 'OK'))),
      ],
    ),
  );
  return ok ?? false;
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
            Text(label ?? t(context, 'Monto', 'Amount'), style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6))),
            Text(Money.format(minor, currency, showCents: AppScope.of(context).settings.showCents), style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: color ?? cs.onSurface, fontFeatures: const <FontFeature>[FontFeature.tabularFigures()])),
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
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Row(
              children: <Widget>[
                Expanded(child: Text(widget.title ?? t(context, 'Monto', 'Amount'), style: Theme.of(context).textTheme.titleMedium)),
                Text(Money.info(widget.currency).symbol, style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6))),
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
            doneLabel: t(context, 'Listo', 'Done'),
            onKey: (String k) => setState(() => _calc.press(k)),
            onDone: () {
              if (_calc.hasPendingOp) {
                setState(() => _calc.press('='));
                return;
              }
              Navigator.pop(context, _calc.valueMinor);
            },
          ),
        ],
      ),
    );
  }
}
