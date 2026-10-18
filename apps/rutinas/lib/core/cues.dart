import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../model/workout.dart';
import 'settings.dart';

/// Sonidos, voz y vibración del temporizador.
abstract class CuePlayer {
  /// Suena uno de los sonidos propios (nada si es [CueSound.none]).
  Future<void> sound(CueSound sound);

  /// Pitido corto de la cuenta atrás.
  Future<void> pip();

  /// Habla con la voz del sistema en el idioma de la app.
  Future<void> speak(String text);

  Future<void> vibrate({bool strong = false});

  /// ¿Hay voz del sistema en el idioma de la app? (null si aún no se sabe).
  bool? get voiceAvailable;

  Future<void> stop();

  Future<void> dispose();
}

/// Archivo de cada sonido dentro de assets/sounds/.
String cueSoundFile(CueSound s) {
  switch (s) {
    case CueSound.auto:
    case CueSound.beep:
      return 'rutinas_beep.wav';
    case CueSound.bell:
      return 'rutinas_bell.wav';
    case CueSound.horn:
      return 'rutinas_horn.wav';
    case CueSound.gong:
      return 'rutinas_gong.wav';
    case CueSound.none:
      return '';
  }
}

/// Reproductor real: audioplayers para los sonidos y flutter_tts para la voz.
/// Los sonidos se mezclan con la música del usuario sin pausarla; la voz la
/// baja un momento mientras habla.
class DeviceCuePlayer implements CuePlayer {
  DeviceCuePlayer(this.settings);

  final AppSettings settings;
  final List<AudioPlayer> _players = <AudioPlayer>[];
  int _next = 0;
  bool _audioReady = false;
  FlutterTts? _tts;
  String? _ttsLanguage;
  bool? _voiceAvailable;

  @override
  bool? get voiceAvailable => _voiceAvailable;

  Future<void> _initAudio() async {
    if (_audioReady) {
      return;
    }
    _audioReady = true;
    try {
      await AudioPlayer.global.setAudioContext(AudioContext(
        android: const AudioContextAndroid(
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.assistanceSonification,
          audioFocus: AndroidAudioFocus.none,
        ),
        iOS: AudioContextIOS(category: AVAudioSessionCategory.playback, options: const <AVAudioSessionOptions>{AVAudioSessionOptions.mixWithOthers}),
      ));
      for (int i = 0; i < 3; i++) {
        final AudioPlayer p = AudioPlayer();
        await p.setReleaseMode(ReleaseMode.stop);
        await p.setPlayerMode(PlayerMode.lowLatency);
        _players.add(p);
      }
    } catch (e) {
      debugPrint('Sonido no disponible: $e');
    }
  }

  Future<void> _play(String file) async {
    if (!settings.sounds || file.isEmpty) {
      return;
    }
    await _initAudio();
    if (_players.isEmpty) {
      return;
    }
    final AudioPlayer p = _players[_next % _players.length];
    _next++;
    try {
      await p.stop();
      await p.setVolume(settings.volume);
      await p.play(AssetSource('sounds/$file'));
    } catch (e) {
      debugPrint('No se pudo reproducir $file: $e');
    }
  }

  @override
  Future<void> sound(CueSound sound) => _play(cueSoundFile(sound));

  @override
  Future<void> pip() => _play('rutinas_pip.wav');

  /// Idiomas de voz preferidos, del más cercano al más general.
  static List<String> preferredLanguages(String language) => language == 'es' ? const <String>['es-CO', 'es-US', 'es-MX', 'es-419', 'es-ES', 'es'] : const <String>['en-US', 'en-GB', 'en-AU', 'en'];

  Future<FlutterTts?> _voice() async {
    final String lang = settings.language;
    if (_tts != null && _ttsLanguage == lang) {
      return _voiceAvailable == true ? _tts : null;
    }
    final FlutterTts tts = _tts ?? FlutterTts();
    _tts = tts;
    _ttsLanguage = lang;
    try {
      if (Platform.isIOS) {
        await tts.setSharedInstance(true);
        await tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playback, <IosTextToSpeechAudioCategoryOptions>[
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          IosTextToSpeechAudioCategoryOptions.duckOthers,
        ], IosTextToSpeechAudioMode.voicePrompt);
      } else if (Platform.isAndroid) {
        await tts.setAudioAttributesForNavigation();
      }
      String? chosen;
      for (final String l in preferredLanguages(lang)) {
        final dynamic ok = await tts.isLanguageAvailable(l);
        if (ok == true || ok == 1) {
          chosen = l;
          break;
        }
      }
      if (chosen == null) {
        final dynamic langs = await tts.getLanguages;
        if (langs is List) {
          for (final dynamic l in langs) {
            if (l is String && l.toLowerCase().startsWith(lang)) {
              chosen = l;
              break;
            }
          }
        }
      }
      if (chosen == null) {
        _voiceAvailable = false;
        return null;
      }
      await tts.setLanguage(chosen);
      await tts.setSpeechRate(Platform.isIOS ? 0.5 : 0.55);
      await tts.awaitSpeakCompletion(false);
      _voiceAvailable = true;
      return tts;
    } catch (e) {
      debugPrint('Voz no disponible: $e');
      _voiceAvailable = false;
      return null;
    }
  }

  @override
  Future<void> speak(String text) async {
    if (!settings.voice || text.trim().isEmpty) {
      return;
    }
    final FlutterTts? tts = await _voice();
    if (tts == null) {
      return;
    }
    try {
      await tts.setVolume(settings.volume);
      await tts.speak(text, focus: true);
    } catch (e) {
      debugPrint('No se pudo hablar: $e');
    }
  }

  @override
  Future<void> vibrate({bool strong = false}) async {
    if (!settings.vibration) {
      return;
    }
    try {
      await (strong ? HapticFeedback.heavyImpact() : HapticFeedback.mediumImpact());
    } catch (_) {}
  }

  @override
  Future<void> stop() async {
    try {
      await _tts?.stop();
    } catch (_) {}
    for (final AudioPlayer p in _players) {
      try {
        await p.stop();
      } catch (_) {}
    }
  }

  @override
  Future<void> dispose() async {
    await stop();
    for (final AudioPlayer p in _players) {
      await p.dispose();
    }
    _players.clear();
    _audioReady = false;
  }
}

/// Reproductor mudo para pruebas y capturas: anota lo que habría sonado.
class SilentCuePlayer implements CuePlayer {
  final List<String> log = <String>[];

  @override
  bool? get voiceAvailable => true;

  @override
  Future<void> sound(CueSound sound) async => log.add('sound:${sound.name}');

  @override
  Future<void> pip() async => log.add('pip');

  @override
  Future<void> speak(String text) async => log.add('speak:$text');

  @override
  Future<void> vibrate({bool strong = false}) async => log.add(strong ? 'vibrate:strong' : 'vibrate');

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
