import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/ledger.dart';
import '../../model/models.dart';
import '../transactions/tx_editor.dart';
import '../widgets/adaptive.dart';
import '../widgets/common.dart';

/// Plantillas (favoritos de un toque).
class TemplatesScreen extends StatelessWidget {
  const TemplatesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    return ListenableBuilder(
      listenable: s.ledger,
      builder: (BuildContext context, Widget? _) {
        final Ledger l = s.ledger;
        final List<TxTemplate> list = List<TxTemplate>.from(l.templates)..sort((TxTemplate a, TxTemplate b) => b.uses.compareTo(a.uses));
        return ReadableScaffold(
          appBar: AppBar(title: Text(t(context, 'Favoritos de un toque', 'One-tap favorites'))),
          floatingActionButton: FloatingActionButton.extended(heroTag: null, onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const TemplateEditor())), icon: const Icon(Icons.add), label: Text(t(context, 'Plantilla', 'Template'))),
          body: list.isEmpty
              ? Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(t(context, 'Una plantilla guarda monto, cuenta y categoría de algo que repites (el bus, el tinto, el almuerzo) para anotarlo con un toque desde Inicio.', 'A template stores the amount, account and category of something you repeat (the bus, coffee, lunch) so you can log it with one tap from Home.'), textAlign: TextAlign.center)))
              : ListView(
                  padding: const EdgeInsets.only(bottom: 96),
                  children: <Widget>[
                    for (final TxTemplate tpl in list)
                      ListTile(
                        leading: IconBadge(icon: tpl.icon, color: tpl.color),
                        title: Text(tpl.name),
                        subtitle: Text(<String>[
                          kindName(context, tpl.kind),
                          if (tpl.accountId != null) l.account(tpl.accountId)?.name ?? '',
                          if (tpl.categoryId != null) l.category(tpl.categoryId)?.name ?? '',
                          '${tpl.uses} ${t(context, 'usos', 'uses')}',
                        ].where((String x) => x.isNotEmpty).join(' · ')),
                        trailing: Text(tpl.amountMinor == null ? t(context, 'pide monto', 'asks amount') : money(context, tpl.amountMinor!, l.account(tpl.accountId)?.currency ?? l.baseCurrency), style: const TextStyle(fontWeight: FontWeight.w700)),
                        onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => TemplateEditor(existing: tpl))),
                      ),
                  ],
                ),
        );
      },
    );
  }
}

/// Edición de una plantilla.
class TemplateEditor extends StatefulWidget {
  const TemplateEditor({super.key, this.existing});

  final TxTemplate? existing;

  @override
  State<TemplateEditor> createState() => _TemplateEditorState();
}

class _TemplateEditorState extends State<TemplateEditor> {
  late final TextEditingController _name = TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _desc = TextEditingController(text: widget.existing?.description ?? '');
  late TxKind _kind = widget.existing?.kind ?? TxKind.expense;
  late int? _amount = widget.existing?.amountMinor;
  late String? _accountId = widget.existing?.accountId;
  late String? _toAccountId = widget.existing?.toAccountId;
  late String? _categoryId = widget.existing?.categoryId;
  late String _icon = widget.existing?.icon ?? 'star';
  late int _color = widget.existing?.color ?? 0xFFFB8C00;

  @override
  void dispose() {
    disposeLater(<ChangeNotifier>[_name, _desc]);
    super.dispose();
  }

  Future<void> _save() async {
    final Ledger l = AppScope.of(context).ledger;
    final String name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context, 'Escribe un nombre.', 'Enter a name.'))));
      return;
    }
    final TxTemplate? e = widget.existing;
    if (e == null) {
      await l.addTemplate(TxTemplate(id: newId(), name: name, kind: _kind, amountMinor: _amount, accountId: _accountId, toAccountId: _toAccountId, categoryId: _categoryId, description: _desc.text.trim(), icon: _icon, color: _color));
    } else {
      e
        ..name = name
        ..kind = _kind
        ..amountMinor = _amount
        ..accountId = _accountId
        ..toAccountId = _toAccountId
        ..categoryId = _categoryId
        ..description = _desc.text.trim()
        ..icon = _icon
        ..color = _color;
      l.save();
    }
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Ledger l = AppScope.of(context).ledger;
    final String currency = l.account(_accountId)?.currency ?? l.baseCurrency;
    return ReadableScaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? t(context, 'Nueva plantilla', 'New template') : t(context, 'Plantilla', 'Template')),
        actions: <Widget>[
          if (widget.existing != null) IconButton(tooltip: t(context, 'Anotar ahora', 'Log now'), icon: const Icon(Icons.bolt), onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => TxEditor(template: widget.existing)))),
          if (widget.existing != null)
            IconButton(
              tooltip: t(context, 'Eliminar', 'Delete'),
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirm(context, t(context, '¿Eliminar plantilla?', 'Delete template?'), '', yes: t(context, 'Eliminar', 'Delete')) && context.mounted) {
                  l.deleteTemplate(widget.existing!.id);
                  Navigator.pop(context);
                }
              },
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
              Expanded(child: TextField(controller: _name, decoration: InputDecoration(labelText: t(context, 'Nombre corto', 'Short name'), border: const OutlineInputBorder()), textCapitalization: TextCapitalization.sentences)),
            ],
          ),
          const SizedBox(height: 12),
          SegmentedButton<TxKind>(
            showSelectedIcon: false,
            segments: <ButtonSegment<TxKind>>[for (final TxKind k in TxKind.values) ButtonSegment<TxKind>(value: k, label: Text(kindName(context, k)))],
            selected: <TxKind>{_kind},
            onSelectionChanged: (Set<TxKind> v) => setState(() {
              _kind = v.first;
              if (_kind == TxKind.transfer) {
                _categoryId = null;
              } else {
                _toAccountId = null;
                final Category? c = l.category(_categoryId);
                if (c != null && c.kind != (_kind == TxKind.expense ? CategoryKind.expense : CategoryKind.income)) {
                  _categoryId = null;
                }
              }
            }),
          ),
          const SizedBox(height: 12),
          AmountTile(
            minor: _amount ?? 0,
            currency: currency,
            label: _amount == null ? t(context, 'Monto (vacío = preguntar cada vez)', 'Amount (empty = ask each time)') : t(context, 'Monto fijo', 'Fixed amount'),
            onTap: () async {
              final int? v = await pickAmount(context, initialMinor: _amount ?? 0, currency: currency);
              if (v != null) {
                setState(() => _amount = v == 0 ? null : v);
              }
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: Text(_kind == TxKind.transfer ? t(context, 'Desde', 'From') : t(context, 'Cuenta', 'Account')),
            subtitle: Text(l.account(_accountId)?.name ?? t(context, 'Preguntar', 'Ask')),
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
              subtitle: Text(l.account(_toAccountId)?.name ?? t(context, 'Preguntar', 'Ask')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final Account? a = await pickAccount(context, exclude: _accountId);
                if (a != null) {
                  setState(() => _toAccountId = a.id);
                }
              },
            )
          else
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
          TextField(controller: _desc, decoration: InputDecoration(labelText: t(context, 'Descripción del movimiento', 'Transaction description'), border: const OutlineInputBorder()), textCapitalization: TextCapitalization.sentences),
          const Divider(height: 24),
          IconColorPicker(icon: _icon, color: _color, onIcon: (String v) => setState(() => _icon = v), onColor: (int v) => setState(() => _color = v)),
        ],
      ),
    );
  }
}
