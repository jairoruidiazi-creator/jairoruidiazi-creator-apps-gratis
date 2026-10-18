import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../audio/click_synth.dart';
import '../../audio/sequencer.dart';

/// Qué pulsos destellan.
enum FlashBeats { all, accents, none }

/// Destello de pantalla del metrónomo, dentro de los límites de WCAG 2.3.1
/// (umbral de tres destellos):
///
/// - Nunca más de 3 destellos en un segundo: entre dos destellos pasan al
///   menos [minGapSeconds]. Si los pulsos van más rápido, destellan solo los
///   acentos; si aun así no se cumple, no destella.
/// - Contraste suave: el cambio de luminancia relativa queda por debajo de
///   [maxLuminanceChange], lejos del 10 % que define un destello general.
/// - Con "quitar animaciones" del sistema no destella.
class ScreenFlash {
  ScreenFlash._();

  /// Separación mínima entre destellos (algo más de 1/3 s).
  static const double minGapSeconds = 0.34;

  /// Cambio máximo de luminancia relativa del fondo durante un destello.
  static const double maxLuminanceChange = 0.06;

  /// Parte del pulso en que el destello está encendido.
  static const double onFraction = 0.12;

  /// Qué pulsos pueden destellar con [c] a [bpm] pulsos por minuto.
  static FlashBeats beatsFor(RhythmConfig c, double bpm) {
    if (!(bpm > 0)) {
      return FlashBeats.none;
    }
    final double beatSeconds = 60 / bpm;
    final int n = c.beatsPerBar;
    final List<int> sounding = <int>[];
    final List<int> accents = <int>[];
    for (int i = 0; i < n; i++) {
      final BeatMode m = i < c.beats.length ? c.beats[i] : (i == 0 ? BeatMode.accent : BeatMode.normal);
      if (m == BeatMode.accent || m == BeatMode.normal) {
        sounding.add(i);
      }
      if (m == BeatMode.accent) {
        accents.add(i);
      }
    }
    if (_minGapBeats(sounding, n) * beatSeconds >= minGapSeconds) {
      return FlashBeats.all;
    }
    if (_minGapBeats(accents, n) * beatSeconds >= minGapSeconds) {
      return FlashBeats.accents;
    }
    return FlashBeats.none;
  }

  /// Menor distancia, en pulsos, entre dos pulsos de [beats] (el compás se
  /// repite: el último y el primero del siguiente también cuentan).
  static double _minGapBeats(List<int> beats, int n) {
    if (beats.isEmpty) {
      return double.infinity;
    }
    if (beats.length == 1) {
      return n.toDouble();
    }
    int gap = n - beats.last + beats.first;
    for (int i = 1; i < beats.length; i++) {
      gap = math.min(gap, beats[i] - beats[i - 1]);
    }
    return gap.toDouble();
  }

  /// Si un pulso de tipo [kind] destella con la regla [rule].
  static bool flashes(FlashBeats rule, BeatKind kind) {
    switch (rule) {
      case FlashBeats.all:
        return kind == BeatKind.accent || kind == BeatKind.normal;
      case FlashBeats.accents:
        return kind == BeatKind.accent;
      case FlashBeats.none:
        return false;
    }
  }

  /// Color de la capa del destello sobre [background]: el tono [tint] con la
  /// mayor opacidad (hasta [maxAlpha]) que no cambia la luminancia más de
  /// [maxLuminanceChange].
  static Color overlay(Color tint, Color background, {double maxAlpha = 0.5}) {
    final double base = background.computeLuminance();
    double lo = 0;
    double hi = maxAlpha;
    if (_change(tint, background, base, hi) <= maxLuminanceChange) {
      return tint.withValues(alpha: hi);
    }
    for (int i = 0; i < 16; i++) {
      final double mid = (lo + hi) / 2;
      if (_change(tint, background, base, mid) <= maxLuminanceChange) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return tint.withValues(alpha: lo);
  }

  static double _change(Color tint, Color background, double base, double alpha) => (Color.alphaBlend(tint.withValues(alpha: alpha), background).computeLuminance() - base).abs();
}
