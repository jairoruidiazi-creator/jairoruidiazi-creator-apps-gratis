import 'dart:async';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_scope.dart';
import 'es.dart';
import 'settings.dart';
import 'strings.dart';
import 'theme.dart';

/// Pregunta de la puerta parental: una multiplicación de dos cifras por dos
/// cifras, escrita en palabras y sin leerla en voz alta. Uno de los factores
/// es "amable" (15 o 25) y el otro va de 13 a 39 sin ser múltiplo de 10, así
/// que un adulto la resuelve de cabeza en dos pasos, sin papel:
/// - por 15: diez veces el número más su mitad (15 × 24 = 240 + 120 = 360);
/// - por 25: el número por cien, dividido entre cuatro (25 × 36 = 3600 ÷ 4 =
///   900).
/// Ningún juego de Pilas pide multiplicar dos números de dos cifras (la
/// carrera de 9 a 11 años multiplica uno de dos cifras por uno de una y llega
/// a la tabla del 12), y la pregunta en palabras pide leer con soltura
/// números grandes.
class GateChallenge {
  GateChallenge._(this.a, this.b);

  factory GateChallenge.random([Random? random]) {
    final Random r = random ?? Random();
    final int amable = amables[r.nextInt(amables.length)];
    int otro;
    do {
      otro = 13 + r.nextInt(27); // 13..39
    } while (otro % 10 == 0 || amables.contains(otro));
    return r.nextBool() ? GateChallenge._(amable, otro) : GateChallenge._(otro, amable);
  }

  /// Factores que se multiplican de cabeza con un truco de dos pasos.
  static const List<int> amables = <int>[15, 25];

  final int a;
  final int b;

  int get answer => a * b;

  /// La pregunta en palabras ("¿Cuánto es quince por veintitrés?").
  String get question => '¿Cuánto es ${Es.numero(a)} por ${Es.numero(b)}?';

  bool check(String text) {
    final String digits = text.trim().replaceAll('.', '').replaceAll(',', '').replaceAll(' ', '');
    final int? n = int.tryParse(digits);
    return n == answer;
  }
}

/// Espera tras los errores: los dos primeros errores seguidos no tienen
/// espera; desde el tercero, 60 s, luego 120 s, 240 s… (hasta 15 minutos).
/// El contador vuelve a cero con un acierto o tras [reinicio] sin errores,
/// para que errores sueltos de días distintos no se acumulen.
class GateLock {
  GateLock._();

  static const int freeTries = 2;

  /// Tiempo sin errores tras el cual el contador vuelve a cero.
  static const Duration reinicio = Duration(minutes: 15);

  /// Errores que todavía cuentan: los guardados, o cero si el último fue
  /// hace [reinicio] o más (o no se sabe cuándo fue).
  static int vigentes(int fails, DateTime? lastFail, DateTime now) {
    if (fails <= 0 || lastFail == null || now.difference(lastFail) >= reinicio) {
      return 0;
    }
    return fails;
  }

  static Duration waitAfter(int fails) {
    if (fails <= freeTries) {
      return Duration.zero;
    }
    final int k = fails - freeTries - 1;
    final int secs = 60 * (1 << (k > 4 ? 4 : k));
    return Duration(seconds: secs > 900 ? 900 : secs);
  }
}

/// Muestra la puerta parental y devuelve true si el adulto la pasó.
Future<bool> showParentalGate(BuildContext context, {String? reason}) async {
  final Services s = AppScope.read(context);
  // Para los que todavía no leen: la voz avisa que esto es para un adulto.
  s.voice.sayAlways(S.esParaUnAdulto);
  final bool? ok = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext context) => _GateDialog(reason: reason, settings: s.settings),
  );
  return ok == true;
}

class _GateDialog extends StatefulWidget {
  const _GateDialog({this.reason, required this.settings});

  final String? reason;
  final AppSettings settings;

  @override
  State<_GateDialog> createState() => _GateDialogState();
}

class _GateDialogState extends State<_GateDialog> {
  GateChallenge _challenge = GateChallenge.random();
  final TextEditingController _ctrl = TextEditingController();
  bool _error = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _scheduleUnlock();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  Duration get _remaining {
    final DateTime? until = widget.settings.gateLockedUntil;
    if (until == null) {
      return Duration.zero;
    }
    final Duration d = until.difference(clock.now());
    return d.isNegative ? Duration.zero : d;
  }

  void _scheduleUnlock() {
    _timer?.cancel();
    if (_remaining > Duration.zero) {
      _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
        if (!mounted) {
          return;
        }
        setState(() {});
        if (_remaining == Duration.zero) {
          t.cancel();
        }
      });
    }
  }

  /// Otra operación, sin contar error (por si la que salió no le gusta al
  /// adulto). Todas son del mismo tipo.
  void _otra() {
    setState(() {
      _challenge = GateChallenge.random();
      _error = false;
      _ctrl.clear();
    });
  }

  Future<void> _submit() async {
    if (_remaining > Duration.zero) {
      return;
    }
    if (_challenge.check(_ctrl.text)) {
      await widget.settings.setGateState(fails: 0);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
      return;
    }
    final DateTime now = clock.now();
    final int fails = GateLock.vigentes(widget.settings.gateFails, widget.settings.gateLastFail, now) + 1;
    final Duration wait = GateLock.waitAfter(fails);
    await widget.settings.setGateState(fails: fails, lockedUntil: wait == Duration.zero ? null : now.add(wait), lastFail: now);
    if (!mounted) {
      return;
    }
    setState(() {
      _error = true;
      _challenge = GateChallenge.random();
      _ctrl.clear();
    });
    _scheduleUnlock();
  }

  @override
  Widget build(BuildContext context) {
    final PilasPalette pal = PilasPalette.of(context);
    final Duration remaining = _remaining;
    final bool locked = remaining > Duration.zero;
    return AlertDialog(
      title: const Text(S.paraAdultos),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (widget.reason != null) ...<Widget>[
              Text(widget.reason!, style: TextStyle(fontSize: 16, color: pal.tintaSuave)),
              const SizedBox(height: 12),
            ],
            const Text(S.resuelveParaEntrar, style: TextStyle(fontSize: 16)),
            const SizedBox(height: 12),
            Text(_challenge.question, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey<String>('puerta-respuesta'),
              controller: _ctrl,
              autofocus: true,
              enabled: !locked,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
              // Sin menú de copiar, pegar o buscar en la web: ningún campo de
              // texto lleva fuera de la app.
              contextMenuBuilder: null,
              enableInteractiveSelection: false,
              autocorrect: false,
              enableSuggestions: false,
              style: const TextStyle(fontSize: 24),
              decoration: InputDecoration(
                labelText: S.respuestaEnCifras,
                errorText: locked ? null : (_error ? S.respuestaIncorrecta : null),
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (locked) ...<Widget>[
              const SizedBox(height: 10),
              Text(S.esperaPuerta(remaining.inSeconds + 1), style: TextStyle(fontSize: 15, color: pal.error, fontWeight: FontWeight.w600)),
            ] else
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey<String>('puerta-otra'),
                  onPressed: _otra,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text(S.otraOperacion),
                ),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text(S.cancelar)),
        FilledButton(onPressed: locked ? null : _submit, child: const Text(S.entrar)),
      ],
    );
  }
}
