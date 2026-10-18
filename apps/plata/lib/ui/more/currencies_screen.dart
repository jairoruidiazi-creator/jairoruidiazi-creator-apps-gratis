import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_scope.dart';
import '../../core/ledger.dart';
import '../../model/models.dart';
import '../../model/money.dart';
import '../widgets/adaptive.dart';

/// Atribución que pide ExchangeRate-API donde se muestran sus tasas.
const String kErApiAttribution = 'Rates By Exchange Rate API';
const String kErApiUrl = 'https://www.exchangerate-api.com';

/// Tasas aceptables a mano: fuera de este rango es casi seguro un error de
/// escritura (un punto de más o de menos).
const double kMinRate = 0.0000001;
const double kMaxRate = 10000000;

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
      ok = await s.rates.refresh(s.ledger.rates, base: s.ledger.baseCurrency, currencies: <String>{...s.settings.extraCurrencies, ...s.ledger.accounts.map((Account a) => a.currency)});
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

  static String _originName(BuildContext context, String? origin) {
    switch (origin) {
      case RateOrigin.trm:
        return 'TRM';
      case RateOrigin.ecb:
        return t(context, 'BCE', 'ECB');
      case RateOrigin.erApi:
        return 'ExchangeRate-API';
    }
    return '';
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
        final bool es = s.settings.spanish;
        final List<String> extras = <String>{...s.settings.extraCurrencies, ...l.accounts.where((Account a) => !a.archived).map((Account a) => a.currency)}.where((String c) => c != l.baseCurrency).toList();
        final bool usesErApi = table.origins.values.contains(RateOrigin.erApi);
        return ReadableScaffold(
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
                title: Text('${t(context, 'Moneda base', 'Base currency')}: ${l.baseCurrency} · ${Money.info(l.baseCurrency).nameFor(spanish: es)}'),
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
                subtitle: Text(t(context, 'Una vez al día si hay internet: TRM oficial (datos.gov.co), Banco Central Europeo (Frankfurter) y, para las monedas que el BCE no publica, ExchangeRate-API. Es la única conexión que hace la app.', 'Once a day when online: official TRM (datos.gov.co), the European Central Bank (Frankfurter) and, for currencies the ECB does not publish, ExchangeRate-API. It is the only connection the app makes.')),
              ),
              if (table.updatedAt != null) Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 4), child: Text('${t(context, 'Última actualización', 'Last update')}: ${formatDate(table.updatedAt!, 'dd MMM yyyy HH:mm', spanish: es)} · ${table.source}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))),
              if (usesErApi)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(onPressed: () => launchUrl(Uri.parse(kErApiUrl), mode: LaunchMode.externalApplication), child: const Text(kErApiAttribution)),
                ),
              if (_message != null) Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 4), child: Text(_message!, style: TextStyle(color: cs.primary))),
              const Divider(),
              if (extras.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(t(context, 'Añade una moneda para tener cuentas en dólares o euros y verlas convertidas en los totales.', 'Add a currency to keep accounts in dollars or euros and see them converted in totals.'))),
              for (final String c in extras)
                ListTile(
                  leading: CircleAvatar(child: Text(Money.info(c).symbol.length > 3 ? c.substring(0, 1) : Money.info(c).symbol, style: const TextStyle(fontSize: 12))),
                  title: Text('$c · ${Money.info(c).nameFor(spanish: es)}'),
                  subtitle: Text(_rateText(context, l, c)),
                  trailing: PopupMenuButton<String>(
                    tooltip: t(context, 'Opciones de $c', '$c options'),
                    onSelected: (String v) async {
                      if (v == 'manual') {
                        final double? r = await askRate(context, c, l.baseCurrency, current: table.manual[c] ?? table.rates[c], automatic: table.rates[c]);
                        if (r != null) {
                          table.manual[c] = r;
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
                      if (s.settings.extraCurrencies.contains(c)) PopupMenuItem<String>(value: 'remove', child: Text(t(context, 'Quitar moneda', 'Remove currency'))),
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
    final bool es = AppScope.of(context).settings.spanish;
    final double? manual = l.rates.manual[c];
    final double? auto = l.rates.rates[c];
    final double? r = manual ?? auto;
    if (r == null) {
      return t(context, 'Sin tasa: se usa 1:1 hasta que se actualice', 'No rate: 1:1 until updated');
    }
    final String value = '1 $c = ${Money.formatRate(r, spanish: es)} ${l.baseCurrency}';
    if (manual != null) {
      return '$value (${t(context, 'manual', 'manual')})';
    }
    final String origin = _originName(context, l.rates.origins[c]);
    return origin.isEmpty ? value : '$value · $origin';
  }

  Future<void> _add(BuildContext context, Services s) async {
    final bool es = s.settings.spanish;
    final List<String> have = <String>{s.ledger.baseCurrency, ...s.settings.extraCurrencies}.toList();
    final String? code = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            for (final CurrencyInfo c in Money.currencies.values)
              if (!have.contains(c.code)) ListTile(leading: CircleAvatar(child: Text(c.symbol.length > 3 ? c.code.substring(0, 1) : c.symbol, style: const TextStyle(fontSize: 12))), title: Text('${c.code} · ${c.nameFor(spanish: es)}'), onTap: () => Navigator.pop(context, c.code)),
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

/// Pide una tasa manual ("1 USD = ¿cuántos COP?") con vista previa, la
/// inversa y un aviso si se aleja mucho de la automática. Acepta "4.123,45",
/// "4123.45", "0,00025" o "1.0856".
Future<double?> askRate(BuildContext context, String currency, String base, {double? current, double? automatic}) async {
  final bool es = AppScope.of(context).settings.spanish;
  final TextEditingController ctrl = TextEditingController(text: current == null ? '' : Money.formatRate(current, spanish: es));
  final double? v = await showDialog<double>(
    context: context,
    builder: (BuildContext context) => StatefulBuilder(
      builder: (BuildContext context, StateSetter setState) {
        final double? r = Money.parseRate(ctrl.text, spanish: es);
        final bool inRange = r != null && r >= kMinRate && r <= kMaxRate;
        String preview;
        if (ctrl.text.trim().isEmpty) {
          preview = '';
        } else if (r == null) {
          preview = t(context, 'Escribe un número mayor que cero.', 'Type a number greater than zero.');
        } else if (!inRange) {
          preview = t(context, 'Esa tasa está fuera de lo razonable; revisa los puntos y comas.', 'That rate is out of range; check the dots and commas.');
        } else {
          preview = '1 $currency = ${Money.formatRate(r, spanish: es)} $base\n1 $base = ${Money.formatRate(1 / r, spanish: es)} $currency';
          if (automatic != null && automatic > 0 && (r / automatic > 1.5 || r / automatic < 1 / 1.5)) {
            preview += '\n${t(context, 'Ojo: es muy distinta de la automática', 'Note: very different from the automatic one')} (${Money.formatRate(automatic, spanish: es)}).';
          }
        }
        return AlertDialog(
          title: Text(t(context, 'Tasa manual de $currency', 'Manual $currency rate')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: t(context, '¿Cuántos $base vale 1 $currency?', 'How many $base is 1 $currency?')),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Text(preview, style: TextStyle(fontSize: 13, color: r != null && inRange ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.error)),
            ],
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(context), child: Text(t(context, 'Cancelar', 'Cancel'))),
            FilledButton(onPressed: r != null && inRange ? () => Navigator.pop(context, r) : null, child: Text(t(context, 'Guardar', 'Save'))),
          ],
        );
      },
    ),
  );
  disposeLater(<ChangeNotifier>[ctrl]);
  return v;
}
