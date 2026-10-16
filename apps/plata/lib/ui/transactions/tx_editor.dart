import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/app_scope.dart';
import '../../core/ledger.dart';
import '../../model/models.dart';
import '../../model/money.dart';
import '../widgets/amount_keypad.dart';
import '../widgets/common.dart';
import '../widgets/icons.dart';

/// Alta y edición de un movimiento.
class TxEditor extends StatefulWidget {
  const TxEditor({super.key, this.existing, this.kind, this.template, this.inbox, this.initialAccountId, this.initialToAccountId, this.initialMinor, this.initialDate, this.initialDescription});

  final Tx? existing;
  final TxKind? kind;
  final TxTemplate? template;
  final InboxItem? inbox;
  final String? initialAccountId;
  final String? initialToAccountId;
  final int? initialMinor;
  final DateTime? initialDate;
  final String? initialDescription;

  @override
  State<TxEditor> createState() => _TxEditorState();
}

class _TxEditorState extends State<TxEditor> {
  late TxKind _kind;
  late Calc _calc;
  int _minor = 0;
  String? _accountId;
  String? _toAccountId;
  int? _toMinor;
  String? _categoryId;
  late DateTime _date;
  final TextEditingController _desc = TextEditingController();
  final TextEditingController _payee = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  final TextEditingController _check = TextEditingController();
  final TextEditingController _tag = TextEditingController();
  final List<String> _tags = <String>[];
  final List<Split> _splits = <Split>[];
  final List<String> _attachments = <String>[];
  int _installments = 1;
  bool _reconciled = false;
  bool _keypad = false;
  bool _more = false;
  bool _saving = false;
  Services? _s;

  @override
  void initState() {
    super.initState();
    final Tx? e = widget.existing;
    final TxTemplate? tpl = widget.template;
    final InboxItem? ib = widget.inbox;
    _kind = e?.kind ?? tpl?.kind ?? (ib == null ? (widget.kind ?? TxKind.expense) : (ib.kind == TxKind.transfer ? TxKind.expense : ib.kind));
    _minor = e?.amountMinor ?? tpl?.amountMinor ?? ib?.amountMinor ?? widget.initialMinor ?? 0;
    _calc = Calc(initialMinor: _minor);
    _accountId = e?.accountId ?? tpl?.accountId ?? ib?.accountId ?? widget.initialAccountId;
    _toAccountId = e?.toAccountId ?? tpl?.toAccountId ?? widget.initialToAccountId;
    _toMinor = e?.toAmountMinor;
    _categoryId = e?.categoryId ?? tpl?.categoryId;
    _date = e?.date ?? ib?.receivedAt ?? widget.initialDate ?? DateTime.now();
    _desc.text = e?.description ?? tpl?.description ?? ib?.merchant ?? widget.initialDescription ?? '';
    _payee.text = e?.payee ?? tpl?.payee ?? '';
    _notes.text = e?.notes ?? (ib == null ? '' : ib.rawText);
    _check.text = e?.checkNumber ?? '';
    _tags.addAll(e?.tags ?? tpl?.tags ?? <String>[]);
    _splits.addAll(e?.splits ?? <Split>[]);
    _attachments.addAll(e?.attachments ?? <String>[]);
    _installments = e?.installments ?? 1;
    _reconciled = e?.reconciled ?? false;
    _keypad = e == null && _minor == 0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_s == null) {
      _s = AppScope.of(context);
      final Ledger l = _s!.ledger;
      if (_accountId == null || l.account(_accountId) == null) {
        final String def = _s!.settings.defaultAccountId;
        _accountId = l.account(def)?.id ?? (l.activeAccounts.isEmpty ? null : l.activeAccounts.first.id);
      }
    }
  }

  @override
  void dispose() {
    disposeLater(<ChangeNotifier>[_desc, _payee, _notes, _check, _tag]);
    super.dispose();
  }

  Ledger get _l => _s!.ledger;
  Account? get _account => _l.account(_accountId);
  String get _currency => _account?.currency ?? _l.baseCurrency;

  void _onKey(String k) => setState(() {
        _calc.press(k);
        _minor = _calc.valueMinor;
      });

  Future<void> _pickDate() async {
    final DateTime? d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (d == null || !mounted) {
      return;
    }
    final TimeOfDay? tm = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_date));
    setState(() => _date = DateTime(d.year, d.month, d.day, tm?.hour ?? _date.hour, tm?.minute ?? _date.minute));
  }

  Future<void> _addAttachment(ImageSource source) async {
    try {
      final XFile? f = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 82);
      if (f == null) {
        return;
      }
      final String rel = 'attachments/${newId()}.jpg';
      await _s!.store.writeBytes(rel, await f.readAsBytes());
      setState(() => _attachments.add(rel));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t(context, 'No se pudo adjuntar', 'Could not attach')}: $e')));
      }
    }
  }

  Future<void> _addSplit() async {
    final CategoryKind ck = _kind == TxKind.income ? CategoryKind.income : CategoryKind.expense;
    final Category? c = await pickCategory(context, ck);
    if (c == null || !mounted) {
      return;
    }
    final int remaining = _minor - _splits.fold<int>(0, (int s, Split p) => s + p.amountMinor);
    final String? txt = await askText(context, '${t(context, 'Monto para', 'Amount for')} ${c.name}', initial: remaining > 0 ? Money.format(remaining, _currency, withSymbol: false) : '', keyboard: const TextInputType.numberWithOptions(decimal: true));
    if (txt == null) {
      return;
    }
    final int? m = Money.parse(txt);
    if (m == null || m <= 0) {
      return;
    }
    setState(() {
      _splits.add(Split(categoryId: c.id, amountMinor: m));
      _minor = _splits.fold<int>(0, (int s, Split p) => s + p.amountMinor);
      _calc = Calc(initialMinor: _minor);
      _categoryId = null;
    });
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    final Ledger l = _l;
    if (_minor <= 0) {
      setState(() => _keypad = true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context, 'Escribe el monto.', 'Enter the amount.'))));
      return;
    }
    if (_accountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context, 'Elige la cuenta.', 'Choose the account.'))));
      return;
    }
    if (_kind == TxKind.transfer && (_toAccountId == null || _toAccountId == _accountId)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context, 'Elige la cuenta de destino.', 'Choose the destination account.'))));
      return;
    }
    setState(() => _saving = true);
    final Tx tx = widget.existing ?? Tx(id: newId(), kind: _kind, amountMinor: _minor, accountId: _accountId!, date: _date);
    tx.kind = _kind;
    tx.amountMinor = _minor;
    tx.accountId = _accountId!;
    tx.toAccountId = _kind == TxKind.transfer ? _toAccountId : null;
    tx.toAmountMinor = _kind == TxKind.transfer ? _toMinor : null;
    tx.categoryId = _splits.isEmpty ? _categoryId : null;
    tx.date = _date;
    tx.description = _desc.text.trim();
    tx.payee = _payee.text.trim();
    tx.notes = _notes.text.trim();
    tx.checkNumber = _check.text.trim();
    tx.tags
      ..clear()
      ..addAll(_tags);
    tx.splits
      ..clear()
      ..addAll(_splits);
    tx.attachments
      ..clear()
      ..addAll(_attachments);
    tx.installments = (_account?.isCredit ?? false) && _kind == TxKind.expense ? _installments : 1;
    tx.reconciled = _reconciled;
    if (widget.inbox != null) {
      tx.source = 'notice';
      widget.inbox!.status = 'accepted';
      widget.inbox!.accountId = _accountId;
    }
    if (widget.existing == null) {
      await l.addTx(tx);
    } else {
      l.updateTx(tx);
    }
    _s!.settings.defaultAccountId = _accountId!;
    await _s!.settings.save();
    if (mounted) {
      Navigator.of(context).pop(tx);
    }
  }

  Future<void> _saveAsTemplate() async {
    final String? name = await askText(context, t(context, 'Nombre de la plantilla', 'Template name'), initial: _desc.text.trim());
    if (name == null || name.trim().isEmpty) {
      return;
    }
    await _l.addTemplate(TxTemplate(id: newId(), name: name.trim(), kind: _kind, amountMinor: _minor > 0 ? _minor : null, accountId: _accountId, toAccountId: _toAccountId, categoryId: _categoryId, description: _desc.text.trim(), payee: _payee.text.trim(), tags: List<String>.from(_tags), icon: _l.category(_categoryId)?.icon ?? 'star', color: _l.category(_categoryId)?.color ?? 0xFFFB8C00));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context, 'Plantilla guardada.', 'Template saved.'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final Ledger l = s.ledger;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Account? acc = _account;
    final Account? to = l.account(_toAccountId);
    final Category? cat = l.category(_categoryId);
    final CategoryKind ck = _kind == TxKind.income ? CategoryKind.income : CategoryKind.expense;
    final bool crossCurrency = _kind == TxKind.transfer && acc != null && to != null && acc.currency != to.currency;
    final List<Suggestion> suggestions = _desc.text.trim().length >= 2 && widget.existing == null ? l.suggest(_desc.text, kind: _kind) : <Suggestion>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? t(context, 'Nuevo movimiento', 'New transaction') : t(context, 'Editar movimiento', 'Edit transaction')),
        actions: <Widget>[
          PopupMenuButton<String>(
            onSelected: (String v) async {
              if (v == 'template') {
                await _saveAsTemplate();
              } else if (v == 'delete' && widget.existing != null) {
                if (await confirm(context, t(context, 'Borrar movimiento', 'Delete transaction'), t(context, 'Esta acción no se puede deshacer.', 'This cannot be undone.'), yes: t(context, 'Borrar', 'Delete'))) {
                  await l.deleteTx(widget.existing!.id);
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                }
              } else if (v == 'duplicate' && widget.existing != null) {
                await l.addTx(widget.existing!.copy(id: newId(), date: DateTime.now()));
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(value: 'template', child: Text(t(context, 'Guardar como plantilla', 'Save as template'))),
              if (widget.existing != null) PopupMenuItem<String>(value: 'duplicate', child: Text(t(context, 'Duplicar hoy', 'Duplicate today'))),
              if (widget.existing != null) PopupMenuItem<String>(value: 'delete', child: Text(t(context, 'Borrar', 'Delete'))),
            ],
          ),
          TextButton(onPressed: _saving ? null : _save, child: Text(t(context, 'Guardar', 'Save'))),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: <Widget>[
                SegmentedButton<TxKind>(
                  segments: <ButtonSegment<TxKind>>[
                    ButtonSegment<TxKind>(value: TxKind.expense, label: Text(t(context, 'Gasto', 'Expense')), icon: const Icon(Icons.remove_circle_outline)),
                    ButtonSegment<TxKind>(value: TxKind.income, label: Text(t(context, 'Ingreso', 'Income')), icon: const Icon(Icons.add_circle_outline)),
                    ButtonSegment<TxKind>(value: TxKind.transfer, label: Text(t(context, 'Transf.', 'Transfer')), icon: const Icon(Icons.swap_horiz)),
                  ],
                  selected: <TxKind>{_kind},
                  showSelectedIcon: false,
                  onSelectionChanged: (Set<TxKind> v) => setState(() {
                    _kind = v.first;
                    if (_kind == TxKind.transfer) {
                      _categoryId = null;
                      _splits.clear();
                    } else if (cat != null && cat.kind != ck) {
                      _categoryId = null;
                    }
                  }),
                ),
                const SizedBox(height: 12),
                AmountTile(minor: _minor, currency: _currency, color: kindColor(context, _kind), onTap: () => setState(() => _keypad = !_keypad), label: _calc.expression.isNotEmpty && _calc.hasPendingOp ? _calc.expression : null),
                if (crossCurrency) ...<Widget>[
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.currency_exchange),
                    title: Text('${t(context, 'Monto recibido en', 'Amount received in')} ${to.currency}'),
                    subtitle: Text(_toMinor == null ? t(context, 'Se calcula con la tasa guardada', 'Computed with the saved rate') : Money.format(_toMinor!, to.currency, showCents: true)),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () async {
                      final String? txt = await askText(context, '${t(context, 'Monto en', 'Amount in')} ${to.currency}', initial: _toMinor == null ? '' : Money.format(_toMinor!, to.currency, withSymbol: false, showCents: true), keyboard: const TextInputType.numberWithOptions(decimal: true));
                      if (txt != null) {
                        setState(() => _toMinor = Money.parse(txt));
                      }
                    },
                  ),
                ],
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: acc == null ? const Icon(Icons.account_balance_wallet_outlined) : IconBadge(icon: acc.icon, color: acc.color),
                  title: Text(_kind == TxKind.transfer ? t(context, 'Desde', 'From') : t(context, 'Cuenta', 'Account')),
                  subtitle: Text(acc?.name ?? t(context, 'Elegir', 'Choose')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final Account? a = await pickAccount(context, exclude: _kind == TxKind.transfer ? _toAccountId : null);
                    if (a != null) {
                      setState(() => _accountId = a.id);
                    }
                  },
                ),
                if (_kind == TxKind.transfer)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: to == null ? const Icon(Icons.call_received) : IconBadge(icon: to.icon, color: to.color),
                    title: Text(t(context, 'Hacia', 'To')),
                    subtitle: Text(to?.name ?? t(context, 'Elegir', 'Choose')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final Account? a = await pickAccount(context, exclude: _accountId, title: t(context, 'Cuenta de destino', 'Destination account'));
                      if (a != null) {
                        setState(() => _toAccountId = a.id);
                      }
                    },
                  )
                else if (_splits.isEmpty)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: cat == null ? const Icon(Icons.label_outline) : IconBadge(icon: cat.icon, color: cat.color),
                    title: Text(t(context, 'Categoría', 'Category')),
                    subtitle: Text(cat == null ? t(context, 'Elegir', 'Choose') : l.categoryPath(cat.id)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final Category? c = await pickCategory(context, ck, current: _categoryId);
                      if (c != null) {
                        setState(() => _categoryId = c.id);
                      }
                    },
                  ),
                if (_splits.isNotEmpty) ...<Widget>[
                  Padding(padding: const EdgeInsets.only(top: 8, bottom: 4), child: Text(t(context, 'Dividido entre categorías', 'Split across categories'), style: Theme.of(context).textTheme.titleSmall)),
                  for (int i = 0; i < _splits.length; i++)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: IconBadge(icon: l.category(_splits[i].categoryId)?.icon ?? 'label', color: l.category(_splits[i].categoryId)?.color ?? 0xFF607D8B, size: 32),
                      title: Text(l.categoryPath(_splits[i].categoryId)),
                      subtitle: Text(Money.format(_splits[i].amountMinor, _currency, showCents: s.settings.showCents)),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() {
                          _splits.removeAt(i);
                          _minor = _splits.fold<int>(0, (int a, Split p) => a + p.amountMinor);
                          _calc = Calc(initialMinor: _minor);
                        }),
                      ),
                    ),
                ],
                if (_kind != TxKind.transfer)
                  Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: _addSplit, icon: const Icon(Icons.call_split), label: Text(_splits.isEmpty ? t(context, 'Dividir en varias categorías', 'Split across categories') : t(context, 'Añadir otra parte', 'Add another part')))),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: Text(t(context, 'Fecha', 'Date')),
                  subtitle: Text('${formatDate(_date, 'EEE dd MMM yyyy', spanish: s.settings.spanish)} · ${formatDate(_date, 'HH:mm')}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _pickDate,
                ),
                TextField(
                  controller: _desc,
                  decoration: InputDecoration(labelText: t(context, 'Descripción', 'Description'), border: const OutlineInputBorder(), isDense: true, hintText: t(context, 'Ej.: Mercado D1', 'E.g.: Groceries')),
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}),
                ),
                if (suggestions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: <Widget>[
                        for (final Suggestion sg in suggestions)
                          ActionChip(
                            avatar: Icon(AppIcons.of(l.category(sg.categoryId)?.icon ?? 'label'), size: 16),
                            label: Text(sg.description),
                            onPressed: () => setState(() {
                              _desc.text = sg.description;
                              _desc.selection = TextSelection.collapsed(offset: _desc.text.length);
                              _categoryId ??= sg.categoryId;
                              if (sg.payee.isNotEmpty && _payee.text.isEmpty) {
                                _payee.text = sg.payee;
                              }
                              if (_minor == 0 && sg.amountMinor != null) {
                                _minor = sg.amountMinor!;
                                _calc = Calc(initialMinor: _minor);
                              }
                            }),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                if ((acc?.isCredit ?? false) && _kind == TxKind.expense)
                  Row(
                    children: <Widget>[
                      Expanded(child: Text(t(context, 'Cuotas', 'Installments'))),
                      DropdownButton<int>(
                        value: _installments,
                        items: <DropdownMenuItem<int>>[
                          for (final int n in (<int>{1, 2, 3, 6, 9, 12, 18, 24, 36, 48, _installments}.toList()..sort())) DropdownMenuItem<int>(value: n, child: Text(n == 1 ? t(context, '1 (pago único)', '1 (single)') : '$n')),
                        ],
                        onChanged: (int? v) => setState(() => _installments = v ?? 1),
                      ),
                    ],
                  ),
                TextButton.icon(onPressed: () => setState(() => _more = !_more), icon: Icon(_more ? Icons.expand_less : Icons.expand_more), label: Text(t(context, 'Más campos (beneficiario, etiquetas, notas, recibo)', 'More fields (payee, tags, notes, receipt)'))),
                if (_more) ...<Widget>[
                  TextField(controller: _payee, decoration: InputDecoration(labelText: t(context, 'Beneficiario / comercio', 'Payee / merchant'), border: const OutlineInputBorder(), isDense: true), textCapitalization: TextCapitalization.words),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: <Widget>[
                      for (final String tg in _tags) InputChip(label: Text('#$tg'), onDeleted: () => setState(() => _tags.remove(tg))),
                      for (final String tg in l.allTags.where((String x) => !_tags.contains(x)).take(8)) ActionChip(label: Text('#$tg'), onPressed: () => setState(() => _tags.add(tg))),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      Expanded(child: TextField(controller: _tag, decoration: InputDecoration(hintText: t(context, 'Nueva etiqueta', 'New tag'), isDense: true), onSubmitted: (_) => _addTag())),
                      IconButton(onPressed: _addTag, icon: const Icon(Icons.add_circle_outline)),
                    ],
                  ),
                  TextField(controller: _notes, maxLines: 3, minLines: 1, decoration: InputDecoration(labelText: t(context, 'Notas', 'Notes'), border: const OutlineInputBorder(), isDense: true)),
                  const SizedBox(height: 10),
                  TextField(controller: _check, decoration: InputDecoration(labelText: t(context, 'Número de cheque o referencia', 'Check or reference number'), border: const OutlineInputBorder(), isDense: true)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      for (final String a in _attachments)
                        Stack(
                          children: <Widget>[
                            ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 72, height: 72, child: _AttachmentThumb(relative: a))),
                            Positioned(right: 0, top: 0, child: InkWell(onTap: () => setState(() => _attachments.remove(a)), child: const CircleAvatar(radius: 11, backgroundColor: Colors.black54, child: Icon(Icons.close, size: 14, color: Colors.white)))),
                          ],
                        ),
                      OutlinedButton.icon(onPressed: () => _addAttachment(ImageSource.camera), icon: const Icon(Icons.photo_camera_outlined), label: Text(t(context, 'Foto del recibo', 'Receipt photo'))),
                      OutlinedButton.icon(onPressed: () => _addAttachment(ImageSource.gallery), icon: const Icon(Icons.photo_library_outlined), label: Text(t(context, 'Galería', 'Gallery'))),
                    ],
                  ),
                  if (widget.existing != null)
                    SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(t(context, 'Conciliado con el extracto', 'Reconciled with statement')), value: _reconciled, onChanged: (bool v) => setState(() => _reconciled = v)),
                ],
              ],
            ),
          ),
          if (_keypad)
            Material(
              color: cs.surfaceContainerLow,
              elevation: 8,
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Row(
                        children: <Widget>[
                          Expanded(child: Text(_calc.expression.isEmpty ? '0' : _calc.expression, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600), textAlign: TextAlign.end)),
                          IconButton(onPressed: () => setState(() => _keypad = false), icon: const Icon(Icons.keyboard_hide_outlined)),
                        ],
                      ),
                    ),
                    AmountKeypad(onKey: _onKey, onDone: () => setState(() => _keypad = false), doneLabel: t(context, 'Listo', 'Done'), showDecimal: Money.info(_currency).decimals > 0 || s.settings.showCents),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _addTag() {
    final String v = _tag.text.trim().replaceAll(' ', '_').replaceAll('#', '');
    if (v.isEmpty) {
      return;
    }
    setState(() {
      if (!_tags.contains(v)) {
        _tags.add(v);
      }
      _tag.clear();
    });
  }
}

class _AttachmentThumb extends StatelessWidget {
  const _AttachmentThumb({required this.relative});

  final String relative;

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    return FutureBuilder<String>(
      future: s.store.absolutePath(relative),
      builder: (BuildContext context, AsyncSnapshot<String> snap) {
        if (!snap.hasData) {
          return ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest);
        }
        return GestureDetector(
          onTap: () => showDialog<void>(context: context, builder: (_) => Dialog(child: InteractiveViewer(child: Image.file(File(snap.data!))))),
          child: Image.file(File(snap.data!), fit: BoxFit.cover, cacheWidth: 200, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined)),
        );
      },
    );
  }
}
