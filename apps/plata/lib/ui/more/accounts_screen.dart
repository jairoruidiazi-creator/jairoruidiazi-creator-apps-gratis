import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/bank_rules.dart';
import '../../core/defaults.dart';
import '../../core/ledger.dart';
import '../../model/models.dart';
import '../../model/money.dart';
import '../transactions/tx_list_screen.dart';
import '../widgets/adaptive.dart';
import '../widgets/common.dart';

/// Cuentas: lista con saldos, bolsillos anidados y archivadas.
class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    return ListenableBuilder(
      listenable: s.ledger,
      builder: (BuildContext context, Widget? _) {
        final Ledger l = s.ledger;
        final List<Account> roots = l.activeAccounts.where((Account a) => !a.isPocket).toList();
        final List<Account> archived = l.accounts.where((Account a) => a.archived).toList();
        return ReadableScaffold(
          appBar: AppBar(
            title: Text(t(context, 'Cuentas', 'Accounts')),
            actions: <Widget>[
              if (archived.isNotEmpty) IconButton(tooltip: t(context, 'Archivadas', 'Archived'), icon: Icon(_showArchived ? Icons.unarchive_outlined : Icons.archive_outlined), onPressed: () => setState(() => _showArchived = !_showArchived)),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(heroTag: null, onPressed: () => _add(context), icon: const Icon(Icons.add), label: Text(t(context, 'Cuenta', 'Account'))),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 96),
            children: <Widget>[
              ListTile(
                title: Text(t(context, 'Patrimonio neto', 'Net worth')),
                subtitle: Text('${t(context, 'Deudas', 'Debt')}: ${money(context, l.debtMinor(), l.baseCurrency)}'),
                trailing: Text(money(context, l.netWorthMinor(), l.baseCurrency), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ),
              for (final Account a in roots) ...<Widget>[
                _AccountRow(account: a),
                for (final Account p in l.activeAccounts.where((Account p) => p.parentId == a.id)) Padding(padding: const EdgeInsets.only(left: 28), child: _AccountRow(account: p)),
              ],
              if (_showArchived && archived.isNotEmpty) ...<Widget>[
                const Divider(),
                Padding(padding: const EdgeInsets.all(8), child: Text(t(context, 'Archivadas', 'Archived'), style: Theme.of(context).textTheme.titleSmall)),
                for (final Account a in archived) _AccountRow(account: a),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _add(BuildContext context) async {
    final bool es = AppScope.of(context).settings.spanish;
    final Account? preset = await showModalBottomSheet<Account>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text(t(context, '¿Qué tipo de cuenta?', 'What kind of account?'), style: Theme.of(context).textTheme.titleMedium)),
            for (final Account p in Defaults.presets(spanish: es))
              ListTile(leading: IconBadge(icon: p.icon, color: p.color), title: Text(p.name), subtitle: Text(accountTypeName(context, p.type)), onTap: () => Navigator.pop(context, p)),
            ListTile(leading: const IconBadge(icon: 'wallet', color: 0xFF9E9E9E), title: Text(t(context, 'Otra', 'Other')), onTap: () => Navigator.pop(context, Account(id: '', name: '', type: AccountType.other, icon: 'wallet', color: 0xFF9E9E9E))),
          ],
        ),
      ),
    );
    if (preset == null || !context.mounted) {
      return;
    }
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => AccountEditor(preset: preset)));
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context) {
    final Ledger l = AppScope.of(context).ledger;
    final Account a = account;
    final int balance = l.balanceMinor(a.id);
    final int shown = a.isCredit ? -balance : balance;
    final List<String> sub = <String>[accountTypeName(context, a.type)];
    if (a.isCredit) {
      final CardStatement st = l.nextPayment(a);
      if (st.dueMinor > 0) {
        sub.add('${t(context, 'pagar', 'pay')} ${money(context, st.dueMinor, a.currency, compact: true)} ${t(context, 'el', 'on')} ${formatDate(st.cycle.payDate, 'dd MMM', spanish: l.spanish)}');
      }
      final int? available = l.availableCreditMinor(a);
      if (available != null) {
        sub.add('${t(context, 'cupo libre', 'available')} ${money(context, available, a.currency, compact: true)}');
      }
    } else if (a.isDebit) {
      sub.add('→ ${l.account(a.linkedAccountId)?.name ?? t(context, 'sin cuenta', 'no account')}');
    } else if (l.activeAccounts.any((Account p) => p.parentId == a.id)) {
      sub.add('${t(context, 'total con bolsillos', 'total with pockets')} ${money(context, l.balanceWithPockets(a.id), a.currency, compact: true)}');
    }
    if (!a.includeInTotal) {
      sub.add(t(context, 'fuera del total', 'excluded from total'));
    }
    return ListTile(
      leading: IconBadge(icon: a.icon, color: a.archived ? 0xFF9E9E9E : a.color),
      title: Text(a.name, style: TextStyle(decoration: a.archived ? TextDecoration.lineThrough : null)),
      subtitle: Text(sub.join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: a.isDebit
          ? const Icon(Icons.link)
          : Text(money(context, shown, a.currency), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: shown < 0 ? kindColor(context, TxKind.expense) : null, fontFeatures: const <FontFeature>[FontFeature.tabularFigures()])),
      onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ReadableScaffold(appBar: AppBar(title: Text(a.name), actions: <Widget>[IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => AccountEditor(existing: a))))]), body: TxListScreen(initialFilter: TxFilter(accountIds: <String>{a.id}))))),
      onLongPress: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => AccountEditor(existing: a))),
    );
  }
}

/// Alta y edición de una cuenta.
class AccountEditor extends StatefulWidget {
  const AccountEditor({super.key, this.existing, this.preset});

  final Account? existing;
  final Account? preset;

  @override
  State<AccountEditor> createState() => _AccountEditorState();
}

class _AccountEditorState extends State<AccountEditor> {
  Account get _base => widget.existing ?? widget.preset ?? Account(id: '', name: '');
  late final TextEditingController _name = TextEditingController(text: _base.name);
  late final TextEditingController _last4 = TextEditingController(text: _base.last4);
  late final TextEditingController _notes = TextEditingController(text: _base.notes);
  late AccountType _type = _base.type;

  /// Banco de la lista de avisos (clave interna), o vacío.
  late String _bank = BankRules.keyFor(_base.bank);
  late String _currency = _base.currency;

  /// Saldo inicial tal como se guarda: en tarjetas y préstamos, la deuda es
  /// negativa (como en todo el libro); en pantalla se pide y muestra en positivo.
  late int _initial = _base.initialMinor;

  bool get _isDebtType => _type == AccountType.credit || _type == AccountType.loan;
  late int _color = _base.color;
  late String _icon = _base.icon;
  late bool _includeInTotal = _base.includeInTotal;
  late String? _parentId = _base.parentId;
  late String? _linkedId = _base.linkedAccountId;
  late int? _limit = _base.creditLimitMinor;
  late int _cutDay = _base.cutDay ?? 15;
  late int _payDay = _base.payDay ?? 5;

  @override
  void dispose() {
    disposeLater(<ChangeNotifier>[_name, _last4, _notes]);
    super.dispose();
  }

  Future<void> _save() async {
    final Ledger l = AppScope.of(context).ledger;
    final String name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context, 'Ponle un nombre a la cuenta.', 'Give the account a name.'))));
      return;
    }
    if (_type == AccountType.pocket && _parentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context, 'Un bolsillo necesita una cuenta madre.', 'A pocket needs a parent account.'))));
      return;
    }
    final Account? e = widget.existing;
    final Account a = e ?? Account(id: newId(), name: name);
    // Deuda en tarjetas y préstamos: negativa, como la lee el libro.
    final int initial = _isDebtType ? -_initial.abs() : _initial;
    a
      ..name = name
      ..type = _type
      ..currency = _type == AccountType.pocket ? (l.account(_parentId)?.currency ?? _currency) : _currency
      ..initialMinor = initial
      ..color = _color
      ..icon = _icon
      ..includeInTotal = _includeInTotal
      ..parentId = _type == AccountType.pocket ? _parentId : null
      ..linkedAccountId = _type == AccountType.debit ? _linkedId : null
      ..creditLimitMinor = _type == AccountType.credit ? _limit : null
      ..cutDay = _type == AccountType.credit ? _cutDay : null
      ..payDay = _type == AccountType.credit ? _payDay : null
      ..bank = _bank
      ..last4 = _last4.text.trim()
      ..notes = _notes.text.trim();
    if (e == null) {
      await l.addAccount(a);
    } else {
      l.save();
    }
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final Ledger l = s.ledger;
    final List<String> currencies = <String>{l.baseCurrency, ...s.settings.extraCurrencies, _currency}.toList();
    return ReadableScaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? t(context, 'Nueva cuenta', 'New account') : t(context, 'Editar cuenta', 'Edit account')),
        actions: <Widget>[
          if (widget.existing != null)
            PopupMenuButton<String>(
              onSelected: (String v) async {
                final Account e = widget.existing!;
                if (v == 'archive') {
                  l.setArchived(e, !e.archived);
                  Navigator.pop(context);
                } else if (v == 'delete') {
                  final bool used = l.accountInUse(e.id);
                  if (await confirm(context, t(context, '¿Eliminar cuenta?', 'Delete account?'), '${used ? t(context, 'Tiene movimientos, así que se archivará en lugar de borrarse.', 'It has transactions, so it will be archived instead of deleted.') : t(context, 'No tiene movimientos; se borrará.', 'It has no transactions; it will be deleted.')} ${t(context, 'Sus programados se pausan y las plantillas que la usan pedirán la cuenta.', 'Its scheduled items are paused and templates using it will ask for the account.')}', yes: t(context, 'Eliminar', 'Delete')) && context.mounted) {
                    l.deleteAccount(e.id);
                    Navigator.pop(context);
                  }
                } else if (v == 'adjust') {
                  await _adjust(context, e);
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                PopupMenuItem<String>(value: 'adjust', child: Text(t(context, 'Ajustar saldo real…', 'Adjust real balance…'))),
                PopupMenuItem<String>(value: 'archive', child: Text(widget.existing!.archived ? t(context, 'Desarchivar', 'Unarchive') : t(context, 'Archivar', 'Archive'))),
                PopupMenuItem<String>(value: 'delete', child: Text(t(context, 'Eliminar', 'Delete'))),
              ],
            ),
          TextButton(onPressed: _save, child: Text(t(context, 'Guardar', 'Save'))),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          Row(
            children: <Widget>[
              IconBadge(icon: _icon, color: _color, size: 52),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: _name, decoration: InputDecoration(labelText: t(context, 'Nombre', 'Name'), border: const OutlineInputBorder()), textCapitalization: TextCapitalization.sentences)),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<AccountType>(
            initialValue: _type,
            isExpanded: true,
            decoration: InputDecoration(labelText: t(context, 'Tipo', 'Type'), border: const OutlineInputBorder()),
            items: <DropdownMenuItem<AccountType>>[for (final AccountType ty in AccountType.values) DropdownMenuItem<AccountType>(value: ty, child: Text(accountTypeName(context, ty), overflow: TextOverflow.ellipsis))],
            onChanged: (AccountType? v) => setState(() => _type = v ?? _type),
          ),
          const SizedBox(height: 12),
          if (_type == AccountType.pocket)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.account_balance_outlined),
              title: Text(t(context, 'Cuenta madre', 'Parent account')),
              subtitle: Text(l.account(_parentId)?.name ?? t(context, 'Elegir…', 'Choose…')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final Account? a = await pickAccount(context, exclude: widget.existing?.id, title: t(context, 'Cuenta del bolsillo', 'Pocket parent'));
                if (a != null && !a.isPocket) {
                  setState(() {
                    _parentId = a.id;
                    _currency = a.currency;
                  });
                }
              },
            )
          else
            DropdownButtonFormField<String>(
              initialValue: _currency,
              isExpanded: true,
              decoration: InputDecoration(labelText: t(context, 'Moneda', 'Currency'), border: const OutlineInputBorder(), helperText: t(context, 'Añade monedas en Más › Monedas.', 'Add currencies under More › Currencies.')),
              items: <DropdownMenuItem<String>>[for (final String c in currencies) DropdownMenuItem<String>(value: c, child: Text('$c · ${Money.info(c).nameFor(spanish: s.settings.spanish)}', overflow: TextOverflow.ellipsis))],
              // Con movimientos (de salida o de llegada) la moneda ya no cambia:
              // sus montos están en ella.
              onChanged: widget.existing != null && l.accountInUse(widget.existing!.id) ? null : (String? v) => setState(() => _currency = v ?? _currency),
            ),
          const SizedBox(height: 12),
          if (_type == AccountType.debit)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.link),
              title: Text(t(context, 'Descuenta de la cuenta', 'Charges the account')),
              subtitle: Text(l.account(_linkedId)?.name ?? t(context, 'Elegir cuenta bancaria…', 'Choose bank account…')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final Account? a = await pickAccount(context, exclude: widget.existing?.id, title: t(context, 'Cuenta de la tarjeta débito', 'Debit card account'));
                if (a != null) {
                  setState(() {
                    _linkedId = a.id;
                    _currency = a.currency;
                  });
                }
              },
            )
          else
            AmountTile(
              minor: _isDebtType ? _initial.abs() : _initial,
              currency: _currency,
              label: _type == AccountType.credit ? t(context, 'Deuda inicial (lo que ya debes)', 'Starting debt (what you already owe)') : (_type == AccountType.loan ? t(context, 'Lo que debes del préstamo', 'What you owe on the loan') : t(context, 'Saldo inicial', 'Opening balance')),
              onTap: () async {
                final int? v = await pickAmount(context, initialMinor: _initial.abs(), currency: _currency, title: _isDebtType ? t(context, 'Lo que debes hoy', 'What you owe today') : t(context, 'Saldo inicial', 'Opening balance'));
                if (v != null) {
                  setState(() => _initial = _isDebtType ? -v.abs() : v);
                }
              },
            ),
          if (_isDebtType) Padding(padding: const EdgeInsets.only(top: 4), child: Text(t(context, 'Es deuda: resta del patrimonio y cuenta en Deudas. Los pagos (transferencias hacia la cuenta) la acercan a cero.', 'It is debt: it lowers your net worth and counts as Debt. Payments (transfers into the account) bring it to zero.'), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)))),
          if (_type == AccountType.credit) ...<Widget>[
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(child: _dayField(context, t(context, 'Día de corte', 'Statement day'), _cutDay, (int v) => setState(() => _cutDay = v))),
                const SizedBox(width: 12),
                Expanded(child: _dayField(context, t(context, 'Día de pago', 'Payment day'), _payDay, (int v) => setState(() => _payDay = v))),
              ],
            ),
            const SizedBox(height: 12),
            AmountTile(
              minor: _limit ?? 0,
              currency: _currency,
              label: t(context, 'Cupo (opcional)', 'Credit limit (optional)'),
              onTap: () async {
                final int? v = await pickAmount(context, initialMinor: _limit ?? 0, currency: _currency, title: t(context, 'Cupo de la tarjeta', 'Card limit'));
                if (v != null) {
                  setState(() => _limit = v == 0 ? null : v);
                }
              },
            ),
          ],
          const SizedBox(height: 12),
          // Los avisos bancarios solo existen en Android: allí se elige el banco de
          // la lista (la clave con que llegan sus avisos) y los últimos dígitos.
          if (defaultTargetPlatform == TargetPlatform.android)
            DropdownButtonFormField<String>(
              initialValue: _bank,
              isExpanded: true,
              decoration: InputDecoration(labelText: t(context, 'Banco o billetera', 'Bank or wallet'), border: const OutlineInputBorder(), helperText: t(context, 'Para reconocer sus avisos', 'Used to match its notices')),
              items: <DropdownMenuItem<String>>[
                DropdownMenuItem<String>(value: '', child: Text(t(context, 'Ninguno u otro', 'None or other'))),
                for (final MapEntry<String, String> b in BankRules.bankNames.entries) DropdownMenuItem<String>(value: b.key, child: Text(BankRules.displayName(b.key, spanish: s.settings.spanish), overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (String? v) => setState(() => _bank = v ?? ''),
            ),
          const SizedBox(height: 12),
          TextField(controller: _last4, keyboardType: TextInputType.number, maxLength: 4, decoration: InputDecoration(labelText: t(context, 'Últimos 4 dígitos (opcional)', 'Last 4 digits (optional)'), border: const OutlineInputBorder(), counterText: '', helperText: defaultTargetPlatform == TargetPlatform.android ? t(context, 'Si los pones, solo se anotan solos los avisos con esos dígitos', 'If set, only notices with these digits are logged automatically') : null)),
          SwitchListTile(contentPadding: EdgeInsets.zero, value: _includeInTotal, onChanged: (bool v) => setState(() => _includeInTotal = v), title: Text(t(context, 'Cuenta en el patrimonio', 'Counts toward net worth'))),
          const Divider(),
          IconColorPicker(icon: _icon, color: _color, onIcon: (String v) => setState(() => _icon = v), onColor: (int v) => setState(() => _color = v)),
          const SizedBox(height: 12),
          TextField(controller: _notes, decoration: InputDecoration(labelText: t(context, 'Notas', 'Notes'), border: const OutlineInputBorder()), maxLines: 2),
        ],
      ),
    );
  }

  Widget _dayField(BuildContext context, String label, int value, ValueChanged<int> onChanged) => DropdownButtonFormField<int>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        items: <DropdownMenuItem<int>>[for (int d = 1; d <= 31; d++) DropdownMenuItem<int>(value: d, child: Text('$d'))],
        onChanged: (int? v) => onChanged(v ?? value),
      );

  /// Ajusta el saldo al real con un movimiento de ajuste: corrige el saldo sin
  /// contar como gasto ni ingreso en informes ni presupuestos.
  Future<void> _adjust(BuildContext context, Account a) async {
    final Ledger l = AppScope.of(context).ledger;
    final int current = l.balanceMinor(a.id);
    final bool debt = a.isCredit || a.type == AccountType.loan;
    final int? real = await pickAmount(context, initialMinor: current.abs(), currency: a.currency, title: debt ? t(context, 'Lo que debes hoy', 'What you owe today') : t(context, 'Saldo real en la cuenta', 'Real account balance'));
    if (real == null || !context.mounted) {
      return;
    }
    final Tx? tx = await l.adjustBalance(a, debt ? -real.abs() : real, description: t(context, 'Ajuste de saldo', 'Balance adjustment'));
    if (!context.mounted) {
      return;
    }
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(
      content: Text(tx == null ? t(context, 'El saldo ya coincidía.', 'The balance already matched.') : t(context, 'Saldo ajustado. El ajuste no cuenta como gasto ni ingreso.', 'Balance adjusted. The adjustment does not count as spending or income.')),
      action: tx == null ? null : SnackBarAction(label: t(context, 'Deshacer', 'Undo'), onPressed: () => l.deleteTx(tx.id)),
    ));
  }
}
