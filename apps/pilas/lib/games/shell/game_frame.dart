import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/parental_gate.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../engine/game_def.dart';
import '../../engine/round_engine.dart';
import '../../model/age_band.dart';
import 'widgets.dart';

/// Marco común de los juegos: cabecera con salida, nivel y progreso; barra de
/// instrucción con voz; cuerpo del juego; y las capas de pista, celebración,
/// respuesta explicada y subida de nivel. También vigila el tiempo de sesión.
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
  });

  final GameLaunch launch;
  final Widget child;
  final RoundEngine? engine;

  /// Texto de la instrucción actual; se muestra y se lee al tocar el altavoz.
  final String instruction;

  /// Qué hacer al tocar el altavoz. Por defecto lee [instruction].
  final VoidCallback? onRepeat;

  /// Botones adicionales en la cabecera (por ejemplo, "guardar" en colorear).
  final List<Widget> actions;
  final Color? background;

  @override
  State<GameFrame> createState() => _GameFrameState();
}

class _GameFrameState extends State<GameFrame> {
  Timer? _limitTimer;
  bool _resting = false;

  @override
  void initState() {
    super.initState();
    _limitTimer = Timer.periodic(const Duration(seconds: 20), (_) => _checkLimit());
  }

  @override
  void dispose() {
    _limitTimer?.cancel();
    super.dispose();
  }

  void _checkLimit() {
    if (!mounted || _resting) {
      return;
    }
    final Services s = AppScope.read(context);
    final int limit = s.settings.sessionLimitMinutes;
    if (limit <= 0) {
      return;
    }
    final int played = s.state.minutesToday - s.state.extraMinutes;
    if (played >= limit) {
      _resting = true;
      s.voice.sayLater(S.horaDeDescansar);
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const RestScreen())).then((_) {
        if (mounted) {
          _resting = false;
        }
      });
    }
  }

  void _repeat() {
    if (widget.onRepeat != null) {
      widget.onRepeat!();
      return;
    }
    if (widget.instruction.isNotEmpty) {
      AppScope.read(context).voice.sayLater(widget.instruction);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Services services = AppScope.of(context);
    final bool leftHanded = widget.launch.profile.leftHanded;
    final RoundEngine? engine = widget.engine;
    final Color areaColor = widget.launch.game.area.color;

    final List<Widget> headerChildren = <Widget>[
      RoundIconButton(
        icon: Icons.close_rounded,
        tooltip: S.salir,
        onPressed: () {
          services.voice.stop();
          Navigator.of(context).maybePop();
        },
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: leftHanded ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: <Widget>[
            Text(widget.launch.game.nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            if (engine != null && widget.launch.game.roundBased)
              AnimatedBuilder(
                animation: engine,
                builder: (BuildContext context, Widget? _) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      decoration: BoxDecoration(color: areaColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                      child: Text('${S.nivel} ${engine.level}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: areaColor)),
                    ),
                    const SizedBox(width: 10),
                    ProgressDots(recent: engine.recent),
                  ],
                ),
              ),
          ],
        ),
      ),
      ...widget.actions,
      const SizedBox(width: 6),
      RoundIconButton(icon: Icons.volume_up_rounded, tooltip: S.repetir, onPressed: _repeat, color: PilasColors.amarillo),
    ];
    final Widget header = Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(children: leftHanded ? headerChildren.reversed.toList() : headerChildren),
    );

    final Widget instruction = widget.instruction.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: GestureDetector(
              onTap: _repeat,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: PilasColors.borde, width: 2),
                ),
                child: Row(
                  children: <Widget>[
                    const Mascot(size: 40),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.instruction,
                        style: TextStyle(fontSize: widget.launch.band.readsText ? 18 : 20, fontWeight: FontWeight.w600, height: 1.25),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );

    final Widget body = Column(
      children: <Widget>[
        header,
        instruction,
        Expanded(child: widget.child),
      ],
    );

    return Scaffold(
      backgroundColor: widget.background ?? PilasColors.fondo,
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            Positioned.fill(child: body),
            if (engine != null) _EngineOverlays(engine: engine),
          ],
        ),
      ),
    );
  }
}

/// Capas de pista, celebración, respuesta y nivel.
class _EngineOverlays extends StatelessWidget {
  const _EngineOverlays({required this.engine});

  final RoundEngine engine;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: engine,
      builder: (BuildContext context, Widget? _) {
        switch (engine.phase) {
          case RoundPhase.playing:
            return const SizedBox.shrink();
          case RoundPhase.hint:
            return Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: IgnorePointer(
                child: _Banner(
                  color: PilasColors.amarillo,
                  icon: Icons.lightbulb_rounded,
                  title: S.casi,
                  text: engine.hintText ?? '',
                ),
              ),
            );
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
      },
    );
  }
}

class _CenterCard extends StatelessWidget {
  const _CenterCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.25),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.7, end: 1),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutBack,
        builder: (BuildContext context, double v, Widget? c) => Transform.scale(scale: v, child: c),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(32),
            boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 8))],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.icon, required this.title, required this.text});

  final Color color;
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color, width: 3),
        boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x26000000), blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, color: color, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: PilasColors.tintaSuave)),
                Text(text, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Pantalla de descanso cuando se cumple el tiempo de sesión.
class RestScreen extends StatelessWidget {
  const RestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final Services services = AppScope.of(context);
    return Scaffold(
      backgroundColor: PilasColors.fondoOscuro,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const Mascot(size: 160),
                const SizedBox(height: 24),
                const BigText(S.horaDeDescansar, size: 34, weight: FontWeight.w700),
                const SizedBox(height: 12),
                const BigText(S.descansoTexto, size: 20, weight: FontWeight.w500),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: () {
                    services.voice.stop();
                    Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
                  },
                  icon: const Icon(Icons.home_rounded),
                  label: const Text(S.listo),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () async {
                    final bool ok = await showParentalGate(context, reason: S.masTiempo);
                    if (ok && context.mounted) {
                      services.state.extraMinutes += 10;
                      Navigator.of(context).pop();
                    }
                  },
                  child: const Text(S.masTiempo),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
