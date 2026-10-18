import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/bank_rules.dart';
import '../../core/ledger.dart';
import '../../model/models.dart';
import '../transactions/tx_editor.dart';
import '../widgets/adaptive.dart';
import '../widgets/common.dart';

/// Avisos bancarios: consentimiento, activación del acceso a notificaciones
/// (Android) y bandeja de sugerencias por confirmar.
class NoticesScreen extends StatefulWidget {
  const NoticesScreen({super.key});

  @override
  State<NoticesScreen> createState() => _NoticesScreenState();
}

class _NoticesScreenState extends State<NoticesScreen> with WidgetsBindingObserver {
  bool? _supported;
  bool _enabledInSystem = false;
  bool _showHistory = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _check();
    }
  }

  Future<void> _check() async {
    if (!mounted) {
      return;
    }
    final Services s = AppScope.of(context);
    final bool sup = await s.notices.bridge.isSupported();
    final bool en = sup && await s.notices.bridge.isEnabled();
    if (mounted) {
      setState(() {
        _supported = sup;
        _enabledInSystem = en;
      });
    }
    if (en && s.settings.noticesEnabled) {
      await s.notices.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[s.ledger, s.settings]),
      builder: (BuildContext context, Widget? _) {
        final Ledger l = s.ledger;
        final ColorScheme cs = Theme.of(context).colorScheme;
        final List<InboxItem> pending = l.pendingInbox;
        final List<InboxItem> history = l.inbox.where((InboxItem i) => i.status != 'pending').toList().reversed.take(30).toList();
        final bool active = s.settings.noticesEnabled && _enabledInSystem;
        return ReadableScaffold(
          appBar: AppBar(title: Text(t(context, 'Avisos bancarios', 'Bank notices'))),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
            children: <Widget>[
              Card(
                color: cs.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(t(context, 'Cómo funciona', 'How it works'), style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 6),
                      Text(t(
                        context,
                        'Cuando Bancolombia, Nequi, Daviplata, Davivienda, BBVA y otros bancos te notifican una compra o una consignación, Plata lee esa notificación en el teléfono, saca el monto y el comercio, y te lo deja aquí como sugerencia. Nada sale del teléfono: la app no tiene acceso a tu banco ni envía datos a ningún servidor. Solo se leen notificaciones de las apps de bancos; las demás se ignoran.',
                        'When your bank app notifies a purchase or a deposit, Plata reads that notification on the phone, extracts the amount and merchant, and leaves it here as a suggestion. Nothing leaves the phone: the app has no access to your bank and sends no data to any server. Only bank app notifications are read; all others are ignored.',
                      )),
                      const SizedBox(height: 6),
                      Text(t(context, 'Las sugerencias no son prueba de nada: revísalas y confírmalas. Un aviso duplicado, un rechazo o un código de seguridad se descartan solos.', 'Suggestions are not proof of anything: review and confirm them. Duplicates, declines and security codes are dropped automatically.'), style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.7))),
                    ],
                  ),
                ),
              ),
              if (_supported == false)
                ListTile(leading: const Icon(Icons.info_outline), title: Text(t(context, 'Solo disponible en Android', 'Android only')), subtitle: Text(t(context, 'iOS no permite que una app lea las notificaciones de otras. En iPhone puedes anotar con los favoritos de un toque.', 'iOS does not let an app read other apps\' notifications. On iPhone, use the one-tap favorites.')))
              else ...<Widget>[
                SwitchListTile(
                  secondary: const Icon(Icons.notifications_active_outlined),
                  value: s.settings.noticesEnabled,
                  onChanged: _supported == null
                      ? null
                      : (bool v) async {
                          s.settings.noticesEnabled = v;
                          await s.settings.save();
                          if (v) {
                            if (!_enabledInSystem) {
                              await s.notices.bridge.openSettings();
                            } else {
                              await s.notices.start();
                            }
                          } else {
                            await s.notices.stop();
                          }
                        },
                  title: Text(t(context, 'Leer avisos de bancos', 'Read bank notices')),
                  subtitle: Text(active
                      ? t(context, 'Activo. Plata está escuchando las notificaciones de bancos.', 'Active. Plata is listening to bank notifications.')
                      : (s.settings.noticesEnabled ? t(context, 'Falta dar el permiso "Acceso a notificaciones" en Android.', 'The Android "Notification access" permission is still missing.') : t(context, 'Apagado.', 'Off.'))),
                ),
                if (s.settings.noticesEnabled && !_enabledInSystem)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: FilledButton.icon(onPressed: () => s.notices.bridge.openSettings(), icon: const Icon(Icons.settings_outlined), label: Text(t(context, 'Abrir "Acceso a notificaciones"', 'Open "Notification access"'))),
                  ),
                SwitchListTile(
                  secondary: const Icon(Icons.bolt_outlined),
                  value: s.settings.noticesAutoPost,
                  onChanged: (bool v) {
                    s.settings.noticesAutoPost = v;
                    s.settings.save();
                  },
                  title: Text(t(context, 'Anotar sin preguntar', 'Log without asking')),
                  subtitle: Text(t(context, 'Si el aviso coincide con una cuenta (por banco o últimos 4 dígitos) se anota directo; si no, queda en la bandeja.', 'If the notice matches an account (by bank or last 4 digits) it is logged directly; otherwise it waits here.')),
                ),
                ListTile(
                  leading: const Icon(Icons.account_balance_outlined),
                  title: Text(t(context, 'Bancos reconocidos', 'Recognised banks')),
                  subtitle: Text(BankRules.bankNames.values.join(', ')),
                ),
              ],
              const Divider(),
              Padding(padding: const EdgeInsets.fromLTRB(4, 4, 4, 4), child: Text('${t(context, 'Por confirmar', 'To confirm')} (${pending.length})', style: Theme.of(context).textTheme.titleMedium)),
              if (pending.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(t(context, 'Nada pendiente.', 'Nothing pending.'), style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6)))),
              for (final InboxItem i in pending) _InboxTile(item: i),
              if (pending.length > 1)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () async {
                      if (await confirm(context, t(context, '¿Descartar todos?', 'Dismiss all?'), '', yes: t(context, 'Descartar', 'Dismiss'))) {
                        for (final InboxItem i in List<InboxItem>.from(pending)) {
                          l.dismissInbox(i);
                        }
                      }
                    },
                    child: Text(t(context, 'Descartar todos', 'Dismiss all')),
                  ),
                ),
              if (history.isNotEmpty)
                TextButton.icon(onPressed: () => setState(() => _showHistory = !_showHistory), icon: Icon(_showHistory ? Icons.expand_less : Icons.expand_more), label: Text(t(context, 'Historial', 'History'))),
              if (_showHistory) for (final InboxItem i in history) _InboxTile(item: i),
            ],
          ),
        );
      },
    );
  }
}

class _InboxTile extends StatelessWidget {
  const _InboxTile({required this.item});

  final InboxItem item;

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final Ledger l = s.ledger;
    final bool pending = item.status == 'pending';
    final Account? guess = l.account(item.accountId) ?? l.guessAccountForNotice(item);
    return Card(
      child: ListTile(
        leading: CircleAvatar(backgroundColor: kindColor(context, item.kind).withValues(alpha: 0.15), child: Icon(item.kind == TxKind.income ? Icons.south_west : Icons.north_east, color: kindColor(context, item.kind))),
        title: Text('${item.merchant.isEmpty ? BankRules.displayName(item.bank) : item.merchant} · ${money(context, item.amountMinor, item.currency)}'),
        subtitle: Text('${BankRules.displayName(item.bank)}${item.last4.isNotEmpty ? ' *${item.last4}' : ''} · ${formatDate(item.receivedAt, 'dd MMM HH:mm', spanish: s.settings.spanish)}${guess != null ? ' → ${guess.name}' : ''}${pending ? '' : ' · ${item.status == 'accepted' ? t(context, 'anotado', 'logged') : t(context, 'descartado', 'dismissed')}'}\n${item.rawText}', maxLines: 3, overflow: TextOverflow.ellipsis),
        isThreeLine: true,
        trailing: pending
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  IconButton(visualDensity: VisualDensity.compact, tooltip: t(context, 'Anotar', 'Log'), icon: Icon(Icons.check_circle, color: kindColor(context, TxKind.income)), onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => TxEditor(inbox: item)))),
                  IconButton(visualDensity: VisualDensity.compact, tooltip: t(context, 'Descartar', 'Dismiss'), icon: const Icon(Icons.cancel_outlined), onPressed: () => l.dismissInbox(item)),
                ],
              )
            : null,
        onTap: pending ? () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => TxEditor(inbox: item))) : null,
      ),
    );
  }
}
