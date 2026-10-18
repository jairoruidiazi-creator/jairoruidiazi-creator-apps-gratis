import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/sfx.dart';
import '../../core/theme.dart';
import '../../engine/game_def.dart';
import '../../engine/round_engine.dart';
import '../colorear/colorear_screen.dart';
import '../shell/canvas_saver.dart';
import '../shell/game_frame.dart';
import '../shell/widgets.dart';

/// Un trazo libre: puntos, color y grosor. [goma] = trazo de borrador.
class _Stroke {
  _Stroke(this.color, this.width, this.points, {this.goma = false});

  final Color color;
  final double width;
  final List<Offset> points;
  final bool goma;

  double get length {
    double l = 0;
    for (int i = 1; i < points.length; i++) {
      l += (points[i] - points[i - 1]).distance;
    }
    return l;
  }
}

/// Un sello (pictograma) puesto en el lienzo.
class _Stamp {
  const _Stamp(this.code, this.at, this.size);

  final String code;
  final Offset at;
  final double size;
}

/// Dibujo y sellos: lienzo libre con pincel de tres grosores, goma, sellos de
/// pictogramas y guardado en Mis dibujos. Sin bien ni mal: al terminar cuenta
/// como actividad, sin niveles ni habilidades. Nunca se guarda un lienzo
/// vacío.
class DibujoScreen extends StatefulWidget {
  const DibujoScreen({super.key, required this.launch});

  final GameLaunch launch;

  @override
  State<DibujoScreen> createState() => _DibujoScreenState();
}

class _DibujoScreenState extends State<DibujoScreen> {
  late final RoundEngine _engine;
  final GlobalKey _canvasKey = GlobalKey();
  final List<_Stroke> _strokes = <_Stroke>[];
  final List<_Stamp> _stamps = <_Stamp>[];
  final List<Object> _history = <Object>[]; // orden de creación para deshacer
  int _colorIndex = 0;
  double _width = 10;
  String? _stamp;
  bool _goma = false;
  bool _saving = false;
  bool _started = false;

  static const List<List<String>> sellos = <List<String>>[
    <String>['2b50', 'estrella'],
    <String>['2764', 'corazón'],
    <String>['1f33b', 'girasol'],
    <String>['1f98b', 'mariposa'],
    <String>['1f41f', 'pez'],
    <String>['1f426', 'pájaro'],
    <String>['2600', 'sol'],
    <String>['2601', 'nube'],
    <String>['1f333', 'árbol'],
    <String>['1f3e0', 'casa'],
    <String>['1f697', 'carro'],
    <String>['1f680', 'cohete'],
    <String>['1f308', 'arcoíris'],
    <String>['1f43b', 'oso'],
    <String>['1f984', 'unicornio'],
    <String>['1f99c', 'loro'],
  ];

  static const List<double> grosores = <double>[5, 10, 20];

  static const List<String> nombresGrosor = <String>['delgado', 'mediano', 'grueso'];

  @override
  void initState() {
    super.initState();
    final Services s = AppScope.read(context);
    _engine = RoundEngine(app: s.state, voice: s.voice, sfx: s.sfx, launch: widget.launch, onNextRound: _limpiar);
    _engine.addListener(_refresh);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _engine.startRound();
      _engine.say('Dibuja lo que quieras. Elige un color o un sello y pinta con el dedo.');
    }
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  void _limpiar() {
    if (!mounted) {
      return;
    }
    setState(() {
      _strokes.clear();
      _stamps.clear();
      _history.clear();
    });
    _engine.startRound();
  }

  /// Hay algo dibujado de verdad: un sello o trazos de color que sumen un
  /// pedazo visible (un toque suelto no basta).
  bool get _hasDrawing {
    if (_stamps.isNotEmpty) {
      return true;
    }
    double total = 0;
    for (final _Stroke s in _strokes) {
      if (!s.goma) {
        total += s.length + s.width;
      }
    }
    return total >= 30;
  }

  void _undo() {
    if (_history.isEmpty || _engine.busy) {
      return;
    }
    unawaited(AppScope.read(context).sfx.play(SfxId.tap));
    setState(() {
      final Object last = _history.removeLast();
      if (last is _Stroke) {
        _strokes.remove(last);
      } else if (last is _Stamp) {
        _stamps.remove(last);
      }
    });
  }

  void _start(Offset p) {
    if (_engine.busy) {
      return;
    }
    if (_stamp != null) {
      final _Stamp st = _Stamp(_stamp!, p, _width * 5 + 24);
      unawaited(AppScope.read(context).sfx.play(SfxId.pop));
      setState(() {
        _stamps.add(st);
        _history.add(st);
      });
      return;
    }
    final _Stroke s = _goma
        ? _Stroke(Colors.white, _width * 2.5, <Offset>[p], goma: true)
        : _Stroke(PaletaLibre.colores[_colorIndex].color, _width, <Offset>[p]);
    setState(() {
      _strokes.add(s);
      _history.add(s);
    });
  }

  void _move(Offset p) {
    if (_stamp != null || _strokes.isEmpty || _engine.busy) {
      return;
    }
    setState(() => _strokes.last.points.add(p));
  }

  Future<void> _guardar({bool silencioso = false}) async {
    if (_saving) {
      return;
    }
    if (!_hasDrawing) {
      if (!silencioso) {
        AppScope.read(context).voice.sayLater('Primero dibuja algo.');
      }
      return;
    }
    _saving = true;
    try {
      await saveCanvasPng(context, _canvasKey, widget.launch.profile.id, silencioso: silencioso);
    } finally {
      _saving = false;
    }
  }

  Future<void> _terminar() async {
    if (_engine.busy) {
      return;
    }
    if (!_hasDrawing) {
      AppScope.read(context).voice.sayLater('Primero dibuja algo.');
      return;
    }
    unawaited(_guardar(silencioso: true));
    await _engine.completeFree(message: '¡Qué buen dibujo! Lo guardé en Mis dibujos.');
  }

  void _say(String text) => AppScope.read(context).voice.sayLater(text);

  void _pickColor(int i) {
    setState(() {
      _colorIndex = i;
      _goma = false;
      _stamp = null;
    });
    _say(PaletaLibre.colores[i].nombre);
  }

  void _pickGoma() {
    setState(() {
      _goma = true;
      _stamp = null;
    });
    _say('Goma');
  }

  void _pickStamp(List<String> s) {
    setState(() {
      _stamp = s[0];
      _goma = false;
    });
    _say('Sello: ${s[1]}');
  }

  void _pickWidth(int i) {
    setState(() => _width = grosores[i]);
    _say('Pincel ${nombresGrosor[i]}');
  }

  @override
  void dispose() {
    _engine.removeListener(_refresh);
    _engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GameFrame(
      launch: widget.launch,
      engine: _engine,
      instruction: 'Dibuja lo que quieras con colores y sellos.',
      child: LayoutBuilder(builder: _layout),
    );
  }

  Widget _layout(BuildContext context, BoxConstraints c) {
    final PilasPalette pal = PilasPalette.of(context);
    final bool leftHanded = widget.launch.profile.leftHanded;
    final Widget canvas = Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Container(
        decoration: BoxDecoration(border: Border.all(color: pal.altoContraste ? pal.bordeFuerte : pal.borde, width: 2), borderRadius: BorderRadius.circular(Dim.radio)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Dim.radio - 2),
          child: Semantics(
            label: 'Lienzo para dibujar',
            child: GestureDetector(
              key: const ValueKey<String>('dibujo-lienzo'),
              behavior: HitTestBehavior.opaque,
              onTapUp: (TapUpDetails d) => _start(d.localPosition),
              onPanStart: (DragStartDetails d) => _start(d.localPosition),
              onPanUpdate: (DragUpdateDetails d) => _move(d.localPosition),
              child: RepaintBoundary(
                key: _canvasKey,
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(child: CustomPaint(painter: _DrawPainter(_strokes))),
                    for (final _Stamp st in _stamps)
                      Positioned(
                        left: st.at.dx - st.size / 2,
                        top: st.at.dy - st.size / 2,
                        child: IgnorePointer(child: EmojiImage(st.code, size: st.size)),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final List<Widget> colores = <Widget>[
      for (int i = 0; i < PaletaLibre.colores.length; i++)
        _ToolButton(
          key: ValueKey<String>('dibujo-color-$i'),
          selected: !_goma && _stamp == null && _colorIndex == i,
          label: 'Color ${PaletaLibre.colores[i].nombre}',
          onTap: () => _pickColor(i),
          child: Container(width: 30, height: 30, decoration: BoxDecoration(color: PaletaLibre.colores[i].color, shape: BoxShape.circle, border: Border.all(color: pal.bordeFuerte))),
        ),
      _ToolButton(key: const ValueKey<String>('dibujo-goma'), selected: _goma, label: 'Goma', onTap: _pickGoma, child: Icon(Icons.auto_fix_normal_rounded, color: pal.tinta)),
    ];
    final List<Widget> pinceles = <Widget>[
      for (int i = 0; i < grosores.length; i++)
        _ToolButton(
          selected: _width == grosores[i] && _stamp == null,
          label: 'Pincel ${nombresGrosor[i]}',
          onTap: () => _pickWidth(i),
          child: Container(width: grosores[i] + 4, height: grosores[i] + 4, decoration: BoxDecoration(color: pal.tinta, shape: BoxShape.circle)),
        ),
    ];
    final List<Widget> stamps = <Widget>[
      for (final List<String> s in sellos) _ToolButton(selected: _stamp == s[0], label: 'Sello: ${s[1]}', onTap: () => _pickStamp(s), child: EmojiImage(s[0], size: 32)),
    ];
    final List<Widget> buttons = <Widget>[
      RoundIconButton(key: const ValueKey<String>('dibujo-deshacer'), icon: Icons.undo_rounded, tooltip: 'Deshacer', onPressed: _history.isEmpty ? null : _undo, size: 52),
      const SizedBox(width: 8),
      RoundIconButton(key: const ValueKey<String>('dibujo-guardar'), icon: Icons.save_alt_rounded, tooltip: 'Guardar en Mis dibujos', onPressed: () => _guardar(), size: 52),
    ];
    final Widget done = FilledButton.icon(
      key: const ValueKey<String>('dibujo-termine'),
      onPressed: _engine.busy ? null : _terminar,
      icon: const Icon(Icons.check_rounded),
      label: const Text('Terminé'),
      style: FilledButton.styleFrom(minimumSize: const Size(120, 52), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
    );
    if (c.maxWidth > c.maxHeight) {
      // Acostado: el lienzo a un lado y las herramientas al otro.
      final double colW = math.min(220, c.maxWidth * 0.4);
      final int cols = math.max(3, (colW / 52).floor());
      final Widget column = SizedBox(
        width: colW,
        child: Column(
          children: <Widget>[
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: <Widget>[
                    _grid(colores, cols),
                    const SizedBox(height: 6),
                    _grid(pinceles, cols),
                    const SizedBox(height: 6),
                    _grid(stamps, cols),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            FittedBox(fit: BoxFit.scaleDown, child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[...buttons, const SizedBox(width: 8), done])),
            const SizedBox(height: 8),
          ],
        ),
      );
      final List<Widget> row = <Widget>[Expanded(child: canvas), column, const SizedBox(width: 8)];
      return Row(children: leftHanded ? row.reversed.toList() : row);
    }
    final int perRow = math.max(4, ((c.maxWidth - 24) / 52).floor());
    final int rows = (colores.length / perRow).ceil();
    final int cols = (colores.length / rows).ceil();
    // «Terminé» ocupa lo que sobra y se achica un poco si la letra es muy
    // grande, para no salirse de la pantalla.
    final List<Widget> bottom = <Widget>[
      ...buttons,
      const SizedBox(width: 8),
      Expanded(child: Align(alignment: leftHanded ? Alignment.centerLeft : Alignment.centerRight, child: FittedBox(fit: BoxFit.scaleDown, child: done))),
    ];
    return Column(
      children: <Widget>[
        Expanded(child: canvas),
        _grid(colores, cols),
        const SizedBox(height: 4),
        SizedBox(
          height: 52,
          child: Row(
            children: <Widget>[
              const SizedBox(width: 8),
              ...pinceles,
              const SizedBox(width: 4),
              Container(width: 2, height: 36, color: pal.borde),
              const SizedBox(width: 4),
              Expanded(child: ListView(scrollDirection: Axis.horizontal, children: stamps)),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: Row(children: leftHanded ? bottom.reversed.toList() : bottom),
        ),
      ],
    );
  }

  Widget _grid(List<Widget> items, int columns) {
    final int rows = (items.length / columns).ceil();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int r = 0; r < rows; r++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[for (int k = r * columns; k < math.min(items.length, (r + 1) * columns); k++) items[k]],
          ),
      ],
    );
  }
}

class _DrawPainter extends CustomPainter {
  _DrawPainter(this.strokes);

  final List<_Stroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    for (final _Stroke s in strokes) {
      final Paint p = Paint()
        ..color = s.color
        ..strokeWidth = s.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      if (s.points.length == 1) {
        canvas.drawCircle(s.points.first, s.width / 2, Paint()..color = s.color);
        continue;
      }
      final Path path = Path()..moveTo(s.points.first.dx, s.points.first.dy);
      for (int i = 1; i < s.points.length; i++) {
        path.lineTo(s.points[i].dx, s.points[i].dy);
      }
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(covariant _DrawPainter old) => true;
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({super.key, required this.selected, required this.label, required this.onTap, required this.child});

  final bool selected;
  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final PilasPalette pal = PilasPalette.of(context);
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            unawaited(AppScope.read(context).sfx.play(SfxId.tap));
            onTap();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: selected ? pal.acentoClaro : pal.tarjeta,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? pal.tinta : pal.bordeFuerte, width: selected ? 3 : 1.5),
            ),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
