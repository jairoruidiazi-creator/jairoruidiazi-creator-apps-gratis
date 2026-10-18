import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/ledger.dart';
import '../../core/periods.dart';
import '../../model/models.dart';
import '../home/home_screen.dart';
import '../transactions/tx_editor.dart';
import '../transactions/tx_tile.dart';
import '../widgets/adaptive.dart';
import '../widgets/common.dart';
import 'accounts_screen.dart';

/// Tarjetas de crédito: estado de cuenta estimado del ciclo, cuotas pendientes
/// y pago. Es capital: Plata no calcula intereses ni cuota de manejo.
class CardsScreen extends StatelessWidget {
  const CardsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    return ListenableBuilder(
      listenable: s.ledger,
      builder: (BuildContext context, Widget? _) {
        final Ledger l = s.ledger;
        final List<Account> cards = l.activeAccounts.where((Account a) => a.isCredit).toList();
        return ReadableScaffold(
          appBar: AppBar(title: Text(t(context, 'Tarjetas de crédito', 'Credit cards'))),
          body: cards.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(t(context, 'Crea una cuenta de tipo "Tarjeta de crédito" con su día de corte y de pago para ver aquí el estado de cuenta y las cuotas.', 'Create a "Credit card" account with its statement and payment days to see the statement and installments here.'), textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const AccountsScreen())), child: Text(t(context, 'Ir a cuentas', 'Go to accounts'))),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
                  children: <Widget>[
                    const _EstimateNote(),
                    for (final Account c in cards) _CardPanel(card: c),
                  ],
                ),
        );
      },
    );
  }
}

/// Aviso fijo: lo que muestra Plata es una estimación del capital.
class _EstimateNote extends StatelessWidget {
  const _EstimateNote();

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.info_outline, size: 20, color: cs.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                t(context, 'Capital estimado, sin intereses ni cuota de manejo: Plata suma las compras, cuotas, avances y abonos que anotas. El extracto de tu banco agrega intereses, cuota de manejo y seguros, así que puede ser mayor: paga con base en él.', 'Estimated principal, without interest or card fees: Plata adds up the purchases, installments, cash advances and payments you log. Your bank statement adds interest, card fees and insurance, so it can be higher: pay based on it.'),
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardPanel extends StatefulWidget {
  const _CardPanel({required this.card});

  final Account card;

  @override
  State<_CardPanel> createState() => _CardPanelState();
}

class _CardPanelState extends State<_CardPanel> {
  int _back = 0;

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final Ledger l = s.ledger;
    final Account c = widget.card;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool es = s.settings.spanish;
    CardCycle cycle = CardCycle.current(c, clock.now());
    for (int i = 0; i < _back; i++) {
      cycle = cycle.previous(c);
    }
    final CardStatement st = l.statement(c, date: cycle.cut);
    final int balance = l.balanceMinor(c.id);
    final int? available = l.availableCreditMinor(c);
    final List<Tx> installments = l.txs.where((Tx tx) => tx.accountId == c.id && tx.installments > 1 && l.remainingInstallments(tx) > 0).toList();
    final int pendingInstallments = installments.fold<int>(0, (int a, Tx tx) => a + l.remainingInstallmentsMinor(tx));
    final List<Tx> cycleTxs = l.inPeriod(st.cycle.period, accountId: c.id);
    final CardDue due = l.cardDue(c);
    final CardStatement next = due.next;
    final int unit = Ledger.displayUnit(c.currency);
    // Extracto más reciente que ya cerró: a ese se le puede anotar el mínimo.
    final CardCycle lastClosed = CardCycle.current(c, clock.now()).previous(c);
    final int? lastMinimum = l.statementMinimum(c, lastClosed.cut);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                IconBadge(icon: c.icon, color: c.color),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('${c.name}${c.last4.isNotEmpty ? ' *${c.last4}' : ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text('${t(context, 'Corte el', 'Closes on the')} ${dayOfMonth(context, c.cutDay ?? 1)} · ${t(context, 'pago el', 'due on the')} ${dayOfMonth(context, c.payDay ?? c.cutDay ?? 1)}${available != null ? ' · ${t(context, 'cupo libre', 'available')} ${money(context, available, c.currency, compact: true)}' : ''}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                IconButton(tooltip: t(context, 'Editar tarjeta', 'Edit card'), icon: const Icon(Icons.edit_outlined), onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => AccountEditor(existing: c)))),
              ],
            ),
            if (due.overdue) ...<Widget>[
              const SizedBox(height: 8),
              OverdueBanner(card: c, due: due),
            ] else if (due.unconfirmed) ...<Widget>[
              const SizedBox(height: 8),
              UnconfirmedBanner(card: c, due: due),
            ],
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(t(context, 'Próximo pago (capital estimado)', 'Next payment (estimated principal)'), style: TextStyle(fontSize: 12, color: cs.onPrimaryContainer.withValues(alpha: 0.8))),
                        Text('${t(context, 'vence', 'due')} ${formatDate(next.cycle.payDate, 'EEE dd MMM', spanish: es)} · ${t(context, 'corte', 'closing')} ${formatDate(next.cycle.cut, 'dd MMM', spanish: es)}', style: TextStyle(fontSize: 12, color: cs.onPrimaryContainer)),
                        if ((due.overdue || due.unconfirmed) && next.previousMinor > 0) Text(t(context, 'Incluye lo que quedó del extracto anterior', 'Includes what was left of the previous statement'), style: TextStyle(fontSize: 12, color: cs.onPrimaryContainer)),
                      ],
                    ),
                  ),
                  Text(money(context, next.dueMinor, c.currency), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: cs.onPrimaryContainer, fontFeatures: const <FontFeature>[FontFeature.tabularFigures()])),
                ],
              ),
            ),
            // El mínimo que pidió el banco: con él, Plata sabe si la tarjeta
            // quedó al día (su estimado no conoce los plazos del banco).
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    lastMinimum == null
                        ? t(context, 'Pago mínimo del extracto del ${formatDate(lastClosed.cut, 'dd MMM', spanish: true)}: sin anotar', 'Minimum payment on the ${formatDate(lastClosed.cut, 'MMM dd', spanish: false)} statement: not entered')
                        : '${t(context, 'Pago mínimo del extracto del ${formatDate(lastClosed.cut, 'dd MMM', spanish: true)}', 'Minimum payment on the ${formatDate(lastClosed.cut, 'MMM dd', spanish: false)} statement')}: ${money(context, lastMinimum, c.currency)}',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ),
                TextButton(onPressed: () => askStatementMinimum(context, c, lastClosed.cut), child: Text(lastMinimum == null ? t(context, 'Anotar', 'Enter') : t(context, 'Cambiar', 'Change'))),
              ],
            ),
            Row(
              children: <Widget>[
                IconButton(tooltip: t(context, 'Ciclo anterior', 'Previous cycle'), icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => _back += 1)),
                Expanded(child: Text('${formatDate(st.cycle.start, 'dd MMM', spanish: es)} – ${formatDate(st.cycle.cut, 'dd MMM yyyy', spanish: es)}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600))),
                IconButton(tooltip: t(context, 'Ciclo siguiente', 'Next cycle'), icon: const Icon(Icons.chevron_right), onPressed: _back == 0 ? null : () => setState(() => _back -= 1)),
              ],
            ),
            if (st.previousMinor != 0) _row(context, st.previousMinor > 0 ? (st.fromBankStatement ? t(context, 'Pago mínimo del último extracto (anotado al crear la tarjeta)', 'Minimum payment on the last statement (entered with the card)') : t(context, 'Saldo anterior sin pagar', 'Previous balance unpaid')) : t(context, 'Saldo a favor anterior', 'Previous credit'), st.previousMinor > 0 ? money(context, st.previousMinor, c.currency) : '−${money(context, -st.previousMinor, c.currency)}'),
            _row(context, t(context, 'Compras del ciclo', 'Purchases this cycle'), money(context, st.purchasesMinor, c.currency)),
            if (st.advancesMinor != 0) _row(context, t(context, 'Avances (o sus cuotas)', 'Cash advances (or their installments)'), money(context, st.advancesMinor, c.currency)),
            _row(context, t(context, 'Cuotas que se facturan', 'Installments billed'), money(context, st.installmentsMinor, c.currency)),
            // Sin abonos se muestra "$ 0", no "−$ 0".
            _row(context, t(context, 'Abonos y devoluciones', 'Payments and refunds'), st.paymentsMinor == 0 ? money(context, 0, c.currency) : '−${money(context, st.paymentsMinor, c.currency)}'),
            // Lo abonado de más sobre este estado se descontó de la deuda de
            // antes de Plata: se muestra para que las líneas sumen el total.
            if (st.toLegacyMinor > 0) _row(context, t(context, 'Abono de más que fue a la deuda de antes', 'Extra payment applied to the earlier debt'), money(context, st.toLegacyMinor, c.currency)),
            const Divider(),
            if (st.creditMinor > 0)
              _row(context, t(context, 'Saldo a favor', 'Credit balance'), money(context, st.creditMinor, c.currency), bold: true)
            else
              _row(context, t(context, 'Capital del estado de cuenta', 'Statement principal'), money(context, st.dueMinor, c.currency), bold: true),
            Text('${t(context, 'Fecha límite de pago', 'Payment due date')}: ${formatDate(st.cycle.payDate, 'EEE dd MMM yyyy', spanish: es)}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            const SizedBox(height: 4),
            if (balance > 0)
              _row(context, t(context, 'Saldo a favor hoy', 'Credit balance today'), money(context, balance, c.currency))
            else
              _row(context, t(context, 'Deuda total hoy (capital)', 'Total debt today (principal)'), money(context, -balance, c.currency)),
            _row(context, t(context, 'Cuotas por facturar', 'Installments still to bill'), money(context, pendingInstallments, c.currency)),
            if (st.legacyMinor > 0) ...<Widget>[
              _row(context, l.cardHasAdjustments(c) ? t(context, 'Deuda de antes de Plata y ajustes', 'Debt from before Plata and adjustments') : t(context, 'Deuda de antes de Plata', 'Debt from before Plata'), money(context, st.legacyMinor, c.currency)),
              Text(t(context, 'Es parte de la deuda inicial que no vence en un solo pago (por ejemplo, cuotas de compras viejas): cuenta en la deuda total y en el cupo, pero no se suma al próximo pago porque Plata no sabe cómo la reparte tu banco. Lo que abones de más se descuenta de aquí. Los ajustes de saldo también van aquí: corrigen la deuda, pero el banco no los cobra en el próximo pago.', 'It is the part of the starting debt that is not due in a single payment (for example, installments of older purchases): it counts toward the total debt and the limit, but it is not added to the next payment because Plata does not know how your bank splits it. Anything you pay beyond a statement is taken off here. Balance adjustments go here too: they correct the debt, but the bank does not charge them in the next payment.'), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ],
            if (installments.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Text(t(context, 'Compras y avances a cuotas', 'Installment purchases and advances'), style: Theme.of(context).textTheme.titleSmall),
              for (final Tx tx in installments)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(tx.description.isEmpty ? (l.category(tx.categoryId)?.name ?? '') : tx.description, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${formatDate(tx.date, 'dd MMM yyyy', spanish: es)} · ${tx.installments - l.remainingInstallments(tx)}/${tx.installments} ${t(context, 'facturadas', 'billed')}'),
                  trailing: Text('${money(context, Ledger.installmentAmount(tx.amountMinor, tx.installments, 1, unit: unit), c.currency, compact: true)}/${t(context, 'cuota', 'inst.')}'),
                  onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => TxEditor(existing: tx))),
                ),
            ],
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('${t(context, 'Movimientos del ciclo', 'Cycle transactions')} (${cycleTxs.length})'),
              children: <Widget>[for (final Tx tx in cycleTxs) TxTile(tx: tx, showDate: true, onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => TxEditor(existing: tx))))],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: next.dueMinor <= 0 ? null : () => openCardPayment(context, c, next.dueMinor),
                icon: const Icon(Icons.payments_outlined),
                label: Text(t(context, 'Registrar pago', 'Log payment')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: <Widget>[
            Expanded(child: Text(label)),
            Text(value, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600, fontSize: bold ? 17 : 14, fontFeatures: const <FontFeature>[FontFeature.tabularFigures()])),
          ],
        ),
      );
}

/// Aviso de un pago de tarjeta vencido: la fecha límite del último estado
/// pasó y quedó capital sin pagar.
class OverdueBanner extends StatelessWidget {
  const OverdueBanner({super.key, required this.card, required this.due});

  final Account card;
  final CardDue due;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: <Widget>[
          Icon(Icons.warning_amber_rounded, color: cs.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('${overdueLabel(context, due.overdueSince!)}: ${t(context, 'faltan', 'still owed')} ${money(context, due.overdueMinor, card.currency)} ${t(context, 'del pago mínimo', 'of the minimum payment')}', style: TextStyle(fontWeight: FontWeight.w700, color: cs.onErrorContainer)),
                Text(t(context, 'Paga cuanto antes: el banco cobra intereses de mora y puede reportarlo.', 'Pay as soon as you can: the bank charges late interest and may report it.'), style: TextStyle(fontSize: 12, color: cs.onErrorContainer)),
              ],
            ),
          ),
          TextButton(onPressed: () => openCardPayment(context, card, due.overdueMinor), child: Text(t(context, 'Pagar', 'Pay'), style: TextStyle(color: cs.onErrorContainer))),
        ],
      ),
    );
  }
}

/// Pide el pago mínimo que el banco cobra en el extracto que cortó en [cut]
/// y lo anota en la tarjeta.
Future<void> askStatementMinimum(BuildContext context, Account card, DateTime cut) async {
  final Ledger l = AppScope.of(context).ledger;
  final bool es = AppScope.of(context).settings.spanish;
  final int? v = await pickAmount(
    context,
    initialMinor: l.statementMinimum(card, cut) ?? 0,
    currency: card.currency,
    title: es ? 'Pago mínimo del extracto del ${formatDate(cut, 'dd MMM', spanish: true)}' : 'Minimum payment on the ${formatDate(cut, 'MMM dd', spanish: false)} statement',
  );
  if (v != null) {
    l.setStatementMinimum(card, cut, v);
  }
}

/// Sin un mínimo conocido, lo que el estimado de Plata dice que quedó de un
/// extracto se informa sin hablar de mora: puede ser una compra o un avance a
/// cuotas anotado a 1 cuota, la cuota de manejo, o un pago que no se anotó.
class UnconfirmedBanner extends StatelessWidget {
  const UnconfirmedBanner({super.key, required this.card, required this.due});

  final Account card;
  final CardDue due;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(unconfirmedText(context, due, card.currency), style: TextStyle(color: cs.onSecondaryContainer)),
          Wrap(
            alignment: WrapAlignment.end,
            children: <Widget>[
              TextButton(onPressed: () => askStatementMinimum(context, card, due.statementCut!), child: Text(t(context, 'Anotar el mínimo', 'Enter the minimum'))),
              TextButton(onPressed: () => openCardPayment(context, card, due.unconfirmedMinor), child: Text(t(context, 'Registrar pago', 'Log payment'))),
            ],
          ),
        ],
      ),
    );
  }
}

/// «Según lo anotado, quedan $X del extracto del 15 oct; si pagaste el
/// mínimo del banco, anótalo.»
String unconfirmedText(BuildContext context, CardDue due, String currency) {
  final bool es = AppScope.of(context).settings.spanish;
  final String amount = money(context, due.unconfirmedMinor, currency);
  return es
      ? 'Según lo anotado, quedan $amount del extracto del ${formatDate(due.statementCut!, 'dd MMM', spanish: true)}; si pagaste el mínimo del banco, anótalo.'
      : 'According to what you logged, $amount is left of the ${formatDate(due.statementCut!, 'MMM dd', spanish: false)} statement; if you paid the bank minimum, enter it.';
}
