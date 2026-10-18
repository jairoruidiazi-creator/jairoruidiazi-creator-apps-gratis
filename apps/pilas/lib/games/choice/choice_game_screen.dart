import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/rng.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../engine/game_def.dart';
import '../../engine/round_engine.dart';
import '../../model/age_band.dart';
import '../shell/game_frame.dart';
import '../shell/widgets.dart';
import 'choice_body.dart';
import 'choice_round.dart';

/// Carrera: una tanda de rondas seguidas, sin reloj, con la marca personal
/// del niño (aciertos al primer intento) por perfil y tramo.
class RaceConfig {
  const RaceConfig({this.length = 10});

  final int length;

  static String recordKey(GameDef game, AgeBand band) => '${game.id}|${band.id}';
}

/// Pantalla genérica para los juegos de elegir la respuesta correcta.
class ChoiceGameScreen extends StatefulWidget {
  const ChoiceGameScreen({super.key, required this.launch, required this.generator, this.race});

  final GameLaunch launch;
  final ChoiceGenerator generator;
  final RaceConfig? race;

  @override
  State<ChoiceGameScreen> createState() => _ChoiceGameScreenState();
}

class _ChoiceGameScreenState extends State<ChoiceGameScreen> {
  late final RoundEngine _engine;
  final Rng _rng = Rng();
  ChoiceRound? _round;
  final Set<String> _wrongIds = <String>{};
  bool _started = false;

  int _raceIndex = 0;
  int _raceCorrect = 0;
  bool _raceDone = false;
  bool _newRecord = false;

  @override
  void initState() {
    super.initState();
    final Services s = AppScope.read(context);
    _engine = RoundEngine(app: s.state, voice: s.voice, sfx: s.sfx, launch: widget.launch, onNextRound: _roundEnded);
    _engine.addListener(_onEngine);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _nextRound();
    }
  }

  void _onEngine() {
    if (mounted) {
      setState(() {});
    }
  }

  void _roundEnded() {
    final RaceConfig? race = widget.race;
    if (race == null) {
      _nextRound();
      return;
    }
    _raceIndex += 1;
    if (_engine.lastSuccess == true) {
      _raceCorrect += 1;
    }
    if (_raceIndex < race.length) {
      _nextRound();
      return;
    }
    unawaited(_finishRace(race));
  }

  Future<void> _finishRace(RaceConfig race) async {
    final Services s = AppScope.read(context);
    final bool nueva = await s.state.saveRecord(RaceConfig.recordKey(widget.launch.game, widget.launch.band), _raceCorrect);
    if (!mounted) {
      return;
    }
    setState(() {
      _raceDone = true;
      _newRecord = nueva;
    });
    s.voice.sayLater('${S.terminasteCarrera} ${S.acertasteDe(_raceCorrect, race.length)}${nueva ? ' ${S.nuevaMarca}' : ''}');
  }

  void _newRace() {
    setState(() {
      _raceIndex = 0;
      _raceCorrect = 0;
      _raceDone = false;
      _newRecord = false;
    });
    _nextRound();
  }

  void _nextRound() {
    if (!mounted) {
      return;
    }
    final ChoiceRound round = widget.generator.next(_rng, widget.launch.band, _engine.level);
    setState(() {
      _round = round;
      _wrongIds.clear();
    });
    _engine.startRound();
    _engine.say(round.spokenInstruction);
  }

  void _tap(ChoiceOption option) {
    final ChoiceRound? round = _round;
    if (round == null || _engine.busy || _wrongIds.contains(option.id) || _raceDone) {
      return;
    }
    if (option.id == round.correctId) {
      unawaited(_engine.correct(praise: round.praise));
    } else {
      setState(() => _wrongIds.add(option.id));
      unawaited(_engine.wrong(hint: round.hint, explain: round.explain, allowRetry: round.allowRetry));
    }
  }

  TileStatus _status(ChoiceOption o) {
    final ChoiceRound round = _round!;
    final bool revealing = _engine.phase == RoundPhase.revealing || _engine.phase == RoundPhase.celebrating || _engine.phase == RoundPhase.levelUp;
    if (revealing && o.id == round.correctId) {
      return TileStatus.correct;
    }
    if (_wrongIds.contains(o.id)) {
      return TileStatus.wrong;
    }
    if (revealing) {
      return TileStatus.dim;
    }
    return TileStatus.normal;
  }

  @override
  void dispose() {
    _engine.removeListener(_onEngine);
    _engine.dispose();
    super.dispose();
  }

  Widget? _raceFooter(PilasPalette pal) {
    final RaceConfig? race = widget.race;
    if (race == null) {
      return null;
    }
    final int? marca = AppScope.of(context).state.recordOf(RaceConfig.recordKey(widget.launch.game, widget.launch.band));
    final int numero = (_raceIndex + 1).clamp(1, race.length).toInt();
    final String texto = '${S.preguntaDe(numero, race.length)} · ${S.aciertos}: $_raceCorrect${marca == null ? '' : ' · ${S.tuMarca}: $marca'}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Semantics(
        label: texto,
        excludeSemantics: true,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.flag_rounded, color: pal.tintaSuave, size: 20),
              const SizedBox(width: 6),
              Text(texto, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: pal.tintaSuave)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _raceSummary(PilasPalette pal) {
    final RaceConfig race = widget.race!;
    final int? marca = AppScope.of(context).state.recordOf(RaceConfig.recordKey(widget.launch.game, widget.launch.band));
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Mascot(size: 96),
            const SizedBox(height: 12),
            const BigText(S.terminasteCarrera, size: 28, weight: FontWeight.w700),
            const SizedBox(height: 8),
            BigText(S.acertasteDe(_raceCorrect, race.length), size: 22, weight: FontWeight.w600),
            if (_newRecord) ...<Widget>[
              const SizedBox(height: 8),
              BigText(S.nuevaMarca, size: 26, weight: FontWeight.w800, color: pal.correcto),
            ] else if (marca != null) ...<Widget>[
              const SizedBox(height: 8),
              BigText('${S.tuMarca}: $marca de ${race.length}', size: 20, weight: FontWeight.w600, color: pal.tintaSuave),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _newRace,
              icon: const Icon(Icons.replay_rounded),
              label: const Text(S.otraCarrera),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final PilasPalette pal = PilasPalette.of(context);
    final ChoiceRound? round = _round;
    if (round == null) {
      return GameFrame(launch: widget.launch, engine: _engine, child: const SizedBox.shrink());
    }
    if (_raceDone) {
      return GameFrame(
        launch: widget.launch,
        engine: _engine,
        instruction: S.terminasteCarrera,
        onRepeat: () => AppScope.read(context).voice.sayLater(S.acertasteDe(_raceCorrect, widget.race!.length)),
        child: _raceSummary(pal),
      );
    }
    return GameFrame(
      launch: widget.launch,
      engine: _engine,
      instruction: round.instruction,
      onRepeat: () => _engine.say(round.spokenInstruction),
      child: ChoiceRoundBody(round: round, statusOf: _status, onTap: _tap, footer: _raceFooter(pal)),
    );
  }
}
