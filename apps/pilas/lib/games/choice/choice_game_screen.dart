import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/rng.dart';
import '../../engine/game_def.dart';
import '../../engine/round_engine.dart';
import '../shell/game_frame.dart';
import '../shell/widgets.dart';
import 'choice_body.dart';
import 'choice_round.dart';

/// Pantalla genérica para los juegos de elegir la respuesta correcta.
class ChoiceGameScreen extends StatefulWidget {
  const ChoiceGameScreen({super.key, required this.launch, required this.generator});

  final GameLaunch launch;
  final ChoiceGenerator generator;

  @override
  State<ChoiceGameScreen> createState() => _ChoiceGameScreenState();
}

class _ChoiceGameScreenState extends State<ChoiceGameScreen> {
  late final RoundEngine _engine;
  final Rng _rng = Rng();
  ChoiceRound? _round;
  final Set<String> _wrongIds = <String>{};
  bool _started = false;

  @override
  void initState() {
    super.initState();
    final Services s = AppScope.read(context);
    _engine = RoundEngine(app: s.state, voice: s.voice, sfx: s.sfx, launch: widget.launch, onNextRound: _nextRound);
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
    if (round == null || _engine.busy || _wrongIds.contains(option.id)) {
      return;
    }
    if (option.id == round.correctId) {
      _engine.correct(praise: round.praise);
    } else {
      setState(() => _wrongIds.add(option.id));
      _engine.wrong(hint: round.hint, explain: round.explain);
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

  @override
  Widget build(BuildContext context) {
    final ChoiceRound? round = _round;
    if (round == null) {
      return GameFrame(launch: widget.launch, engine: _engine, child: const SizedBox.shrink());
    }
    return GameFrame(
      launch: widget.launch,
      engine: _engine,
      instruction: round.instruction,
      onRepeat: () => _engine.say(round.spokenInstruction),
      child: ChoiceRoundBody(round: round, statusOf: _status, onTap: _tap),
    );
  }
}
