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
/// responden tres preguntas de comprensión. Cada pregunta es una ronda. Las
/// opciones salen en un orden distinto cada vez, así que la respuesta no
/// tiene un lugar fijo. Los cuentos no tienen niveles.
class CuentosScreen extends StatefulWidget {
  const CuentosScreen({super.key, required this.launch, this.rng});

  final GameLaunch launch;

  /// Azar (se fija en las pruebas).
  final Rng? rng;

  @override
  State<CuentosScreen> createState() => _CuentosScreenState();
}

class _CuentosScreenState extends State<CuentosScreen> {
  late final RoundEngine _engine;
  late final Rng _rng = widget.rng ?? Rng();
  final Set<String> _leidos = <String>{};
  Cuento? _cuento;
  int _page = 0;
  int _question = -1; // -1 = leyendo el cuento
  bool _rereading = false;

  /// Orden en pantalla de las opciones de la pregunta actual.
  List<int> _order = <int>[];

  /// Opciones ya descartadas (una respuesta equivocada no se puede repetir).
  final Set<int> _wrong = <int>{};
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
      _wrong.clear();
    });
    _engine.startRound();
    _engine.say('${c.titulo}. ${c.paginas.first.texto}');
  }

  /// Prepara la pregunta [i]: baraja sus opciones.
  void _setQuestion(int i) {
    final PreguntaCuento q = _cuento!.preguntas[i];
    _question = i;
    _chosen = -1;
    _wrong.clear();
    _order = _rng.shuffled(<int>[for (int k = 0; k < q.opciones.length; k++) k]);
  }

  /// Lo que dice la voz al presentar la pregunta: a los que todavía no leen
  /// también les lee las opciones, en el orden en que aparecen.
  String _spokenQuestion(PreguntaCuento q) {
    if (widget.launch.band.readsText) {
      return q.texto;
    }
    return '${q.texto} ${_order.map((int k) => '${q.opciones[k].texto}.').join(' ')}';
  }

  void _advance() {
    if (!mounted || _cuento == null) {
      return;
    }
    if (_question + 1 < _cuento!.preguntas.length) {
      setState(() => _setQuestion(_question + 1));
      _engine.startRound();
      _engine.say(_spokenQuestion(_cuento!.preguntas[_question]));
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
    setState(() => _setQuestion(0));
    _engine.say('Ahora, las preguntas. ${_spokenQuestion(c.preguntas[0])}');
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
    _engine.say(_spokenQuestion(c.preguntas[_question]));
  }

  void _answer(int i) {
    final Cuento? c = _cuento;
    if (c == null || _question < 0 || _engine.busy || _wrong.contains(i)) {
      return;
    }
    final PreguntaCuento q = c.preguntas[_question];
    setState(() => _chosen = i);
    if (i == q.correcta) {
      unawaited(_engine.correct(praise: q.explicacion));
    } else {
      _wrong.add(i);
      // Con tres opciones, tras un error quedan dos: hay segunda oportunidad
      // (que ya no cuenta como acierto).
      final int quedan = q.opciones.length - _wrong.length;
      unawaited(_engine.wrong(
        hint: q.pista ?? 'Vuelve a pensar en el cuento. Si quieres, toca Releer.',
        explain: q.explicacion,
        allowRetry: quedan >= 2,
      ));
    }
  }

  String _currentSpeech() {
    final Cuento? c = _cuento;
    if (c == null) {
      return '';
    }
    if (_question >= 0 && !_rereading) {
      return _spokenQuestion(c.preguntas[_question]);
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
          : LayoutBuilder(
              builder: (BuildContext context, BoxConstraints k) =>
                  _question >= 0 && !_rereading ? _buildQuestion(c, c.preguntas[_question], lee, k) : _buildPage(c, lee),
            ),
    );
  }

  Widget _buildPage(Cuento c, bool lee) {
    final PilasPalette pal = PilasPalette.of(context);
    final Pagina p = c.paginas[_page];
    final bool last = _page == c.paginas.length - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              EmojiImage(c.portada, size: 32),
              const SizedBox(width: 8),
              Expanded(child: Text(c.titulo, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: pal.tinta))),
              Text('${_page + 1} / ${c.paginas.length}', style: TextStyle(fontSize: 15, color: pal.tintaSuave)),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: pal.tarjeta, borderRadius: BorderRadius.circular(Dim.radio), border: Border.all(color: pal.altoContraste ? pal.bordeFuerte : pal.borde, width: 2)),
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Column(
                  children: <Widget>[
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      // Con cuatro pictogramas en un teléfono angosto, la
                      // escena se achica en lugar de salirse.
                      child: FittedBox(
                        key: ValueKey<int>(_page),
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            for (int i = 0; i < p.escena.length; i++) ...<Widget>[
                              if (i > 0) const SizedBox(width: 14),
                              EmojiImage(p.escena[i], size: p.escena.length == 1 ? 110 : 76),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Semantics(
                      button: true,
                      label: p.texto,
                      hint: 'Toca para escucharlo',
                      excludeSemantics: true,
                      child: GestureDetector(
                        onTap: () => AppScope.read(context).voice.sayLater(p.texto),
                        child: Text(
                          p.texto,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: lee ? 21 : 24, height: 1.45, fontFamily: 'Andika', color: pal.tinta),
                        ),
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
              RoundIconButton(key: const ValueKey<String>('cuento-anterior'), icon: Icons.chevron_left_rounded, tooltip: 'Página anterior', onPressed: _page == 0 ? null : () => _goPage(-1)),
              const SizedBox(width: 12),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: last
                      ? FilledButton.icon(
                          key: const ValueKey<String>('cuento-preguntas'),
                          onPressed: _rereading ? _backToQuestion : _startQuestions,
                          icon: const Icon(Icons.quiz_rounded),
                          label: Text(_rereading ? 'Volver a la pregunta' : 'Preguntas'),
                          style: FilledButton.styleFrom(minimumSize: const Size(140, 56)),
                        )
                      : FilledButton.icon(
                          key: const ValueKey<String>('cuento-siguiente'),
                          onPressed: () => _goPage(1),
                          icon: const Icon(Icons.chevron_right_rounded),
                          label: const Text('Siguiente'),
                          style: FilledButton.styleFrom(minimumSize: const Size(140, 56)),
                        ),
                ),
              ),
            ],
          ),
          if (_rereading && !last) ...<Widget>[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const ValueKey<String>('cuento-volver-pregunta'),
                onPressed: _backToQuestion,
                icon: const Icon(Icons.quiz_rounded),
                label: const Text('Volver a la pregunta'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuestion(Cuento c, PreguntaCuento q, bool lee, BoxConstraints k) {
    final PilasPalette pal = PilasPalette.of(context);
    final bool conEmoji = q.opciones.every((OpcionCuento o) => o.emoji != null) && !lee;
    final Widget header = Row(
      children: <Widget>[
        EmojiImage(c.portada, size: 32),
        const SizedBox(width: 8),
        Expanded(child: Text('Pregunta ${_question + 1} de ${c.preguntas.length}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: pal.tintaSuave))),
        TextButton.icon(
          key: const ValueKey<String>('cuento-releer'),
          onPressed: _engine.busy ? null : _reread,
          icon: const Icon(Icons.menu_book_rounded),
          label: const Text('Releer'),
        ),
      ],
    );
    final Widget question = Semantics(
      button: true,
      label: q.texto,
      hint: 'Toca para escucharla',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => AppScope.read(context).voice.sayLater(_spokenQuestion(q)),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: pal.tarjeta, borderRadius: BorderRadius.circular(Dim.radio), border: Border.all(color: pal.altoContraste ? pal.bordeFuerte : pal.borde, width: 2)),
          child: Text(q.texto, textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, height: 1.35, color: pal.tinta)),
        ),
      ),
    );
    final Widget options = ListView.separated(
      physics: const ClampingScrollPhysics(),
      itemCount: _order.length,
      separatorBuilder: (BuildContext context, int i) => const SizedBox(height: 10),
      itemBuilder: (BuildContext context, int pos) {
        final int i = _order[pos];
        final OpcionCuento o = q.opciones[i];
        TileStatus status = TileStatus.normal;
        if (_wrong.contains(i)) {
          status = TileStatus.wrong;
        } else if (_chosen == i && i == q.correcta) {
          status = TileStatus.correct;
        } else if (_engine.phase == RoundPhase.revealing && i == q.correcta) {
          status = TileStatus.correct;
        }
        return OptionTile(
          key: ValueKey<String>('opcion-$i'),
          status: status,
          semanticsLabel: o.texto,
          onTap: _engine.busy || _wrong.contains(i) ? null : () => _answer(i),
          minHeight: 64,
          child: Row(
            children: <Widget>[
              if (o.emoji != null) ...<Widget>[
                EmojiImage(o.emoji!, size: conEmoji ? 56 : 36),
                const SizedBox(width: 14),
              ],
              Expanded(child: Text(o.texto, style: TextStyle(fontSize: conEmoji ? 20 : 18, fontWeight: FontWeight.w600, color: pal.tinta))),
            ],
          ),
        );
      },
    );
    if (k.maxWidth > k.maxHeight) {
      // Acostado: la pregunta a un lado y las opciones al otro.
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(flex: 2, child: SingleChildScrollView(child: Column(children: <Widget>[header, const SizedBox(height: 6), question]))),
            const SizedBox(width: 12),
            Expanded(flex: 3, child: options),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        children: <Widget>[
          header,
          const SizedBox(height: 6),
          question,
          const SizedBox(height: 12),
          Expanded(child: options),
        ],
      ),
    );
  }
}
