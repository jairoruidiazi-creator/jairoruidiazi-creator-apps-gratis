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
/// cifras (factores de 13 a 39 que no son múltiplos de 10), escrita en
/// palabras y sin leerla en voz alta. Ningún juego de Pilas practica esa
/// operación (la carrera de 9 a 11 años multiplica por una cifra).
class GateChallenge {
  GateChallenge._(this.a, this.b);

  factory GateChallenge.random([Random? random]) {
    final Random r = random ?? Random();
    int pick() {
      while (true) {
        final int v = 13 + r.nextInt(27); // 13..39
        if (v % 10 != 0) {
          return v;
        }
      }
    }

    return GateChallenge._(pick(), pick());
  }

  final int a;
  final int b;

  int get answer => a * b;

  /// La pregunta en palabras ("¿Cuánto es veintitrés por diecisiete?").
  String get question => '¿Cuánto es ${Es.numero(a)} por ${Es.numero(b)}?';

  bool check(String text) {
    final String digits = text.trim().replaceAll('.', '').replaceAll(',', '').replaceAll(' ', '');
    final int? n = int.tryParse(digits);
    return n == answer;
  }
}

/// Espera tras los errores: desde el tercer error seguido, 60 s, luego 120 s,
/// 240 s… (hasta 15 minutos).
class GateLock {
  GateLock._();

  static const int freeTries = 2;

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
  s.voice.sayLater(S.esParaUnAdulto);
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
    final int fails = widget.settings.gateFails + 1;
    final Duration wait = GateLock.waitAfter(fails);
    await widget.settings.setGateState(fails: fails, lockedUntil: wait == Duration.zero ? null : clock.now().add(wait));
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
            ],
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
