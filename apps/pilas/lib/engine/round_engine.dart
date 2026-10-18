import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/app_state.dart';
import '../core/sfx.dart';
import '../core/speech.dart';
import '../core/strings.dart';
import '../model/progress.dart';
import 'game_def.dart';
import 'mastery.dart';

/// Fase visible de una ronda.
enum RoundPhase { playing, hint, celebrating, revealing, levelUp }

/// Lleva la cuenta de intentos, aplica la política de retroalimentación y
/// registra el dominio.
///
/// - Solo el primer intento cuenta: una ronda es un acierto si se resolvió sin
///   ningún error. La segunda oportunidad sirve para aprender, no suma.
/// - Primer error: pista (si quedan al menos dos opciones por elegir). Segundo
///   error, o primer error con dos opciones: se muestra la respuesta explicada.
/// - Los tableros (memoria, laberinto, sudoku…) se terminan siempre y dicen si
///   se resolvieron con eficiencia.
/// - Los juegos libres no tienen aciertos: solo cuentan como actividad.
class RoundEngine extends ChangeNotifier {
  RoundEngine({
    required this.app,
    required this.voice,
    required this.sfx,
    required this.launch,
    required this.onNextRound,
  });

  final AppState app;
  final Voice voice;
  final Sfx sfx;
  final GameLaunch launch;

  /// Lo llama el motor cuando la ronda terminó y hay que generar la siguiente.
  final VoidCallback onNextRound;

  RoundPhase phase = RoundPhase.playing;
  int attempts = 0;
  int roundNumber = 0;
  String? hintText;
  String? revealText;
  String? overlayTitle;
  StickerAward? sticker;

  /// Resultado de la última ronda terminada (acierto al primer intento).
  bool? lastSuccess;
  bool _disposed = false;
  Timer? _timer;
  Completer<void>? _waiting;

  static const Duration celebrate = Duration(milliseconds: 1100);
  static const Duration reveal = Duration(milliseconds: 2600);
  static const Duration levelUpDur = Duration(milliseconds: 2200);

  GameDef get game => launch.game;

  MasteryState? get _mastery => app.progressOf(launch.profile.id).masteryIfAny(game.id, launch.band);

  int get level => _mastery?.level ?? 1;

  int get maxLevel => game.levelsFor(launch.band);

  /// Rondas que mira la regla de dominio de este juego.
  int get window => game.mastery.window;

  /// Aciertos de las últimas rondas en el nivel actual (para los puntos de progreso).
  List<bool> get recent => List<bool>.unmodifiable(_mastery?.recent ?? const <bool>[]);

  bool get busy => phase != RoundPhase.playing && phase != RoundPhase.hint;

  bool get disposed => _disposed;

  void startRound() {
    attempts = 0;
    hintText = null;
    revealText = null;
    overlayTitle = null;
    sticker = null;
    phase = RoundPhase.playing;
    roundNumber += 1;
    _notify();
  }

  /// Deja el motor quieto y sin capas, sin empezar otra ronda: al terminar
  /// una carrera, el resumen queda a la vista y se puede tocar. Se llama
  /// desde [onNextRound], cuando ya no queda ninguna espera pendiente.
  void settle() {
    attempts = 0;
    hintText = null;
    revealText = null;
    overlayTitle = null;
    sticker = null;
    phase = RoundPhase.playing;
    _notify();
  }

  /// Dice la instrucción de la ronda.
  void say(String text) {
    voice.sayLater(text);
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  /// El niño respondió bien. Cuenta como acierto solo si fue al primer intento.
  Future<void> correct({String? praise}) async {
    if (busy || _disposed) {
      return;
    }
    final bool firstTry = attempts == 0;
    phase = RoundPhase.celebrating;
    overlayTitle = firstTry ? S.excelente : S.muyBien;
    _notify();
    unawaited(sfx.play(firstTry ? SfxId.great : SfxId.ok));
    if (praise != null && praise.isNotEmpty) {
      voice.sayLater(praise);
    }
    lastSuccess = firstTry;
    final RoundFeedback fb = await app.recordRound(game, launch.band, firstTry);
    await _wait(celebrate);
    await _afterRecord(fb);
  }

  /// El niño respondió mal. Con [allowRetry] (quedan al menos dos opciones), la
  /// primera vez muestra la pista; si no, o la segunda vez, la respuesta.
  Future<void> wrong({required String hint, required String explain, bool allowRetry = true}) async {
    if (busy || _disposed) {
      return;
    }
    attempts += 1;
    if (attempts == 1 && allowRetry) {
      phase = RoundPhase.hint;
      hintText = hint;
      _notify();
      unawaited(sfx.play(SfxId.hint));
      voice.sayLater(hint);
      return;
    }
    phase = RoundPhase.revealing;
    revealText = explain;
    overlayTitle = S.asiEs;
    _notify();
    unawaited(sfx.play(SfxId.hint));
    voice.sayLater(explain);
    lastSuccess = false;
    await app.recordRound(game, launch.band, false);
    await _wait(reveal);
    if (_disposed) {
      return;
    }
    onNextRound();
  }

  /// Pista sin terminar la ronda (tableros: sudoku, pixel, trazo). La ronda
  /// sigue y su resultado lo decide [finishBoard].
  void showHint(String text) {
    if (busy || _disposed) {
      return;
    }
    attempts += 1;
    phase = RoundPhase.hint;
    hintText = text;
    _notify();
    unawaited(sfx.play(SfxId.hint));
    voice.sayLater(text);
  }

  /// Quita la pista de la barra cuando el tablero sigue bien.
  void clearHint() {
    if (phase == RoundPhase.hint && !_disposed) {
      phase = RoundPhase.playing;
      hintText = null;
      _notify();
    }
  }

  /// Un tablero terminado (memoria, laberinto, sudoku): se celebra siempre y
  /// se registra como acierto o no según la eficiencia.
  Future<void> finishBoard({required bool success, required String message}) async {
    if (busy || _disposed) {
      return;
    }
    phase = RoundPhase.celebrating;
    overlayTitle = success ? S.muyBien : S.loLograste;
    _notify();
    unawaited(sfx.play(success ? SfxId.great : SfxId.ok));
    voice.sayLater(message);
    lastSuccess = success;
    final RoundFeedback fb = await app.recordRound(game, launch.band, success);
    await _wait(celebrate + const Duration(milliseconds: 700));
    await _afterRecord(fb);
  }

  Future<void> _afterRecord(RoundFeedback fb) async {
    if (_disposed) {
      return;
    }
    if (fb.event == MasteryEvent.levelUp || fb.sticker != null) {
      phase = RoundPhase.levelUp;
      sticker = fb.sticker;
      overlayTitle = fb.event == MasteryEvent.levelUp ? S.nuevoNivel : S.nuevaPegatina;
      _notify();
      unawaited(sfx.play(fb.event == MasteryEvent.levelUp ? SfxId.levelUp : SfxId.sticker));
      voice.sayLater(fb.event == MasteryEvent.levelUp ? S.nuevoNivel : S.ganastePegatina);
      await _wait(levelUpDur);
      if (_disposed) {
        return;
      }
    }
    onNextRound();
  }

  /// Juegos libres (colorear libre, dibujo, pixel libre): se celebra y cuenta
  /// como actividad de la sesión, sin niveles, aciertos ni habilidades.
  Future<void> completeFree({String? message}) async {
    if (busy || _disposed) {
      return;
    }
    phase = RoundPhase.celebrating;
    overlayTitle = S.listoExclamacion;
    _notify();
    unawaited(sfx.play(SfxId.ok));
    if (message != null && message.isNotEmpty) {
      voice.sayLater(message);
    }
    lastSuccess = null;
    await app.recordActivity(game);
    await _wait(celebrate);
    if (_disposed) {
      return;
    }
    onNextRound();
  }

  Future<void> _wait(Duration d) {
    final Completer<void> c = Completer<void>();
    _timer?.cancel();
    _waiting = c;
    _timer = Timer(d, () {
      if (!c.isCompleted) {
        c.complete();
      }
    });
    return c.future;
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    final Completer<void>? w = _waiting;
    if (w != null && !w.isCompleted) {
      w.complete();
    }
    super.dispose();
  }
}
