import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/speech.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../engine/game_def.dart';
import '../../engine/round_engine.dart';
import '../../model/age_band.dart';
import 'widgets.dart';

/// Marco común de los juegos: salida, nombre, nivel y progreso; la
/// instrucción con voz (y la pista, en el mismo lugar); el cuerpo del juego; y
/// las capas de celebración, respuesta explicada y subida de nivel.
///
/// - La pista va dentro del diseño, en la barra de instrucción: nunca tapa
///   botones ni opciones.
/// - En un teléfono acostado, la cabecera y la instrucción pasan a una
///   columna lateral para que el juego tenga todo el alto.
/// - Modo zurdo: los botones y la columna lateral quedan del lado izquierdo.
/// - Al salir por cualquier camino (botón, "atrás", gesto) se calla la voz.
class GameFrame extends StatefulWidget {
  const GameFrame({
    super.key,
    required this.launch,
    required this.child,
    this.engine,
    this.instruction = '',
    this.onRepeat,
    this.actions = const <Widget>[],
    this.background,
    this.showProgress = true,
  });

  final GameLaunch launch;
  final Widget child;
  final RoundEngine? engine;

  /// Texto de la instrucción actual; se muestra y se lee al tocar el altavoz.
  final String instruction;

  /// Qué hacer al tocar el altavoz. Por defecto lee [instruction].
  final VoidCallback? onRepeat;

  /// Botones del juego (guardar, deshacer…): van con los de la cabecera.
  final List<Widget> actions;
  final Color? background;

  /// Muestra el nivel y los puntos de progreso (si el juego tiene niveles).
  final bool showProgress;

  /// Ancho de la columna lateral en un teléfono acostado.
  static double sidebarWidth(double screenWidth) => (screenWidth * 0.3).clamp(200.0, 280.0).toDouble();

  /// Si con este tamaño de pantalla el marco usa la columna lateral.
  static bool usesSidebar(Size size) => size.width > size.height && size.height < 560;

  @override
  State<GameFrame> createState() => _GameFrameState();
}

class _GameFrameState extends State<GameFrame> {
  late final Voice _voice;

  @override
  void initState() {
    super.initState();
    _voice = AppScope.read(context).voice;
  }

  @override
  void dispose() {
    // Salir del juego por cualquier camino calla la voz.
    unawaited(_voice.stop());
    super.dispose();
  }

  void _repeat() {
    if (widget.onRepeat != null) {
      widget.onRepeat!();
      return;
    }
    if (widget.instruction.isNotEmpty) {
      _voice.sayLater(widget.instruction);
    }
  }

  void _repeatHint(String hint) {
    _voice.sayLater(hint);
  }

  @override
  Widget build(BuildContext context) {
    final PilasPalette pal = PilasPalette.of(context);
    final RoundEngine? engine = widget.engine;
    final Widget content = engine == null
        ? _layout(context, pal, null)
        : AnimatedBuilder(animation: engine, builder: (BuildContext context, Widget? _) => _layout(context, pal, engine));
    return Scaffold(
      backgroundColor: widget.background ?? pal.fondo,
      body: SafeArea(child: content),
    );
  }

  Widget _layout(BuildContext context, PilasPalette pal, RoundEngine? engine) {
    final bool leftHanded = widget.launch.profile.leftHanded;
    final GameDef game = widget.launch.game;
    final String? hint = engine != null && engine.phase == RoundPhase.hint ? engine.hintText : null;

    final Widget exitButton = RoundIconButton(
      icon: Icons.close_rounded,
      tooltip: S.salir,
      onPressed: () {
        unawaited(_voice.stop());
        Navigator.of(context).maybePop();
      },
    );
    final Widget repeatButton = RoundIconButton(icon: Icons.volume_up_rounded, tooltip: S.repetir, onPressed: _repeat, color: pal.destacado);
    final Widget title = Text(
      game.nombre,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: pal.tinta, height: 1.15),
    );
    final bool progressVisible = widget.showProgress && engine != null && game.hasLevels;
    final Widget? progress = progressVisible
        ? FittedBox(
            fit: BoxFit.scaleDown,
            alignment: leftHanded ? Alignment.centerRight : Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(color: pal.acentoClaro, borderRadius: BorderRadius.circular(12)),
                  child: Text('${S.nivel} ${engine.level}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: pal.areaTexto(game.area))),
                ),
                const SizedBox(width: 10),
                ProgressDots(recent: engine.recent, total: engine.window),
              ],
            ),
          )
        : null;

    final Widget instruction = _InstructionBar(
      text: widget.instruction,
      hint: hint,
      reads: widget.launch.band.readsText,
      onTap: hint != null ? () => _repeatHint(hint) : _repeat,
    );

    final Widget body = Stack(
      fit: StackFit.expand,
      children: <Widget>[
        widget.child,
        if (engine != null) _EngineOverlays(engine: engine),
      ],
    );

    return LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
      final Size size = Size(c.maxWidth, c.maxHeight);
      if (GameFrame.usesSidebar(MediaQuery.sizeOf(context)) && c.maxWidth > c.maxHeight) {
        // Teléfono acostado: columna lateral con todo lo del marco.
        final double w = GameFrame.sidebarWidth(size.width);
        final Widget sidebar = SizedBox(
          width: w,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: _ordered(leftHanded, <Widget>[
                    exitButton,
                    const Spacer(),
                    ...widget.actions,
                    if (widget.actions.isNotEmpty) const SizedBox(width: 6),
                    repeatButton,
                  ]),
                ),
                const SizedBox(height: 6),
                title,
                if (progress != null) ...<Widget>[const SizedBox(height: 4), progress],
                const SizedBox(height: 8),
                Expanded(child: SingleChildScrollView(child: instruction)),
              ],
            ),
          ),
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: leftHanded ? <Widget>[sidebar, Expanded(child: body)] : <Widget>[Expanded(child: body), sidebar],
        );
      }
      final Widget header = Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: LayoutBuilder(builder: (BuildContext context, BoxConstraints hc) {
          // En un teléfono angosto, los botones propios del juego bajan a una
          // segunda fila junto al nivel, para no aplastar el nombre.
          final bool twoRows = widget.actions.isNotEmpty && hc.maxWidth < 440;
          if (!twoRows) {
            return Row(
              children: _ordered(leftHanded, <Widget>[
                exitButton,
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: leftHanded ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                    children: <Widget>[title, if (progress != null) progress],
                  ),
                ),
                ...widget.actions,
                const SizedBox(width: 6),
                repeatButton,
              ]),
            );
          }
          return Column(
            children: <Widget>[
              Row(children: _ordered(leftHanded, <Widget>[exitButton, const SizedBox(width: 10), Expanded(child: title), const SizedBox(width: 6), repeatButton])),
              const SizedBox(height: 6),
              Row(
                children: _ordered(leftHanded, <Widget>[
                  Expanded(child: Align(alignment: leftHanded ? Alignment.centerRight : Alignment.centerLeft, child: progress ?? const SizedBox.shrink())),
                  const SizedBox(width: 6),
                  ...widget.actions,
                ]),
              ),
            ],
          );
        }),
      );
      // La instrucción no puede comerse el juego: si es muy larga (texto
      // grande en un teléfono pequeño), se desplaza dentro de su espacio.
      final double maxInstruction = math.max(72, size.height * 0.3);
      return Column(
        children: <Widget>[
          header,
          if (widget.instruction.isNotEmpty || hint != null)
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxInstruction),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: SingleChildScrollView(child: instruction),
              ),
            ),
          Expanded(child: body),
        ],
      );
    });
  }

  List<Widget> _ordered(bool leftHanded, List<Widget> items) => leftHanded ? items.reversed.toList() : items;
}

/// Barra de instrucción. Durante la pista muestra la pista en el mismo lugar
/// (no encima del juego) con su propio color e ícono.
class _InstructionBar extends StatelessWidget {
  const _InstructionBar({required this.text, required this.hint, required this.reads, required this.onTap});

  final String text;
  final String? hint;
  final bool reads;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final PilasPalette pal = PilasPalette.of(context);
    final bool isHint = hint != null;
    final double fontSize = reads ? 18 : 20;
    return Semantics(
      liveRegion: isHint,
      button: true,
      label: isHint ? '${S.casi} $hint' : text,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          key: isHint ? const ValueKey<String>('pista') : const ValueKey<String>('instruccion'),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isHint ? pal.pistaClaro : pal.tarjeta,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isHint ? pal.pista : (pal.altoContraste ? pal.bordeFuerte : pal.borde), width: isHint ? 3 : 2),
          ),
          child: Row(
            children: <Widget>[
              if (isHint) Icon(Icons.lightbulb_rounded, color: pal.pista, size: 34) else const Mascot(size: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (isHint) Text(S.casi, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: pal.pista)),
                    Text(
                      isHint ? hint! : text,
                      style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600, height: 1.25, color: pal.tinta),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Capas de celebración, respuesta explicada y subida de nivel. Cubren solo
/// la zona del juego: la cabecera (salir, repetir) sigue a mano.
class _EngineOverlays extends StatelessWidget {
  const _EngineOverlays({required this.engine});

  final RoundEngine engine;

  @override
  Widget build(BuildContext context) {
    switch (engine.phase) {
      case RoundPhase.playing:
      case RoundPhase.hint:
        return const SizedBox.shrink();
      case RoundPhase.celebrating:
        return Positioned.fill(
          child: IgnorePointer(
            child: _CenterCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Mascot(size: 110),
                  const SizedBox(height: 12),
                  BigText(engine.overlayTitle ?? S.muyBien, size: 32, weight: FontWeight.w700),
                ],
              ),
            ),
          ),
        );
      case RoundPhase.revealing:
        return Positioned.fill(
          child: _CenterCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Mascot(size: 90),
                const SizedBox(height: 10),
                BigText(engine.overlayTitle ?? S.asiEs, size: 26, weight: FontWeight.w700),
                const SizedBox(height: 8),
                BigText(engine.revealText ?? '', size: 20, weight: FontWeight.w500),
              ],
            ),
          ),
        );
      case RoundPhase.levelUp:
        return Positioned.fill(
          child: IgnorePointer(
            child: _CenterCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (engine.sticker != null) EmojiImage(engine.sticker!.emoji, size: 120) else const Mascot(size: 110),
                  const SizedBox(height: 12),
                  BigText(engine.overlayTitle ?? S.nuevoNivel, size: 30, weight: FontWeight.w700),
                ],
              ),
            ),
          ),
        );
    }
  }
}

class _CenterCard extends StatelessWidget {
  const _CenterCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final PilasPalette pal = PilasPalette.of(context);
    return Container(
      color: Colors.black.withValues(alpha: 0.25),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      // En apaisado la zona de juego es baja: la tarjeta se achica si no cabe.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.7, end: 1),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutBack,
          builder: (BuildContext context, double v, Widget? c) => Transform.scale(scale: v, child: c),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: pal.tarjeta,
              borderRadius: BorderRadius.circular(32),
              border: pal.altoContraste ? Border.all(color: pal.bordeFuerte, width: 3) : null,
              boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 8))],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
