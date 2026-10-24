import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/bank_rules.dart';
import '../../core/ledger.dart';
import '../../core/periods.dart';
import '../../core/reminders.dart';
import '../../model/models.dart';
import '../more/accounts_screen.dart';
import '../more/cards_screen.dart';
import '../more/currencies_screen.dart';
import '../more/notices_screen.dart';
import '../more/scheduled_screen.dart';
import '../more/templates_screen.dart';
import '../transactions/tx_editor.dart';
import '../transactions/tx_list_screen.dart';
import '../widgets/adaptive.dart';
import '../widgets/common.dart';
import '../widgets/icons.dart';
import '../widgets/live.dart';

/// Inicio: patrimonio, cuentas, resumen del periodo, próximos pagos,
/// avisos bancarios pendientes y favoritos de un toque.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onGoTo});

  /// Cambia de pestaña (0 inicio, 1 movimientos, 2 presupuestos, 3 informes, 4 más).
  final ValueChanged<int> onGoTo;

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    return LiveBuilder(
      listenable: Listenable.merge(<Listenable>[s.ledger, s.settings]),
      builder: (BuildContext context) {
        final Ledger l = s.ledger;
        final DateTime now = clock.now();
        final Period period = l.periodSpec.containing(now);
        final PeriodTotals totals = l.totals(period);
        final List<Account> visible = l.activeAccounts.where((Account a) => !a.isPocket && !a.isDebit).toList();
        final List<InboxItem> inbox = l.pendingInbox;
        final bool noticesAvailable = defaultTargetPlatform == TargetPlatform.android;
        final List<Scheduled> upcoming = l.upcoming(days: 7, now: now);
        // Una tarjeta aparece si vence en 10 días o menos y, mientras quede
        // algo sin pagar después de la fecha límite, como vencida.
        final List<_CardDue> cardDues = <_CardDue>[
          for (final Account a in l.activeAccounts)
            if (a.isCredit && a.payDay != null)
              _CardDue(a, l.cardDue(a, now: now)),
        ].where((_CardDue c) => c.due.overdue || c.due.unconfirmed || (c.statement.dueMinor > 0 && daysBetween(now, c.statement.cycle.payDate) <= 10)).toList();
        final List<BudgetProgress> budgets = l.budgets.map((Budget b) => l.progress(b, now: now)).toList()..sort((BudgetProgress a, BudgetProgress b) => b.fraction.compareTo(a.fraction));
        return ReadableScaffold(
          appBar: AppBar(
            title: const Text('Plata'),
            actions: <Widget>[
              IconButton(
                tooltip: s.settings.hideBalances ? t(context, 'Mostrar saldos', 'Show balances') : t(context, 'Ocultar saldos', 'Hide balances'),
                icon: Icon(s.settings.hideBalances ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                onPressed: () {
                  s.settings.hideBalances = !s.settings.hideBalances;
                  s.settings.save();
                },
              ),
              // Los avisos bancarios solo existen en Android (iOS no deja leer notificaciones).
              if (noticesAvailable)
                IconButton(
                  tooltip: t(context, 'Avisos bancarios', 'Bank notices'),
                  icon: Badge(isLabelVisible: inbox.isNotEmpty, label: Text('${inbox.length}'), child: const Icon(Icons.inbox_outlined)),
                  onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const NoticesScreen())),
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
            children: <Widget>[
              if (!s.settings.onboarded) _welcome(context, s),
              if (s.settings.notificationsAllowed == false && Reminders.wanted(l, s.settings)) _notificationsOff(context),
              // Abonos que Plata tomó por el pago hecho fuera de Plata de un
              // extracto marcado y esperan respuesta: se ven hasta contestar.
              for (final Tx p in l.pendingOutsideMatches()) ...<Widget>[
                OutsideMatchCard(tx: p),
                const SizedBox(height: 8),
              ],
              _netWorth(context, l, period),
              const SizedBox(height: 12),
              _sectionTitle(context, t(context, 'Cuentas', 'Accounts'), action: t(context, 'Ver todas', 'See all'), onAction: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const AccountsScreen()))),
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints box) {
                  // En tableta las tarjetas se ensanchan para que los nombres
                  // largos ("Tarjeta de crédito") no se corten; la cuarta se
                  // asoma para que se note que la fila sigue.
                  final double minWidth = _AccountCard.widthFor(context);
                  final double width = box.maxWidth >= 600 ? math.max(minWidth, (box.maxWidth - 3 * 8) / 3.4) : minWidth;
                  return SizedBox(
                    height: _AccountCard.heightFor(context),
                    child: visible.isEmpty
                        ? Center(child: Text(t(context, 'Sin cuentas', 'No accounts')))
                        : ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: visible.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 8),
                            itemBuilder: (BuildContext context, int i) => _AccountCard(account: visible[i], width: width, onTap: () => _openAccount(context, visible[i])),
                          ),
                  );
                },
              ),
              const SizedBox(height: 12),
              _periodCard(context, l, period, totals, budgets),
              if (noticesAvailable && inbox.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                _sectionTitle(context, t(context, 'Avisos por confirmar', 'Notices to confirm'), action: t(context, 'Ver', 'Open'), onAction: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const NoticesScreen()))),
                for (final InboxItem i in inbox.take(3)) _InboxRow(item: i),
              ],
              if (upcoming.isNotEmpty || cardDues.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                _sectionTitle(context, t(context, 'Próximos pagos', 'Upcoming'), action: t(context, 'Programados', 'Scheduled'), onAction: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const ScheduledScreen()))),
                for (final _CardDue c in cardDues)
                  if (c.due.overdue)
                    ListTile(
                      dense: true,
                      leading: IconBadge(icon: c.account.icon, color: c.account.color, size: 34),
                      title: Text('${t(context, 'Pago', 'Payment')} ${c.account.name}'),
                      subtitle: Text('${overdueLabel(context, c.due.overdueSince!)} · ${t(context, 'falta del pago mínimo', 'left of the minimum payment')}', style: TextStyle(color: kindColor(context, TxKind.expense), fontWeight: FontWeight.w600)),
                      trailing: Text(money(context, c.due.overdueMinor, c.account.currency), style: TextStyle(fontWeight: FontWeight.w700, color: kindColor(context, TxKind.expense))),
                      onTap: () => openCardPayment(context, c.account, c.due.overdueMinor),
                    )
                  else if (c.due.unconfirmed)
                    ListTile(
                      dense: true,
                      leading: IconBadge(icon: c.account.icon, color: c.account.color, size: 34),
                      title: Text('${t(context, 'Pago', 'Payment')} ${c.account.name}'),
                      subtitle: Text(unconfirmedText(context, c.due, c.account.currency)),
                      onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const CardsScreen())),
                    )
                  else
                    ListTile(
                      dense: true,
                      leading: IconBadge(icon: c.account.icon, color: c.account.color, size: 34),
                      title: Text('${t(context, 'Pago', 'Payment')} ${c.account.name}'),
                      subtitle: Text('${t(context, 'Vence', 'Due')} ${payDateText(context, l, c.account, c.statement.cycle.payDate)} · ${t(context, 'capital estimado', 'estimated principal')}'),
                      trailing: Text(money(context, c.statement.dueMinor, c.account.currency), style: const TextStyle(fontWeight: FontWeight.w700)),
                      onTap: () => openCardPayment(context, c.account, c.statement.dueMinor),
                    ),
                for (final Scheduled sch in upcoming.take(5)) _ScheduledRow(item: sch),
              ],
              const SizedBox(height: 12),
              _sectionTitle(context, t(context, 'Favoritos de un toque', 'One-tap favorites'), action: t(context, 'Editar', 'Edit'), onAction: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const TemplatesScreen()))),
              _templates(context, s),
            ],
          ),
        );
      },
    );
  }

  Widget _welcome(BuildContext context, Services s) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(t(context, '¡Bienvenido a Plata!', 'Welcome to Plata!'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(t(
              context,
              'Tus finanzas viven solo en este teléfono, cifradas. Empieza creando tus cuentas (Nequi, Daviplata, banco, efectivo, tarjeta) y anota cada gasto con el botón +. En Más › Seguridad puedes poner una clave.',
              'Your finances live only on this phone, encrypted. Start by creating your accounts (bank, cash, wallet, card) and log each expense with the + button. You can set a passcode under More › Security.',
            )),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: <Widget>[
                FilledButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const AccountsScreen())), icon: const Icon(Icons.account_balance_wallet_outlined), label: Text(t(context, 'Crear cuentas', 'Create accounts'))),
                TextButton(
                  onPressed: () {
                    s.settings.onboarded = true;
                    s.settings.save();
                  },
                  child: Text(t(context, 'Entendido', 'Got it')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Hay recordatorios pero el sistema no deja mostrarlos: se dice aquí,
  /// con un botón para dar el permiso.
  Widget _notificationsOff(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.secondaryContainer,
      child: ListTile(
        leading: Icon(Icons.notifications_off_outlined, color: cs.onSecondaryContainer),
        title: Text(t(context, 'Tus recordatorios no aparecerán', 'Your reminders will not show'), style: TextStyle(color: cs.onSecondaryContainer)),
        subtitle: Text(t(context, 'Las notificaciones de Plata están apagadas.', 'Plata notifications are turned off.'), style: TextStyle(color: cs.onSecondaryContainer)),
        trailing: TextButton(
          onPressed: () => ensureNotifications(context, force: true, why: t(context, 'Para avisarte antes de tus pagos programados y de la fecha límite de tus tarjetas.', 'To remind you before your scheduled payments and card due dates.')),
          child: Text(t(context, 'Activar', 'Turn on')),
        ),
      ),
    );
  }

  Widget _netWorth(BuildContext context, Ledger l, Period period) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final int net = l.netWorthMinor();
    final int debt = l.debtMinor();
    final List<String> missing = l.currenciesWithoutRate();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(t(context, 'Patrimonio neto', 'Net worth'), style: TextStyle(color: cs.onSurfaceVariant)),
                  Text(money(context, net, l.baseCurrency), style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: net < 0 ? kindColor(context, TxKind.expense) : cs.onSurface, fontFeatures: const <FontFeature>[FontFeature.tabularFigures()])),
                  if (debt > 0) Text('${t(context, 'Deudas', 'Debt')}: ${money(context, debt, l.baseCurrency)}', style: TextStyle(color: kindColor(context, TxKind.expense), fontSize: 13)),
                  if (missing.isNotEmpty)
                    InkWell(
                      onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const CurrenciesScreen())),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: <Widget>[
                            Icon(Icons.warning_amber_rounded, size: 16, color: cs.tertiary),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                t(context, 'Sin tasa para ${missing.join(', ')}: se suma 1:1', 'No rate for ${missing.join(', ')}: counted 1:1'),
                                style: TextStyle(color: cs.tertiary, fontSize: 12.5, decoration: TextDecoration.underline, decorationColor: cs.tertiary),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(l.periodSpec.label(period, spanish: l.spanish), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                Text(counted(context, period.days, oneEs: 'día', manyEs: 'días', oneEn: 'day', manyEn: 'days'), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _periodCard(BuildContext context, Ledger l, Period period, PeriodTotals totals, List<BudgetProgress> budgets) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final int daysLeft = daysBetween(clock.now(), period.end);
    final int perDay = daysLeft > 0 ? ((totals.incomeMinor - totals.expenseMinor) / daysLeft).floor() : 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(child: Text(t(context, 'Este periodo', 'This period'), style: Theme.of(context).textTheme.titleMedium)),
                TextButton(onPressed: () => onGoTo(3), child: Text(t(context, 'Informes', 'Reports'))),
              ],
            ),
            Row(
              children: <Widget>[
                Expanded(child: _kpi(context, t(context, 'Ingresos', 'Income'), money(context, totals.incomeMinor, l.baseCurrency, compact: true), kindColor(context, TxKind.income))),
                Expanded(child: _kpi(context, t(context, 'Gastos', 'Expenses'), money(context, totals.expenseMinor, l.baseCurrency, compact: true), kindColor(context, TxKind.expense))),
                Expanded(child: _kpi(context, t(context, 'Neto', 'Net'), money(context, totals.netMinor, l.baseCurrency, compact: true), totals.netMinor < 0 ? kindColor(context, TxKind.expense) : cs.onSurface)),
              ],
            ),
            if (daysLeft > 0 && totals.netMinor > 0) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${daysLeft == 1 ? t(context, 'Te queda 1 día', '1 day left') : t(context, 'Te quedan $daysLeft días', '$daysLeft days left')} · ${money(context, perDay, l.baseCurrency)}/${t(context, 'día', 'day')}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))),
            if (budgets.isNotEmpty) ...<Widget>[
              const Divider(height: 18),
              for (final BudgetProgress p in budgets.take(3)) _BudgetLine(progress: p, homePeriod: period, onTap: () => onGoTo(2)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _kpi(BuildContext context, String label, String value, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color, fontFeatures: const <FontFeature>[FontFeature.tabularFigures()]), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      );

  Widget _templates(BuildContext context, Services s) {
    final List<TxTemplate> list = List<TxTemplate>.from(s.ledger.templates)..sort((TxTemplate a, TxTemplate b) => b.uses.compareTo(a.uses));
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Text(t(context, 'Guarda un movimiento como plantilla (menú ⋮ del editor) y anótalo aquí con un toque.', 'Save a transaction as a template (⋮ menu in the editor) and log it here with one tap.'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: <Widget>[
        for (final TxTemplate tpl in list.take(12))
          ActionChip(
            avatar: Icon(AppIcons.of(tpl.icon), color: Color(tpl.color), size: 18),
            label: Text(tpl.amountMinor == null ? tpl.name : '${tpl.name} · ${money(context, tpl.amountMinor!, s.ledger.account(tpl.accountId)?.currency ?? s.ledger.baseCurrency, compact: true)}'),
            onPressed: () => _applyTemplate(context, s, tpl),
          ),
      ],
    );
  }

  Future<void> _applyTemplate(BuildContext context, Services s, TxTemplate tpl) async {
    // Sin monto, sin cuenta, una transferencia sin destino o entre monedas sin
    // tasa: no se anota a ciegas, se abre el editor con la plantilla.
    final Tx? tx = s.ledger.account(tpl.accountId) == null ? null : await s.ledger.applyTemplate(tpl);
    if (!context.mounted) {
      return;
    }
    if (tx == null) {
      await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => TxEditor(template: tpl)));
      return;
    }
    // Un pago a la tarjeta que puede ser el pago hecho fuera de Plata de un
    // extracto marcado: la misma pregunta del editor, enseguida.
    await askOutsideMatch(context, tx);
    if (!context.mounted) {
      return;
    }
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text('${t(context, 'Anotado', 'Logged')}: ${tpl.name} ${money(context, tx.amountMinor, tx.currency)}'),
      action: SnackBarAction(
        label: t(context, 'Deshacer', 'Undo'),
        onPressed: () {
          tpl.uses = tpl.uses > 0 ? tpl.uses - 1 : 0;
          s.ledger.deleteTx(tx.id);
        },
      ),
    ));
  }

  void _openAccount(BuildContext context, Account a) {
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ReadableScaffold(appBar: AppBar(title: Text(a.name)), body: TxListScreen(initialFilter: TxFilter(accountIds: <String>{a.id})))));
  }

  Widget _sectionTitle(BuildContext context, String title, {String? action, VoidCallback? onAction}) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 0, 2),
        child: Row(
          children: <Widget>[
            Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
            if (action != null) TextButton(onPressed: onAction, child: Text(action)),
          ],
        ),
      );
}

class _CardDue {
  const _CardDue(this.account, this.due);

  final Account account;
  final CardDue due;

  CardStatement get statement => due.next;
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.account, required this.width, required this.onTap});

  final Account account;
  final double width;
  final VoidCallback onTap;

  /// Alto de las tarjetas de cuenta: crece con el tamaño de letra del
  /// teléfono para que el nombre, el saldo y la línea de abajo quepan.
  static double heightFor(BuildContext context) {
    final TextScaler ts = MediaQuery.textScalerOf(context);
    final double row = math.max(30.0, ts.scale(14) * 1.4);
    return math.max(118.0, 24 + row + 10 + ts.scale(18) * 1.35 + ts.scale(11) * 1.45 + 8);
  }

  static double widthFor(BuildContext context) => 170 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.4);

  @override
  Widget build(BuildContext context) {
    final Ledger l = AppScope.of(context).ledger;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final int balance = l.balanceWithPockets(account.id);
    String sub;
    Color? subColor;
    if (account.isCredit) {
      final CardDue due = l.cardDue(account);
      final CardStatement st = due.next;
      if (due.overdue) {
        sub = overdueLabel(context, due.overdueSince!);
        subColor = kindColor(context, TxKind.expense);
      } else if (st.dueMinor > 0) {
        sub = '${t(context, 'Pagar', 'Pay')} ${money(context, st.dueMinor, account.currency, compact: true)} · ${dayText(context, l.effectivePayDate(account, st.cycle.payDate))}';
      } else if (balance > 0) {
        sub = t(context, 'Saldo a favor', 'Credit balance');
      } else {
        sub = t(context, 'Al día', 'Up to date');
      }
    } else if (isDebtAccount(account) && balance > 0) {
      sub = t(context, 'Saldo a favor', 'Credit balance');
    } else {
      final List<Account> pockets = l.activeAccounts.where((Account p) => p.parentId == account.id).toList();
      sub = pockets.isEmpty ? accountTypeName(context, account.type) : '${counted(context, pockets.length, oneEs: 'bolsillo', manyEs: 'bolsillos', oneEn: 'pocket', manyEn: 'pockets')} · ${money(context, l.balanceMinor(account.id), account.currency, compact: true)} ${t(context, 'libre', 'free')}';
    }
    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    IconBadge(icon: account.icon, color: account.color, size: 30),
                    const SizedBox(width: 8),
                    Expanded(child: Text(account.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
                  ],
                ),
                const Spacer(),
                Text(balanceText(context, account, balance), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: balanceColor(context, account, balance) ?? cs.onSurface, fontFeatures: const <FontFeature>[FontFeature.tabularFigures()])),
                Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: subColor ?? cs.onSurfaceVariant, fontWeight: subColor != null ? FontWeight.w600 : null)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BudgetLine extends StatelessWidget {
  const _BudgetLine({required this.progress, required this.homePeriod, required this.onTap});

  final BudgetProgress progress;

  /// Periodo de la tarjeta de Inicio: si el del presupuesto es otro (una
  /// quincena), se dice cuál, para no mezclarlo con el mes sin aviso.
  final Period homePeriod;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Ledger l = AppScope.of(context).ledger;
    final Color color = progress.over ? kindColor(context, TxKind.expense) : (progress.fraction > 0.85 ? warnColor(context) : Theme.of(context).colorScheme.primary);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(child: Text(progress.period == homePeriod ? progress.budget.name : '${progress.budget.name} · ${progress.period.start.day}–${progress.period.lastDay.day} ${formatDate(progress.period.lastDay, 'MMM', spanish: l.spanish)}', maxLines: 1, overflow: TextOverflow.ellipsis)),
                Text('${money(context, progress.spentMinor, l.baseCurrency, compact: true)} / ${money(context, progress.limitMinor, l.baseCurrency, compact: true)}', style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 3),
            ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: progress.fraction.clamp(0.0, 1.0), color: color, minHeight: 6)),
          ],
        ),
      ),
    );
  }
}

class _InboxRow extends StatelessWidget {
  const _InboxRow({required this.item});

  final InboxItem item;

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final Account? guess = s.ledger.account(item.accountId) ?? s.ledger.matchNotice(item).account;
    return ListTile(
      dense: true,
      leading: CircleAvatar(backgroundColor: kindColor(context, item.kind).withValues(alpha: 0.15), child: Icon(noticeIcon(item), color: kindColor(context, item.kind), size: 18)),
      title: Text('${item.merchant.isEmpty ? BankRules.displayName(item.bank, spanish: s.settings.spanish) : item.merchant} · ${money(context, item.amountMinor, item.currency)}', maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${noticeHint(context, item)}${BankRules.displayName(item.bank, spanish: s.settings.spanish)}${item.last4.isNotEmpty ? ' *${item.last4}' : ''} · ${formatDate(item.receivedAt, 'dd MMM HH:mm', spanish: s.settings.spanish)}${guess != null ? ' → ${guess.name}' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(tooltip: t(context, 'Descartar', 'Dismiss'), icon: const Icon(Icons.close), onPressed: () => s.ledger.dismissInbox(item)),
          IconButton(tooltip: t(context, 'Revisar y anotar', 'Review and log'), icon: const Icon(Icons.check), onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => TxEditor(inbox: item)))),
        ],
      ),
      onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => TxEditor(inbox: item))),
    );
  }
}

class _ScheduledRow extends StatelessWidget {
  const _ScheduledRow({required this.item});

  final Scheduled item;

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final Ledger l = s.ledger;
    final Account? a = l.account(item.accountId);
    final int days = daysBetween(clock.now(), item.nextDate);
    final String when = days < 0 ? t(context, 'Vencido', 'Overdue') : (days == 0 ? t(context, 'Hoy', 'Today') : (days == 1 ? t(context, 'Mañana', 'Tomorrow') : formatDate(item.nextDate, 'EEE dd MMM', spanish: s.settings.spanish)));
    return ListTile(
      dense: true,
      leading: IconBadge(icon: l.category(item.categoryId)?.icon ?? 'repeat', color: l.category(item.categoryId)?.color ?? 0xFF607D8B, size: 34),
      title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(l.noticeDuplicateFor(item) != null || l.pendingNoticeFor(item) != null ? '$when · ${t(context, '¿Ya lo anotó un aviso?', 'Already logged from a notice?')}' : '$when · ${a?.name ?? ''}${item.autoPost ? '' : ' · ${t(context, 'manual', 'manual')}'}', maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text('${item.kind == TxKind.expense ? '−' : (item.kind == TxKind.income ? '+' : '')}${money(context, item.amountMinor, a?.currency ?? l.baseCurrency)}', style: TextStyle(fontWeight: FontWeight.w700, color: kindColor(context, item.kind))),
      onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ScheduledEditor(existing: item))),
    );
  }
}

/// Prefijo de un aviso que pide más cuidado: posible duplicado de algo ya
/// anotado, o devolución (entra como ingreso, no como gasto).
String noticeHint(BuildContext context, InboxItem item) {
  // Se vuelve a mirar al mostrarlo: el movimiento o el programado igual pudo
  // anotarse después de que llegó el aviso.
  final Ledger l = AppScope.of(context).ledger;
  final String? acc = item.accountId ?? l.matchNotice(item).account?.id;
  final bool live = item.kind != TxKind.transfer && ((acc != null && l.likelyDuplicate(item, acc) != null) || l.scheduledDuplicateFor(item) != null);
  if (item.duplicateOf != null || live) {
    return '${t(context, 'Posible duplicado', 'Possible duplicate')} · ';
  }
  if (item.flow == NoticeFlow.refund) {
    return '${t(context, 'Devolución', 'Refund')} · ';
  }
  return '';
}

/// Ícono de un aviso: entra, sale o se mueve entre cuentas propias.
IconData noticeIcon(InboxItem item) {
  if (item.kind == TxKind.transfer) {
    return item.flow == NoticeFlow.cardPayment ? Icons.credit_score_outlined : Icons.swap_horiz;
  }
  return item.kind == TxKind.income ? Icons.south_west : Icons.north_east;
}

/// Abre el editor para pagar una tarjeta: desde una cuenta en la moneda de la
/// tarjeta (la última usada, si sirve) y por lo que vence. Si no hay ninguna
/// cuenta en esa moneda, el editor lo plantea como transferencia entre
/// monedas: el monto que llega a la tarjeta es lo que vence y el que sale se
/// calcula con la tasa guardada.
/// [date] propone la fecha del pago: al registrar un extracto que se marcó
/// como pagado, su fecha límite (el pago se hizo antes, no hoy). Con
/// [statement], el pago queda vinculado al extracto que cortó ese día.
/// Devuelve el movimiento guardado (null si se cancela).
Future<Tx?> openCardPayment(BuildContext context, Account card, int dueMinor, {DateTime? date, DateTime? statement}) {
  final Services s = AppScope.of(context);
  final Account? source = s.ledger.paymentSourceFor(card, preferredId: s.settings.defaultAccountId);
  return Navigator.push<Tx>(
    context,
    MaterialPageRoute<Tx>(
      builder: (_) => TxEditor(
        kind: TxKind.transfer,
        initialAccountId: source?.id,
        initialToAccountId: card.id,
        initialToMinor: dueMinor,
        initialDate: date,
        initialDescription: t(context, 'Pago ${card.name}', '${card.name} payment'),
        statementOf: statement == null ? null : dayKey(statement),
      ),
    ),
  );
}
