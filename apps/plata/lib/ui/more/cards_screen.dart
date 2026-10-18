import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/ledger.dart';
import '../../core/periods.dart';
import '../../model/models.dart';
import '../transactions/tx_editor.dart';
import '../transactions/tx_tile.dart';
import '../widgets/common.dart';
import 'accounts_screen.dart';

/// Tarjetas de crédito: estado de cuenta del ciclo, cuotas pendientes y pago.
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
        return Scaffold(
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
                  children: <Widget>[for (final Account c in cards) _CardPanel(card: c)],
                ),
        );
      },
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
    final List<Tx> installments = l.txs.where((Tx tx) => tx.accountId == c.id && tx.installments > 1 && l.remainingInstallments(tx) > 0).toList();
    final int pendingInstallments = installments.fold<int>(0, (int a, Tx tx) => a + (tx.amountMinor / tx.installments).round() * l.remainingInstallments(tx));
    final List<Tx> cycleTxs = l.inPeriod(st.cycle.period, accountId: c.id);
    final CardStatement next = l.nextPayment(c);
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
                      Text('${t(context, 'Corte', 'Statement')} ${c.cutDay} · ${t(context, 'Pago', 'Payment')} ${c.payDay}${c.creditLimitMinor != null ? ' · ${t(context, 'cupo libre', 'available')} ${money(context, c.creditLimitMinor! - (-balance), c.currency, compact: true)}' : ''}', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6))),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => AccountEditor(existing: c)))),
              ],
            ),
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
                        Text(t(context, 'Próximo pago', 'Next payment'), style: TextStyle(fontSize: 12, color: cs.onPrimaryContainer.withValues(alpha: 0.8))),
                        Text('${t(context, 'vence', 'due')} ${formatDate(next.cycle.payDate, 'EEE dd MMM', spanish: es)} · ${t(context, 'corte', 'statement')} ${formatDate(next.cycle.cut, 'dd MMM', spanish: es)}', style: TextStyle(fontSize: 12, color: cs.onPrimaryContainer)),
                      ],
                    ),
                  ),
                  Text(money(context, next.dueMinor, c.currency), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: cs.onPrimaryContainer, fontFeatures: const <FontFeature>[FontFeature.tabularFigures()])),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => _back += 1)),
                Expanded(child: Text('${formatDate(st.cycle.start, 'dd MMM', spanish: es)} – ${formatDate(st.cycle.cut, 'dd MMM yyyy', spanish: es)}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600))),
                IconButton(icon: const Icon(Icons.chevron_right), onPressed: _back == 0 ? null : () => setState(() => _back -= 1)),
              ],
            ),
            _row(context, t(context, 'Compras del ciclo', 'Purchases this cycle'), money(context, st.purchasesMinor, c.currency)),
            _row(context, t(context, 'Cuotas que se facturan', 'Installments billed'), money(context, st.installmentsMinor, c.currency)),
            _row(context, t(context, 'Abonos aplicados', 'Payments applied'), '−${money(context, st.paymentsMinor, c.currency)}'),
            const Divider(),
            _row(context, t(context, 'Saldo del estado de cuenta', 'Statement balance'), money(context, st.dueMinor, c.currency), bold: true),
            Text('${t(context, 'Fecha límite de pago', 'Payment due date')}: ${formatDate(st.cycle.payDate, 'EEE dd MMM yyyy', spanish: es)}', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.65))),
            const SizedBox(height: 4),
            _row(context, t(context, 'Deuda total hoy', 'Total debt today'), money(context, -balance, c.currency)),
            _row(context, t(context, 'Cuotas por facturar', 'Installments still to bill'), money(context, pendingInstallments, c.currency)),
            if (installments.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Text(t(context, 'Compras a cuotas', 'Installment purchases'), style: Theme.of(context).textTheme.titleSmall),
              for (final Tx tx in installments)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(tx.description.isEmpty ? (l.category(tx.categoryId)?.name ?? '') : tx.description, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${formatDate(tx.date, 'dd MMM yyyy', spanish: es)} · ${tx.installments - l.remainingInstallments(tx)}/${tx.installments} ${t(context, 'pagadas', 'billed')}'),
                  trailing: Text('${money(context, (tx.amountMinor / tx.installments).round(), c.currency, compact: true)}/${t(context, 'cuota', 'inst.')}'),
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
                onPressed: next.dueMinor <= 0
                    ? null
                    : () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => TxEditor(kind: TxKind.transfer, initialAccountId: l.activeAccounts.where((Account a) => !a.isCredit && !a.isPocket && !a.isDebit).map((Account a) => a.id).firstOrNull, initialToAccountId: c.id, initialMinor: next.dueMinor, initialDescription: t(context, 'Pago tarjeta', 'Card payment')))),
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
