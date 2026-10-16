import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'settings.dart';

/// Voz del sistema en español. Toda instrucción se puede repetir tocando al
/// personaje; si el dispositivo no tiene voz en español, la app sigue
/// funcionando con el texto en pantalla.
class Voice {
  Voice(this.settings);

  final AppSettings settings;
  final FlutterTts _tts = FlutterTts();
  bool _ready = false;
  bool available = false;
  String? language;

  /// Idiomas preferidos, del más local al más general.
  static const List<String> preferred = <String>['es-CO', 'es-MX', 'es-US', 'es-419', 'es-AR', 'es-ES', 'es'];

  Future<void> init() async {
    if (_ready) {
      return;
    }
    _ready = true;
    try {
      String? chosen;
      for (final String lang in preferred) {
        final dynamic ok = await _tts.isLanguageAvailable(lang);
        if (ok == true) {
          chosen = lang;
          break;
        }
      }
      if (chosen == null) {
        final dynamic langs = await _tts.getLanguages;
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
        await _tts.setLanguage(chosen);
        language = chosen;
        available = true;
      }
      await _tts.setSpeechRate(settings.voiceRate);
      await _tts.setPitch(1.05);
      await _tts.setVolume(1.0);
      await _tts.awaitSpeakCompletion(true);
    } catch (e) {
      debugPrint('Voz no disponible: $e');
      available = false;
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
      await _tts.stop();
      await _tts.setSpeechRate(settings.voiceRate);
      await _tts.speak(text);
    } catch (e) {
      debugPrint('Error al hablar: $e');
    }
  }

  /// Dice un texto sin esperar a que termine (para no bloquear la interfaz).
  void sayLater(String text) {
    unawaited(say(text));
  }

  Future<void> stop() async {
    if (!_ready) {
      return;
    }
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
