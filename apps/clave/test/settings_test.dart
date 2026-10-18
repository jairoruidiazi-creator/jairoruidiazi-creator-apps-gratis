// Ajustes: lo guardado se valida al leer (G11), solo se escriben las claves
// que cambian y solo el idioma y el tema rehacen la app (M10), y el ritmo del
// metrónomo se recuerda (M11).

import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:clave/audio/sequencer.dart';
import 'package:clave/core/settings.dart';
import 'package:clave/music/notes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Sin nada guardado, idioma y notación del teléfono; luego manda lo guardado (G6)', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final AppSettings fresh = AppSettings(deviceLocale: const Locale('en', 'US'));
    await fresh.load();
    expect(fresh.language, 'en');
    expect(fresh.notation, Notation.english);
    SharedPreferences.setMockInitialValues(<String, Object>{'language': 'es', 'notation': Notation.german.index});
    final AppSettings saved = AppSettings(deviceLocale: const Locale('en', 'US'));
    await saved.load();
    expect(saved.language, 'es');
    expect(saved.notation, Notation.german);
  });

  test('Al cambiar el idioma la notación lo sigue, salvo que se haya elegido a mano (2.ª ronda, N-M7)', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final AppSettings st = AppSettings(deviceLocale: const Locale('en', 'US'));
    await st.load();
    expect(st.notation, Notation.english);
    st.setLanguage('es');
    await st.save();
    expect(st.notation, Notation.solfeo);
    st.setLanguage('en');
    await st.save();
    expect(st.notation, Notation.english);
    // Elegida a mano: ya no cambia con el idioma, tampoco al volver a abrir.
    st.chooseNotation(Notation.german);
    await st.save();
    st.setLanguage('es');
    await st.save();
    expect(st.notation, Notation.german);
    final AppSettings again = AppSettings(deviceLocale: const Locale('en', 'US'));
    await again.load();
    expect(again.notationChosen, isTrue);
    again.setLanguage('en');
    expect(again.notation, Notation.german);
    // La notación que cambió sola con el idioma no cuenta como elegida.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final AppSettings auto = AppSettings(deviceLocale: const Locale('en', 'US'));
    await auto.load();
    auto.setLanguage('es');
    await auto.save();
    final AppSettings reopened = AppSettings(deviceLocale: const Locale('en', 'US'));
    await reopened.load();
    expect(reopened.notation, Notation.solfeo);
    expect(reopened.notationChosen, isFalse);
    reopened.setLanguage('en');
    expect(reopened.notation, Notation.english);
  });

  test('Valores guardados fuera de rango o de otro tipo se corrigen (G11)', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'language': 'fr',
      'themeMode': 'neón',
      'a4': 'cuatrocientos',
      'temperament': 99,
      'temperamentRoot': -4,
      'customTemperament': <String>['10', 'NaN', '900', 'x'],
      'transposition': 40,
      'capo': -2,
      'toleranceCents': 1e9,
      'damping': -1.0,
      'audioDelayMs': 5000,
      'recordingFormat': 'mp3',
      'dailyGoalMinutes': 0,
      'metronomeVolume': 3.0,
      'beatView': 'otro',
      'metronomeConfig': '{no es json',
      'activeSetlistIndex': -8,
    });
    final AppSettings st = AppSettings();
    await st.load();
    expect(st.language, 'es');
    expect(st.themeMode, 'system');
    expect(st.a4, 440);
    expect(st.temperament, Temperament.values.last);
    expect(st.temperamentRoot, 0);
    expect(st.customTemperament.every((double c) => c.isFinite && c.abs() <= 50), isTrue);
    expect(st.transposition, 14);
    expect(st.capo, 0);
    expect(st.toleranceCents, 15);
    expect(st.damping, 0);
    expect(st.audioDelayMs, AppSettings.maxAudioDelayMs);
    expect(st.recordingFormat, 'aac');
    expect(st.dailyGoalMinutes, 5);
    expect(st.metronomeVolume, 1);
    expect(st.beatView, 'pendulum');
    expect(st.savedRhythm, isNull);
    expect(st.activeSetlistIndex, 0);
  });

  test('Guardar escribe solo lo que cambió y solo el idioma o el tema avisan a toda la app (M10)', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final AppSettings st = AppSettings();
    await st.load();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    int appearance = 0;
    int all = 0;
    st.appearance.addListener(() => appearance++);
    st.addListener(() => all++);
    st.metronomeVolume = 0.4;
    await st.save();
    expect(prefs.getKeys(), <String>{'metronomeVolume'});
    expect(appearance, 0);
    expect(all, 1);
    // Mover un deslizador muchas veces solo reescribe esa clave.
    for (int i = 0; i < 20; i++) {
      st.audioDelayMs = i * 10;
      await st.save();
    }
    expect(prefs.getKeys(), <String>{'metronomeVolume', 'audioDelayMs'});
    expect(appearance, 0);
    st.language = 'en';
    await st.save();
    expect(appearance, 1);
    st.themeMode = 'dark';
    await st.save();
    expect(appearance, 2);
    // Sin cambios, no se escribe ni se avisa de la apariencia.
    await st.save();
    expect(appearance, 2);
  });

  test('El ritmo del metrónomo se recuerda entre aperturas (M11)', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final AppSettings st = AppSettings();
    await st.load();
    const RhythmConfig c = RhythmConfig(bpm: 132, beatsPerBar: 6, denominator: 8, beats: <BeatMode>[BeatMode.accent, BeatMode.normal, BeatMode.normal, BeatMode.accent, BeatMode.normal, BeatMode.normal]);
    st.metronomeConfig = jsonEncode(c.toJson());
    st.activeSetlistId = 's1';
    st.activeSetlistIndex = 2;
    await st.save();
    final AppSettings again = AppSettings();
    await again.load();
    expect(again.savedRhythm?.bpm, 132);
    expect(again.savedRhythm?.timeSignature, '6/8');
    expect(again.activeSetlistId, 's1');
    expect(again.activeSetlistIndex, 2);
  });
}
