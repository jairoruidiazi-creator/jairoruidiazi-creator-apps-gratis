import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/parental_gate.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../games/shell/widgets.dart';
import '../model/profile.dart';

/// Pantalla de descanso: aparece al cumplirse el tiempo de la sesión y tapa
/// todo hasta que termina la cuenta regresiva. No se cierra con "atrás" ni
/// con el gesto de borde; un adulto puede dar más tiempo o cambiar de jugador.
class RestScreen extends StatefulWidget {
  const RestScreen({super.key});

  static Route<void> route() => MaterialPageRoute<void>(builder: (_) => const RestScreen(), settings: const RouteSettings(name: 'descanso'));

  @override
  State<RestScreen> createState() => _RestScreenState();
}

class _RestScreenState extends State<RestScreen> {
  Timer? _timer;
  bool _announcedEnd = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        AppScope.read(context).voice.sayAlways(S.horaDeDescansar);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _volver() async {
    final Services s = AppScope.read(context);
    await s.state.finishRest();
    if (mounted) {
      Navigator.of(context).pop();
      s.voice.soltarRetenido();
    }
  }

  Future<void> _masTiempo() async {
    final bool ok = await showParentalGate(context, reason: S.masTiempoRazon);
    if (!ok || !mounted) {
      return;
    }
    final Services s = AppScope.read(context);
    await s.state.grantExtraTime();
    if (mounted) {
      Navigator.of(context).pop();
      s.voice.soltarRetenido();
    }
  }

  Future<void> _cambiar() async {
    final bool ok = await showParentalGate(context, reason: S.cambiarJugador);
    if (!ok || !mounted) {
      return;
    }
    final NavigatorState nav = Navigator.of(context);
    final Services s = AppScope.read(context);
    s.voice.descartarRetenido();
    await s.state.selectProfile(null);
    nav.popUntil((Route<dynamic> r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final PilasPalette pal = PilasPalette.of(context);
    final Profile? p = s.state.current;
    final Duration left = p == null ? Duration.zero : s.state.restRemaining(p.id);
    final bool done = left == Duration.zero;
    if (done && !_announcedEnd) {
      _announcedEnd = true;
      s.voice.sayAlways(S.descansoTerminado);
    }
    final int secs = left.inSeconds + (left.inMilliseconds % 1000 > 0 ? 1 : 0);
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: pal.fondoSuave,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Mascot(size: 120),
                    const SizedBox(height: 20),
                    BigText(done ? S.descansoTerminado : S.horaDeDescansar, size: 32, weight: FontWeight.w700),
                    const SizedBox(height: 12),
                    if (!done) ...<Widget>[
                      const BigText(S.descansoTexto, size: 20, weight: FontWeight.w500),
                      const SizedBox(height: 20),
                      // El lector de pantalla anuncia solo cuando cambia el
                      // minuto, no cada segundo de la cuenta regresiva.
                      Semantics(
                        key: const ValueKey<String>('descanso-cuenta'),
                        liveRegion: true,
                        label: S.quedanMinutos((secs + 59) ~/ 60),
                        excludeSemantics: true,
                        child: Text(S.quedan(secs ~/ 60, secs % 60), style: TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: pal.tinta)),
                      ),
                    ],
                    const SizedBox(height: 28),
                    if (done)
                      FilledButton.icon(
                        onPressed: _volver,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text(S.volverAJugar),
                      ),
                    const SizedBox(height: 12),
                    if (!done)
                      TextButton(onPressed: _masTiempo, child: const Text(S.masTiempo)),
                    TextButton(onPressed: _cambiar, child: const Text(S.cambiarJugador)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
