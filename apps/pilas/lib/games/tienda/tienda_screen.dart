import 'dart:async';

import 'package:flutter/material.dart';

import '../../content/money.dart';
import '../../core/app_scope.dart';
import '../../core/rng.dart';
import '../../core/sfx.dart';
import '../../core/theme.dart';
import '../../engine/game_def.dart';
import '../../engine/round_engine.dart';
import '../choice/choice_body.dart';
import '../choice/choice_round.dart';
import '../shell/game_frame.dart';
import '../shell/widgets.dart';
import 'tienda_generator.dart';

/// La tienda: rondas de elegir y rondas de pagar con monedas y billetes.
class TiendaScreen extends StatefulWidget {
  const TiendaScreen({super.key, required this.launch});

  final GameLaunch launch;

  @override
  State<TiendaScreen> createState() => _TiendaScreenState();
}

class _TiendaScreenState extends State<TiendaScreen> {
  late final RoundEngine _engine;
  final Rng _rng = Rng();
  final TiendaGenerator _gen = TiendaGenerator();
  TiendaRound? _round;
  final Set<String> _wrongIds = <String>{};
  final List<Denominacion> _bandeja = <Denominacion>[];
  bool _started = false;

  @override
  void initState() {
    super.initState();
    final Services s = AppScope.read(context);
    _engine = RoundEngine(app: s.state, voice: s.voice, sfx: s.sfx, launch: widget.launch, onNextRound: _next);
    _engine.addListener(_refresh);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _next();
    }
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  void _next() {
    if (!mounted) {
      return;
    }
    final TiendaRound r = _gen.next(_rng, widget.launch.band, _engine.level);
    setState(() {
      _round = r;
      _wrongIds.clear();
      _bandeja.clear();
    });
    _engine.startRound();
    _engine.say(_instruction(r));
  }

  String _instruction(TiendaRound r) => r.choice != null ? r.choice!.spokenInstruction : r.pago!.instruction;

  // ---------------------------------------------------------------- elegir

  void _tapOption(ChoiceOption o) {
    final ChoiceRound? round = _round?.choice;
    if (round == null || _engine.busy || _wrongIds.contains(o.id)) {
      return;
    }
    if (o.id == round.correctId) {
      _engine.correct(praise: round.praise);
    } else {
      setState(() => _wrongIds.add(o.id));
      _engine.wrong(hint: round.hint, explain: round.explain);
    }
  }

  TileStatus _status(ChoiceOption o) {
    final ChoiceRound round = _round!.choice!;
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

  // ---------------------------------------------------------------- pagar

  int get _suma => _bandeja.fold<int>(0, (int s, Denominacion d) => s + d.valor);

  void _agregar(Denominacion d) {
    if (_engine.busy) {
      return;
    }
    final Services s = AppScope.read(context);
    unawaited(s.sfx.play(SfxId.pop));
    setState(() => _bandeja.add(d));
    s.voice.sayLater(pesosEnPalabras(_suma));
  }

  void _quitar(int index) {
    if (_engine.busy) {
      return;
    }
    setState(() => _bandeja.removeAt(index));
    AppScope.read(context).voice.sayLater(pesosEnPalabras(_suma));
  }

  void _pagar() {
    final PagoRound? pago = _round?.pago;
    if (pago == null || _engine.busy) {
      return;
    }
    final int total = pago.total;
    final int suma = _suma;
    if (suma == total) {
      _engine.correct(praise: 'Pagaste ${pesosEnPalabras(total)} exactos.');
      return;
    }
    final String llevas = pesosEnPalabras(suma);
    final String faltan = suma < total ? 'Te faltan ${pesosEnPalabras(total - suma)}.' : 'Te sobran ${pesosEnPalabras(suma - total)}.';
    _engine.wrong(
      hint: 'Llevas $llevas y necesitas ${pesosEnPalabras(total)}. $faltan',
      explain: 'Eran ${pesosEnPalabras(total)}: ${_combinacion(pago)}.',
    );
    if (suma > total) {
      setState(() => _bandeja.clear());
    }
  }

  /// Una forma de armar el total con las denominaciones disponibles, de mayor a menor.
  String _combinacion(PagoRound pago) {
    final List<Denominacion> ds = List<Denominacion>.from(pago.denominaciones)..sort((Denominacion a, Denominacion b) => b.valor.compareTo(a.valor));
    int resto = pago.total;
    final List<String> partes = <String>[];
    for (final Denominacion d in ds) {
      final int n = resto ~/ d.valor;
      if (n > 0) {
        partes.add('$n de ${formatPesos(d.valor)}');
        resto -= n * d.valor;
      }
    }
    return partes.join(', ');
  }

  @override
  void dispose() {
    _engine.removeListener(_refresh);
    _engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TiendaRound? r = _round;
    if (r == null) {
      return GameFrame(launch: widget.launch, engine: _engine, child: const SizedBox.shrink());
    }
    if (r.choice != null) {
      return GameFrame(
        launch: widget.launch,
        engine: _engine,
        instruction: r.choice!.instruction,
        onRepeat: () => _engine.say(r.choice!.spokenInstruction),
        child: ChoiceRoundBody(round: r.choice!, statusOf: _status, onTap: _tapOption),
      );
    }
    final PagoRound pago = r.pago!;
    return GameFrame(
      launch: widget.launch,
      engine: _engine,
      instruction: pago.instruction,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
          final bool wide = c.maxWidth > c.maxHeight * 1.15;
          if (wide) {
            // Apaisado: productos y bandeja a la izquierda; monedero y botón a la derecha.
            final double right = (c.maxWidth - 12) * 4 / 9;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  flex: 5,
                  child: Column(
                    children: <Widget>[
                      _productos(pago, emoji: 48),
                      const SizedBox(height: 8),
                      Expanded(child: _bandejaView()),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 4,
                  child: Column(
                    children: <Widget>[
                      Expanded(child: SingleChildScrollView(child: _monedero(pago, _coinWidth(pago, right)))),
                      const SizedBox(height: 8),
                      _botonPagar(),
                    ],
                  ),
                ),
              ],
            );
          }
          final double coinWidth = _coinWidth(pago, c.maxWidth);
          if (c.maxHeight < 560) {
            // Vertical pero bajo (la mayoría de los teléfonos, o texto grande):
            // todo se desplaza y la bandeja tiene un alto fijo.
            return SingleChildScrollView(
              child: Column(
                children: <Widget>[
                  _productos(pago, emoji: 52),
                  const SizedBox(height: 12),
                  SizedBox(height: 140, child: _bandejaView()),
                  const SizedBox(height: 12),
                  _monedero(pago, coinWidth),
                  const SizedBox(height: 12),
                  _botonPagar(),
                ],
              ),
            );
          }
          return Column(
            children: <Widget>[
              _productos(pago, emoji: 64),
              const SizedBox(height: 12),
              Expanded(child: _bandejaView()),
              const SizedBox(height: 12),
              _monedero(pago, coinWidth),
              const SizedBox(height: 12),
              _botonPagar(),
            ],
          );
        }),
      ),
    );
  }

  /// Ancho de cada moneda o billete para que el monedero quepa en dos filas
  /// como mucho: en un teléfono angosto se achican en lugar de empujar la bandeja.
  double _coinWidth(PagoRound pago, double available) {
    final int n = pago.denominaciones.length;
    final int perRow = n <= 1 ? 1 : (n / 2).ceil();
    return ((available - (perRow - 1) * 10) / perRow - 16).clamp(56.0, 96.0).toDouble();
  }

  Widget _productos(PagoRound pago, {required double emoji}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(Dim.radio), border: Border.all(color: PilasColors.borde, width: 2)),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 20,
        runSpacing: 8,
        children: <Widget>[
          for (final Producto p in pago.productos)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                EmojiImage(p.item.emoji, size: emoji, semanticsLabel: p.item.nombre),
                Text(formatPesos(p.precio), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              ],
            ),
          if (pago.productos.length > 1)
            Text('= ${formatPesos(pago.total)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: PilasColors.azul)),
        ],
      ),
    );
  }

  Widget _bandejaView() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PilasColors.verdeClaro,
        borderRadius: BorderRadius.circular(Dim.radio),
        border: Border.all(color: PilasColors.verde, width: 2),
      ),
      child: Column(
        children: <Widget>[
          Text('Llevas ${formatPesos(_suma)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: <Widget>[
                  for (int i = 0; i < _bandeja.length; i++)
                    GestureDetector(
                      onTap: () => _quitar(i),
                      child: Semantics(
                        button: true,
                        label: 'Quitar ${_bandeja[i].nombre}',
                        child: MoneyWidget(denominacion: _bandeja[i], width: 84),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _monedero(PagoRound pago, double coinWidth) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.center,
      children: <Widget>[
        for (final Denominacion d in pago.denominaciones)
          OptionTile(
            padding: const EdgeInsets.all(8),
            minHeight: 56,
            semanticsLabel: 'Agregar ${d.nombre}',
            onTap: () => _agregar(d),
            child: MoneyWidget(denominacion: d, width: coinWidth),
          ),
      ],
    );
  }

  Widget _botonPagar() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _bandeja.isEmpty ? null : _pagar,
        icon: const Icon(Icons.shopping_bag_rounded),
        label: const Text('Pagar'),
      ),
    );
  }
}
