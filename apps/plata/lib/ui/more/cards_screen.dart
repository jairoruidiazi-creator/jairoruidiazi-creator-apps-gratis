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
    // «· cupo libre $ 2,47 M» va entero en una línea (espacios que no parten).
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
                      Text('${t(context, 'Corte el', 'Closes on the')} ${dayOfMonth(context, c.cutDay ?? 1)} · ${t(context, 'pago el', 'due on the')} ${dayOfMonth(context, c.payDay ?? c.cutDay ?? 1)}${available != null ? ' ${'· ${t(context, 'cupo libre', 'available')} ${money(context, available, c.currency, compact: true)}'.replaceAll(' ', '\u00A0')}' : ''}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                IconButton(tooltip: t(context, 'Editar tarjeta', 'Edit card'), icon: const Icon(Icons.edit_outlined), onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => AccountEditor(existing: c)))),
              ],
            ),
            // Abonos que Plata tomó por el pago hecho fuera de Plata de un
            // extracto marcado (de cualquier extracto) y esperan respuesta.
            for (final Tx p in l.pendingOutsideMatches(card: c)) ...<Widget>[
              const SizedBox(height: 8),
              OutsideMatchCard(tx: p),
            ],
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
            scrollable: true,
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
  // Lo que faltaba del mínimo queda como «Pago hecho fuera de Plata» (o solo
  // la marca, si es de antes de que la tarjeta empezara en Plata).
  final bool? payment = await askPaymentKind(context, card, cut);
  if (payment == null || !context.mounted) {
    return;
  }
  final int missing = l.statementMissing(card, cut) ?? 0;
  if (answer == _Paid.paidAndLog && payment && missing > 0) {
    // Se registra desde una cuenta de Plata, vinculado y por lo que faltaba
    // (no el mínimo entero: lo anotado ya cuenta). La marca queda al
    // guardarlo; si se cancela, el extracto sigue sin marcar.
    final Tx? saved = await openCardPayment(context, card, missing, date: proposedPaymentDate(l, card, cut), statement: cut);
    if (saved != null) {
      l.markStatementPaid(card, cut, payment: false);
    }
    return;
  }
  l.markStatementPaid(card, cut, payment: payment);
  if (!context.mounted) {
    return;
  }
  if (answer == _Paid.paidAndLog) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(payment
            ? t(context, 'Lo que anotaste ya cubre ese mínimo: no hay nada más que registrar.', 'What you logged already covers that minimum: there is nothing else to log.')
            : t(context, 'Marcado como pagado. La deuda que anotaste al crear la tarjeta ya lo descuenta: no hay nada que registrar.', 'Marked as paid. The debt you entered when you added the card already accounts for it: there is nothing to log.'))));
  } else {
    showPaidSnackBar(context, card, cut);
  }
}

/// Si «Ya lo pagué» del extracto que cortó en [cut] crea un pago hecho fuera
/// de Plata (true) o solo marca (false). Para un extracto de antes de que la
/// tarjeta empezara en Plata, con deuda inicial, pregunta si se pagó antes
/// de crearla: entonces la deuda inicial ya lo descuenta y solo se marca.
/// Null si se cancela.
Future<bool?> askPaymentKind(BuildContext context, Account card, DateTime cut) async {
  final Ledger l = AppScope.of(context).ledger;
  final MarkKind kind = l.markKind(card, cut);
  if (kind != MarkKind.ask) {
    return kind == MarkKind.payment;
  }
  final bool? before = await showDialog<bool>(
        context: context,
        builder: (BuildContext c) => AlertDialog(
          scrollable: true,
          title: Text(t(c, '¿Lo pagaste antes de crear la tarjeta en Plata?', 'Did you pay it before adding the card to Plata?')),
          content: Text(t(
            c,
            'El extracto del ${dayText(c, cut)} es de antes de que empezaras a llevar ${card.name} en Plata. Si lo pagaste antes de crear la tarjeta, la deuda que anotaste ya lo descuenta y solo se marca. Si lo pagaste después, se anota como pago hecho fuera de Plata y baja la deuda.',
            'The ${dayText(c, cut)} statement is from before you started tracking ${card.name} in Plata. If you paid it before adding the card, the debt you entered already accounts for it and it is only marked. If you paid it afterwards, it is logged as a payment made outside Plata and lowers the debt.',
          )),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(c), child: Text(t(c, 'Cancelar', 'Cancel'))),
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t(c, 'Después', 'Afterwards'))),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(t(c, 'Antes', 'Before'))),
          ],
        ),
      );
  return before == null ? null : !before;
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
  final int outside = l.outsidePayment(card, cut);
  final String amount = money(context, outside, card.currency);
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(outside > 0
        ? t(context, 'Marcado como pagado: $amount por fuera de Plata. Si lo pagaste desde una cuenta que tienes en Plata, regístralo en Tarjetas.', 'Marked as paid: $amount outside Plata. If you paid from an account you have in Plata, log it in Cards.')
        : t(context, 'Marcado como pagado.', 'Marked as paid.')),
    action: SnackBarAction(label: t(context, 'Deshacer', 'Undo'), onPressed: () => l.markStatementPaid(card, cut, paid: false)),
  ));
}

/// «Ya lo pagué» del aviso rojo o de la notificación: guarda como pagado
/// fuera de Plata lo que el aviso decía que faltaba. Si el aviso ya no
/// corresponde (es de antes de cambiar el día de corte, el extracto ya está
/// marcado o lo anotado ya cubre el mínimo) no marca nada y lo dice.
Future<void> markPaidFromBanner(BuildContext context, Account card, DateTime cut) async {
  final Ledger l = AppScope.of(context).ledger;
  void say(String es, String en) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context, es, en))));
  if (CardCycle.current(card, cut).cut != dateOnly(cut)) {
    say('Ese aviso es de antes de cambiar el día de corte de ${card.name} y ya no corresponde a ningún extracto: no se marcó nada. Revisa la tarjeta en Tarjetas.', 'That notice is from before the ${card.name} closing day changed and no longer matches any statement: nothing was marked. Check the card in Cards.');
    return;
  }
  if (l.isStatementPaid(card, cut)) {
    say('Ese extracto ya estaba marcado como pagado.', 'That statement was already marked as paid.');
    return;
  }
  final int missing = l.statementMissing(card, cut) ?? 0;
  if (missing <= 0) {
    say('Según lo anotado, ese pago mínimo ya está cubierto: no se marcó nada.', 'According to what you logged, that minimum payment is already covered: nothing was marked.');
    return;
  }
  final bool? payment = await askPaymentKind(context, card, cut);
  if (payment == null || !context.mounted) {
    return;
  }
  l.markStatementPaid(card, cut, amount: missing, payment: payment);
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
/// cuánto se pagó con movimientos de Plata y cuánto fuera de Plata, o cuánto
/// falta (la misma cifra del aviso rojo), y pregunta por los abonos sin
/// vínculo que podrían ser el pago de fuera. Cada botón dice en su nombre
/// accesible de qué extracto es.
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
    final List<Tx> linked = l.statementPayments(card, cut).where((Tx x) => !x.isOutsidePayment).toList();
    final bool marked = l.isStatementPaid(card, cut);
    final int linkedTotal = l.linkedPayments(card, cut);
    final int outside = l.outsidePayment(card, cut);
    final String when = linked.map((Tx x) => dayText(context, x.date)).toSet().join(', ');
    final String withTx = linked.length == 1 ? t(context, 'con el movimiento del $when', 'with the $when transaction') : t(context, 'con los movimientos del $when', 'with the $when transactions');
    final String text;
    if (!marked) {
      // Sin marca, solo con pagos vinculados: lo que falta es lo del aviso.
      final int missing = l.statementMissing(card, cut) ?? 0;
      text = missing > 0
          ? t(context, 'Extracto del $day: ${m(linkedTotal)} abonados $withTx; faltan ${m(missing)} del mínimo', '$day statement: ${m(linkedTotal)} paid $withTx; ${m(missing)} of the minimum is missing')
          : t(context, 'Extracto del $day pagado $withTx (${m(linkedTotal)})', '$day statement paid $withTx (${m(linkedTotal)})');
    } else if (linkedTotal == 0) {
      text = outside > 0 ? t(context, 'Extracto del $day pagado: ${m(outside)} por fuera de Plata', '$day statement paid: ${m(outside)} outside Plata') : t(context, 'Extracto del $day marcado como pagado', '$day statement marked as paid');
    } else if (outside == 0) {
      text = t(context, 'Extracto del $day pagado $withTx (${m(linkedTotal)})', '$day statement paid $withTx (${m(linkedTotal)})');
    } else {
      text = t(context, 'Extracto del $day pagado: ${m(linkedTotal)} $withTx, ${m(outside)} por fuera de Plata', '$day statement paid: ${m(linkedTotal)} $withTx, ${m(outside)} outside Plata');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text(text, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            // Registrar lo que se dio por pagado fuera lo reemplaza: no se
            // puede registrar dos veces.
            if (marked && outside > 0)
              TextButton(
                onPressed: () => openCardPayment(context, card, outside, date: proposedPaymentDate(l, card, cut), statement: cut),
                child: Text(t(context, 'Registrar el pago', 'Log the payment'), semanticsLabel: t(context, 'Registrar el pago del extracto del $day', 'Log the payment of the $day statement')),
              ),
            // También en cero (después de reemplazarlo, de borrar el pago
            // registrado o de contestar «Antes»): así se vuelve a anotar.
            if (marked)
              TextButton(
                onPressed: () async {
                  final int? v = await pickAmount(context, initialMinor: outside, currency: card.currency, title: t(context, 'Pagado fuera de Plata (extracto del $day)', 'Paid outside Plata ($day statement)'));
                  if (v != null) {
                    l.setOutsidePayment(card, cut, v);
                  }
                },
                child: Text(t(context, 'Cambiar monto', 'Change amount'), semanticsLabel: t(context, 'Cambiar lo pagado fuera de Plata del extracto del $day', 'Change what was paid outside Plata for the $day statement')),
              ),
            if (marked)
              TextButton(
                onPressed: () => l.markStatementPaid(card, cut, paid: false),
                child: Text(t(context, 'Desmarcar', 'Unmark'), semanticsLabel: t(context, 'Desmarcar el extracto del $day', 'Unmark the $day statement')),
              ),
          ],
        ),
      ],
    );
  }
}

/// Texto de la pregunta por un abono que Plata tomó provisionalmente por el
/// pago hecho fuera de Plata de un extracto.
String _outsideMatchText(BuildContext context, Ledger l, Tx p) {
  final Account? card = l.pendingOutsideCard(p);
  final DateTime? cut = l.pendingOutsideCut(p);
  if (card == null || cut == null) {
    return '';
  }
  final int marked = l.outsidePayment(card, cut) + l.pendingOutsideMatches(card: card, cut: cut).fold<int>(0, (int a, Tx x) => a + (x.outsideTaken ?? 0));
  final String amount = money(context, p.kind == TxKind.transfer ? l.receivedMinor(p) : p.amountMinor, card.currency);
  return t(
    context,
    'Marcaste el extracto del ${dayText(context, cut)} de ${card.name} como pagado fuera de Plata (${money(context, marked, card.currency)}). Si el abono del ${dayText(context, p.date)} ($amount) es ese mismo pago, se cuenta una sola vez. Si es otro pago, queda aparte y baja el próximo pago. Mientras no contestes, Plata lo cuenta como ese pago.',
    'You marked the ${dayText(context, cut)} ${card.name} statement as paid outside Plata (${money(context, marked, card.currency)}). If the ${dayText(context, p.date)} payment ($amount) is that same payment, it is counted once. If it is another payment, it stays separate and lowers the next payment. Until you answer, Plata counts it as that payment.',
  );
}

/// La pregunta «¿Es el pago del extracto…?» justo después de anotar un abono
/// que Plata tomó provisionalmente por un pago hecho fuera de Plata (el
/// editor, el favorito de un toque, «Anotar ahora» y «Duplicar hoy» la
/// hacen con este mismo diálogo). Si con «Es otro pago» puede ser el de otro
/// extracto, pregunta otra vez. Si se cierra sin contestar (no se puede
/// tocando fuera ni con Atrás), la pregunta sigue en Inicio y en Tarjetas.
Future<void> askOutsideMatch(BuildContext context, Tx saved) async {
  final Ledger l = AppScope.of(context).ledger;
  for (int i = 0; i < 12; i++) {
    final Iterable<Tx> found = l.txs.where((Tx x) => x.id == saved.id);
    if (found.isEmpty || !found.first.outsidePending || !context.mounted) {
      return;
    }
    final Tx p = found.first;
    final DateTime cut = l.pendingOutsideCut(p)!;
    final bool? same = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext c) => PopScope(
        canPop: false,
        child: AlertDialog(
          scrollable: true,
          title: Text(t(c, '¿Es el pago del extracto del ${dayText(c, cut)}?', 'Is it the payment of the ${dayText(c, cut)} statement?')),
          content: Text(_outsideMatchText(c, l, p)),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t(c, 'Es otro pago', 'It is another payment'))),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(t(c, 'Sí, es ese pago', 'Yes, it is that payment'))),
          ],
        ),
      ),
    );
    if (same == null) {
      return;
    }
    l.answerOutsideMatch(p, same: same);
  }
}

/// La pregunta pendiente de un abono que llegó sin pasar por una pantalla (un
/// programado automático, un aviso) o que nadie contestó: en Inicio y en
/// Tarjetas, hasta que se conteste.
class OutsideMatchCard extends StatelessWidget {
  const OutsideMatchCard({super.key, required this.tx});

  final Tx tx;

  @override
  Widget build(BuildContext context) {
    final Ledger l = AppScope.of(context).ledger;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final DateTime? cut = l.pendingOutsideCut(tx);
    if (cut == null) {
      return const SizedBox.shrink();
    }
    final String day = dayText(context, tx.date);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      decoration: BoxDecoration(color: cs.tertiaryContainer, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(t(context, '¿Es el pago del extracto del ${dayText(context, cut)}?', 'Is it the payment of the ${dayText(context, cut)} statement?'), style: TextStyle(fontWeight: FontWeight.w700, color: cs.onTertiaryContainer)),
          const SizedBox(height: 2),
          Text(_outsideMatchText(context, l, tx), style: TextStyle(fontSize: 12, color: cs.onTertiaryContainer)),
          Wrap(
            alignment: WrapAlignment.end,
            children: <Widget>[
              TextButton(
                onPressed: () => l.answerOutsideMatch(tx, same: false),
                child: Text(t(context, 'Es otro pago', 'It is another payment'), semanticsLabel: t(context, 'No, el abono del $day es otro pago', 'No, the $day payment is another one'), style: TextStyle(color: cs.onTertiaryContainer)),
              ),
              TextButton(
                onPressed: () => l.answerOutsideMatch(tx, same: true),
                child: Text(t(context, 'Sí, es ese pago', 'Yes, it is that payment'), semanticsLabel: t(context, 'Sí, el abono del $day es el pago del extracto del ${dayText(context, cut)}', 'Yes, the $day payment is the payment of the ${dayText(context, cut)} statement'), style: TextStyle(color: cs.onTertiaryContainer, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
