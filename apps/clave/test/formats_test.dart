// Formatos por idioma (M15, M7), voz del conteo (M13), tipos de archivo de
// preajustes (B4) y sesión de audio (M9).

import 'dart:ui' show Locale;

import 'package:audioplayers/audioplayers.dart';
import 'package:clave/audio/audio_session.dart';
import 'package:clave/audio/count_in_voice.dart';
import 'package:clave/core/app_scope.dart';
import 'package:clave/core/platform_actions.dart';
import 'package:clave/core/settings.dart';
import 'package:clave/music/notes.dart';
import 'package:clave/ui/recorder/recorder_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Porcentajes, decimales y tiempos según el idioma (M15)', () {
    // Con espacio duro: el número y el signo no se separan al final de una línea.
    expect(formatPercent(0.3, spanish: true), '30\u00a0%');
    expect(formatPercent(0.3, spanish: false), '30%');
    expect(formatDecimal(44.1, spanish: true), '44,1');
    expect(formatDecimal(44.1, spanish: false), '44.1');
    expect(formatDecimal(440, spanish: true, decimals: 0), '440');
    expect(formatMinutes(59), '0 min');
    expect(formatMinutes(12 * 60), '12 min');
    expect(formatMinutes(3900), '1 h 05 min');
    expect(formatMinutes(7200), '2 h');
    expect(formatMinutes(7259), '2 h');
    expect(formatPracticeTime(45), '45 s');
    expect(formatPracticeTime(0), '0 min');
    expect(formatPracticeTime(125), '2 min');
    expect(formatClock(75500), '01:15');
  });

  test('Velocidades, nombres y tipos de archivo de las tomas (M7)', () {
    expect(formatSpeed(0.75, spanish: true), '0,75');
    expect(formatSpeed(0.5, spanish: false), '0.5');
    expect(formatSpeed(1.0, spanish: true), '1');
    expect(kPlaybackSpeeds, contains(1.0));
    expect(shareFileName('Bambuco: toma 3/4', 'recordings/1.m4a'), 'Bambuco_ toma 3_4.m4a');
    expect(shareFileName('   ', 'recordings/1.wav'), 'Clave.wav');
    expect(shareFileName('.oculto', 'recordings/1.flac'), 'Clave.flac');
    expect(shareFileName('x' * 200, 'recordings/1.m4a').length, 60 + '.m4a'.length);
    expect(mimeForFormat('aac'), 'audio/mp4');
    expect(mimeForFormat('wav'), 'audio/wav');
    expect(mimeForFormat('flac'), 'audio/flac');
  });

  test('El conteo usa una voz instalada del idioma de la app (M13)', () {
    expect(pickVoiceLanguage(<String>['en-US', 'es-ES'], spanish: true), 'es-ES');
    expect(pickVoiceLanguage(<String>['es-ES', 'es-CO'], spanish: true), 'es-CO');
    expect(pickVoiceLanguage(<String>['es_US'], spanish: true), 'es_US');
    expect(pickVoiceLanguage(<String>['es'], spanish: true), 'es');
    expect(pickVoiceLanguage(<String>['en-GB', 'en-US'], spanish: false), 'en-US');
    expect(pickVoiceLanguage(<String>['en-IN'], spanish: false), 'en-IN');
    expect(pickVoiceLanguage(<String>['fr-FR', 'pt-BR'], spanish: true), isNull);
    expect(pickVoiceLanguage(<String>[], spanish: false), isNull);
  });

  test('El idioma y la notación iniciales siguen al teléfono (G6)', () {
    expect(languageForLocale(const Locale('es', 'CO')), 'es');
    expect(languageForLocale(const Locale('en', 'US')), 'en');
    expect(languageForLocale(const Locale('pt', 'BR')), 'en');
    expect(languageForLocale(null), 'en');
    final AppSettings en = AppSettings(deviceLocale: const Locale('en', 'GB'));
    expect(en.language, 'en');
    expect(en.spanish, isFalse);
    expect(en.notation, Notation.english);
    final AppSettings es = AppSettings(deviceLocale: const Locale('es', 'MX'));
    expect(es.language, 'es');
    expect(es.notation, Notation.solfeo);
  });

  test('Importar pide JSON con tipo uniforme y MIME (B4)', () {
    expect(kJsonTypeGroup.extensions, contains('json'));
    expect(kJsonTypeGroup.mimeTypes, contains('application/json'));
    expect(kJsonTypeGroup.uniformTypeIdentifiers, contains('public.json'));
  });

  test('La sesión de audio deja sonar otras apps y no pide el foco (M9)', () {
    final AudioContext c = playbackAudioContext();
    expect(c.iOS.category, AVAudioSessionCategory.playback);
    expect(c.iOS.options, contains(AVAudioSessionOptions.mixWithOthers));
    expect(c.android.audioFocus, AndroidAudioFocus.none);
  });
}
