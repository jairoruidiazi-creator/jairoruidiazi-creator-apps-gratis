import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../content/coloring_pages.dart';
import '../../core/app_scope.dart';
import '../../core/sfx.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../engine/game_def.dart';
import '../../engine/round_engine.dart';
import '../../model/age_band.dart';
import '../shell/game_frame.dart';
import '../shell/widgets.dart';
import 'coloring_painter.dart';

/// Colorear: libre con la paleta, o por números y letras.
class ColorearScreen extends StatefulWidget {
  const ColorearScreen({super.key, required this.launch, this.porNumeros = false});

  final GameLaunch launch;

  /// Modo "por números" (y por letras en primaria).
  final bool porNumeros;

  @override
  State<ColorearScreen> createState() => _ColorearScreenState();
}

class _ColorearScreenState extends State<ColorearScreen> {
  late final RoundEngine _engine;
  List<ColoringPage>? _pages;
  ColoringPage? _page;
  ColoringLayout? _layout;
  final Map<String, Color> _fills = <String, Color>{};
  final List<Map<String, Color>> _history = <Map<String, Color>>[];
  Color _color = const Color(0xFFE53935);
  int _paletteIndex = 0;
  String? _highlight;
  Timer? _highlightTimer;
  bool _saving = false;
  final GlobalKey _canvasKey = GlobalKey();

  static const List<Color> _paletaLibre = <Color>[
    Color(0xFFE53935), Color(0xFFFB8C00), Color(0xFFFDD835), Color(0xFF43A047), Color(0xFF9CCC65),
    Color(0xFF1E88E5), Color(0xFF4FC3F7), Color(0xFF8E24AA), Color(0xFFEC407A), Color(0xFF6D4C41),
    Color(0xFF90A4AE), Color(0xFFF5CBA7), Color(0xFF263238), Colors.white,
  ];

  @override
  void initState() {
    super.initState();
    final Services s = AppScope.read(context);
    _engine = RoundEngine(app: s.state, voice: s.voice, sfx: s.sfx, launch: widget.launch, onNextRound: _volverAlCatalogo);
    _engine.addListener(_refresh);
    _load();
  }

  Future<void> _load() async {
    final List<ColoringPage> all = await ColoringLibrary.load();
    if (!mounted) {
      return;
    }
    final int bandIndex = widget.launch.band.index;
    setState(() {
      _pages = all.where((ColoringPage p) => p.minBand <= bandIndex).toList();
    });
    AppScope.read(context).voice.sayLater('Elige un dibujo para pintar.');
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  void _volverAlCatalogo() {
    if (!mounted) {
      return;
    }
    setState(() {
      _page = null;
      _layout = null;
      _fills.clear();
      _history.clear();
    });
  }

  void _abrir(ColoringPage page) {
    setState(() {
      _page = page;
      _layout = ColoringLayout(page);
      _fills.clear();
      _history.clear();
      _paletteIndex = 0;
      _color = widget.porNumeros ? page.palette.first : _paletaLibre.first;
    });
    _engine.startRound();
    _engine.say(widget.porNumeros ? 'Pinta cada zona con el color de su número.' : 'Toca una zona para pintarla con el color que elijas.');
  }

  List<Color> get _palette => widget.porNumeros ? (_page?.palette ?? <Color>[]) : _paletaLibre;

  void _tapCanvas(Offset local, Size size) {
    final ColoringLayout? layout = _layout;
    final ColoringPage? page = _page;
    if (layout == null || page == null || _engine.busy) {
      return;
    }
    final Offset p = ColoringLayout.toPage(page.viewBox, size, local);
    final ColoringRegion? r = layout.hitTest(p);
    if (r == null) {
      return;
    }
    final Services s = AppScope.read(context);
    if (widget.porNumeros) {
      if (r.targetColor != _color) {
        unawaited(s.sfx.play(SfxId.hint));
        s.voice.sayLater(_etiqueta(r.number, 'esa zona es la') + '. Busca ese color.');
        setState(() => _highlight = r.id);
        _highlightTimer?.cancel();
        _highlightTimer = Timer(const Duration(milliseconds: 900), () {
          if (mounted) {
            setState(() => _highlight = null);
          }
        });
        return;
      }
    }
    unawaited(s.sfx.play(SfxId.pop));
    setState(() {
      _history.add(Map<String, Color>.from(_fills));
      if (_history.length > 30) {
        _history.removeAt(0);
      }
      if (_color == Colors.white) {
        _fills.remove(r.id);
      } else {
        _fills[r.id] = _color;
      }
    });
    if (widget.porNumeros && _complete) {
      _engine.say('¡Terminaste el dibujo!');
      unawaited(_guardar(silencioso: true).then((_) => _engine.completeFree()));
    }
  }

  bool get _complete {
    final ColoringPage? page = _page;
    if (page == null) {
      return false;
    }
    for (final ColoringRegion r in page.regions) {
      if (_fills[r.id] != r.targetColor) {
        return false;
      }
    }
    return true;
  }

  String _etiqueta(int n, String prefijo) {
    if (widget.launch.band.readsText) {
      // Por letras en primaria: 1 = A, 2 = B...
      return '$prefijo letra ${String.fromCharCode(64 + n)}';
    }
    return '$prefijo número $n';
  }

  void _deshacer() {
    if (_history.isEmpty) {
      return;
    }
    setState(() {
      _fills
        ..clear()
        ..addAll(_history.removeLast());
    });
  }

  Future<void> _guardar({bool silencioso = false}) async {
    if (_saving) {
      return;
    }
    _saving = true;
    try {
      final RenderRepaintBoundary? boundary = _canvasKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        return;
      }
      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        return;
      }
      final Uint8List bytes = data.buffer.asUint8List();
      final Services s = AppScope.read(context);
      final String name = 'drawings/${widget.launch.profile.id}/${DateTime.now().millisecondsSinceEpoch}.png';
      await s.store.writeBytes(name, bytes);
      if (!silencioso && mounted) {
        unawaited(s.sfx.play(SfxId.sticker));
        s.voice.sayLater('Guardado en mis dibujos.');
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Guardado en Mis dibujos')));
      }
    } finally {
      _saving = false;
    }
  }

  Future<void> _terminar() async {
    await _guardar(silencioso: true);
    if (mounted) {
      await _engine.completeFree();
    }
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _engine.removeListener(_refresh);
    _engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColoringPage? page = _page;
    if (page == null) {
      return GameFrame(
        launch: widget.launch,
        engine: _engine,
        instruction: 'Elige un dibujo para pintar.',
        child: _catalogo(),
      );
    }
    final bool leftHanded = widget.launch.profile.leftHanded;
    return GameFrame(
      launch: widget.launch,
      engine: _engine,
      instruction: widget.porNumeros ? 'Pinta cada zona con el color de su número.' : page.nombre,
      actions: <Widget>[
        RoundIconButton(icon: Icons.undo_rounded, tooltip: 'Deshacer', onPressed: _history.isEmpty ? null : _deshacer),
        const SizedBox(width: 6),
        RoundIconButton(icon: Icons.save_alt_rounded, tooltip: S.guardar, onPressed: () => _guardar()),
      ],
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          final bool landscape = c.maxWidth > c.maxHeight;
          final Widget canvas = Padding(
            padding: const EdgeInsets.all(12),
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints cc) {
                final Size size = Size(cc.maxWidth, cc.maxHeight);
                return GestureDetector(
                  onTapDown: (TapDownDetails d) => _tapCanvas(d.localPosition, size),
                  child: RepaintBoundary(
                    key: _canvasKey,
                    child: Container(
                      color: Colors.white,
                      child: CustomPaint(
                        size: size,
                        painter: ColoringPainter(layout: _layout!, fills: Map<String, Color>.from(_fills), showNumbers: widget.porNumeros, highlight: _highlight),
                      ),
                    ),
                  ),
                );
              },
            ),
          );
          final Widget palette = _paletteBar(vertical: landscape);
          final Widget done = Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: widget.porNumeros ? null : _terminar,
                icon: const Icon(Icons.check_rounded),
                label: const Text(S.listo),
              ),
            ),
          );
          if (landscape) {
            final List<Widget> row = <Widget>[Expanded(child: canvas), palette];
            return Column(
              children: <Widget>[
                Expanded(child: Row(children: leftHanded ? row.reversed.toList() : row)),
                if (!widget.porNumeros) done,
              ],
            );
          }
          return Column(
            children: <Widget>[
              Expanded(child: canvas),
              palette,
              if (!widget.porNumeros) done,
            ],
          );
        },
      ),
    );
  }

  Widget _paletteBar({required bool vertical}) {
    final List<Color> colors = _palette;
    final List<Widget> swatches = <Widget>[];
    for (int i = 0; i < colors.length; i++) {
      final Color c = colors[i];
      final bool selected = i == _paletteIndex;
      swatches.add(
        Padding(
          padding: const EdgeInsets.all(4),
          child: Semantics(
            button: true,
            selected: selected,
            label: widget.porNumeros ? _etiqueta(i + 1, 'color') : (c == Colors.white ? 'Borrador' : 'Color'),
            child: GestureDetector(
              onTap: () {
                unawaited(AppScope.read(context).sfx.play(SfxId.tap));
                setState(() {
                  _paletteIndex = i;
                  _color = c;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: selected ? 54 : 46,
                height: selected ? 54 : 46,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(color: selected ? PilasColors.tinta : Colors.black.withValues(alpha: 0.2), width: selected ? 4 : 2),
                ),
                child: widget.porNumeros
                    ? Center(
                        child: Text(
                          widget.launch.band.readsText ? String.fromCharCode(65 + i) : '${i + 1}',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _contrast(c)),
                        ),
                      )
                    : (c == Colors.white ? const Icon(Icons.cleaning_services_rounded, size: 20, color: PilasColors.tinta) : null),
              ),
            ),
          ),
        ),
      );
    }
    if (vertical) {
      return SizedBox(
        width: 70,
        child: SingleChildScrollView(child: Column(children: swatches)),
      );
    }
    return SizedBox(
      height: 70,
      child: SingleChildScrollView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), child: Row(children: swatches)),
    );
  }

  Color _contrast(Color c) {
    final double lum = c.computeLuminance();
    return lum > 0.5 ? PilasColors.tinta : Colors.white;
  }

  Widget _catalogo() {
    final List<ColoringPage>? pages = _pages;
    if (pages == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final int cols = c.maxWidth > 900 ? 4 : (c.maxWidth > 560 ? 3 : 2);
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 14, crossAxisSpacing: 14, childAspectRatio: 0.9),
          itemCount: pages.length,
          itemBuilder: (BuildContext context, int i) {
            final ColoringPage p = pages[i];
            return OptionTile(
              semanticsLabel: p.nombre,
              onTap: () => _abrir(p),
              padding: const EdgeInsets.all(8),
              child: Column(
                children: <Widget>[
                  Expanded(
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: ColoringPainter(layout: ColoringLayout(p), fills: const <String, Color>{}, showNumbers: false),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(p.nombre, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
