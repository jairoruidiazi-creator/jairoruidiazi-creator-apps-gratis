import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/ledger.dart';
import '../../model/models.dart';
import '../widgets/adaptive.dart';
import '../widgets/common.dart';

String frequencyName(BuildContext context, Frequency f) {
  final bool es = AppScope.of(context).settings.spanish;
  switch (f.unit) {
    case FrequencyUnit.day:
      return f.every == 1 ? (es ? 'Cada día' : 'Every day') : (es ? 'Cada ${f.every} días' : 'Every ${f.every} days');
    case FrequencyUnit.week:
      return f.every == 1 ? (es ? 'Cada semana' : 'Every week') : (es ? 'Cada ${f.every} semanas' : 'Every ${f.every} weeks');
    case FrequencyUnit.month:
      return f.every == 1 ? (es ? 'Cada mes' : 'Every month') : (es ? 'Cada ${f.every} meses' : 'Every ${f.every} months');
    case FrequencyUnit.year:
      return f.every == 1 ? (es ? 'Cada año' : 'Every year') : (es ? 'Cada ${f.every} años' : 'Every ${f.every} years');
    case FrequencyUnit.quincena:
      return es ? 'Quincenal (15 y fin de mes)' : 'Twice a month (15th and last day)';
  }
}

/// Movimientos programados: arriendo, servicios, salario, cuotas.
class ScheduledScreen extends StatelessWidget {
  const ScheduledScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    return ListenableBuilder(
      listenable: s.ledger,
      builder: (BuildContext context, Widget? _) {
        final Ledger l = s.ledger;
        final List<Scheduled> list = List<Scheduled>.from(l.scheduled)
          ..sort((Scheduled a, Scheduled b) {
            if (a.enabled != b.enabled) {
              return a.enabled ? -1 : 1;
            }
            return a.nextDate.compareTo(b.nextDate);
          });
        final DateTime today = dateOnly(clock.now());
        final MonthlyCommitments commitments = l.monthlyCommitments();
        final int monthlyOut = commitments.outMinor;
        final int monthlyIn = commitments.inMinor;
        return ReadableScaffold(
          appBar: AppBar(title: Text(t(context, 'Programados', 'Scheduled'))),
          floatingActionButton: FloatingActionButton.extended(heroTag: null, onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const ScheduledEditor())), icon: const Icon(Icons.add), label: Text(t(context, 'Programado', 'Scheduled'))),
          body: list.isEmpty
              ? Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(t(context, 'Programa el arriendo, los servicios, el salario o las cuotas: Plata los anota solo (o te recuerda) cuando toca.', 'Schedule rent, utilities, salary or installments: Plata logs them for you (or reminds you) when due.'), textAlign: TextAlign.center)))
              : ListView(
                  padding: const EdgeInsets.only(bottom: 96),
                  children: <Widget>[
                    ListTile(
                      title: Text(t(context, 'Compromisos fijos al mes', 'Fixed monthly commitments')),
                      subtitle: Text('${t(context, 'Salen', 'Out')} ${money(context, monthlyOut, l.baseCurrency)} · ${t(context, 'Entran', 'In')} ${money(context, monthlyIn, l.baseCurrency)}'),
                    ),
                    for (final Scheduled sch in list)
                      ListTile(
                        leading: IconBadge(icon: l.category(sch.categoryId)?.icon ?? (sch.kind == TxKind.transfer ? 'transfer' : 'repeat'), color: sch.enabled ? (l.category(sch.categoryId)?.color ?? 0xFF607D8B) : 0xFF9E9E9E),
                        title: Text(sch.name, style: TextStyle(decoration: sch.enabled ? null : TextDecoration.lineThrough)),
                        subtitle: Text('${frequencyName(context, sch.frequency)} · ${_when(context, sch, today)} · ${l.account(sch.accountId)?.name ?? ''}${sch.autoPost ? '' : ' · ${t(context, 'manual', 'manual')}'}', maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: Text('${sch.kind == TxKind.expense ? '−' : (sch.kind == TxKind.income ? '+' : '')}${money(context, sch.amountMinor, l.account(sch.accountId)?.currency ?? l.baseCurrency)}', style: TextStyle(fontWeight: FontWeight.w700, color: kindColor(context, sch.kind))),
                        onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ScheduledEditor(existing: sch))),
                      ),
                  ],
                ),
        );
      },
    );
  }

  String _when(BuildContext context, Scheduled s, DateTime today) {
    final int days = daysBetween(today, s.nextDate);
    if (!s.enabled) {
      return t(context, 'pausado', 'paused');
    }
    if (days < 0) {
      return -days == 1 ? t(context, 'vencido hace 1 día', 'overdue by 1 day') : t(context, 'vencido hace ${-days} días', 'overdue by ${-days} days');
    }
    if (days == 0) {
      return t(context, 'hoy', 'today');
    }
    if (days == 1) {
      return t(context, 'mañana', 'tomorrow');
    }
    return formatDate(s.nextDate, 'EEE dd MMM', spanish: AppScope.of(context).settings.spanish);
  }
}

/// Alta y edición de un programado.
class ScheduledEditor extends StatefulWidget {
  const ScheduledEditor({super.key, this.existing});

  final Scheduled? existing;

  @override
  State<ScheduledEditor> createState() => _ScheduledEditorState();
}

class _ScheduledEditorState extends State<ScheduledEditor> {
  late final TextEditingController _name = TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _desc = TextEditingController(text: widget.existing?.description ?? '');
  late final TextEditingController _every = TextEditingController(text: '${widget.existing?.frequency.every ?? 1}');
  late TxKind _kind = widget.existing?.kind ?? TxKind.expense;
  late int _amount = widget.existing?.amountMinor ?? 0;
  late String? _accountId = widget.existing?.accountId;
  late String? _toAccountId = widget.existing?.toAccountId;

  /// Monto fijo que llega al destino de una transferencia entre monedas
  /// (null = con la tasa del día en que se anota).
  late int? _toAmount = widget.existing?.toAmountMinor;
  late String? _categoryId = widget.existing?.categoryId;
  late FrequencyUnit _unit = widget.existing?.frequency.unit ?? FrequencyUnit.month;
  late DateTime _next = widget.existing?.nextDate ?? dateOnly(clock.now());
  late DateTime? _end = widget.existing?.endDate;
  late bool _autoPost = widget.existing?.autoPost ?? true;
  late int _remind = widget.existing?.remindDaysBefore ?? 1;
  late bool _enabled = widget.existing?.enabled ?? true;
  Services? _s;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_s == null) {
      _s = AppScope.of(context);
      _accountId ??= _s!.ledger.account(_s!.settings.defaultAccountId)?.id ?? _s!.ledger.activeAccounts.firstOrNull?.id;
    }
  }

  @override
  void dispose() {
    disposeLater(<ChangeNotifier>[_name, _desc, _every]);
    super.dispose();
  }

  Future<void> _save() async {
    final Ledger l = _s!.ledger;
    final String name = _name.text.trim();
    if (name.isEmpty || _amount <= 0 || _accountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context, 'Completa nombre, monto y cuenta.', 'Fill in name, amount and account.'))));
      return;
    }
    if (_kind == TxKind.transfer && (l.account(_toAccountId) == null || _toAccountId == _accountId)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context, 'Elige la cuenta de destino.', 'Choose the destination account.'))));
      return;
    }
    // Con recordatorio: se pide el permiso de notificaciones ahora, que es
    // cuando hace falta (si ya está concedido no pregunta nada).
    final bool newReminder = _remind >= 0 && _enabled && _s!.settings.billReminders && (widget.existing == null || widget.existing!.remindDaysBefore < 0);
    if (newReminder) {
      await ensureNotifications(context, why: t(context, 'Para recordarte «$name» antes de que toque.', 'To remind you about "$name" before it is due.'));
      if (!mounted) {
        return;
      }
    }
    final int? toAmount = _crossCurrency(l) ? _toAmount : null;
    final Frequency f = Frequency(unit: _unit, every: (int.tryParse(_every.text) ?? 1).clamp(1, 365));
    final Scheduled? e = widget.existing;
    if (e == null) {
      await l.addScheduled(Scheduled(id: newId(), name: name, kind: _kind, amountMinor: _amount, accountId: _accountId!, toAccountId: _kind == TxKind.transfer ? _toAccountId : null, toAmountMinor: toAmount, categoryId: _kind == TxKind.transfer ? null : _categoryId, description: _desc.text.trim(), frequency: f, nextDate: _next, anchorDate: _next, endDate: _end, autoPost: _autoPost, remindDaysBefore: _remind, enabled: _enabled));
    } else {
      final bool dateChanged = e.nextDate != _next;
      e
        ..name = name
        ..kind = _kind
        ..amountMinor = _amount
        ..accountId = _accountId!
        ..toAccountId = _kind == TxKind.transfer ? _toAccountId : null
        ..toAmountMinor = toAmount
        ..categoryId = _kind == TxKind.transfer ? null : _categoryId
        ..description = _desc.text.trim()
        ..frequency = f
        ..nextDate = _next
        ..endDate = _end
        ..autoPost = _autoPost
        ..remindDaysBefore = _remind
        ..enabled = _enabled;
      if (dateChanged) {
        e.anchorDate = _next;
      }
      l.save();
    }
    if (mounted) {
      Navigator.pop(context);
    }
  }

  bool _crossCurrency(Ledger l) {
    final Account? from = l.account(_accountId);
    final Account? to = l.account(_toAccountId);
    return _kind == TxKind.transfer && from != null && to != null && from.currency != to.currency;
  }

  @override
  Widget build(BuildContext context) {
    final Services s = _s ?? AppScope.of(context);
    final Ledger l = s.ledger;
    final String currency = l.account(_accountId)?.currency ?? l.baseCurrency;
    final Account? toAccount = l.account(_toAccountId);
    final Scheduled? e = widget.existing;
    return ReadableScaffold(
      appBar: AppBar(
        title: Text(e == null ? t(context, 'Nuevo programado', 'New scheduled') : t(context, 'Programado', 'Scheduled')),
        actions: <Widget>[
          if (e != null)
            PopupMenuButton<String>(
              onSelected: (String v) async {
                if (v == 'post') {
                  try {
                    await l.postScheduled(e);
                  } on TxRejected catch (err) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(txProblemText(context, err))));
                    }
                    return;
                  }
                  if (context.mounted) {
                    Navigator.pop(context);
                  }
                } else if (v == 'skip') {
                  l.skipScheduled(e);
                  if (context.mounted) {
                    Navigator.pop(context);
                  }
                } else if (v == 'delete') {
                  if (await confirm(context, t(context, '¿Eliminar programado?', 'Delete scheduled?'), t(context, 'Los movimientos ya anotados se conservan.', 'Already logged transactions are kept.'), yes: t(context, 'Eliminar', 'Delete')) && context.mounted) {
                    l.deleteScheduled(e.id);
                    Navigator.pop(context);
                  }
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                PopupMenuItem<String>(value: 'post', child: Text(t(context, 'Anotar ahora', 'Log now'))),
                PopupMenuItem<String>(value: 'skip', child: Text(t(context, 'Saltar esta vez', 'Skip this one'))),
                PopupMenuItem<String>(value: 'delete', child: Text(t(context, 'Eliminar', 'Delete'))),
              ],
            ),
          TextButton(onPressed: _save, child: Text(t(context, 'Guardar', 'Save'))),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          TextField(controller: _name, decoration: InputDecoration(labelText: t(context, 'Nombre (Arriendo, Internet, Salario…)', 'Name (Rent, Internet, Salary…)'), border: const OutlineInputBorder()), textCapitalization: TextCapitalization.sentences),
          const SizedBox(height: 12),
          SegmentedButton<TxKind>(
            showSelectedIcon: false,
            segments: <ButtonSegment<TxKind>>[for (final TxKind k in TxKind.values) ButtonSegment<TxKind>(value: k, label: Text(kindName(context, k)))],
            selected: <TxKind>{_kind},
            onSelectionChanged: (Set<TxKind> v) => setState(() {
              _kind = v.first;
              final Category? c = l.category(_categoryId);
              if (c != null && _kind != TxKind.transfer && c.kind != (_kind == TxKind.expense ? CategoryKind.expense : CategoryKind.income)) {
                _categoryId = null;
              }
            }),
          ),
          const SizedBox(height: 12),
          AmountTile(
            minor: _amount,
            currency: currency,
            onTap: () async {
              final int? v = await pickAmount(context, initialMinor: _amount, currency: currency);
              if (v != null) {
                setState(() => _amount = v);
              }
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: Text(_kind == TxKind.transfer ? t(context, 'Desde', 'From') : t(context, 'Cuenta', 'Account')),
            subtitle: Text(l.account(_accountId)?.name ?? t(context, 'Elegir…', 'Choose…')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final Account? a = await pickAccount(context);
              if (a != null) {
                setState(() => _accountId = a.id);
              }
            },
          ),
          if (_kind == TxKind.transfer)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.arrow_forward),
              title: Text(t(context, 'Hacia', 'To')),
              subtitle: Text(l.account(_toAccountId)?.name ?? t(context, 'Elegir…', 'Choose…')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final Account? a = await pickAccount(context, exclude: _accountId);
                if (a != null) {
                  setState(() => _toAccountId = a.id);
                }
              },
            ),
          if (_crossCurrency(l) && toAccount != null)
            AmountTile(
              minor: _toAmount ?? 0,
              currency: toAccount.currency,
              label: _toAmount == null ? t(context, 'Monto recibido (vacío = con la tasa del día)', 'Amount received (empty = rate of the day)') : t(context, 'Monto recibido fijo', 'Fixed amount received'),
              onTap: () async {
                final int? v = await pickAmount(context, initialMinor: _toAmount ?? 0, currency: toAccount.currency, title: '${t(context, 'Monto recibido en', 'Amount received in')} ${toAccount.currency}');
                if (v != null) {
                  setState(() => _toAmount = v <= 0 ? null : v);
                }
              },
            ),
          if (_crossCurrency(l) && _toAmount == null)
            Padding(padding: const EdgeInsets.only(top: 4), child: Text(t(context, 'Si el día que toca no hay tasa entre las dos monedas, queda pendiente para que lo confirmes.', 'If there is no rate between the two currencies on the day, it waits for you to confirm it.'), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant))),
          if (_kind != TxKind.transfer)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.label_outline),
              title: Text(t(context, 'Categoría', 'Category')),
              subtitle: Text(l.categoryPath(_categoryId).isEmpty ? t(context, 'Sin categoría', 'Uncategorized') : l.categoryPath(_categoryId)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final Category? c = await pickCategory(context, _kind == TxKind.expense ? CategoryKind.expense : CategoryKind.income, current: _categoryId);
                if (c != null) {
                  setState(() => _categoryId = c.id);
                }
              },
            ),
          TextField(controller: _desc, decoration: InputDecoration(labelText: t(context, 'Descripción (opcional)', 'Description (optional)'), border: const OutlineInputBorder()), textCapitalization: TextCapitalization.sentences),
          const Divider(height: 24),
          Row(
            children: <Widget>[
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<FrequencyUnit>(
                  initialValue: _unit,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: t(context, 'Se repite', 'Repeats'), border: const OutlineInputBorder()),
                  items: <DropdownMenuItem<FrequencyUnit>>[for (final FrequencyUnit u in FrequencyUnit.values) DropdownMenuItem<FrequencyUnit>(value: u, child: Text(frequencyName(context, Frequency(unit: u)), overflow: TextOverflow.ellipsis))],
                  onChanged: (FrequencyUnit? v) => setState(() => _unit = v ?? _unit),
                ),
              ),
              if (_unit != FrequencyUnit.quincena) ...<Widget>[
                const SizedBox(width: 12),
                Expanded(child: TextField(controller: _every, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: t(context, 'Cada', 'Every'), border: const OutlineInputBorder()))),
              ],
            ],
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: Text(t(context, 'Próxima fecha', 'Next date')),
            subtitle: Text(formatDate(_next, 'EEE dd MMM yyyy', spanish: s.settings.spanish)),
            trailing: const Icon(Icons.edit_calendar_outlined),
            onTap: () async {
              final DateTime? d = await showDatePicker(context: context, initialDate: _next, firstDate: DateTime(2000), lastDate: DateTime(2100));
              if (d != null) {
                setState(() => _next = dateOnly(d));
              }
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_busy_outlined),
            title: Text(t(context, 'Termina', 'Ends')),
            subtitle: Text(_end == null ? t(context, 'Nunca', 'Never') : formatDate(_end!, 'EEE dd MMM yyyy', spanish: s.settings.spanish)),
            trailing: _end == null ? const Icon(Icons.chevron_right) : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _end = null)),
            onTap: () async {
              final DateTime? d = await showDatePicker(context: context, initialDate: _end ?? _next, firstDate: DateTime(2000), lastDate: DateTime(2100));
              if (d != null) {
                setState(() => _end = dateOnly(d));
              }
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _autoPost,
            onChanged: (bool v) => setState(() => _autoPost = v),
            title: Text(t(context, 'Anotar automáticamente', 'Log automatically')),
            subtitle: Text(t(context, 'Si lo apagas, aparece como pendiente hasta que lo confirmes.', 'If off, it stays pending until you confirm it.')),
          ),
          DropdownButtonFormField<int>(
            initialValue: _remind,
            isExpanded: true,
            decoration: InputDecoration(labelText: t(context, 'Recordatorio', 'Reminder'), border: const OutlineInputBorder()),
            items: <DropdownMenuItem<int>>[
              DropdownMenuItem<int>(value: -1, child: Text(t(context, 'Sin recordatorio', 'No reminder'))),
              DropdownMenuItem<int>(value: 0, child: Text(t(context, 'El mismo día', 'Same day'))),
              DropdownMenuItem<int>(value: 1, child: Text(t(context, '1 día antes', '1 day before'))),
              DropdownMenuItem<int>(value: 3, child: Text(t(context, '3 días antes', '3 days before'))),
              DropdownMenuItem<int>(value: 7, child: Text(t(context, '7 días antes', '7 days before'))),
            ],
            onChanged: (int? v) => setState(() => _remind = v ?? 1),
          ),
          SwitchListTile(contentPadding: EdgeInsets.zero, value: _enabled, onChanged: (bool v) => setState(() => _enabled = v), title: Text(t(context, 'Activo', 'Active'))),
        ],
      ),
    );
  }
}
