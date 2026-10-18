import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/ledger.dart';
import '../../model/models.dart';
import '../widgets/common.dart';

/// Fila de un movimiento en las listas.
class TxTile extends StatelessWidget {
  const TxTile({super.key, required this.tx, this.onTap, this.showDate = false});

  final Tx tx;
  final VoidCallback? onTap;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final Ledger l = s.ledger;
    final Account? a = l.account(tx.accountId);
    final Account? to = l.account(tx.toAccountId);
    final Category? c = tx.splits.isEmpty ? l.category(tx.categoryId) : null;
    final bool refund = tx.kind == TxKind.income && tx.splits.isEmpty && l.isRefundCategory(tx.categoryId);
    final Color color = tx.isAdjustment ? Theme.of(context).colorScheme.onSurfaceVariant : kindColor(context, tx.kind);
    final String title = tx.description.isNotEmpty
        ? tx.description
        : (tx.kind == TxKind.transfer
            ? '${a?.name ?? '?'} → ${to?.name ?? '?'}'
            : (tx.isAdjustment ? t(context, 'Ajuste de saldo', 'Balance adjustment') : (tx.splits.isNotEmpty ? t(context, 'Dividido', 'Split') : (c?.name ?? t(context, 'Sin categoría', 'Uncategorized')))));
    final bool crossCurrency = tx.kind == TxKind.transfer && to != null && to.currency != tx.currency;
    final List<String> subtitle = <String>[
      if (showDate) formatDate(tx.date, 'dd MMM', spanish: s.settings.spanish),
      if (tx.isAdjustment) t(context, 'Ajuste (no cuenta en informes)', 'Adjustment (not in reports)'),
      if (refund) t(context, 'Reembolso', 'Refund'),
      if (tx.kind == TxKind.transfer) '${a?.name ?? ''} → ${to?.name ?? ''}' else if (tx.splits.isNotEmpty) counted(context, tx.splits.length, oneEs: 'categoría', manyEs: 'categorías', oneEn: 'category', manyEn: 'categories') else if (c != null) l.categoryPath(c.id),
      if (tx.kind != TxKind.transfer && a != null) a.name,
      if (tx.installments > 1) '${tx.installments} ${t(context, 'cuotas', 'installments')}',
      if (tx.payee.isNotEmpty && tx.payee != tx.description) tx.payee,
    ];
    final String sign = tx.kind == TxKind.expense ? '−' : (tx.kind == TxKind.income ? '+' : '');
    final List<Widget> marks = <Widget>[
      if (tx.attachments.isNotEmpty) Icon(Icons.attachment, size: 14, semanticLabel: t(context, 'Con foto de recibo', 'With receipt photo')),
      if (tx.reconciled) Icon(Icons.check_circle_outline, size: 14, semanticLabel: t(context, 'Conciliado', 'Reconciled')),
      if (tx.source == 'notice') Icon(Icons.notifications_outlined, size: 14, semanticLabel: t(context, 'Desde un aviso del banco', 'From a bank notice')),
      if (tx.scheduledId != null) Icon(Icons.event_repeat, size: 14, semanticLabel: t(context, 'Programado', 'Scheduled')),
    ];
    return ListTile(
      leading: tx.kind == TxKind.transfer
          ? CircleAvatar(backgroundColor: color.withValues(alpha: 0.15), child: Icon(Icons.swap_horiz, color: color))
          : (tx.isAdjustment
              ? CircleAvatar(backgroundColor: color.withValues(alpha: 0.12), child: Icon(Icons.tune, color: color))
              : IconBadge(icon: c?.icon ?? (tx.splits.isNotEmpty ? 'label' : 'more'), color: c?.color ?? 0xFF9E9E9E)),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle.join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
      // Con texto grande el monto se reduce antes que empujar el título.
      trailing: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.42),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text('$sign${money(context, tx.amountMinor, tx.currency)}', style: TextStyle(fontWeight: FontWeight.w700, color: color, fontFeatures: const <FontFeature>[FontFeature.tabularFigures()])),
              if (crossCurrency) Text('→ ${money(context, l.receivedMinor(tx), to.currency)}', style: TextStyle(fontSize: 12, color: color)),
              if (marks.isNotEmpty) Row(mainAxisSize: MainAxisSize.min, children: marks),
            ],
          ),
        ),
      ),
      onTap: onTap,
    );
  }
}
