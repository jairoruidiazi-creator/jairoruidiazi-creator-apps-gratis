import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/exports.dart';
import '../../core/ledger.dart';
import '../../core/periods.dart';
import '../../core/sharing.dart';
import '../../model/models.dart';
import '../../model/money.dart';
import '../transactions/tx_editor.dart';
import '../transactions/tx_tile.dart';
import '../widgets/adaptive.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/live.dart';

/// Informes: categorías (dona con detalle), tendencia, presupuestos y flujo
/// por cuenta, con exportación CSV/XLSX del periodo.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  static const List<String> _tabsEs = <String>['Categorías', 'Tendencia', 'Presupuestos', 'Cuentas'];
  static const List<String> _tabsEn = <String>['Categories', 'Trend', 'Budgets', 'Accounts'];
  int _shift = 0;
  int _tab = 0;
  CategoryKind _kind = CategoryKind.expense;
  String? _accountId;
  String? _drill;
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    return LiveBuilder(
      listenable: Listenable.merge(<Listenable>[s.ledger, s.settings]),
      builder: (BuildContext context) {
        final Ledger l = s.ledger;
        if (_accountId != null && l.account(_accountId)?.archived != false) {
          _accountId = null;
        }
        final Period period = l.periodSpec.shift(l.periodSpec.containing(clock.now()), _shift);
        return ReadableScaffold(
          appBar: AppBar(
            title: Text(t(context, 'Informes', 'Reports')),
            actions: <Widget>[
              PopupMenuButton<String>(
                tooltip: t(context, 'Exportar', 'Export'),
                icon: const Icon(Icons.ios_share),
                onSelected: (String v) => _export(context, s, period, v),
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(value: 'csv', child: Text(t(context, 'CSV del periodo', 'Period CSV'))),
                  PopupMenuItem<String>(value: 'xlsx', child: Text(t(context, 'Excel del periodo', 'Period Excel'))),
                  PopupMenuItem<String>(value: 'csv_all', child: Text(t(context, 'CSV de todo', 'CSV of everything'))),
                  PopupMenuItem<String>(value: 'xlsx_all', child: Text(t(context, 'Excel de todo', 'Excel of everything'))),
                ],
              ),
            ],
          ),
          body: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: Row(
                  children: <Widget>[
                    IconButton(
                      tooltip: t(context, 'Periodo anterior', 'Previous period'),
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => setState(() {
                        _shift -= 1;
                        _drill = null;
                        _selected = null;
                      }),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() {
                          _shift = 0;
                          _drill = null;
                          _selected = null;
                        }),
                        child: Text(l.periodSpec.label(period, spanish: s.settings.spanish), textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
                      ),
                    ),
                    IconButton(
                      tooltip: t(context, 'Periodo siguiente', 'Next period'),
                      icon: const Icon(Icons.chevron_right),
                      onPressed: _shift >= 0
                          ? null
                          : () => setState(() {
                                _shift += 1;
                                _drill = null;
                                _selected = null;
                              }),
                    ),
                    PopupMenuButton<String>(
                      tooltip: _accountId == null ? t(context, 'Cuenta: todas', 'Account: all') : '${t(context, 'Cuenta', 'Account')}: ${l.account(_accountId)?.name ?? ''}',
                      icon: Icon(_accountId == null ? Icons.account_balance_wallet_outlined : Icons.account_balance_wallet),
                      onSelected: (String v) => setState(() {
                        _accountId = v == '' ? null : v;
                        _drill = null;
                        _selected = null;
                      }),
                      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                        PopupMenuItem<String>(value: '', child: Text(t(context, 'Todas las cuentas', 'All accounts'))),
                        for (final Account a in l.activeAccounts) PopupMenuItem<String>(value: a.id, child: Text(a.name)),
                      ],
                    ),
                  ],
                ),
              ),
              // A todo el ancho: si las secciones no caben en una línea, la
              // segunda arranca alineada a la izquierda con el resto.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 0,
                  children: <Widget>[
                    for (int i = 0; i < _tabsEs.length; i++)
                      ChoiceChip(label: Text(t(context, _tabsEs[i], _tabsEn[i])), selected: _tab == i, onSelected: (_) => setState(() => _tab = i)),
                  ],
                ),
              ),
              Expanded(child: _body(context, l, period)),
            ],
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context, Ledger l, Period period) {
    if (_tab == 0) {
      return _categories(context, l, period);
    }
    if (_tab == 1) {
      return _trend(context, l, period);
    }
    if (_tab == 2) {
      return _budgets(context, l, period);
    }
    return _accounts(context, l, period);
  }

  /// Rótulos del eje de las barras (vacíos si los saldos están ocultos).
  String Function(double) _axis(BuildContext context) {
    final Services s = AppScope.of(context);
    if (s.settings.hideBalances) {
      return (double v) => '';
    }
    final bool es = s.settings.spanish;
    return (double v) => Money.compactNumber(v, spanish: es);
  }

  Widget _categories(BuildContext context, Ledger l, Period period) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final PeriodTotals totals = l.totals(period, accountId: _accountId);
    final List<CategoryTotal> data = _drill == null ? l.byCategory(period, kind: _kind, accountId: _accountId) : _childrenTotals(l, period, _drill!);
    final int total = data.fold<int>(0, (int a, CategoryTotal c) => a + (c.amountMinor > 0 ? c.amountMinor : 0));
    final List<PieSlice> slices = <PieSlice>[
      for (final CategoryTotal c in data) PieSlice(value: c.amountMinor.toDouble(), color: Color(l.category(c.categoryId)?.color ?? 0xFF9E9E9E), label: l.category(c.categoryId)?.name ?? t(context, 'Sin categoría', 'Uncategorized')),
    ];
    final List<Tx> drillTxs = _drill == null ? const <Tx>[] : _txsOf(l, period, _drill!);
    final String kindLabel = _kind == CategoryKind.expense ? t(context, 'Gastos', 'Expenses') : t(context, 'Ingresos', 'Income');
    final String described = <String>[
      '$kindLabel: ${money(context, total, l.baseCurrency)}',
      for (int i = 0; i < data.length && i < 8; i++) '${slices[i].label} ${total == 0 ? 0 : (data[i].amountMinor / total * 100).round()} %',
    ].join('. ');
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      children: <Widget>[
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 4,
          children: <Widget>[
            SegmentedButton<CategoryKind>(
              showSelectedIcon: false,
              segments: <ButtonSegment<CategoryKind>>[
                ButtonSegment<CategoryKind>(value: CategoryKind.expense, label: Text(t(context, 'Gastos', 'Expenses'))),
                ButtonSegment<CategoryKind>(value: CategoryKind.income, label: Text(t(context, 'Ingresos', 'Income'))),
              ],
              selected: <CategoryKind>{_kind},
              onSelectionChanged: (Set<CategoryKind> v) => setState(() {
                _kind = v.first;
                _drill = null;
                _selected = null;
              }),
            ),
            if (_drill != null)
              TextButton.icon(
                onPressed: () => setState(() {
                  _drill = null;
                  _selected = null;
                }),
                icon: const Icon(Icons.arrow_back, size: 18),
                label: Text(t(context, 'Volver', 'Back')),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_drill != null) Text(l.categoryPath(_drill), style: Theme.of(context).textTheme.titleMedium),
        Center(
          child: DonutChart(
            slices: slices,
            size: 200,
            selected: _selected,
            semanticsLabel: described,
            centerTitle: money(context, _selected != null && _selected! < data.length ? data[_selected!].amountMinor : total, l.baseCurrency, compact: true),
            centerSubtitle: _selected != null && _selected! < slices.length ? slices[_selected!].label : (_kind == CategoryKind.expense ? t(context, 'gastos', 'expenses') : t(context, 'ingresos', 'income')),
          ),
        ),
        Text('${t(context, 'Ingresos', 'Income')} ${money(context, totals.incomeMinor, l.baseCurrency, compact: true)} · ${t(context, 'Gastos', 'Expenses')} ${money(context, totals.expenseMinor, l.baseCurrency, compact: true)} · ${t(context, 'Neto', 'Net')} ${money(context, totals.netMinor, l.baseCurrency, compact: true)}', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        if (_kind == CategoryKind.expense)
          Text(t(context, 'Los reembolsos descuentan del gasto de su categoría.', 'Refunds are subtracted from their category spending.'), textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        const SizedBox(height: 8),
        if (data.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(t(context, 'Sin movimientos en este periodo.', 'No transactions in this period.'), textAlign: TextAlign.center)),
        for (int i = 0; i < data.length; i++)
          _CategoryRow(
            total: data[i],
            fraction: total == 0 ? 0 : data[i].amountMinor / total,
            selected: _selected == i,
            onTap: () {
              final String? id = data[i].categoryId;
              if (_drill == null && id != null && l.children(id).isNotEmpty) {
                setState(() {
                  _drill = id;
                  _selected = null;
                });
              } else {
                setState(() => _selected = _selected == i ? null : i);
              }
            },
          ),
        if (_drill != null && drillTxs.isNotEmpty) ...<Widget>[
          const Divider(),
          Text(t(context, 'Movimientos', 'Transactions'), style: Theme.of(context).textTheme.titleMedium),
          for (final Tx tx in drillTxs) TxTile(tx: tx, showDate: true, onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => TxEditor(existing: tx)))),
        ],
      ],
    );
  }

  /// Totales de las subcategorías de [rootId], con la misma regla que la vista
  /// general (los reembolsos descuentan).
  List<CategoryTotal> _childrenTotals(Ledger l, Period period, String rootId) {
    final Set<String> tree = l.categoryTree(rootId);
    return l.byCategory(period, kind: _kind, accountId: _accountId, roots: false).where((CategoryTotal c) => c.categoryId != null && tree.contains(c.categoryId)).toList();
  }

  /// Movimientos que suman (o descuentan) en las categorías de [rootId].
  List<Tx> _txsOf(Ledger l, Period period, String rootId) {
    final Set<String> tree = l.categoryTree(rootId);
    bool counts(Tx tx, String? categoryId) {
      if (categoryId == null || !tree.contains(categoryId)) {
        return false;
      }
      if (_kind == CategoryKind.expense) {
        return tx.kind == TxKind.expense || (tx.kind == TxKind.income && l.isRefundCategory(categoryId));
      }
      return tx.kind == TxKind.income && !l.isRefundCategory(categoryId);
    }

    return l.inPeriod(period, accountId: _accountId).where((Tx tx) {
      if (tx.isNeutral || tx.kind == TxKind.transfer || (_accountId != null && !l.chargesAccount(tx, _accountId!))) {
        return false;
      }
      return tx.splits.isEmpty ? counts(tx, tx.categoryId) : tx.splits.any((TxSplit sp) => counts(tx, sp.categoryId));
    }).toList();
  }

  /// Los 6 periodos que terminan en el elegido con las flechas.
  Widget _trend(BuildContext context, Ledger l, Period period) {
    final bool es = AppScope.of(context).settings.spanish;
    final List<PeriodTotals> data = l.trend(6, now: period.start, accountId: _accountId);
    final List<String> labels = data.map((PeriodTotals p) => l.periodSpec.mode == PeriodMode.quincena ? '${p.period.start.day}–${p.period.lastDay.day} ${formatDate(p.period.start, 'MMM', spanish: es)}' : formatDate(p.period.start, 'MMM', spanish: es)).toList();
    final double avgExpense = data.isEmpty ? 0 : data.fold<int>(0, (int a, PeriodTotals p) => a + p.expenseMinor) / data.length;
    final double avgIncome = data.isEmpty ? 0 : data.fold<int>(0, (int a, PeriodTotals p) => a + p.incomeMinor) / data.length;
    final String incomeWord = t(context, 'ingresos', 'income');
    final String expenseWord = t(context, 'gastos', 'expenses');
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: <Widget>[
        Text(t(context, 'Ingresos y gastos por periodo', 'Income and expenses per period'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        BarsChart(
          groups: <BarGroup>[for (int i = 0; i < data.length; i++) BarGroup(label: labels[i], values: <double>[data[i].incomeMinor / 100, data[i].expenseMinor / 100])],
          colors: <Color>[kindColor(context, TxKind.income), kindColor(context, TxKind.expense)],
          formatValue: _axis(context),
          height: 200,
          semanticsLabel: '${t(context, 'Ingresos y gastos por periodo', 'Income and expenses per period')}. ${<String>[
            for (int i = 0; i < data.length; i++) '${l.periodSpec.label(data[i].period, spanish: es)}: $incomeWord ${money(context, data[i].incomeMinor, l.baseCurrency)}, $expenseWord ${money(context, data[i].expenseMinor, l.baseCurrency)}',
          ].join('. ')}',
        ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 16,
          children: <Widget>[
            _legend(context, kindColor(context, TxKind.income), t(context, 'Ingresos', 'Income')),
            _legend(context, kindColor(context, TxKind.expense), t(context, 'Gastos', 'Expenses')),
          ],
        ),
        const SizedBox(height: 16),
        Text(t(context, 'Neto por periodo', 'Net per period'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        LineChart(
          values: <double>[for (final PeriodTotals p in data) p.netMinor / 100],
          labels: labels,
          height: 150,
          semanticsLabel: '${t(context, 'Neto por periodo', 'Net per period')}. ${<String>[
            for (final PeriodTotals p in data) '${l.periodSpec.label(p.period, spanish: es)}: ${money(context, p.netMinor, l.baseCurrency)}',
          ].join('. ')}',
        ),
        const SizedBox(height: 16),
        Card(
          child: Column(
            children: <Widget>[
              ListTile(dense: true, title: Text(t(context, 'Gasto promedio por periodo', 'Average spending per period')), trailing: Text(money(context, avgExpense.round(), l.baseCurrency), style: const TextStyle(fontWeight: FontWeight.w700))),
              ListTile(dense: true, title: Text(t(context, 'Ingreso promedio por periodo', 'Average income per period')), trailing: Text(money(context, avgIncome.round(), l.baseCurrency), style: const TextStyle(fontWeight: FontWeight.w700))),
              ListTile(dense: true, title: Text(t(context, 'Tasa de ahorro', 'Savings rate')), trailing: Text(avgIncome <= 0 ? '—' : '${((avgIncome - avgExpense) / avgIncome * 100).toStringAsFixed(0)} %', style: const TextStyle(fontWeight: FontWeight.w700))),
            ],
          ),
        ),
        const SizedBox(height: 8),
        for (final PeriodTotals p in data.reversed)
          ListTile(
            dense: true,
            title: Text(l.periodSpec.label(p.period, spanish: es)),
            subtitle: Text('+${money(context, p.incomeMinor, l.baseCurrency, compact: true)} · −${money(context, p.expenseMinor, l.baseCurrency, compact: true)}'),
            trailing: Text(money(context, p.netMinor, l.baseCurrency), style: TextStyle(fontWeight: FontWeight.w700, color: p.netMinor < 0 ? kindColor(context, TxKind.expense) : kindColor(context, TxKind.income))),
          ),
      ],
    );
  }

  Widget _legend(BuildContext context, Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: <Widget>[Container(width: 12, height: 12, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))), const SizedBox(width: 6), Text(label, style: const TextStyle(fontSize: 12))]);

  /// Presupuestos en el periodo elegido con las flechas: el de cada uno que
  /// contiene su último día (o hoy, si es el periodo en curso).
  Widget _budgets(BuildContext context, Ledger l, Period period) {
    final DateTime today = clock.now();
    final DateTime ref = period.contains(today) ? today : period.lastDay;
    final List<BudgetProgress> list = l.budgets.map((Budget b) => l.progress(b, now: ref)).toList();
    if (list.isEmpty) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(t(context, 'Aún no tienes presupuestos. Créalos en la pestaña Presupuestos.', 'No budgets yet. Create them in the Budgets tab.'), textAlign: TextAlign.center)));
    }
    final Color capColor = Theme.of(context).colorScheme.primary.withValues(alpha: 0.5);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: <Widget>[
        BarsChart(
          groups: <BarGroup>[for (final BudgetProgress p in list) BarGroup(label: p.budget.name, values: <double>[p.limitMinor / 100, p.spentMinor / 100])],
          colors: <Color>[capColor, kindColor(context, TxKind.expense)],
          formatValue: _axis(context),
          height: 200,
          semanticsLabel: <String>[
            for (final BudgetProgress p in list) '${p.budget.name}: ${t(context, 'gastado', 'spent')} ${money(context, p.spentMinor, l.baseCurrency)} ${t(context, 'de', 'of')} ${money(context, p.limitMinor, l.baseCurrency)}',
          ].join('. '),
        ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 16,
          children: <Widget>[
            _legend(context, capColor, t(context, 'Tope', 'Cap')),
            _legend(context, kindColor(context, TxKind.expense), t(context, 'Gastado', 'Spent')),
          ],
        ),
        const SizedBox(height: 8),
        for (final BudgetProgress p in list)
          ListTile(
            dense: true,
            leading: Icon(p.over ? Icons.warning_amber : Icons.check_circle_outline, color: p.over ? kindColor(context, TxKind.expense) : kindColor(context, TxKind.income)),
            title: Text(p.budget.name),
            subtitle: Text('${money(context, p.spentMinor, l.baseCurrency)} / ${money(context, p.limitMinor, l.baseCurrency)} · ${(p.fraction * 100).toStringAsFixed(0)} %'),
            trailing: Text(money(context, p.availableMinor, l.baseCurrency, compact: true), style: TextStyle(fontWeight: FontWeight.w700, color: p.over ? kindColor(context, TxKind.expense) : null)),
          ),
      ],
    );
  }

  Widget _accounts(BuildContext context, Ledger l, Period period) {
    final List<AccountFlow> flows = l.cashFlow(period);
    final ColorScheme cs = Theme.of(context).colorScheme;
    // En el periodo en curso el saldo es el de hoy (sin lo que tiene fecha
    // futura); en uno pasado, el del cierre.
    final DateTime tomorrow = addDays(dateOnly(clock.now()), 1);
    final bool current = period.end.isAfter(tomorrow);
    final DateTime limit = current ? tomorrow : period.end;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: <Widget>[
        Text(t(context, 'Entradas y salidas por cuenta', 'In and out per account'), style: Theme.of(context).textTheme.titleMedium),
        Text(t(context, 'Incluye transferencias entre cuentas.', 'Includes transfers between accounts.'), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        const SizedBox(height: 8),
        if (flows.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(t(context, 'Sin movimientos en este periodo.', 'No transactions in this period.'), textAlign: TextAlign.center)),
        for (final AccountFlow f in flows)
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: IconBadge(icon: f.account.icon, color: f.account.color),
                title: Text(f.account.name),
                subtitle: Text('${t(context, 'Entró', 'In')} ${money(context, f.inMinor, f.account.currency, compact: true)} · ${t(context, 'Salió', 'Out')} ${money(context, f.outMinor, f.account.currency, compact: true)}\n${current ? t(context, 'Saldo hoy', 'Balance today') : t(context, 'Saldo al cierre', 'Closing balance')} ${money(context, l.balanceMinor(f.account.id, before: limit), f.account.currency, compact: true)}'),
                trailing: Text(money(context, f.netMinor, f.account.currency, compact: true), style: TextStyle(fontWeight: FontWeight.w700, color: f.netMinor < 0 ? kindColor(context, TxKind.expense) : kindColor(context, TxKind.income))),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _export(BuildContext context, Services s, Period period, String what) async {
    final Ledger l = s.ledger;
    final bool all = what.endsWith('_all');
    final List<Tx> txs = all ? List<Tx>.from(l.txs) : l.inPeriod(period, accountId: _accountId);
    final String stamp = all ? (s.settings.spanish ? 'todo' : 'all') : dayKey(period.start);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String failed = t(context, 'No se pudo exportar. Intenta de nuevo.', 'Could not export. Try again.');
    try {
      if (what.startsWith('csv')) {
        await shareBytes(s.store, 'plata-$stamp.csv', Exports.csvBytes(l, txs, spanish: s.settings.spanish), text: 'Plata CSV');
      } else {
        await shareBytes(s.store, 'plata-$stamp.xlsx', Exports.xlsx(l, txs, spanish: s.settings.spanish), text: 'Plata XLSX');
      }
    } catch (e) {
      debugPrint('Exportar: $e');
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.total, required this.fraction, required this.selected, required this.onTap});

  final CategoryTotal total;
  final double fraction;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Ledger l = AppScope.of(context).ledger;
    final Category? c = l.category(total.categoryId);
    final Color color = Color(c?.color ?? 0xFF9E9E9E);
    return ListTile(
      dense: true,
      selected: selected,
      leading: c == null ? const CircleAvatar(child: Icon(Icons.help_outline)) : IconBadge(icon: c.icon, color: c.color, size: 34),
      title: Row(
        children: <Widget>[
          Expanded(child: Text(c?.name ?? t(context, 'Sin categoría', 'Uncategorized'), maxLines: 2, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          Flexible(child: Text(money(context, total.amountMinor, l.baseCurrency), textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w700))),
        ],
      ),
      subtitle: Row(
        children: <Widget>[
          Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: fraction.clamp(0.0, 1.0), color: color, backgroundColor: color.withValues(alpha: 0.15), minHeight: 5))),
          const SizedBox(width: 8),
          Text('${(fraction * 100).toStringAsFixed(0)} %', style: const TextStyle(fontSize: 12)),
          if (c != null && l.children(c.id).isNotEmpty && total.categoryId != null) Icon(Icons.chevron_right, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant) else const SizedBox(width: 16),
        ],
      ),
      onTap: onTap,
    );
  }
}
