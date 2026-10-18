import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../legal/legal_document.dart';
import '../widgets/adaptive.dart';
import 'accounts_screen.dart';
import 'backup_screen.dart';
import 'cards_screen.dart';
import 'categories_screen.dart';
import 'currencies_screen.dart';
import 'guide_screen.dart';
import 'notices_screen.dart';
import 'scheduled_screen.dart';
import 'security_screen.dart';
import 'settings_screen.dart';
import 'templates_screen.dart';

/// Pestaña Más: acceso a todas las secciones secundarias.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final bool android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[s.ledger, s.lock]),
      builder: (BuildContext context, Widget? _) => ReadableScaffold(
        appBar: AppBar(title: Text(t(context, 'Más', 'More'))),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: <Widget>[
            _tile(context, Icons.account_balance_wallet_outlined, t(context, 'Cuentas', 'Accounts'), t(context, 'Efectivo, bancos, billeteras, bolsillos, préstamos', 'Cash, banks, wallets, pockets, loans'), const AccountsScreen()),
            _tile(context, Icons.credit_card, t(context, 'Tarjetas de crédito', 'Credit cards'), t(context, 'Estado de cuenta, cuotas y fecha de pago', 'Statement, installments and due date'), const CardsScreen()),
            _tile(context, Icons.label_outline, t(context, 'Categorías', 'Categories'), t(context, 'Gastos e ingresos con subcategorías', 'Expenses and income with subcategories'), const CategoriesScreen()),
            _tile(context, Icons.event_repeat, t(context, 'Programados', 'Scheduled'), t(context, 'Arriendo, servicios, salario, cuotas', 'Rent, utilities, salary, installments'), const ScheduledScreen()),
            _tile(context, Icons.star_outline, t(context, 'Favoritos de un toque', 'One-tap favorites'), t(context, 'Plantillas de lo que anotas seguido', 'Templates for what you log often'), const TemplatesScreen()),
            _tile(context, Icons.currency_exchange, t(context, 'Monedas', 'Currencies'), t(context, 'Dólares, euros y tasas (TRM)', 'Dollars, euros and rates (TRM)'), const CurrenciesScreen()),
            if (android) _tile(context, Icons.notifications_active_outlined, t(context, 'Avisos bancarios', 'Bank notices'), t(context, 'Sugerencias desde las notificaciones del banco', 'Suggestions from bank notifications'), const NoticesScreen(), badge: s.ledger.pendingInbox.length),
            const Divider(),
            _tile(context, s.lock.enabled ? Icons.lock : Icons.lock_open_outlined, t(context, 'Seguridad', 'Security'), s.lock.enabled ? t(context, 'Clave activa', 'Passcode on') : t(context, 'Sin clave de acceso', 'No passcode'), const SecurityScreen()),
            _tile(context, Icons.backup_outlined, t(context, 'Copias de seguridad', 'Backups'), t(context, 'Exportar, importar y copias automáticas', 'Export, import and automatic copies'), const BackupScreen()),
            _tile(context, Icons.settings_outlined, t(context, 'Ajustes', 'Settings'), t(context, 'Periodo, moneda, recordatorios, tema, idioma', 'Period, currency, reminders, theme, language'), const SettingsScreen()),
            _tile(context, Icons.help_outline, t(context, 'Guía y acerca de', 'Guide and about'), t(context, 'Cómo sacarle provecho a Plata', 'How to get the most out of Plata'), const GuideScreen()),
            _tile(context, Icons.privacy_tip_outlined, t(context, 'Política de privacidad', 'Privacy policy'), t(context, 'Qué datos maneja Plata y dónde quedan', 'What data Plata handles and where it stays'), PrivacyPolicyScreen(spanish: s.settings.spanish)),
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, IconData icon, String title, String subtitle, Widget page, {int badge = 0}) => ListTile(
        leading: Badge(isLabelVisible: badge > 0, label: Text('$badge'), child: Icon(icon)),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page)),
      );
}
