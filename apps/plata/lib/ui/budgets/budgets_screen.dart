import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/ledger.dart';
import '../../core/periods.dart';
import '../../model/models.dart';
import '../transactions/tx_editor.dart';
import '../transactions/tx_tile.dart';
import '../widgets/adaptive.dart';
import '../widgets/common.dart';
import '../widgets/icons.dart';
import '../widgets/live.dart';

/// Presupuestos por categoría (o globales) con avance del periodo.
class BudgetsScreen extends StatelessWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    return LiveBuilder(
      listenable: Listenable.merge(<Listenable>[s.ledger, s.settings]),
      builder: (BuildContext context) {
        final Ledger l = s.ledger;
        final List<BudgetProgress> list = l.budgets.map((Budget b) => l.progress(b)).toList();
        final int totalLimit = list.fold<int>(0, (int a, BudgetProgress p) => a + p.limitMinor);
        final int totalSpent = list.fold<int>(0, (int a, BudgetProgress p) => a + p.spentMinor);
        // El total solo se muestra si no cuenta dos veces el mismo gasto
        // (presupuestos que se cruzan o de periodos distintos).
        final bool summable = l.canSumBudgets(list);
        return ReadableScaffold(
          appBar: AppBar(title: Text(t(context, 'Presupuestos', 'Budgets'))),
          floatingActionButton: FloatingActionButton.extended(
            heroTag: null,
            onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const BudgetEditor())),
            icon: const Icon(Icons.add),
            label: Text(t(context, 'Presupuesto', 'Budget')),
          ),
          body: list.isEmpty
              ? Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(Icons.savings_outlined, size: 56),
                        const SizedBox(height: 12),
                        Text(t(context, 'Ponle un tope a una categoría (mercado, salidas) o a todo el mes y mira cuánto te queda.', 'Cap a category (groceries, going out) or the whole month and see what is left.'), textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                  children: <Widget>[
                    if (summable) _totalCard(context, l, totalSpent, totalLimit),
                    for (final BudgetProgress p in list) _BudgetCard(progress: p),
                  ],
                ),
        );
      },
    );
  }

  /// Resumen de todos los presupuestos, con lo disponible rotulado igual que
  /// en cada tarjeta.
  Widget _totalCard(BuildContext context, Ledger l, int totalSpent, int totalLimit) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool over = totalSpent > totalLimit;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(t(context, 'Total presupuestado', 'Total budgeted'), style: Theme.of(context).textTheme.titleMedium),
                  Text('${money(context, totalSpent, l.baseCurrency)} ${t(context, 'gastado de', 'spent of')} ${money(context, totalLimit, l.baseCurrency)}', style: TextStyle(color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(money(context, totalLimit - totalSpent, l.baseCurrency, compact: true), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: over ? kindColor(context, TxKind.expense) : cs.primary)),
                Text(over ? t(context, 'excedido', 'over') : t(context, 'disponible', 'left'), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({required this.progress});

  final BudgetProgress progress;

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final Ledger l = s.ledger;
    final Budget b = progress.budget;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Color color = progress.over ? kindColor(context, TxKind.expense) : (progress.fraction > 0.85 ? warnColor(context) : cs.primary);
    final int daysLeft = daysBetween(clock.now(), progress.period.end);
    final int perDay = daysLeft > 0 && progress.availableMinor > 0 ? progress.availableMinor ~/ daysLeft : 0;
    final String cats = b.categoryIds.isEmpty ? t(context, 'Todos los gastos', 'All expenses') : b.categoryIds.map((String id) => l.category(id)?.name ?? '?').join(', ');
    final Category? first = b.categoryIds.isEmpty ? null : l.category(b.categoryIds.first);
    final String days = daysLeft > 0 ? (daysLeft == 1 ? t(context, 'queda 1 día', '1 day left') : t(context, 'quedan $daysLeft días', '$daysLeft days left')) : '';
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => BudgetEditor(existing: b))),
        child: Padding(
          // Abajo poco margen: el botón "Ver movimientos" ya trae su propia
          // área de toque de 48 dp.
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  IconBadge(icon: first?.icon ?? 'savings', color: first?.color ?? 0xFF00897B, size: 36),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(b.name, style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
                        Text('$cats${b.accountId != null ? ' · ${l.account(b.accountId)?.name ?? ''}' : ''}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Text(money(context, progress.availableMinor, l.baseCurrency, compact: true), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: color)),
                      Text(progress.over ? t(context, 'excedido', 'over') : t(context, 'disponible', 'left'), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Semantics(
                label: '${(progress.fraction * 100).round()} % ${t(context, 'usado', 'used')}',
                child: ExcludeSemantics(child: ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: progress.fraction.clamp(0.0, 1.0), color: color, minHeight: 10))),
              ),
              const SizedBox(height: 6),
              Text('${money(context, progress.spentMinor, l.baseCurrency)} / ${money(context, progress.limitMinor, l.baseCurrency)}${progress.carryMinor != 0 ? ' (${progress.carryMinor > 0 ? '+' : ''}${money(context, progress.carryMinor, l.baseCurrency, compact: true)} ${t(context, 'arrastre', 'rollover')})' : ''}', style: const TextStyle(fontSize: 12)),
              Text(<String>[_periodLabel(context, b, progress.period), if (days.isNotEmpty) days, if (perDay > 0) '${money(context, perDay, l.baseCurrency, compact: true)} ${t(context, 'al día', 'a day')}'].join(' · '), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => BudgetTxsScreen(budget: b, period: progress.period))),
                  icon: const Icon(Icons.list_alt, size: 18),
                  label: Text(t(context, 'Ver movimientos', 'See transactions')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _periodLabel(BuildContext context, Budget b, Period p) {
    final bool es = AppScope.of(context).settings.spanish;
    switch (b.period) {
      case BudgetPeriod.week:
        return '${formatDate(p.start, 'dd MMM', spanish: es)}–${formatDate(p.lastDay, 'dd MMM', spanish: es)}';
      case BudgetPeriod.quincena:
        return '${p.start.day}–${p.lastDay.day} ${formatDate(p.start, 'MMM', spanish: es)}';
      case BudgetPeriod.month:
        return p.start.day == 1 ? formatDate(p.start, 'MMM yyyy', spanish: es) : '${formatDate(p.start, 'dd MMM', spanish: es)}–${formatDate(p.lastDay, 'dd MMM', spanish: es)}';
      case BudgetPeriod.year:
        return '${p.start.year}';
      case BudgetPeriod.custom:
        return '${formatDate(p.start, 'dd MMM', spanish: es)}–${formatDate(p.lastDay, 'dd MMM', spanish: es)}';
    }
  }
}

/// Los movimientos que cuentan en un presupuesto durante su periodo, con la
/// misma regla del cálculo: subcategorías incluidas y reembolsos restando.
class BudgetTxsScreen extends StatelessWidget {
  const BudgetTxsScreen({super.key, required this.budget, required this.period});

  final Budget budget;
  final Period period;

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    return ListenableBuilder(
      listenable: s.ledger,
      builder: (BuildContext context, Widget? _) {
        final Ledger l = s.ledger;
        final List<Tx> list = l.budgetTxs(budget, period);
        final int spent = l.budgetSpent(budget, period);
        final bool es = s.settings.spanish;
        return ReadableScaffold(
          appBar: AppBar(title: Text(budget.name)),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text(
                  '${formatDate(period.start, 'dd MMM', spanish: es)}–${formatDate(period.lastDay, 'dd MMM yyyy', spanish: es)} · ${t(context, 'gastado', 'spent')} ${money(context, spent, l.baseCurrency)}${list.any((Tx x) => x.kind == TxKind.income) ? t(context, ' (los reembolsos restan)', ' (refunds subtract)') : ''}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              if (list.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(t(context, 'Nada cuenta en este presupuesto todavía.', 'Nothing counts toward this budget yet.'), textAlign: TextAlign.center)),
              for (final Tx tx in list) TxTile(tx: tx, showDate: true, onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => TxEditor(existing: tx)))),
            ],
          ),
        );
      },
    );
  }
}

String budgetPeriodName(BuildContext context, BudgetPeriod p) {
  switch (p) {
    case BudgetPeriod.week:
      return t(context, 'Semanal', 'Weekly');
    case BudgetPeriod.quincena:
      return t(context, 'Quincenal', 'Twice a month');
    case BudgetPeriod.month:
      return t(context, 'Mensual', 'Monthly');
    case BudgetPeriod.year:
      return t(context, 'Anual', 'Yearly');
    case BudgetPeriod.custom:
      return t(context, 'Personalizado (días)', 'Custom (days)');
  }
}

/// Alta y edición de un presupuesto.
class BudgetEditor extends StatefulWidget {
  const BudgetEditor({super.key, this.existing});

  final Budget? existing;

  @override
  State<BudgetEditor> createState() => _BudgetEditorState();
}

class _BudgetEditorState extends State<BudgetEditor> {
  late final TextEditingController _name = TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _days = TextEditingController(text: '${widget.existing?.customDays ?? 30}');
  late final TextEditingController _notes = TextEditingController(text: widget.existing?.notes ?? '');
  late int _amount = widget.existing?.amountMinor ?? 0;
  late final Set<String> _cats = widget.existing?.categoryIds.toSet() ?? <String>{};
  late String? _accountId = widget.existing?.accountId;
  late BudgetPeriod _period = widget.existing?.period ?? BudgetPeriod.month;
  late DateTime _start = widget.existing?.startDate ?? DateTime(clock.now().year, clock.now().month);
  late bool _rollover = widget.existing?.rollover ?? false;

  @override
  void dispose() {
    disposeLater(<ChangeNotifier>[_name, _days, _notes]);
    super.dispose();
  }

  Future<void> _save() async {
    final Services s = AppScope.of(context);
    final Ledger l = s.ledger;
    if (_amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context, 'Indica un monto mayor que cero.', 'Enter an amount greater than zero.'))));
      return;
    }
    String name = _name.text.trim();
    if (name.isEmpty) {
      name = _cats.isEmpty ? t(context, 'Gasto total', 'Total spending') : _cats.map((String id) => l.category(id)?.name ?? '').join(', ');
    }
    final Budget? e = widget.existing;
    if (e == null) {
      await l.addBudget(Budget(id: newId(), name: name, amountMinor: _amount, categoryIds: _cats.toList(), accountId: _accountId, period: _period, customDays: int.tryParse(_days.text) ?? 30, startDate: _start, rollover: _rollover, notes: _notes.text.trim()));
    } else {
      e
        ..name = name
        ..accountId = _accountId
        ..period = _period
        ..customDays = int.tryParse(_days.text) ?? 30
        ..startDate = _start
        ..rollover = _rollover
        ..notes = _notes.text.trim();
      e.categoryIds
        ..clear()
        ..addAll(_cats);
      // El tope nuevo vale desde el periodo en curso: los anteriores (y su
      // arrastre) conservan el que tenían.
      e.changeAmount(_amount, from: BudgetPeriods.containing(e, clock.now()).start);
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
    final ColorScheme cs = Theme.of(context).colorScheme;
    return ReadableScaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? t(context, 'Nuevo presupuesto', 'New budget') : t(context, 'Presupuesto', 'Budget')),
        actions: <Widget>[
          if (widget.existing != null)
            IconButton(
              tooltip: t(context, 'Eliminar', 'Delete'),
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirm(context, t(context, '¿Eliminar presupuesto?', 'Delete budget?'), t(context, 'Los movimientos no se tocan.', 'Transactions are not affected.'), yes: t(context, 'Eliminar', 'Delete')) && context.mounted) {
                  l.deleteBudget(widget.existing!.id);
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
          AmountTile(
            minor: _amount,
            currency: l.baseCurrency,
            label: t(context, 'Tope por periodo', 'Cap per period'),
            onTap: () async {
              final int? v = await pickAmount(context, initialMinor: _amount, currency: l.baseCurrency, title: t(context, 'Tope del presupuesto', 'Budget cap'));
              if (v != null) {
                setState(() => _amount = v);
              }
            },
          ),
          const SizedBox(height: 12),
          TextField(controller: _name, decoration: InputDecoration(labelText: t(context, 'Nombre (opcional)', 'Name (optional)'), border: const OutlineInputBorder()), textCapitalization: TextCapitalization.sentences),
          const SizedBox(height: 12),
          DropdownButtonFormField<BudgetPeriod>(
            initialValue: _period,
            isExpanded: true,
            decoration: InputDecoration(labelText: t(context, 'Periodo', 'Period'), border: const OutlineInputBorder()),
            items: <DropdownMenuItem<BudgetPeriod>>[for (final BudgetPeriod p in BudgetPeriod.values) DropdownMenuItem<BudgetPeriod>(value: p, child: Text(budgetPeriodName(context, p), overflow: TextOverflow.ellipsis))],
            onChanged: (BudgetPeriod? v) => setState(() => _period = v ?? BudgetPeriod.month),
          ),
          if (_period == BudgetPeriod.custom) ...<Widget>[
            const SizedBox(height: 12),
            TextField(controller: _days, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: t(context, 'Duración en días', 'Length in days'), border: const OutlineInputBorder())),
          ],
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: Text(t(context, 'Empieza', 'Starts')),
            subtitle: Text(formatDate(_start, 'EEE dd MMM yyyy', spanish: s.settings.spanish)),
            trailing: const Icon(Icons.edit_calendar_outlined),
            onTap: () async {
              final DateTime? d = await showDatePicker(context: context, initialDate: _start, firstDate: DateTime(2000), lastDate: DateTime(2100));
              if (d != null) {
                setState(() => _start = dateOnly(d));
              }
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _rollover,
            onChanged: (bool v) => setState(() => _rollover = v),
            title: Text(t(context, 'Arrastrar sobrante', 'Roll over leftovers')),
            subtitle: Text(t(context, 'Lo que no gastes (o te pases) pasa al siguiente periodo.', 'Whatever you do not spend (or overspend) carries to the next period.')),
          ),
          const Divider(),
          Text(t(context, 'Categorías', 'Categories'), style: Theme.of(context).textTheme.titleMedium),
          Text(t(context, 'Sin selección = todos los gastos.', 'None selected = all expenses.'), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          const SizedBox(height: 6),
          for (final Category r in l.roots(CategoryKind.expense)) ...<Widget>[
            FilterChip(
              avatar: Icon(AppIcons.of(r.icon), size: 16, color: Color(r.color)),
              label: Text(r.name),
              selected: _cats.contains(r.id),
              onSelected: (bool v) => setState(() {
                if (v) {
                  _cats.add(r.id);
                  _cats.removeWhere((String id) => l.children(r.id).any((Category c) => c.id == id));
                } else {
                  _cats.remove(r.id);
                }
              }),
            ),
            if (l.children(r.id).isNotEmpty && !_cats.contains(r.id))
              Padding(
                padding: const EdgeInsets.only(left: 20, bottom: 4),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  children: <Widget>[
                    for (final Category c in l.children(r.id))
                      FilterChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(c.name, style: const TextStyle(fontSize: 12)),
                        selected: _cats.contains(c.id),
                        onSelected: (bool v) => setState(() => v ? _cats.add(c.id) : _cats.remove(c.id)),
                      ),
                  ],
                ),
              ),
          ],
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: Text(t(context, 'Solo una cuenta (opcional)', 'Only one account (optional)')),
            subtitle: Text(_accountId == null ? t(context, 'Todas las cuentas', 'All accounts') : (l.account(_accountId)?.name ?? '')),
            trailing: _accountId == null ? const Icon(Icons.chevron_right) : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _accountId = null)),
            onTap: () async {
              final Account? a = await pickAccount(context, title: t(context, 'Cuenta o tarjeta del presupuesto', 'Budget account or card'));
              if (a != null) {
                setState(() => _accountId = a.id);
              }
            },
          ),
          const SizedBox(height: 8),
          TextField(controller: _notes, decoration: InputDecoration(labelText: t(context, 'Notas', 'Notes'), border: const OutlineInputBorder()), maxLines: 2),
        ],
      ),
    );
  }
}
