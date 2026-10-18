import 'dart:async';
import 'dart:math' as math;

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
      unawaited(_engine.correct(praise: round.praise));
    } else {
      setState(() => _wrongIds.add(o.id));
      unawaited(_engine.wrong(hint: round.hint, explain: round.explain, allowRetry: round.allowRetry));
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
    if (_engine.busy || index >= _bandeja.length) {
      return;
    }
    setState(() => _bandeja.removeAt(index));
    AppScope.read(context).voice.sayLater(_suma == 0 ? 'No llevas nada.' : pesosEnPalabras(_suma));
  }

  void _pagar() {
    final PagoRound? pago = _round?.pago;
    if (pago == null || _engine.busy) {
      return;
    }
    final int total = pago.total;
    final int suma = _suma;
    if (suma == total) {
      unawaited(_engine.correct(praise: 'Pagaste ${pesosEnPalabras(total)} exactos.'));
      return;
    }
    final String llevas = pesosEnPalabras(suma);
    final String diferencia = suma < total ? 'Te faltan ${pesosEnPalabras(total - suma)}.' : 'Te sobran ${pesosEnPalabras(suma - total)}: quita alguna moneda o billete.';
    unawaited(_engine.wrong(
      hint: 'Llevas $llevas y necesitas ${pesosEnPalabras(total)}. $diferencia',
      explain: 'Eran ${pesosEnPalabras(total)}: ${_combinacion(pago)}.',
    ));
  }

  /// Una forma de armar el total con las denominaciones disponibles, de mayor a menor.
  String _combinacion(PagoRound pago) {
    final List<Denominacion> ds = List<Denominacion>.from(pago.denominaciones)..sort((Denominacion a, Denominacion b) => b.valor.compareTo(a.valor));
    int resto = pago.total;
    final List<String> partes = <String>[];
    for (final Denominacion d in ds) {
      final int n = resto ~/ d.valor;
      if (n > 0) {
        partes.add('${d.esBillete ? (n == 1 ? 'un billete' : '$n billetes') : (n == 1 ? 'una moneda' : '$n monedas')} de ${formatPesos(d.valor)}');
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
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
          final bool wide = c.maxWidth > c.maxHeight * 1.15;
          if (wide) {
            // Apaisado: productos, bandeja y monedero en tres columnas a todo lo alto.
            final double monederoW = c.maxWidth * 5 / 12 - 12;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(flex: 3, child: _productosColumna(pago)),
                const SizedBox(width: 12),
                Expanded(flex: 4, child: _bandejaView()),
                const SizedBox(width: 12),
                Expanded(
                  flex: 5,
                  child: Column(
                    children: <Widget>[
                      Expanded(child: Center(child: SingleChildScrollView(child: _monedero(pago, _coinWidth(pago, monederoW, 3))))),
                      const SizedBox(height: 8),
                      _botonPagar(),
                    ],
                  ),
                ),
              ],
            );
          }
          final double coinWidth = _coinWidth(pago, c.maxWidth, 2);
          return Column(
            children: <Widget>[
              _productos(pago, emoji: c.maxHeight < 520 ? 44 : 60),
              const SizedBox(height: 10),
              Expanded(child: _bandejaView()),
              const SizedBox(height: 10),
              _monedero(pago, coinWidth),
              const SizedBox(height: 10),
              _botonPagar(),
            ],
          );
        }),
      ),
    );
  }

  /// Ancho de cada moneda o billete para que el monedero quepa en [filas]
  /// filas como mucho.
  double _coinWidth(PagoRound pago, double available, int filas) {
    final int n = pago.denominaciones.length;
    final int perRow = n <= 1 ? 1 : (n / filas).ceil();
    return ((available - (perRow - 1) * 10) / perRow - 16).clamp(52.0, 96.0).toDouble();
  }

  Widget _productos(PagoRound pago, {required double emoji}) {
    final PilasPalette pal = PilasPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: pal.tarjeta, borderRadius: BorderRadius.circular(Dim.radio), border: Border.all(color: pal.altoContraste ? pal.bordeFuerte : pal.borde, width: 2)),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (int i = 0; i < pago.productos.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: 20),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  EmojiImage(pago.productos[i].item.emoji, size: emoji, semanticsLabel: pago.productos[i].item.nombre),
                  Text(formatPesos(pago.productos[i].precio), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: pal.tinta)),
                ],
              ),
            ],
            if (pago.productos.length > 1) ...<Widget>[
              const SizedBox(width: 16),
              Text('= ${formatPesos(pago.total)}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: pal.acento)),
            ],
          ],
        ),
      ),
    );
  }

  /// Los productos uno debajo de otro (dibujo y precio en la misma línea),
  /// achicados si la columna no alcanza.
  Widget _productosColumna(PagoRound pago) {
    final PilasPalette pal = PilasPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: pal.tarjeta, borderRadius: BorderRadius.circular(Dim.radio), border: Border.all(color: pal.altoContraste ? pal.bordeFuerte : pal.borde, width: 2)),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (final Producto p in pago.productos)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      EmojiImage(p.item.emoji, size: 48, semanticsLabel: p.item.nombre),
                      const SizedBox(width: 8),
                      Text(formatPesos(p.precio), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: pal.tinta)),
                    ],
                  ),
                ),
              if (pago.productos.length > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('= ${formatPesos(pago.total)}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: pal.acento)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bandejaView() {
    final PilasPalette pal = PilasPalette.of(context);
    final Widget total = FittedBox(
      fit: BoxFit.scaleDown,
      child: Text('Llevas ${formatPesos(_suma)}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: pal.tinta)),
    );
    final Widget monedas = Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: <Widget>[
        for (int i = 0; i < _bandeja.length; i++)
          Semantics(
            button: true,
            label: 'Quitar ${_bandeja[i].nombre}',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: () => _quitar(i),
              child: MoneyWidget(denominacion: _bandeja[i], width: 84),
            ),
          ),
      ],
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: pal.correctoClaro,
        borderRadius: BorderRadius.circular(Dim.radio),
        border: Border.all(color: pal.correcto, width: 2),
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints b) {
          if (b.maxHeight < 80) {
            return SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[total, const SizedBox(height: 8), monedas]));
          }
          return Column(
            children: <Widget>[
              Semantics(liveRegion: true, child: total),
              const SizedBox(height: 8),
              Expanded(child: SingleChildScrollView(child: monedas)),
            ],
          );
        },
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
          SizedBox(
            width: math.max(coinWidth + 16, 56),
            child: OptionTile(
              key: ValueKey<String>('dinero-${d.valor}'),
              padding: const EdgeInsets.all(8),
              minHeight: 56,
              minWidth: 56,
              semanticsLabel: 'Agregar ${d.nombre}',
              onTap: () => _agregar(d),
              child: FittedBox(fit: BoxFit.scaleDown, child: MoneyWidget(denominacion: d, width: coinWidth)),
            ),
          ),
      ],
    );
  }

  Widget _botonPagar() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        key: const ValueKey<String>('pagar'),
        onPressed: _bandeja.isEmpty || _engine.busy ? null : _pagar,
        icon: const Icon(Icons.shopping_bag_rounded),
        label: const Text('Pagar'),
      ),
    );
  }
}
