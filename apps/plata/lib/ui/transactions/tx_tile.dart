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
    final Color color = kindColor(context, tx.kind);
    final String title = tx.description.isNotEmpty
        ? tx.description
        : (tx.kind == TxKind.transfer ? '${a?.name ?? '?'} → ${to?.name ?? '?'}' : (tx.splits.isNotEmpty ? t(context, 'Dividido', 'TxSplit') : (c?.name ?? t(context, 'Sin categoría', 'Uncategorized'))));
    final List<String> subtitle = <String>[
      if (showDate) formatDate(tx.date, 'dd MMM', spanish: s.settings.spanish),
      if (tx.kind == TxKind.transfer) '${a?.name ?? ''} → ${to?.name ?? ''}' else if (tx.splits.isNotEmpty) '${tx.splits.length} ${t(context, 'categorías', 'categories')}' else if (c != null) l.categoryPath(c.id),
      if (tx.kind != TxKind.transfer && a != null) a.name,
      if (tx.installments > 1) '${tx.installments} ${t(context, 'cuotas', 'installments')}',
      if (tx.payee.isNotEmpty && tx.payee != tx.description) tx.payee,
    ];
    final String sign = tx.kind == TxKind.expense ? '−' : (tx.kind == TxKind.income ? '+' : '');
    return ListTile(
      leading: tx.kind == TxKind.transfer
          ? CircleAvatar(backgroundColor: color.withValues(alpha: 0.15), child: Icon(Icons.swap_horiz, color: color))
          : IconBadge(icon: c?.icon ?? (tx.splits.isNotEmpty ? 'label' : 'more'), color: c?.color ?? 0xFF9E9E9E),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Text('$sign${money(context, tx.amountMinor, tx.currency)}', style: TextStyle(fontWeight: FontWeight.w700, color: color, fontFeatures: const <FontFeature>[FontFeature.tabularFigures()])),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (tx.attachments.isNotEmpty) const Icon(Icons.attachment, size: 14),
              if (tx.reconciled) const Icon(Icons.check_circle_outline, size: 14),
              if (tx.source == 'notice') const Icon(Icons.notifications_outlined, size: 14),
              if (tx.scheduledId != null) const Icon(Icons.event_repeat, size: 14),
            ],
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}
