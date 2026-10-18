import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/bank_rules.dart';
import '../../core/ledger.dart';
import '../../model/models.dart';
import '../home/home_screen.dart';
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
        // La bandeja va de lo más nuevo a lo más viejo: el historial muestra los 30 más recientes.
        final List<InboxItem> history = l.noticeHistory();
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
                        'Cuando la app de tu banco o billetera te notifica una compra o una consignación, Plata lee esa notificación en el teléfono, saca el monto y el comercio, y te lo deja aquí como sugerencia. Nada sale del teléfono: la app no tiene acceso a tu banco ni envía datos a ningún servidor. Solo se leen las notificaciones de las apps de la lista de abajo; las demás se ignoran.',
                        'When your bank or wallet app notifies a purchase or a deposit, Plata reads that notification on the phone, extracts the amount and merchant, and leaves it here as a suggestion. Nothing leaves the phone: the app has no access to your bank and sends no data to any server. Only notifications from the apps listed below are read; all others are ignored.',
                      )),
                      const SizedBox(height: 6),
                      Text(t(context, 'Las sugerencias no son prueba de nada: revísalas y confírmalas. Un aviso duplicado, un rechazo, un código de seguridad o publicidad se descartan solos. Los pagos de tarjeta, retiros y movimientos entre tus cuentas se proponen como transferencias, para no contarlos como gasto.', 'Suggestions are not proof of anything: review and confirm them. Duplicates, declines, security codes and ads are dropped automatically. Card payments, withdrawals and moves between your own accounts are proposed as transfers so they are not counted as spending.'), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
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
                          // Aviso destacado antes de pedir el acceso especial (política
                          // de datos de usuario de Google Play): qué se lee y para qué.
                          if (v && !_enabledInSystem) {
                            final bool ok = await confirm(
                              context,
                              t(context, '¿Permitir que Plata lea los avisos de tus bancos?', 'Allow Plata to read your bank notifications?'),
                              t(
                                context,
                                'Plata leerá el título y el texto de las notificaciones de las apps de bancos y billeteras de su lista para sugerirte el movimiento con el monto y el comercio. Las notificaciones de otras apps se ignoran. Todo se procesa en el teléfono y no se envía a ningún servidor. Puedes quitar el acceso cuando quieras.\n\nEn la siguiente pantalla busca Plata en "Acceso a notificaciones" y actívalo.',
                                'Plata will read the title and text of notifications from the bank and wallet apps on its list to suggest the transaction with its amount and merchant. Notifications from other apps are ignored. Everything is processed on the phone and nothing is sent to any server. You can revoke access at any time.\n\nOn the next screen, find Plata under "Notification access" and turn it on.',
                              ),
                              yes: t(context, 'Continuar', 'Continue'),
                            );
                            if (!ok) {
                              return;
                            }
                          }
                          s.settings.noticesEnabled = v;
                          await s.settings.save();
                          if (v) {
                            await s.notices.bridge.setEnabled(true);
                            if (!_enabledInSystem) {
                              await s.notices.bridge.openSettings();
                            } else {
                              await s.notices.start();
                            }
                            return;
                          }
                          // Apagado de verdad: el servicio deja de guardar avisos, se
                          // borran los que esperaban y se ofrece quitar el permiso.
                          await s.notices.disable();
                          if (_enabledInSystem && context.mounted) {
                            final bool open = await confirm(
                              context,
                              t(context, 'Plata ya no lee avisos', 'Plata no longer reads notices'),
                              t(context, 'Se borraron los avisos que esperaban. Android todavía le da a Plata el "Acceso a notificaciones": si quieres quitarlo también, desactívalo en la siguiente pantalla.', 'Waiting notices were deleted. Android still grants Plata "Notification access": to remove it too, turn it off on the next screen.'),
                              yes: t(context, 'Quitar el permiso', 'Remove access'),
                            );
                            if (open) {
                              await s.notices.bridge.openSettings();
                            }
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
                  subtitle: Text(t(context, 'Solo gastos e ingresos cuya cuenta se reconoce sin dudas: por sus últimos 4 dígitos o porque es tu única cuenta de ese banco (sin dígitos registrados), y en la misma moneda. Lo demás queda aquí para revisar.', 'Only expenses and income whose account is recognised without doubt: by its last 4 digits, or because it is your only account at that bank (with no digits set), and in the same currency. Everything else waits here for review.')),
                ),
                ListTile(
                  leading: const Icon(Icons.account_balance_outlined),
                  title: Text(t(context, 'Apps que se leen', 'Apps that are read')),
                  subtitle: Text('${BankRules.namesList(spanish: s.settings.spanish)}. ${t(context, 'Para que un aviso se asocie a tu cuenta, elige el banco en la cuenta (Más › Cuentas).', 'For a notice to match your account, choose the bank on the account (More › Accounts).')}'),
                ),
              ],
              const Divider(),
              Padding(padding: const EdgeInsets.fromLTRB(4, 4, 4, 4), child: Text('${t(context, 'Por confirmar', 'To confirm')} (${pending.length})', style: Theme.of(context).textTheme.titleMedium)),
              if (pending.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(t(context, 'Nada pendiente.', 'Nothing pending.'), style: TextStyle(color: cs.onSurfaceVariant))),
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
    final Account? guess = l.account(item.accountId) ?? l.matchNotice(item).account;
    void log() => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => TxEditor(inbox: item)));
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ListTile(
            leading: CircleAvatar(backgroundColor: kindColor(context, item.kind).withValues(alpha: 0.15), child: Icon(noticeIcon(item), color: kindColor(context, item.kind))),
            title: Text('${item.merchant.isEmpty ? BankRules.displayName(item.bank, spanish: s.settings.spanish) : item.merchant} · ${money(context, item.amountMinor, item.currency)}'),
            subtitle: Text('${pending ? noticeHint(context, item) : ''}${BankRules.displayName(item.bank, spanish: s.settings.spanish)}${item.last4.isNotEmpty ? ' *${item.last4}' : ''} · ${formatDate(item.receivedAt, 'dd MMM HH:mm', spanish: s.settings.spanish)}${guess != null ? ' → ${guess.name}' : ''}${pending ? '' : ' · ${item.status == 'accepted' ? t(context, 'anotado', 'logged') : t(context, 'descartado', 'dismissed')}'}\n${item.rawText}', maxLines: 3, overflow: TextOverflow.ellipsis),
            isThreeLine: true,
            onTap: pending ? log : null,
          ),
          // Acciones con texto y tamaño de toque completo (antes eran dos íconos apilados).
          if (pending)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: 8,
                children: <Widget>[
                  TextButton.icon(onPressed: () => l.dismissInbox(item), icon: const Icon(Icons.close), label: Text(t(context, 'Descartar', 'Dismiss'))),
                  FilledButton.tonalIcon(onPressed: log, icon: const Icon(Icons.check), label: Text(t(context, 'Anotar', 'Log'))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
