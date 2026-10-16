import 'dart:async';

import 'package:flutter/material.dart';

import '../../content/cuentos.dart';
import '../../core/app_scope.dart';
import '../../core/rng.dart';
import '../../core/sfx.dart';
import '../../core/theme.dart';
import '../../engine/game_def.dart';
import '../../engine/round_engine.dart';
import '../../model/age_band.dart';
import '../shell/game_frame.dart';
import '../shell/widgets.dart';

/// Cuentos con voz: se lee (y se escucha) un cuento por páginas y después se
/// responden tres preguntas de comprensión. Cada pregunta es una ronda.
class CuentosScreen extends StatefulWidget {
  const CuentosScreen({super.key, required this.launch});

  final GameLaunch launch;

  @override
  State<CuentosScreen> createState() => _CuentosScreenState();
}

class _CuentosScreenState extends State<CuentosScreen> {
  late final RoundEngine _engine;
  final Rng _rng = Rng();
  final Set<String> _leidos = <String>{};
  Cuento? _cuento;
  int _page = 0;
  int _question = -1; // -1 = leyendo el cuento
  bool _rereading = false;
  int _chosen = -1;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    final Services s = AppScope.read(context);
    _engine = RoundEngine(app: s.state, voice: s.voice, sfx: s.sfx, launch: widget.launch, onNextRound: _advance);
    _engine.addListener(_refresh);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _newStory();
    }
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  void _newStory() {
    if (!mounted) {
      return;
    }
    List<Cuento> pool = CuentoBank.forBand(widget.launch.band).where((Cuento c) => !_leidos.contains(c.id)).toList();
    if (pool.isEmpty) {
      _leidos.clear();
      pool = CuentoBank.forBand(widget.launch.band);
    }
    final Cuento c = _rng.pick(pool);
    _leidos.add(c.id);
    setState(() {
      _cuento = c;
      _page = 0;
      _question = -1;
      _rereading = false;
      _chosen = -1;
    });
    _engine.startRound();
    _engine.say('${c.titulo}. ${c.paginas.first.texto}');
  }

  void _advance() {
    if (!mounted || _cuento == null) {
      return;
    }
    if (_question + 1 < _cuento!.preguntas.length) {
      setState(() {
        _question += 1;
        _chosen = -1;
      });
      _engine.startRound();
      _engine.say(_cuento!.preguntas[_question].texto);
    } else {
      _newStory();
    }
  }

  void _goPage(int delta) {
    final Cuento? c = _cuento;
    if (c == null) {
      return;
    }
    final int next = (_page + delta).clamp(0, c.paginas.length - 1).toInt();
    if (next == _page) {
      return;
    }
    unawaited(AppScope.read(context).sfx.play(SfxId.page));
    setState(() => _page = next);
    AppScope.read(context).voice.sayLater(c.paginas[next].texto);
  }

  void _startQuestions() {
    final Cuento? c = _cuento;
    if (c == null) {
      return;
    }
    setState(() {
      _question = 0;
      _chosen = -1;
    });
    _engine.say('Ahora, las preguntas. ${c.preguntas[0].texto}');
  }

  void _reread() {
    setState(() {
      _page = 0;
      _rereading = true;
    });
    AppScope.read(context).voice.sayLater(_cuento!.paginas[0].texto);
  }

  void _backToQuestion() {
    final Cuento? c = _cuento;
    if (c == null || _question < 0) {
      return;
    }
    setState(() => _rereading = false);
    _engine.say(c.preguntas[_question].texto);
  }

  void _answer(int i) {
    final Cuento? c = _cuento;
    if (c == null || _question < 0 || _engine.busy) {
      return;
    }
    final PreguntaCuento q = c.preguntas[_question];
    setState(() => _chosen = i);
    if (i == q.correcta) {
      _engine.correct(praise: q.explicacion);
    } else {
      _engine.wrong(hint: q.pista ?? 'Vuelve a pensar en el cuento. Si quieres, tócalo para releerlo.', explain: q.explicacion);
    }
  }

  String _currentSpeech() {
    final Cuento? c = _cuento;
    if (c == null) {
      return '';
    }
    if (_question >= 0 && !_rereading) {
      return c.preguntas[_question].texto;
    }
    return c.paginas[_page].texto;
  }

  @override
  void dispose() {
    _engine.removeListener(_refresh);
    _engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Cuento? c = _cuento;
    final bool lee = widget.launch.band.readsText;
    return GameFrame(
      launch: widget.launch,
      engine: _engine,
      onRepeat: () => AppScope.read(context).voice.sayLater(_currentSpeech()),
      child: c == null
          ? const SizedBox.shrink()
          : (_question >= 0 && !_rereading ? _buildQuestion(c, c.preguntas[_question], lee) : _buildPage(c, lee)),
    );
  }

  Widget _buildPage(Cuento c, bool lee) {
    final Pagina p = c.paginas[_page];
    final bool last = _page == c.paginas.length - 1;
    final bool releyendo = _rereading;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              EmojiImage(c.portada, size: 32),
              const SizedBox(width: 8),
              Expanded(child: Text(c.titulo, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
              Text('${_page + 1} / ${c.paginas.length}', style: const TextStyle(fontSize: 14, color: PilasColors.tintaSuave)),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(Dim.radio), border: Border.all(color: PilasColors.borde, width: 2)),
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Column(
                  children: <Widget>[
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Row(
                        key: ValueKey<int>(_page),
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          for (int i = 0; i < p.escena.length; i++) ...<Widget>[
                            if (i > 0) const SizedBox(width: 14),
                            EmojiImage(p.escena[i], size: p.escena.length == 1 ? 120 : 84),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: () => AppScope.read(context).voice.sayLater(p.texto),
                      child: Text(
                        p.texto,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: lee ? 21 : 24, height: 1.45, fontFamily: 'Andika', color: PilasColors.tinta),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              RoundIconButton(icon: Icons.chevron_left_rounded, tooltip: 'Anterior', onPressed: _page == 0 ? null : () => _goPage(-1)),
              const Spacer(),
              if (last)
                FilledButton.icon(
                  onPressed: releyendo ? _backToQuestion : _startQuestions,
                  icon: const Icon(Icons.quiz_rounded),
                  label: Text(releyendo ? 'Volver a la pregunta' : 'Preguntas', style: const TextStyle(fontSize: 18)),
                  style: FilledButton.styleFrom(minimumSize: const Size(160, 52)),
                )
              else
                FilledButton.icon(
                  onPressed: () => _goPage(1),
                  icon: const Icon(Icons.chevron_right_rounded),
                  label: const Text('Siguiente', style: TextStyle(fontSize: 18)),
                  style: FilledButton.styleFrom(minimumSize: const Size(160, 52)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuestion(Cuento c, PreguntaCuento q, bool lee) {
    final bool conEmoji = q.opciones.every((OpcionCuento o) => o.emoji != null) && !lee;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              EmojiImage(c.portada, size: 32),
              const SizedBox(width: 8),
              Expanded(child: Text('Pregunta ${_question + 1} de ${c.preguntas.length}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: PilasColors.tintaSuave))),
              TextButton.icon(
                onPressed: _engine.busy ? null : _reread,
                icon: const Icon(Icons.menu_book_rounded),
                label: const Text('Releer'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => AppScope.read(context).voice.sayLater(q.texto),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(Dim.radio), border: Border.all(color: PilasColors.borde, width: 2)),
              child: Text(q.texto, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, height: 1.35)),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              physics: const ClampingScrollPhysics(),
              itemCount: q.opciones.length,
              separatorBuilder: (BuildContext context, int i) => const SizedBox(height: 10),
              itemBuilder: (BuildContext context, int i) {
                final OpcionCuento o = q.opciones[i];
                TileStatus status = TileStatus.normal;
                if (_chosen == i) {
                  status = i == q.correcta ? TileStatus.correct : TileStatus.wrong;
                } else if (_engine.phase == RoundPhase.revealing && i == q.correcta) {
                  status = TileStatus.correct;
                }
                return OptionTile(
                  status: status,
                  semanticsLabel: o.texto,
                  onTap: _engine.busy ? null : () => _answer(i),
                  minHeight: 64,
                  child: Row(
                    children: <Widget>[
                      if (o.emoji != null) ...<Widget>[
                        EmojiImage(o.emoji!, size: conEmoji ? 56 : 36),
                        const SizedBox(width: 14),
                      ],
                      Expanded(child: Text(o.texto, style: TextStyle(fontSize: conEmoji ? 20 : 18, fontWeight: FontWeight.w600))),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
