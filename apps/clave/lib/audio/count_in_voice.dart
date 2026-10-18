import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Elige la voz del sistema para el conteo: la primera de [preferred] que
/// esté instalada o, si no, cualquiera del mismo idioma. null si no hay
/// ninguna voz de ese idioma.
String? pickVoiceLanguage(List<String> installed, {required bool spanish}) {
  final List<String> preferred = spanish ? const <String>['es-CO', 'es-419', 'es-US', 'es-MX', 'es-ES'] : const <String>['en-US', 'en-GB', 'en-AU', 'en-CA'];
  String norm(String s) => s.replaceAll('_', '-').toLowerCase();
  final List<String> have = installed.map(norm).toList();
  for (final String p in preferred) {
    final int i = have.indexOf(p.toLowerCase());
    if (i >= 0) {
      return installed[i];
    }
  }
  final String prefix = spanish ? 'es' : 'en';
  for (int i = 0; i < have.length; i++) {
    if (have[i] == prefix || have[i].startsWith('$prefix-')) {
      return installed[i];
    }
  }
  return null;
}

/// Conteo hablado del metrónomo con la voz del sistema.
class CountInVoice {
  CountInVoice();

  FlutterTts? _tts;
  String? _language;
  bool? _spanish;

  FlutterTts get _engine => _tts ??= FlutterTts();

  /// Prepara la voz del idioma. Devuelve false si el teléfono no tiene una
  /// voz de ese idioma (o no hay motor de voz): la app avisa y no habla.
  Future<bool> prepare({required bool spanish}) async {
    if (_spanish == spanish && _language != null) {
      return true;
    }
    _spanish = spanish;
    _language = null;
    try {
      final Object? raw = await _engine.getLanguages;
      final List<String> installed = raw is List ? raw.whereType<String>().toList() : <String>[];
      final String? lang = pickVoiceLanguage(installed, spanish: spanish);
      if (lang == null) {
        return false;
      }
      final Object? ok = await _engine.setLanguage(lang);
      if (ok != 1 && ok != true) {
        return false;
      }
      await _engine.setSpeechRate(0.6);
      _language = lang;
      return true;
    } catch (e) {
      debugPrint('Voz del conteo: $e');
      return false;
    }
  }

  Future<void> speak(int n) async {
    final bool? spanish = _spanish;
    if (_language == null || spanish == null || n < 1 || n > 12) {
      return;
    }
    const List<String> es = <String>['uno', 'dos', 'tres', 'cuatro', 'cinco', 'seis', 'siete', 'ocho', 'nueve', 'diez', 'once', 'doce'];
    const List<String> en = <String>['one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', 'eleven', 'twelve'];
    try {
      await _engine.speak(spanish ? es[n - 1] : en[n - 1]);
    } catch (e) {
      debugPrint('Voz del conteo: $e');
    }
  }

  Future<void> stop() async {
    final FlutterTts? t = _tts;
    if (t == null) {
      return;
    }
    try {
      await t.stop();
    } catch (_) {}
  }
}
