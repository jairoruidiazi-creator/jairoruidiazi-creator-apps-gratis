import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'settings.dart';

/// Voz del sistema en español. Toda instrucción se puede repetir tocando el
/// altavoz; si el dispositivo no tiene voz en español, la app sigue con el
/// texto en pantalla y lo avisa (en Ajustes y en el inicio de los niños que
/// todavía no leen). Avisa a quien escuche cuando termina de prepararse.
class Voice extends ChangeNotifier {
  Voice(this.settings, {FlutterTts? tts}) : _ttsOverride = tts;

  final AppSettings settings;
  final FlutterTts? _ttsOverride;
  FlutterTts? _tts;
  Future<void>? _initFuture;

  /// Ya se intentó preparar la voz (con o sin éxito).
  bool ready = false;

  /// Hay una voz en español.
  bool available = false;

  /// Idioma de la voz elegida (por ejemplo es-CO).
  String? language;

  /// Idiomas preferidos, del más local al más general.
  static const List<String> preferred = <String>['es-CO', 'es-MX', 'es-US', 'es-419', 'es-AR', 'es-ES', 'es'];

  FlutterTts get _engine => _tts ??= _ttsOverride ?? FlutterTts();

  Future<void> init() => _initFuture ??= _init();

  Future<void> _init() async {
    try {
      final FlutterTts tts = _engine;
      String? chosen;
      for (final String lang in preferred) {
        final dynamic ok = await tts.isLanguageAvailable(lang);
        if (ok == true) {
          chosen = lang;
          break;
        }
      }
      if (chosen == null) {
        final dynamic langs = await tts.getLanguages;
        if (langs is List) {
          for (final dynamic l in langs) {
            if (l is String && l.toLowerCase().startsWith('es')) {
              chosen = l;
              break;
            }
          }
        }
      }
      if (chosen != null) {
        await tts.setLanguage(chosen);
        language = chosen;
        available = true;
        await _preferLocalVoice(tts, chosen);
      }
      await tts.setSpeechRate(settings.voiceRate);
      await tts.setPitch(1.05);
      await tts.setVolume(1.0);
      await tts.awaitSpeakCompletion(true);
    } catch (e) {
      debugPrint('Voz no disponible: $e');
      available = false;
    }
    ready = true;
    notifyListeners();
  }

  /// En Android, si el motor ofrece una voz instalada en el teléfono para el
  /// idioma elegido, se usa esa y no una que necesite internet.
  Future<void> _preferLocalVoice(FlutterTts tts, String lang) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      final dynamic voices = await tts.getVoices;
      if (voices is! List) {
        return;
      }
      final String want = lang.toLowerCase();
      Map<dynamic, dynamic>? best;
      for (final dynamic v in voices) {
        if (v is! Map) {
          continue;
        }
        final String locale = '${v['locale'] ?? ''}'.toLowerCase();
        final bool red = '${v['network_required'] ?? '0'}' == '1';
        final bool noInstalada = '${v['features'] ?? ''}'.contains('notInstalled');
        if (red || noInstalada || !locale.startsWith(want.split('-').first)) {
          continue;
        }
        if (best == null || locale == want) {
          best = v;
        }
      }
      if (best != null) {
        await tts.setVoice(<String, String>{'name': '${best['name']}', 'locale': '${best['locale']}'});
      }
    } catch (e) {
      debugPrint('No se pudo elegir una voz local: $e');
    }
  }

  /// Dice un texto. Interrumpe lo que se estuviera diciendo.
  Future<void> say(String text) async {
    if (!settings.voiceEnabled || text.trim().isEmpty) {
      return;
    }
    await init();
    if (!available) {
      return;
    }
    try {
      await _engine.stop();
      await _engine.setSpeechRate(settings.voiceRate);
      await _engine.speak(text);
    } catch (e) {
      debugPrint('Error al hablar: $e');
    }
  }

  /// Dice un texto sin esperar a que termine (para no bloquear la interfaz).
  void sayLater(String text) {
    unawaited(say(text));
  }

  Future<void> stop() async {
    if (_tts == null) {
      return;
    }
    try {
      await _tts!.stop();
    } catch (_) {}
  }
}
