import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../model/models.dart';

/// Tasas de cambio: la TRM oficial (datos abiertos de la Superintendencia
/// Financiera, conjunto 32sa-8pi3) para el dólar, y Frankfurter (Banco Central
/// Europeo) para las demás monedas, con open.er-api.com como respaldo para las
/// latinoamericanas que el BCE no publica. Una consulta al día, opcional.
class RateService {
  RateService({http.Client? client, this.timeout = const Duration(seconds: 12)}) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  static const String trmUrl = 'https://www.datos.gov.co/resource/32sa-8pi3.json?\$order=vigenciadesde%20DESC&\$limit=1';
  static const String frankfurterUrl = 'https://api.frankfurter.app/latest?from=USD';
  static const String erApiUrl = 'https://open.er-api.com/v6/latest/USD';

  /// Actualiza [table] (tasas "1 unidad = x [base]") para [currencies].
  /// Devuelve verdadero si consiguió al menos la TRM.
  Future<bool> refresh(RateTable table, {required String base, required Set<String> currencies, DateTime? now}) async {
    final Set<String> wanted = <String>{...currencies, 'USD', 'COP'}..remove(base);
    // 1. Tasas de cada moneda a dólar (1 USD = r[X] X).
    final Map<String, double> perUsd = <String, double>{'USD': 1};
    double? trm;
    try {
      trm = await _fetchTrm();
      if (trm != null) {
        perUsd['COP'] = trm;
      }
    } catch (e) {
      debugPrint('TRM: $e');
    }
    final Set<String> others = wanted.where((String c) => c != 'USD' && c != 'COP').toSet();
    if (others.isNotEmpty || base != 'COP' && base != 'USD') {
      try {
        perUsd.addAll(await _fetchFrankfurter());
      } catch (e) {
        debugPrint('Frankfurter: $e');
      }
      final Set<String> missing = <String>{...others, base}.where((String c) => !perUsd.containsKey(c)).toSet();
      if (missing.isNotEmpty) {
        try {
          final Map<String, double> er = await _fetchErApi();
          for (final String c in missing) {
            if (er.containsKey(c)) {
              perUsd[c] = er[c]!;
            }
          }
          perUsd.putIfAbsent('COP', () => er['COP'] ?? 0);
        } catch (e) {
          debugPrint('er-api: $e');
        }
      }
    }
    final double? basePerUsd = perUsd[base];
    if (basePerUsd == null || basePerUsd <= 0) {
      return false;
    }
    bool any = false;
    for (final String c in wanted) {
      final double? r = perUsd[c];
      if (r != null && r > 0) {
        // 1 X = (1/r) USD = basePerUsd / r [base]
        table.rates[c] = basePerUsd / r;
        any = true;
      }
    }
    if (any) {
      table.updatedAt = now ?? DateTime.now();
      table.source = trm != null ? 'TRM + BCE' : 'BCE';
    }
    return any;
  }

  Future<double?> _fetchTrm() async {
    final http.Response r = await _client.get(Uri.parse(trmUrl), headers: <String, String>{'Accept': 'application/json'}).timeout(timeout);
    if (r.statusCode != 200) {
      return null;
    }
    final dynamic body = jsonDecode(r.body);
    if (body is List && body.isNotEmpty && body.first is Map) {
      final dynamic v = (body.first as Map<String, dynamic>)['valor'];
      final double? d = v is num ? v.toDouble() : double.tryParse(v.toString());
      return d != null && d > 0 ? d : null;
    }
    return null;
  }

  Future<Map<String, double>> _fetchFrankfurter() async {
    final http.Response r = await _client.get(Uri.parse(frankfurterUrl)).timeout(timeout);
    if (r.statusCode != 200) {
      return <String, double>{};
    }
    final dynamic body = jsonDecode(r.body);
    final Map<String, double> out = <String, double>{};
    if (body is Map && body['rates'] is Map) {
      (body['rates'] as Map<String, dynamic>).forEach((String k, dynamic v) {
        if (v is num && v > 0) {
          out[k] = v.toDouble();
        }
      });
    }
    return out;
  }

  Future<Map<String, double>> _fetchErApi() async {
    final http.Response r = await _client.get(Uri.parse(erApiUrl)).timeout(timeout);
    if (r.statusCode != 200) {
      return <String, double>{};
    }
    final dynamic body = jsonDecode(r.body);
    final Map<String, double> out = <String, double>{};
    if (body is Map && body['rates'] is Map) {
      (body['rates'] as Map<String, dynamic>).forEach((String k, dynamic v) {
        if (v is num && v > 0) {
          out[k] = v.toDouble();
        }
      });
    }
    return out;
  }

  void dispose() => _client.close();
}
