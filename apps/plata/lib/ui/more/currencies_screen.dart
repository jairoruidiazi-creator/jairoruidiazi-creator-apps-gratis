import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/ledger.dart';
import '../../model/models.dart';
import '../../model/money.dart';
import '../widgets/common.dart';

/// Monedas extra y tasas de cambio (TRM / BCE o manual).
class CurrenciesScreen extends StatefulWidget {
  const CurrenciesScreen({super.key});

  @override
  State<CurrenciesScreen> createState() => _CurrenciesScreenState();
}

class _CurrenciesScreenState extends State<CurrenciesScreen> {
  bool _busy = false;
  String? _message;

  Future<void> _refresh() async {
    final Services s = AppScope.of(context);
    setState(() {
      _busy = true;
      _message = null;
    });
    bool ok = false;
    try {
      ok = await s.rates.refresh(s.ledger.rates, base: s.ledger.baseCurrency, currencies: s.settings.extraCurrencies.toSet());
    } catch (_) {
      ok = false;
    }
    s.settings.lastRatesAttempt = clock.now();
    await s.settings.save();
    if (ok) {
      s.ledger.save();
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _message = ok ? t(context, 'Tasas actualizadas.', 'Rates updated.') : t(context, 'Sin conexión o sin respuesta. Puedes escribir la tasa a mano.', 'No connection or no answer. You can type the rate by hand.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[s.ledger, s.settings]),
      builder: (BuildContext context, Widget? _) {
        final Ledger l = s.ledger;
        final RateTable table = l.rates;
        final ColorScheme cs = Theme.of(context).colorScheme;
        final List<String> extras = s.settings.extraCurrencies.where((String c) => c != l.baseCurrency).toList();
        return Scaffold(
          appBar: AppBar(
            title: Text(t(context, 'Monedas', 'Currencies')),
            actions: <Widget>[
              IconButton(tooltip: t(context, 'Actualizar tasas', 'Refresh rates'), icon: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh), onPressed: _busy ? null : _refresh),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(heroTag: null, onPressed: () => _add(context, s), icon: const Icon(Icons.add), label: Text(t(context, 'Moneda', 'Currency'))),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: Text('${t(context, 'Moneda base', 'Base currency')}: ${l.baseCurrency} · ${Money.info(l.baseCurrency).name}'),
                subtitle: Text(t(context, 'Los totales e informes se muestran en esta moneda. Se cambia en Ajustes.', 'Totals and reports are shown in this currency. Change it in Settings.')),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.cloud_download_outlined),
                value: s.settings.ratesAuto,
                onChanged: (bool v) {
                  s.settings.ratesAuto = v;
                  s.settings.save();
                },
                title: Text(t(context, 'Actualizar tasas automáticamente', 'Update rates automatically')),
                subtitle: Text(t(context, 'Una vez al día si hay internet: TRM oficial (datos.gov.co) y Banco Central Europeo. Es la única conexión que hace la app.', 'Once a day when online: official TRM (datos.gov.co) and the European Central Bank. It is the only connection the app makes.')),
              ),
              if (table.updatedAt != null) Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 4), child: Text('${t(context, 'Última actualización', 'Last update')}: ${formatDate(table.updatedAt!, 'dd MMM yyyy HH:mm', spanish: s.settings.spanish)} · ${table.source}', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6)))),
              if (_message != null) Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 4), child: Text(_message!, style: TextStyle(color: cs.primary))),
              const Divider(),
              if (extras.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(t(context, 'Añade una moneda para tener cuentas en dólares o euros y verlas convertidas en los totales.', 'Add a currency to keep accounts in dollars or euros and see them converted in totals.'))),
              for (final String c in extras)
                ListTile(
                  leading: CircleAvatar(child: Text(Money.info(c).symbol.length > 3 ? c.substring(0, 1) : Money.info(c).symbol, style: const TextStyle(fontSize: 12))),
                  title: Text('$c · ${Money.info(c).name}'),
                  subtitle: Text(_rateText(context, l, c)),
                  trailing: PopupMenuButton<String>(
                    onSelected: (String v) async {
                      if (v == 'manual') {
                        final String? txt = await askText(context, '1 $c = ¿cuántos ${l.baseCurrency}?', initial: table.manual[c]?.toString() ?? table.rates[c]?.toStringAsFixed(2) ?? '', keyboard: const TextInputType.numberWithOptions(decimal: true));
                        final int? minor = txt == null ? null : Money.parse(txt);
                        if (minor != null && minor > 0) {
                          table.manual[c] = minor / 100;
                          l.save();
                        }
                      } else if (v == 'auto') {
                        table.manual.remove(c);
                        l.save();
                      } else if (v == 'remove') {
                        final bool used = l.accounts.any((Account a) => a.currency == c);
                        if (used) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context, 'Hay cuentas en esa moneda; archívalas primero.', 'There are accounts in that currency; archive them first.'))));
                          }
                          return;
                        }
                        s.settings.extraCurrencies = s.settings.extraCurrencies.where((String x) => x != c).toList();
                        await s.settings.save();
                      }
                    },
                    itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                      PopupMenuItem<String>(value: 'manual', child: Text(t(context, 'Tasa manual…', 'Manual rate…'))),
                      if (table.manual.containsKey(c)) PopupMenuItem<String>(value: 'auto', child: Text(t(context, 'Volver a automática', 'Back to automatic'))),
                      PopupMenuItem<String>(value: 'remove', child: Text(t(context, 'Quitar moneda', 'Remove currency'))),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  String _rateText(BuildContext context, Ledger l, String c) {
    final double? manual = l.rates.manual[c];
    final double? auto = l.rates.rates[c];
    final double? r = manual ?? auto;
    if (r == null) {
      return t(context, 'Sin tasa: se usa 1:1 hasta que se actualice', 'No rate: 1:1 until updated');
    }
    final String value = Money.format((r * 100).round(), l.baseCurrency, showCents: true);
    return manual != null ? '1 $c = $value (${t(context, 'manual', 'manual')})' : '1 $c = $value';
  }

  Future<void> _add(BuildContext context, Services s) async {
    final List<String> have = <String>{s.ledger.baseCurrency, ...s.settings.extraCurrencies}.toList();
    final String? code = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            for (final CurrencyInfo c in Money.currencies.values)
              if (!have.contains(c.code)) ListTile(leading: CircleAvatar(child: Text(c.symbol.length > 3 ? c.code.substring(0, 1) : c.symbol, style: const TextStyle(fontSize: 12))), title: Text('${c.code} · ${c.name}'), onTap: () => Navigator.pop(context, c.code)),
          ],
        ),
      ),
    );
    if (code == null) {
      return;
    }
    s.settings.extraCurrencies = <String>[...s.settings.extraCurrencies, code];
    await s.settings.save();
    if (s.settings.ratesAuto && mounted) {
      await _refresh();
    }
  }
}
