import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/ledger.dart';
import '../../core/periods.dart';
import '../../model/models.dart';
import '../widgets/adaptive.dart';
import '../widgets/common.dart';
import 'tx_editor.dart';
import 'tx_tile.dart';

/// Movimientos: lista por día con búsqueda y filtros, o calendario mensual.
class TxListScreen extends StatefulWidget {
  const TxListScreen({super.key, this.initialFilter});

  final TxFilter? initialFilter;

  @override
  State<TxListScreen> createState() => _TxListScreenState();
}

class _TxListScreenState extends State<TxListScreen> {
  late TxFilter _filter = widget.initialFilter ?? const TxFilter();
  final TextEditingController _search = TextEditingController();
  bool _calendar = false;
  DateTime _month = DateTime(clock.now().year, clock.now().month);
  DateTime? _selectedDay;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    return ListenableBuilder(
      listenable: s.ledger,
      builder: (BuildContext context, Widget? _) {
        final Ledger l = s.ledger;
        final List<Tx> all = l.search(_filter);
        // Sin barra de título propia: en la pestaña el buscador debe quedar
        // debajo de la barra de estado (al abrirse desde otra pantalla, el
        // Scaffold de afuera ya quitó ese margen y SafeArea no suma nada).
        return ReadableScaffold(
          body: SafeArea(
            bottom: false,
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _search,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search),
                            hintText: t(context, 'Buscar descripción, comercio, nota, monto…', 'Search description, payee, note, amount…'),
                            isDense: true,
                            border: const OutlineInputBorder(),
                            suffixIcon: _filter.text.isEmpty ? null : IconButton(icon: const Icon(Icons.clear), onPressed: () { _search.clear(); setState(() => _filter = _filter.copyWith(text: '')); }),
                          ),
                          onChanged: (String v) => setState(() => _filter = _filter.copyWith(text: v)),
                        ),
                      ),
                      IconButton(
                        tooltip: t(context, 'Filtros', 'Filters'),
                        icon: Badge(isLabelVisible: !_filter.copyWith(text: '').isEmpty, child: const Icon(Icons.tune)),
                        onPressed: () async {
                          final TxFilter? f = await showFilterSheet(context, _filter);
                          if (f != null) {
                            setState(() => _filter = f);
                          }
                        },
                      ),
                      IconButton(
                        tooltip: _calendar ? t(context, 'Lista', 'List') : t(context, 'Calendario', 'Calendar'),
                        icon: Icon(_calendar ? Icons.view_list_outlined : Icons.calendar_month_outlined),
                        onPressed: () => setState(() {
                          _calendar = !_calendar;
                          // El calendario abre con el día de hoy elegido y sus movimientos abajo.
                          if (_calendar && _selectedDay == null) {
                            final DateTime now = clock.now();
                            _month = DateTime(now.year, now.month);
                            _selectedDay = dateOnly(now);
                          }
                        }),
                      ),
                    ],
                  ),
                ),
                Expanded(child: _calendar ? _calendarView(context, l, all) : _listView(context, l, all)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _listView(BuildContext context, Ledger l, List<Tx> list) {
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l.txs.isEmpty ? t(context, 'Aún no hay movimientos. Toca + para anotar el primero.', 'No transactions yet. Tap + to add the first one.') : t(context, 'Nada coincide con la búsqueda.', 'Nothing matches your search.'), textAlign: TextAlign.center),
        ),
      );
    }
    // Agrupadas por día con el total del día (gastos e ingresos en moneda base).
    final List<Object> items = <Object>[];
    String? lastKey;
    final Map<String, int> dayNet = <String, int>{};
    for (final Tx tx in list) {
      if (tx.kind != TxKind.transfer) {
        dayNet[tx.dayKey] = (dayNet[tx.dayKey] ?? 0) + (tx.kind == TxKind.income ? 1 : -1) * l.toBase(tx.amountMinor, tx.currency, rate: tx.rateToBase);
      }
    }
    for (final Tx tx in list) {
      if (tx.dayKey != lastKey) {
        items.add(tx.date);
        lastKey = tx.dayKey;
      }
      items.add(tx);
    }
    final int income = list.where((Tx x) => x.kind == TxKind.income).fold<int>(0, (int a, Tx x) => a + l.toBase(x.amountMinor, x.currency, rate: x.rateToBase));
    final int expense = list.where((Tx x) => x.kind == TxKind.expense).fold<int>(0, (int a, Tx x) => a + l.toBase(x.amountMinor, x.currency, rate: x.rateToBase));
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: items.length + 1,
      itemBuilder: (BuildContext context, int i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Row(
              children: <Widget>[
                Expanded(child: Text('${list.length} ${t(context, 'movimientos', 'transactions')}', style: Theme.of(context).textTheme.bodySmall)),
                Text('+${money(context, income, l.baseCurrency, compact: true)}  −${money(context, expense, l.baseCurrency, compact: true)}', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          );
        }
        final Object it = items[i - 1];
        if (it is DateTime) {
          final int net = dayNet[dayKey(it)] ?? 0;
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
            child: Row(
              children: <Widget>[
                Expanded(child: Text(_dayLabel(context, it), style: Theme.of(context).textTheme.labelLarge)),
                Text(money(context, net, l.baseCurrency), style: TextStyle(fontSize: 12, color: net >= 0 ? kindColor(context, TxKind.income) : kindColor(context, TxKind.expense))),
              ],
            ),
          );
        }
        final Tx tx = it as Tx;
        return TxTile(tx: tx, onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TxEditor(existing: tx))));
      },
    );
  }

  String _dayLabel(BuildContext context, DateTime d) {
    final DateTime today = dateOnly(clock.now());
    final DateTime day = dateOnly(d);
    final bool spanish = AppScope.of(context).settings.spanish;
    if (day == today) {
      return t(context, 'Hoy', 'Today');
    }
    if (day == today.subtract(const Duration(days: 1))) {
      return t(context, 'Ayer', 'Yesterday');
    }
    return formatDate(d, day.year == today.year ? 'EEE dd MMM' : 'EEE dd MMM yyyy', spanish: spanish);
  }

  Widget _calendarView(BuildContext context, Ledger l, List<Tx> list) {
    final bool spanish = AppScope.of(context).settings.spanish;
    final Map<String, List<Tx>> byDay = <String, List<Tx>>{};
    for (final Tx tx in list) {
      byDay.putIfAbsent(tx.dayKey, () => <Tx>[]).add(tx);
    }
    final DateTime first = DateTime(_month.year, _month.month);
    final int daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final int leading = (first.weekday + 6) % 7; // lunes = 0
    final List<Scheduled> upcoming = l.scheduled.where((Scheduled sc) => sc.enabled).toList();
    final List<Tx> selected = _selectedDay == null ? <Tx>[] : (byDay[dayKey(_selectedDay!)] ?? <Tx>[]);
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            IconButton(onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)), icon: const Icon(Icons.chevron_left)),
            Expanded(child: Text(monthName(_month, spanish: spanish), textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium)),
            IconButton(onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1)), icon: const Icon(Icons.chevron_right)),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: <Widget>[
              for (final String d in spanish ? <String>['L', 'M', 'X', 'J', 'V', 'S', 'D'] : <String>['M', 'T', 'W', 'T', 'F', 'S', 'S']) Expanded(child: Text(d, textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelSmall)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, childAspectRatio: 0.9),
            itemCount: leading + daysInMonth,
            itemBuilder: (BuildContext context, int i) {
              if (i < leading) {
                return const SizedBox.shrink();
              }
              final DateTime day = DateTime(_month.year, _month.month, i - leading + 1);
              final List<Tx> txs = byDay[dayKey(day)] ?? <Tx>[];
              int net = 0;
              for (final Tx tx in txs) {
                if (tx.kind != TxKind.transfer) {
                  net += (tx.kind == TxKind.income ? 1 : -1) * l.toBase(tx.amountMinor, tx.currency, rate: tx.rateToBase);
                }
              }
              final bool hasBill = upcoming.any((Scheduled sc) => dateOnly(sc.nextDate) == day);
              final bool sel = _selectedDay != null && dateOnly(_selectedDay!) == day;
              final bool today = dateOnly(clock.now()) == day;
              return InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() => _selectedDay = day),
                child: Container(
                  margin: const EdgeInsets.all(1.5),
                  decoration: BoxDecoration(color: sel ? Theme.of(context).colorScheme.primaryContainer : null, borderRadius: BorderRadius.circular(8), border: today ? Border.all(color: Theme.of(context).colorScheme.primary) : null),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text('${day.day}', style: TextStyle(fontWeight: today ? FontWeight.w800 : FontWeight.w500, fontSize: 13)),
                      if (txs.isNotEmpty) Text(money(context, net, l.baseCurrency, compact: true, withSymbol: false), style: TextStyle(fontSize: 9, color: net >= 0 ? kindColor(context, TxKind.income) : kindColor(context, TxKind.expense)), maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (hasBill) Icon(Icons.notifications_active_outlined, size: 10, color: Theme.of(context).colorScheme.secondary),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _selectedDay == null
              ? Center(child: Text(t(context, 'Toca un día para ver sus movimientos.', 'Tap a day to see its transactions.'), style: Theme.of(context).textTheme.bodySmall))
              : ListView(
                  padding: const EdgeInsets.only(bottom: 96),
                  children: <Widget>[
                    for (final Scheduled sc in upcoming.where((Scheduled x) => dateOnly(x.nextDate) == dateOnly(_selectedDay!)))
                      ListTile(
                        leading: const Icon(Icons.event_repeat),
                        title: Text(sc.name),
                        subtitle: Text(t(context, 'Programado', 'Scheduled')),
                        trailing: Text(money(context, sc.amountMinor, l.account(sc.accountId)?.currency ?? l.baseCurrency)),
                      ),
                    for (final Tx tx in selected) TxTile(tx: tx, onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TxEditor(existing: tx)))),
                    if (selected.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TxEditor(initialDate: DateTime(_selectedDay!.year, _selectedDay!.month, _selectedDay!.day, 12)))),
                          icon: const Icon(Icons.add),
                          label: Text(t(context, 'Anotar en este día', 'Add on this day')),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Hoja de filtros avanzados.
Future<TxFilter?> showFilterSheet(BuildContext context, TxFilter current) {
  return showModalBottomSheet<TxFilter>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) => _FilterSheet(initial: current),
  );
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.initial});

  final TxFilter initial;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late TxFilter _f = widget.initial;

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final Ledger l = s.ledger;
    final TextTheme tt = Theme.of(context).textTheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (BuildContext context, ScrollController sc) => Column(
        children: <Widget>[
          Expanded(
            child: ListView(
        controller: sc,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(t(context, 'Filtros', 'Filters'), style: tt.titleLarge)),
              TextButton(onPressed: () => setState(() => _f = TxFilter(text: _f.text)), child: Text(t(context, 'Limpiar', 'Clear'))),
            ],
          ),
          Text(t(context, 'Tipo', 'Type'), style: tt.titleSmall),
          Wrap(
            spacing: 6,
            children: <Widget>[
              for (final TxKind k in TxKind.values)
                FilterChip(label: Text(kindName(context, k)), selected: _f.kinds.contains(k), onSelected: (bool v) => setState(() => _f = _f.copyWith(kinds: v ? <TxKind>{..._f.kinds, k} : (<TxKind>{..._f.kinds}..remove(k))))),
            ],
          ),
          const SizedBox(height: 8),
          Text(t(context, 'Cuentas', 'Accounts'), style: tt.titleSmall),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: <Widget>[
              for (final Account a in l.activeAccounts)
                FilterChip(label: Text(a.name), selected: _f.accountIds.contains(a.id), onSelected: (bool v) => setState(() => _f = _f.copyWith(accountIds: v ? <String>{..._f.accountIds, a.id} : (<String>{..._f.accountIds}..remove(a.id))))),
            ],
          ),
          const SizedBox(height: 8),
          Text(t(context, 'Categorías', 'Categories'), style: tt.titleSmall),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: <Widget>[
              for (final Category c in <Category>[...l.roots(CategoryKind.expense), ...l.roots(CategoryKind.income)])
                FilterChip(
                  label: Text(c.name),
                  selected: _f.categoryIds.contains(c.id),
                  onSelected: (bool v) => setState(() {
                    final Set<String> ids = <String>{..._f.categoryIds};
                    final Set<String> tree = l.categoryTree(c.id);
                    if (v) {
                      ids.addAll(tree);
                    } else {
                      ids.removeAll(tree);
                    }
                    _f = _f.copyWith(categoryIds: ids);
                  }),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(t(context, 'Fechas', 'Dates'), style: tt.titleSmall),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: <Widget>[
              ActionChip(
                avatar: const Icon(Icons.event, size: 16),
                label: Text(_f.from == null ? t(context, 'Desde', 'From') : formatDate(_f.from!, 'dd MMM yyyy', spanish: s.settings.spanish)),
                onPressed: () async {
                  final DateTime? d = await showDatePicker(context: context, initialDate: _f.from ?? clock.now(), firstDate: DateTime(2000), lastDate: DateTime(2100));
                  if (d != null) {
                    setState(() => _f = _f.copyWith(from: d));
                  }
                },
              ),
              ActionChip(
                avatar: const Icon(Icons.event, size: 16),
                label: Text(_f.to == null ? t(context, 'Hasta', 'To') : formatDate(_f.to!, 'dd MMM yyyy', spanish: s.settings.spanish)),
                onPressed: () async {
                  final DateTime? d = await showDatePicker(context: context, initialDate: _f.to ?? clock.now(), firstDate: DateTime(2000), lastDate: DateTime(2100));
                  if (d != null) {
                    setState(() => _f = _f.copyWith(to: d));
                  }
                },
              ),
              for (final List<Object> q in <List<Object>>[
                <Object>[t(context, 'Este periodo', 'This period'), 0],
                <Object>[t(context, 'Periodo anterior', 'Last period'), -1],
                <Object>[t(context, 'Este año', 'This year'), 'year'],
              ])
                ActionChip(
                  label: Text(q[0] as String),
                  onPressed: () => setState(() {
                    if (q[1] == 'year') {
                      _f = _f.copyWith(from: DateTime(clock.now().year), to: DateTime(clock.now().year, 12, 31));
                    } else {
                      final Period p = l.periodSpec.shift(l.periodSpec.containing(clock.now()), q[1] as int);
                      _f = _f.copyWith(from: p.start, to: p.lastDay);
                    }
                  }),
                ),
              if (_f.from != null || _f.to != null) ActionChip(avatar: const Icon(Icons.clear, size: 16), label: Text(t(context, 'Quitar fechas', 'Clear dates')), onPressed: () => setState(() => _f = _f.copyWith(clearDates: true))),
            ],
          ),
          const SizedBox(height: 8),
          Text(t(context, 'Monto', 'Amount'), style: tt.titleSmall),
          Row(
            children: <Widget>[
              Expanded(child: TextFormField(initialValue: _f.minMinor == null ? '' : (_f.minMinor! ~/ 100).toString(), decoration: InputDecoration(labelText: t(context, 'Mínimo', 'Min'), isDense: true), keyboardType: TextInputType.number, onChanged: (String v) => setState(() => _f = _f.copyWith(minMinor: v.isEmpty ? null : (int.tryParse(v.replaceAll('.', '')) ?? 0) * 100, clearMin: v.isEmpty)))),
              const SizedBox(width: 12),
              Expanded(child: TextFormField(initialValue: _f.maxMinor == null ? '' : (_f.maxMinor! ~/ 100).toString(), decoration: InputDecoration(labelText: t(context, 'Máximo', 'Max'), isDense: true), keyboardType: TextInputType.number, onChanged: (String v) => setState(() => _f = _f.copyWith(maxMinor: v.isEmpty ? null : (int.tryParse(v.replaceAll('.', '')) ?? 0) * 100, clearMax: v.isEmpty)))),
            ],
          ),
          const SizedBox(height: 8),
          if (l.allTags.isNotEmpty) ...<Widget>[
            Text(t(context, 'Etiquetas', 'Tags'), style: tt.titleSmall),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: <Widget>[
                for (final String tg in l.allTags) FilterChip(label: Text('#$tg'), selected: _f.tags.contains(tg), onSelected: (bool v) => setState(() => _f = _f.copyWith(tags: v ? <String>{..._f.tags, tg} : (<String>{..._f.tags}..remove(tg))))),
              ],
            ),
          ],
          SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(t(context, 'Solo con foto de recibo', 'Only with receipt photo')), value: _f.onlyWithAttachment, onChanged: (bool v) => setState(() => _f = _f.copyWith(onlyWithAttachment: v))),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(t(context, 'Solo sin categoría', 'Only uncategorized')), value: _f.onlyUncategorized, onChanged: (bool v) => setState(() => _f = _f.copyWith(onlyUncategorized: v))),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(t(context, 'Solo sin conciliar', 'Only unreconciled')), value: _f.onlyUnreconciled, onChanged: (bool v) => setState(() => _f = _f.copyWith(onlyUnreconciled: v))),
        ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton(onPressed: () => Navigator.pop(context, _f), child: Text(t(context, 'Aplicar', 'Apply'))),
            ),
          ),
        ],
      ),
    );
  }
}
