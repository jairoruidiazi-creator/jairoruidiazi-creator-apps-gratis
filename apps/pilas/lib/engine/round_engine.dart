import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/app_state.dart';
import '../core/sfx.dart';
import '../core/speech.dart';
import '../model/progress.dart';
import 'game_def.dart';
import 'mastery.dart';

/// Fase visible de una ronda.
enum RoundPhase { playing, hint, celebrating, revealing, levelUp }

/// Lleva la cuenta de intentos, aplica la política de retroalimentación
/// (primer error: pista; segundo: respuesta explicada) y registra el dominio.
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
  bool _disposed = false;
  Timer? _timer;

  static const Duration celebrate = Duration(milliseconds: 1100);
  static const Duration reveal = Duration(milliseconds: 2600);
  static const Duration levelUpDur = Duration(milliseconds: 2200);

  int get level => app.progressOf(launch.profile.id).masteryFor(launch.game.id, launch.band).level;

  int get maxLevel => launch.game.levelsFor(launch.band);

  /// Aciertos de las últimas rondas en el nivel actual (para los puntos de progreso).
  List<bool> get recent => List<bool>.unmodifiable(app.progressOf(launch.profile.id).masteryFor(launch.game.id, launch.band).recent);

  bool get busy => phase != RoundPhase.playing && phase != RoundPhase.hint;

  void startRound() {
    attempts = 0;
    hintText = null;
    revealText = null;
    overlayTitle = null;
    sticker = null;
    phase = RoundPhase.playing;
    roundNumber += 1;
    notifyListeners();
  }

  /// Dice la instrucción de la ronda.
  void say(String text) {
    voice.sayLater(text);
  }

  /// El niño respondió bien.
  Future<void> correct({String? praise}) async {
    if (busy) {
      return;
    }
    final bool firstTry = attempts == 0;
    phase = RoundPhase.celebrating;
    overlayTitle = firstTry ? '¡Excelente!' : '¡Muy bien!';
    notifyListeners();
    unawaited(sfx.play(firstTry ? SfxId.great : SfxId.ok));
    if (praise != null && praise.isNotEmpty) {
      voice.sayLater(praise);
    }
    final RoundFeedback fb = await app.recordRound(launch.game, launch.band, true);
    await _wait(celebrate);
    await _afterRecord(fb);
  }

  /// Un tablero terminado (memoria, laberinto, sudoku): se celebra siempre y
  /// se registra como acierto o no según la eficiencia.
  Future<void> finishBoard({required bool success, required String message}) async {
    if (busy) {
      return;
    }
    phase = RoundPhase.celebrating;
    overlayTitle = success ? '¡Muy bien!' : '¡Lo lograste!';
    notifyListeners();
    unawaited(sfx.play(success ? SfxId.great : SfxId.ok));
    voice.sayLater(message);
    final RoundFeedback fb = await app.recordRound(launch.game, launch.band, success);
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
      overlayTitle = fb.event == MasteryEvent.levelUp ? '¡Subiste de nivel!' : '¡Nueva pegatina!';
      notifyListeners();
      unawaited(sfx.play(fb.event == MasteryEvent.levelUp ? SfxId.levelUp : SfxId.sticker));
      voice.sayLater(fb.event == MasteryEvent.levelUp ? '¡Subiste de nivel!' : '¡Ganaste una pegatina!');
      await _wait(levelUpDur);
      if (_disposed) {
        return;
      }
    }
    onNextRound();
  }

  /// El niño respondió mal. La primera vez muestra la pista; la segunda, la respuesta.
  Future<void> wrong({required String hint, required String explain}) async {
    if (busy) {
      return;
    }
    attempts += 1;
    if (attempts == 1) {
      phase = RoundPhase.hint;
      hintText = hint;
      notifyListeners();
      unawaited(sfx.play(SfxId.hint));
      voice.sayLater(hint);
      return;
    }
    phase = RoundPhase.revealing;
    revealText = explain;
    overlayTitle = 'Así es';
    notifyListeners();
    unawaited(sfx.play(SfxId.hint));
    voice.sayLater(explain);
    await app.recordRound(launch.game, launch.band, false);
    await _wait(reveal);
    if (_disposed) {
      return;
    }
    onNextRound();
  }

  /// Para juegos sin respuesta correcta única (colorear, historias): registra
  /// una ronda completada sin evaluar.
  Future<void> completeFree() async {
    if (busy) {
      return;
    }
    phase = RoundPhase.celebrating;
    overlayTitle = '¡Listo!';
    notifyListeners();
    unawaited(sfx.play(SfxId.ok));
    final RoundFeedback fb = await app.recordRound(launch.game, launch.band, true);
    await _wait(celebrate);
    await _afterRecord(fb);
  }

  Future<void> _wait(Duration d) {
    final Completer<void> c = Completer<void>();
    _timer?.cancel();
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
    super.dispose();
  }
}
