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
                        Text('${t(context, 'vence', 'due')} ${payDateText(context, l, c, next.cycle.payDate)} · ${t(context, 'corte', 'closing')} ${dayText(context, next.cycle.cut)}', style: TextStyle(fontSize: 12, color: cs.onPrimaryContainer)),
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
                        ? t(context, 'Pago mínimo del extracto del ${dayText(context, lastClosed.cut)}: sin anotar', 'Minimum payment on the ${dayText(context, lastClosed.cut)} statement: not entered')
                        : '${t(context, 'Pago mínimo del extracto del ${dayText(context, lastClosed.cut)}', 'Minimum payment on the ${dayText(context, lastClosed.cut)} statement')}: ${money(context, lastMinimum, c.currency)}',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ),
                TextButton(onPressed: () => askStatementMinimum(context, c, lastClosed.cut), child: Text(lastMinimum == null ? t(context, 'Anotar', 'Enter') : t(context, 'Cambiar', 'Change'))),
              ],
            ),
            // Extractos marcados «Ya lo pagué» o pagados con un movimiento
            // vinculado: se ve cuál, y se registra el pago o se desmarca.
            for (final CardCycle paid in <CardCycle>[lastClosed, lastClosed.previous(c), lastClosed.previous(c).previous(c)].where((CardCycle x) => l.isStatementPaid(c, x.cut) || l.statementPayments(c, x.cut).isNotEmpty))
              _PaidStatementRow(card: c, cut: paid.cut),
            Row(
              children: <Widget>[
                IconButton(tooltip: t(context, 'Ciclo anterior', 'Previous cycle'), icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => _back += 1)),
                Expanded(child: Text('${dayText(context, st.cycle.start)} – ${dayText(context, st.cycle.cut, year: true)}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600))),
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
            Text('${t(context, 'Fecha límite de pago', 'Payment due date')}: ${payDateText(context, l, c, st.cycle.payDate, year: true)}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
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
                  subtitle: Text('${dayText(context, tx.date, year: true)} · ${tx.installments - l.remainingInstallments(tx)}/${tx.installments} ${t(context, 'facturadas', 'billed')}'),
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
                label: Text(t(context, 'Abonar a la tarjeta', 'Pay card')),
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
                Text(t(context, 'Según lo anotado en Plata. Si no lo has pagado, hazlo cuanto antes: el banco cobra intereses de mora y puede reportarlo. Si ya pagaste, regístralo o toca «Ya lo pagué».', 'According to what you logged in Plata. If you have not paid it, do it as soon as you can: the bank charges late interest and may report it. If you already paid, log it or tap "Already paid".'), style: TextStyle(fontSize: 12, color: cs.onErrorContainer)),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              TextButton(onPressed: () => openCardPayment(context, card, due.overdueMinor), child: Text(t(context, 'Pagar', 'Pay'), style: TextStyle(color: cs.onErrorContainer))),
              TextButton(onPressed: () => markPaidFromBanner(context, card, due.statementCut!), child: Text(t(context, 'Ya lo pagué', 'Already paid'), style: TextStyle(color: cs.onErrorContainer))),
            ],
          ),
        ],
      ),
    );
  }
}

/// Respuesta a «¿Ya lo pagaste?».
enum _Paid { notYet, paid, paidAndLog }

/// Pide el pago mínimo que el banco cobra en el extracto que cortó en [cut]
/// y lo anota en la tarjeta. Enseguida pregunta si ya se pagó: un mínimo que
/// ya se pagó fuera de Plata, anotado como pendiente, terminaría en una mora
/// falsa. Con [alreadyPaid] (el botón «Pagué solo el mínimo») no pregunta.
Future<void> askStatementMinimum(BuildContext context, Account card, DateTime cut, {bool alreadyPaid = false}) async {
  final Ledger l = AppScope.of(context).ledger;
  final int? v = await pickAmount(
    context,
    initialMinor: l.statementMinimum(card, cut) ?? 0,
    currency: card.currency,
    title: t(context, 'Pago mínimo del extracto del ${dayText(context, cut)}', 'Minimum payment on the ${dayText(context, cut)} statement'),
  );
  if (v == null || !context.mounted) {
    return;
  }
  l.setStatementMinimum(card, cut, v);
  if (v == 0) {
    return;
  }
  _Paid? answer = _Paid.paid;
  if (!alreadyPaid) {
    answer = await showDialog<_Paid>(
      context: context,
      barrierDismissible: false,
      // Ni tocando fuera ni con Atrás: hay que contestar. Si aun así se cierra
      // sin respuesta, la marca queda como estaba.
      builder: (BuildContext c) => PopScope(
        canPop: false,
        child: AlertDialog(
            title: Text(t(c, '¿Ya lo pagaste?', 'Have you already paid it?')),
            content: Text(t(c, 'Si ya pagaste este mínimo (en la app del banco, por ejemplo), Plata lo da por pagado y no te avisará mora por este extracto. Si lo pagaste desde una cuenta que tienes en Plata, regístralo para que el saldo cuadre.', 'If you already paid this minimum (in your bank app, for example), Plata counts it as paid and will not warn you about this statement. If you paid from an account you have in Plata, log it so the balance adds up.')),
            actions: <Widget>[
              TextButton(onPressed: () => Navigator.pop(c, _Paid.notYet), child: Text(t(c, 'Todavía no', 'Not yet'))),
              TextButton(onPressed: () => Navigator.pop(c, _Paid.paid), child: Text(t(c, 'Sí, ya lo pagué', 'Yes, I paid it'))),
              FilledButton(onPressed: () => Navigator.pop(c, _Paid.paidAndLog), child: Text(t(c, 'Sí, registrar el pago', 'Yes, log the payment'))),
            ],
          ),
      ),
    );
  }
  if (answer == null) {
    return;
  }
  if (answer == _Paid.notYet) {
    // «Todavía no» también deshace un «Ya lo pagué» anterior de ese extracto.
    if (l.isStatementPaid(card, cut)) {
      l.markStatementPaid(card, cut, paid: false);
    }
    return;
  }
  if (!context.mounted) {
    return;
  }
  l.markStatementPaid(card, cut);
  if (answer == _Paid.paidAndLog) {
    await openCardPayment(context, card, v, date: proposedPaymentDate(l, card, cut), statement: cut);
  } else if (alreadyPaid) {
    showPaidSnackBar(context, card, cut);
  }
}

/// Fecha que se propone al registrar el pago de un extracto ya pagado: su
/// fecha límite real (el pago se hizo antes de hoy), o hoy si aún no llega.
DateTime proposedPaymentDate(Ledger l, Account card, DateTime cut) {
  final DateTime due = l.effectivePayDate(card, CardCycle.current(card, cut).payDate);
  final DateTime today = dateOnly(clock.now());
  final DateTime d = due.isAfter(today) ? today : due;
  return DateTime(d.year, d.month, d.day, 12);
}

/// Confirmación de «Ya lo pagué», con «Deshacer»: un toque equivocado no
/// apaga la única alarma de un pago pendiente.
void showPaidSnackBar(BuildContext context, Account card, DateTime cut) {
  final Ledger l = AppScope.of(context).ledger;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(t(context, 'Marcado como pagado. Si lo pagaste desde una cuenta que tienes en Plata, regístralo en Tarjetas.', 'Marked as paid. If you paid from an account you have in Plata, log it in Cards.')),
    action: SnackBarAction(label: t(context, 'Deshacer', 'Undo'), onPressed: () => l.markStatementPaid(card, cut, paid: false)),
  ));
}

/// Marca como pagado el extracto de un aviso de pago pendiente, aunque el
/// pago no esté anotado, y ofrece registrarlo.
void markPaidFromBanner(BuildContext context, Account card, DateTime cut) {
  AppScope.of(context).ledger.markStatementPaid(card, cut);
  showPaidSnackBar(context, card, cut);
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
              // Primero, registrar el pago: es lo más común (un pago que no se
              // anotó). Aparte, quien pagó solo el mínimo lo anota ya pagado.
              TextButton(onPressed: () => openCardPayment(context, card, due.unconfirmedMinor), child: Text(t(context, 'Ya pagué: registrar el pago', 'I paid: log the payment'))),
              TextButton(onPressed: () => askStatementMinimum(context, card, due.statementCut!, alreadyPaid: true), child: Text(t(context, 'Pagué solo el mínimo: anotarlo', 'I paid only the minimum: enter it'))),
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
      ? 'Según lo anotado, quedan $amount del extracto del ${dayText(context, due.statementCut!)}. Si ya pagaste, regístralo; si pagaste solo el mínimo del banco, anótalo.'
      : 'According to what you logged, $amount is left of the ${dayText(context, due.statementCut!)} statement. If you already paid, log it; if you paid only the bank minimum, enter it.';
}

/// Fila de un extracto marcado «Ya lo pagué» o con pagos vinculados: dice
/// cuánto se pagó con movimientos de Plata, cuánto con lo anotado y cuánto
/// se da por pagado fuera de Plata (o cuánto falta, si no está marcado).
/// Cada botón dice en su nombre accesible de qué extracto es.
class _PaidStatementRow extends StatelessWidget {
  const _PaidStatementRow({required this.card, required this.cut});

  final Account card;
  final DateTime cut;

  @override
  Widget build(BuildContext context) {
    final Ledger l = AppScope.of(context).ledger;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final String day = dayText(context, cut);
    String m(int v) => money(context, v, card.currency);
    final List<Tx> linked = l.statementPayments(card, cut);
    final bool marked = l.isStatementPaid(card, cut);
    final int linkedTotal = l.linkedPayments(card, cut);
    final int absorbed = marked ? l.absorbedPayments(card, cut) : 0;
    final int outside = l.assumedPayment(card, cut);
    final int? minimum = l.statementMinimum(card, cut);
    final List<String> dates = linked.map((Tx x) => dayText(context, x.date)).toSet().toList();
    final String when = dates.join(', ');
    final String withTx = linked.length == 1 ? t(context, 'con el movimiento del $when', 'with the $when transaction') : t(context, 'con los movimientos del $when', 'with the $when transactions');
    final String text;
    if (!marked) {
      // Sin marca, solo con pagos vinculados.
      final int missing = minimum == null ? 0 : minimum - linkedTotal;
      text = missing > 0
          ? t(context, 'Extracto del $day: ${m(linkedTotal)} abonados $withTx; faltan ${m(missing)} del mínimo', '$day statement: ${m(linkedTotal)} paid $withTx; ${m(missing)} of the minimum is missing')
          : t(context, 'Extracto del $day pagado $withTx (${m(linkedTotal)})', '$day statement paid $withTx (${m(linkedTotal)})');
    } else if (linked.isEmpty && absorbed == 0) {
      text = t(context, 'Extracto del $day marcado como pagado', '$day statement marked as paid');
    } else if (absorbed == 0 && outside == 0) {
      text = t(context, 'Extracto del $day pagado $withTx (${m(linkedTotal)})', '$day statement paid $withTx (${m(linkedTotal)})');
    } else {
      final List<String> parts = <String>[
        if (linkedTotal > 0) '${m(linkedTotal)} $withTx',
        if (absorbed > 0) t(context, '${m(absorbed)} con lo anotado', '${m(absorbed)} with what you logged'),
        if (outside > 0) t(context, '${m(outside)} por fuera de Plata', '${m(outside)} outside Plata'),
      ];
      text = t(context, 'Extracto del $day pagado: ${parts.join(', ')}', '$day statement paid: ${parts.join(', ')}');
    }
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Text(text, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        // Solo mientras quede una parte que se da por pagada fuera de Plata:
        // registrarla la reemplaza, y no se puede registrar dos veces.
        if (marked && outside > 0)
          TextButton(
            onPressed: () => openCardPayment(context, card, outside, date: proposedPaymentDate(l, card, cut), statement: cut),
            child: Text(t(context, 'Registrar el pago', 'Log the payment'), semanticsLabel: t(context, 'Registrar el pago del extracto del $day', 'Log the payment of the $day statement')),
          ),
        if (marked)
          TextButton(
            onPressed: () => l.markStatementPaid(card, cut, paid: false),
            child: Text(t(context, 'Desmarcar', 'Unmark'), semanticsLabel: t(context, 'Desmarcar el extracto del $day', 'Unmark the $day statement')),
          ),
      ],
    );
  }
}
