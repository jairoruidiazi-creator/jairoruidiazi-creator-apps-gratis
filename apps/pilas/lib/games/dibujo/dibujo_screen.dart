import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/sfx.dart';
import '../../core/theme.dart';
import '../../engine/game_def.dart';
import '../../engine/round_engine.dart';
import '../shell/canvas_saver.dart';
import '../shell/game_frame.dart';
import '../shell/widgets.dart';

/// Un trazo libre: puntos, color y grosor.
class _Stroke {
  _Stroke(this.color, this.width, this.points);

  final Color color;
  final double width;
  final List<Offset> points;
}

/// Un sello (pictograma) puesto en el lienzo.
class _Stamp {
  const _Stamp(this.code, this.at, this.size);

  final String code;
  final Offset at;
  final double size;
}

/// Dibujo y sellos: lienzo libre con pincel, borrador, sellos de pictogramas
/// y guardado en Mis dibujos. Sin bien ni mal: al terminar se registra una
/// ronda completada.
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
  Color _color = const Color(0xFFE53935);
  double _width = 10;
  String? _stamp;
  bool _eraser = false;
  bool _saving = false;
  bool _started = false;

  static const List<Color> _paleta = <Color>[
    Color(0xFFE53935), Color(0xFFFB8C00), Color(0xFFFDD835), Color(0xFF43A047), Color(0xFF9CCC65),
    Color(0xFF1E88E5), Color(0xFF4FC3F7), Color(0xFF8E24AA), Color(0xFFEC407A), Color(0xFF6D4C41),
    Color(0xFF263238), Colors.white,
  ];

  static const List<List<String>> _sellos = <List<String>>[
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
    <String>['1f99c', 'guacamaya'],
  ];

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

  void _undo() {
    if (_history.isEmpty) {
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
    final _Stroke s = _Stroke(_eraser ? Colors.white : _color, _eraser ? _width * 2.5 : _width, <Offset>[p]);
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

  Future<void> _guardar() async {
    if (_saving) {
      return;
    }
    _saving = true;
    try {
      await saveCanvasPng(context, _canvasKey, widget.launch.profile.id);
    } finally {
      _saving = false;
    }
  }

  Future<void> _terminar() async {
    if (_strokes.isEmpty && _stamps.isEmpty) {
      AppScope.read(context).voice.sayLater('Primero dibuja algo.');
      return;
    }
    await _guardarSilencioso();
    if (mounted) {
      await _engine.completeFree();
    }
  }

  Future<void> _guardarSilencioso() async {
    if (_saving) {
      return;
    }
    _saving = true;
    try {
      await saveCanvasPng(context, _canvasKey, widget.launch.profile.id, silencioso: true);
    } finally {
      _saving = false;
    }
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
      actions: <Widget>[
        RoundIconButton(icon: Icons.undo_rounded, tooltip: 'Deshacer', onPressed: _undo),
        const SizedBox(width: 6),
        RoundIconButton(icon: Icons.save_alt_rounded, tooltip: 'Guardar', onPressed: _guardar),
      ],
      child: LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
        final bool wide = c.maxWidth > c.maxHeight * 1.15;
        final Widget canvas = Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Dim.radio),
            child: Container(
              decoration: BoxDecoration(border: Border.all(color: PilasColors.borde, width: 2), borderRadius: BorderRadius.circular(Dim.radio)),
              child: RepaintBoundary(
                key: _canvasKey,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (DragStartDetails d) => _start(d.localPosition),
                  onPanUpdate: (DragUpdateDetails d) => _move(d.localPosition),
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
        );
        final Widget tools = _Tools(
          paleta: _paleta,
          sellos: _sellos,
          color: _color,
          eraser: _eraser,
          stamp: _stamp,
          width: _width,
          vertical: wide,
          onColor: (Color c) => setState(() {
            _color = c;
            _eraser = false;
            _stamp = null;
          }),
          onEraser: () => setState(() {
            _eraser = true;
            _stamp = null;
          }),
          onStamp: (String s) => setState(() {
            _stamp = s;
            _eraser = false;
          }),
          onWidth: (double w) => setState(() => _width = w),
        );
        final Widget done = Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: FilledButton.icon(
            onPressed: _engine.busy ? null : _terminar,
            icon: const Icon(Icons.check_rounded),
            label: const Text('Terminé', style: TextStyle(fontSize: 18)),
            style: FilledButton.styleFrom(minimumSize: const Size(160, 50)),
          ),
        );
        if (wide) {
          return Row(
            children: <Widget>[
              Expanded(child: Column(children: <Widget>[Expanded(child: canvas), done])),
              SizedBox(width: 120, child: tools),
            ],
          );
        }
        return Column(children: <Widget>[Expanded(child: canvas), tools, done]);
      }),
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

class _Tools extends StatelessWidget {
  const _Tools({
    required this.paleta,
    required this.sellos,
    required this.color,
    required this.eraser,
    required this.stamp,
    required this.width,
    required this.vertical,
    required this.onColor,
    required this.onEraser,
    required this.onStamp,
    required this.onWidth,
  });

  final List<Color> paleta;
  final List<List<String>> sellos;
  final Color color;
  final bool eraser;
  final String? stamp;
  final double width;
  final bool vertical;
  final ValueChanged<Color> onColor;
  final VoidCallback onEraser;
  final ValueChanged<String> onStamp;
  final ValueChanged<double> onWidth;

  @override
  Widget build(BuildContext context) {
    final List<Widget> items = <Widget>[
      for (final Color c in paleta)
        if (c == Colors.white)
          _ToolButton(selected: eraser, label: 'Borrador', onTap: onEraser, child: const Icon(Icons.cleaning_services_rounded, color: PilasColors.tintaSuave))
        else
          _ToolButton(
            selected: !eraser && stamp == null && color == c,
            label: 'Color',
            onTap: () => onColor(c),
            child: Container(width: 30, height: 30, decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: Colors.black.withValues(alpha: 0.15)))),
          ),
      for (final List<String> s in sellos) _ToolButton(selected: stamp == s[0], label: 'Sello: ${s[1]}', onTap: () => onStamp(s[0]), child: EmojiImage(s[0], size: 30)),
    ];
    final Widget grosor = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final double w in <double>[5, 10, 20])
          _ToolButton(
            selected: width == w,
            label: 'Grosor $w',
            onTap: () => onWidth(w),
            child: Container(width: w + 6, height: w + 6, decoration: const BoxDecoration(color: PilasColors.tinta, shape: BoxShape.circle)),
          ),
      ],
    );
    if (vertical) {
      return Container(
        margin: const EdgeInsets.fromLTRB(0, 4, 12, 12),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(Dim.radio), border: Border.all(color: PilasColors.borde, width: 2)),
        child: SingleChildScrollView(
          child: Column(
            children: <Widget>[
              Wrap(alignment: WrapAlignment.center, children: items),
              const Divider(),
              Wrap(alignment: WrapAlignment.center, children: <Widget>[grosor]),
            ],
          ),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(Dim.radio), border: Border.all(color: PilasColors.borde, width: 2)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              children: items,
            ),
          ),
          const SizedBox(height: 4),
          grosor,
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.selected, required this.label, required this.onTap, required this.child});

  final bool selected;
  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(3),
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: GestureDetector(
          onTap: () {
            unawaited(AppScope.read(context).sfx.play(SfxId.tap));
            onTap();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: selected ? PilasColors.amarillo.withValues(alpha: 0.5) : PilasColors.fondo,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? PilasColors.tinta : PilasColors.borde, width: selected ? 3 : 1.5),
            ),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
