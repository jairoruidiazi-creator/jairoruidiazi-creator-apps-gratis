import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../content/coloring_pages.dart';
import '../../core/app_scope.dart';
import '../../core/sfx.dart';
import '../../core/theme.dart';
import '../../engine/game_def.dart';
import '../../engine/round_engine.dart';
import '../../model/age_band.dart';
import '../shell/canvas_saver.dart';
import '../shell/game_frame.dart';
import '../shell/widgets.dart';
import 'coloring_painter.dart';

/// Herramienta activa: pintar con el color elegido o borrar con la goma.
enum ColoringTool { pintar, goma }

/// Un color de la paleta libre con su nombre.
class NamedSwatch {
  const NamedSwatch(this.color, this.nombre);

  final Color color;
  final String nombre;
}

/// Paleta libre de Colorear y de Dibujo, con el nombre de cada color (para
/// la voz y el lector de pantalla). El blanco no está: es el fondo, y para
/// borrar está la goma.
class PaletaLibre {
  PaletaLibre._();

  static const List<NamedSwatch> colores = <NamedSwatch>[
    NamedSwatch(Color(0xFFE53935), 'rojo'),
    NamedSwatch(Color(0xFFFB8C00), 'naranja'),
    NamedSwatch(Color(0xFFFDD835), 'amarillo'),
    NamedSwatch(Color(0xFF9CCC65), 'verde claro'),
    NamedSwatch(Color(0xFF43A047), 'verde'),
    NamedSwatch(Color(0xFF4FC3F7), 'celeste'),
    NamedSwatch(Color(0xFF1E88E5), 'azul'),
    NamedSwatch(Color(0xFF8E24AA), 'morado'),
    NamedSwatch(Color(0xFFEC407A), 'rosado'),
    NamedSwatch(Color(0xFF6D4C41), 'café'),
    NamedSwatch(Color(0xFFF5CBA7), 'durazno'),
    NamedSwatch(Color(0xFF263238), 'negro'),
  ];
}

/// Lo que pasa en una lámina, separado de la pantalla para poder probarlo:
/// qué zonas están pintadas, con qué color, y cuántos errores hubo.
///
/// - El blanco es un color como cualquier otro: pinta, no borra. Para borrar
///   está la goma (en los dos modos).
/// - En el modo por números, un color que no es el de la zona no se pone y
///   cuenta como error.
class ColoringSession {
  ColoringSession(this.page, {required this.porNumeros});

  final ColoringPage page;
  final bool porNumeros;
  final Map<String, Color> fills = <String, Color>{};
  final List<Map<String, Color>> _history = <Map<String, Color>>[];

  /// Veces que se tocó una zona con un color que no era el suyo.
  int errors = 0;

  bool get canUndo => _history.isNotEmpty;

  bool get isEmpty => fills.isEmpty;

  /// Pinta [r] con [c]. Devuelve false si en el modo por números el color no
  /// es el de la zona (no se pinta y cuenta como error).
  bool paint(ColoringRegion r, Color c) {
    if (porNumeros && r.targetColor != c) {
      errors += 1;
      return false;
    }
    if (fills[r.id] == c) {
      return true;
    }
    _push();
    fills[r.id] = c;
    return true;
  }

  /// Borra la zona con la goma. Devuelve false si ya estaba sin pintar.
  bool erase(ColoringRegion r) {
    if (!fills.containsKey(r.id)) {
      return false;
    }
    _push();
    fills.remove(r.id);
    return true;
  }

  bool undo() {
    if (_history.isEmpty) {
      return false;
    }
    fills
      ..clear()
      ..addAll(_history.removeLast());
    return true;
  }

  void _push() {
    _history.add(Map<String, Color>.from(fills));
    if (_history.length > 40) {
      _history.removeAt(0);
    }
  }

  /// Todas las zonas tienen el color de su número.
  bool get complete {
    for (final ColoringRegion r in page.regions) {
      if (fills[r.id] != r.targetColor) {
        return false;
      }
    }
    return true;
  }

  /// Colores de la lámina ordenados por su número (el 1 primero).
  static List<Color> numberPalette(ColoringPage page) {
    final Map<int, Color> byNumber = <int, Color>{};
    for (final ColoringRegion r in page.regions) {
      byNumber.putIfAbsent(r.number, () => r.targetColor);
    }
    final List<int> numbers = byNumber.keys.toList()..sort();
    return <Color>[for (final int n in numbers) byNumber[n]!];
  }
}

/// Colorear: libre con la paleta (sin evaluación) o por números (por letras
/// desde los 7 años), que se termina al pintar todas las zonas con su color.
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
  ColoringSession? _session;
  ColoringTool _tool = ColoringTool.pintar;
  int _colorIndex = 0;
  String? _highlight;
  Timer? _highlightTimer;
  bool _saving = false;
  final GlobalKey _canvasKey = GlobalKey();

  /// Por letras desde los 7 años (en la lámina y en la paleta); por números antes.
  bool get _letras => widget.launch.band.readsText;

  String _etiqueta(int n) => _letras ? String.fromCharCode(64 + n) : '$n';

  String _conEtiqueta(int n) => _letras ? 'la letra ${_etiqueta(n)}' : 'el número $n';

  @override
  void initState() {
    super.initState();
    final Services s = AppScope.read(context);
    _engine = RoundEngine(app: s.state, voice: s.voice, sfx: s.sfx, launch: widget.launch, onNextRound: _volverAlCatalogo);
    _engine.addListener(_refresh);
    unawaited(_load());
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
    AppScope.read(context).voice.sayLater('Elige una lámina para pintar.');
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
    _highlightTimer?.cancel();
    setState(() {
      _session = null;
      _highlight = null;
    });
  }

  String get _instruction {
    final ColoringSession? s = _session;
    if (s == null) {
      return 'Elige una lámina para pintar.';
    }
    if (widget.porNumeros) {
      return _letras ? 'Pinta cada zona con el color de su letra.' : 'Pinta cada zona con el color de su número.';
    }
    return 'Elige un color y toca una zona para pintarla.';
  }

  void _abrir(ColoringPage page) {
    unawaited(AppScope.read(context).sfx.play(SfxId.page));
    setState(() {
      _session = ColoringSession(page, porNumeros: widget.porNumeros);
      _tool = ColoringTool.pintar;
      _colorIndex = 0;
      _highlight = null;
    });
    _engine.startRound();
    _engine.say(_instruction);
  }

  List<Color> get _colors => widget.porNumeros ? ColoringSession.numberPalette(_session!.page) : <Color>[for (final NamedSwatch s in PaletaLibre.colores) s.color];

  Color get _color {
    final List<Color> cs = _colors;
    return cs[_colorIndex.clamp(0, cs.length - 1)];
  }

  void _tapCanvas(Offset local, Size size) {
    final ColoringSession? session = _session;
    if (session == null || _engine.busy) {
      return;
    }
    final ColoringLayout layout = ColoringLayout.of(session.page);
    final ColoringRegion? r = layout.hitTest(ColoringLayout.toPage(session.page.viewBox, size, local));
    if (r == null) {
      return;
    }
    final Services s = AppScope.read(context);
    if (_tool == ColoringTool.goma) {
      if (session.erase(r)) {
        unawaited(s.sfx.play(SfxId.tap));
        setState(() {});
      }
      return;
    }
    if (!session.paint(r, _color)) {
      unawaited(s.sfx.play(SfxId.hint));
      s.voice.sayLater('Esa zona tiene ${_conEtiqueta(r.number)}. Busca ese color en la paleta.');
      setState(() => _highlight = r.id);
      _highlightTimer?.cancel();
      _highlightTimer = Timer(const Duration(milliseconds: 1200), () {
        if (mounted) {
          setState(() => _highlight = null);
        }
      });
      return;
    }
    unawaited(s.sfx.play(SfxId.pop));
    setState(() {});
    if (widget.porNumeros && session.complete) {
      unawaited(_terminarPorNumeros(session));
    }
  }

  Future<void> _terminarPorNumeros(ColoringSession session) async {
    // La captura se toma ya (la lámina está completa en pantalla) y se guarda
    // mientras se celebra.
    unawaited(_guardar(silencioso: true));
    // Eficiente: la lámina terminada con dos colores equivocados como mucho.
    final bool ok = session.errors <= 2;
    await _engine.finishBoard(
      success: ok,
      message: ok ? '¡Terminaste la lámina! Quedó guardada en Mis dibujos.' : '¡Terminaste la lámina! La próxima vez mira bien ${_letras ? 'la letra' : 'el número'} de cada zona antes de pintar.',
    );
  }

  void _deshacer() {
    final ColoringSession? s = _session;
    if (s == null || _engine.busy || !s.undo()) {
      return;
    }
    unawaited(AppScope.read(context).sfx.play(SfxId.tap));
    setState(() {});
  }

  Future<void> _guardar({bool silencioso = false}) async {
    final ColoringSession? s = _session;
    if (_saving || s == null) {
      return;
    }
    if (s.isEmpty) {
      // Nunca se guarda una lámina en blanco.
      if (!silencioso) {
        AppScope.read(context).voice.sayLater('Primero pinta alguna zona.');
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

  Future<void> _terminarLibre() async {
    final ColoringSession? s = _session;
    if (s == null || _engine.busy) {
      return;
    }
    if (s.isEmpty) {
      AppScope.read(context).voice.sayLater('Primero pinta alguna zona.');
      return;
    }
    unawaited(_guardar(silencioso: true));
    await _engine.completeFree(message: '¡Qué bonita! La guardé en Mis dibujos.');
  }

  void _pick(int i) {
    unawaited(AppScope.read(context).sfx.play(SfxId.tap));
    setState(() {
      _colorIndex = i;
      _tool = ColoringTool.pintar;
    });
    AppScope.read(context).voice.sayLater(_swatchName(i));
  }

  void _pickGoma() {
    unawaited(AppScope.read(context).sfx.play(SfxId.tap));
    setState(() => _tool = ColoringTool.goma);
    AppScope.read(context).voice.sayLater('Goma: toca una zona para borrarla.');
  }

  String _swatchName(int i) => widget.porNumeros ? 'Color ${_letras ? 'letra' : 'número'} ${_etiqueta(i + 1)}' : PaletaLibre.colores[i].nombre;

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _engine.removeListener(_refresh);
    _engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColoringSession? session = _session;
    return GameFrame(
      launch: widget.launch,
      engine: _engine,
      instruction: _instruction,
      child: session == null ? _catalogo() : LayoutBuilder(builder: (BuildContext context, BoxConstraints c) => _pageLayout(session, c)),
    );
  }

  Widget _pageLayout(ColoringSession session, BoxConstraints c) {
    final bool leftHanded = widget.launch.profile.leftHanded;
    final Widget canvas = Padding(padding: const EdgeInsets.all(8), child: _canvas(session));
    final List<Widget> buttons = <Widget>[
      RoundIconButton(key: const ValueKey<String>('colorear-laminas'), icon: Icons.grid_view_rounded, tooltip: 'Elegir otra lámina', onPressed: _engine.busy ? null : _volverAlCatalogo, size: 52),
      const SizedBox(width: 8),
      RoundIconButton(key: const ValueKey<String>('colorear-deshacer'), icon: Icons.undo_rounded, tooltip: 'Deshacer', onPressed: session.canUndo ? _deshacer : null, size: 52),
      const SizedBox(width: 8),
      RoundIconButton(key: const ValueKey<String>('colorear-guardar'), icon: Icons.save_alt_rounded, tooltip: 'Guardar en Mis dibujos', onPressed: () => _guardar(), size: 52),
    ];
    final Widget? listo = widget.porNumeros
        ? null
        : FilledButton.icon(
            key: const ValueKey<String>('colorear-listo'),
            onPressed: _engine.busy ? null : _terminarLibre,
            icon: const Icon(Icons.check_rounded),
            label: const Text('Listo'),
            style: FilledButton.styleFrom(minimumSize: const Size(110, 52), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
          );
    final int items = _colors.length + 1;
    if (c.maxWidth > c.maxHeight) {
      // Acostado: la lámina a un lado y la paleta con los botones al otro.
      final double colW = math.min(220, c.maxWidth * 0.4);
      final int cols = math.max(2, (colW / _swatch).floor());
      final Widget column = SizedBox(
        width: colW,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: <Widget>[
              Expanded(child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: _palette(cols)))),
              const SizedBox(height: 8),
              FittedBox(fit: BoxFit.scaleDown, child: Row(mainAxisSize: MainAxisSize.min, children: buttons)),
              if (listo != null) ...<Widget>[const SizedBox(height: 8), FittedBox(fit: BoxFit.scaleDown, child: listo)],
            ],
          ),
        ),
      );
      final List<Widget> row = <Widget>[Expanded(child: canvas), column, const SizedBox(width: 8)];
      return Row(children: leftHanded ? row.reversed.toList() : row);
    }
    final int perRow = math.max(4, ((c.maxWidth - 24) / _swatch).floor());
    final int rows = (items / perRow).ceil();
    final int cols = (items / rows).ceil();
    // «Listo» ocupa lo que sobra a su lado y se achica un poco si la letra es
    // muy grande, para no salirse de la pantalla.
    final List<Widget> bottom = <Widget>[
      ...buttons,
      if (listo == null)
        const Spacer()
      else ...<Widget>[
        const SizedBox(width: 8),
        Expanded(child: Align(alignment: leftHanded ? Alignment.centerLeft : Alignment.centerRight, child: FittedBox(fit: BoxFit.scaleDown, child: listo))),
      ],
    ];
    return Column(
      children: <Widget>[
        Expanded(child: canvas),
        _palette(cols),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: Row(children: leftHanded ? bottom.reversed.toList() : bottom),
        ),
      ],
    );
  }

  Widget _canvas(ColoringSession session) {
    final PilasPalette pal = PilasPalette.of(context);
    final ColoringLayout layout = ColoringLayout.of(session.page);
    final int pintadas = session.fills.length;
    final int total = session.page.regions.length;
    // El lienzo toma la forma de la lámina: sin franjas blancas alrededor.
    final Rect vb = session.page.viewBox;
    return Semantics(
      label: 'Lámina: ${session.page.nombre}. $pintadas de $total zonas pintadas.',
      child: Center(
        child: AspectRatio(
          aspectRatio: vb.width / vb.height,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints cc) {
              final Size size = Size(cc.maxWidth, cc.maxHeight);
              return GestureDetector(
                key: const ValueKey<String>('colorear-lienzo'),
                behavior: HitTestBehavior.opaque,
                onTapDown: (TapDownDetails d) => _tapCanvas(d.localPosition, size),
                child: RepaintBoundary(
                  key: _canvasKey,
                  child: Container(
                    color: Colors.white,
                    child: CustomPaint(
                      size: size,
                      painter: ColoringPainter(
                        layout: layout,
                        fills: Map<String, Color>.from(session.fills),
                        label: widget.porNumeros ? _etiqueta : null,
                        highlight: _highlight,
                        highlightColor: pal.pista,
                        frameColor: pal.borde,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Lado de cada botón de la paleta: 48 dp en un teléfono y 60 en una
  /// tableta, donde sobra espacio.
  double get _swatch => MediaQuery.sizeOf(context).shortestSide >= 600 ? 60 : 48;

  Widget _palette(int columns) {
    final PilasPalette pal = PilasPalette.of(context);
    final List<Color> colors = _colors;
    final double t = _swatch;
    final List<Widget> swatches = <Widget>[];
    for (int i = 0; i < colors.length; i++) {
      final Color c = colors[i];
      final bool selected = _tool == ColoringTool.pintar && i == _colorIndex;
      swatches.add(
        Semantics(
          button: true,
          selected: selected,
          label: _swatchName(i),
          excludeSemantics: true,
          child: GestureDetector(
            key: ValueKey<String>('color-$i'),
            behavior: HitTestBehavior.opaque,
            onTap: () => _pick(i),
            child: SizedBox(
              width: t,
              height: t,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: selected ? t - 4 : t - 10,
                  height: selected ? t - 4 : t - 10,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(color: selected ? pal.tinta : pal.bordeFuerte, width: selected ? 4 : 1.5),
                  ),
                  child: widget.porNumeros
                      ? Center(
                          child: Text(
                            _etiqueta(i + 1),
                            textScaler: TextScaler.noScaling,
                            style: TextStyle(fontSize: t * 0.38, fontWeight: FontWeight.w800, color: _onColor(c)),
                          ),
                        )
                      : (selected ? Icon(Icons.check_rounded, size: 20, color: _onColor(c)) : null),
                ),
              ),
            ),
          ),
        ),
      );
    }
    final bool goma = _tool == ColoringTool.goma;
    swatches.add(
      Semantics(
        button: true,
        selected: goma,
        label: 'Goma para borrar',
        excludeSemantics: true,
        child: GestureDetector(
          key: const ValueKey<String>('colorear-goma'),
          behavior: HitTestBehavior.opaque,
          onTap: _pickGoma,
          child: SizedBox(
            width: t,
            height: t,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: goma ? t - 4 : t - 10,
                height: goma ? t - 4 : t - 10,
                decoration: BoxDecoration(
                  color: goma ? pal.acentoClaro : pal.tarjeta,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: goma ? pal.tinta : pal.bordeFuerte, width: goma ? 4 : 1.5),
                ),
                child: Icon(Icons.auto_fix_normal_rounded, size: t * 0.46, color: pal.tinta),
              ),
            ),
          ),
        ),
      ),
    );
    final int rows = (swatches.length / columns).ceil();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int r = 0; r < rows; r++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[for (int k = r * columns; k < math.min(swatches.length, (r + 1) * columns); k++) swatches[k]],
          ),
      ],
    );
  }

  /// Tinta legible sobre un color de la paleta.
  Color _onColor(Color c) => c.computeLuminance() > 0.4 ? const Color(0xFF1F2954) : Colors.white;

  Widget _catalogo() {
    final List<ColoringPage>? pages = _pages;
    if (pages == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final PilasPalette pal = PilasPalette.of(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final int cols = math.max(2, (c.maxWidth / 180).floor());
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 14, crossAxisSpacing: 14, childAspectRatio: 0.9),
          itemCount: pages.length,
          itemBuilder: (BuildContext context, int i) {
            final ColoringPage p = pages[i];
            return OptionTile(
              key: ValueKey<String>('lamina-${p.id}'),
              semanticsLabel: p.nombre,
              onTap: () => _abrir(p),
              padding: const EdgeInsets.all(8),
              child: Column(
                children: <Widget>[
                  Expanded(
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: ColoringPainter(layout: ColoringLayout.of(p), fills: const <String, Color>{}, frameColor: pal.borde),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(p.nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: pal.tinta)),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
