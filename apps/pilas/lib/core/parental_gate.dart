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

/// Pregunta de la puerta parental: una multiplicación de dos números de dos
/// cifras, escrita en palabras y sin leerla en voz alta. Es una tarea pensada
/// para adultos ("adult-level task", como la llama Apple): la puerta dice que
/// se puede usar la calculadora del teléfono.
/// - Los dos factores van de 13 a 39 y ninguno es múltiplo de 5 (ni de 10):
///   no hay atajos como "por 25 es por cien entre cuatro", y el resultado
///   nunca termina en 0.
/// - Se descartan los pares que la app entrena ([entrenado]): la tienda
///   multiplica precios redondos (múltiplos de 500) por 2 a 12, y la carrera
///   multiplica por una cifra o por 12; ningún par de la puerta sale ahí
///   (test/ui_flows_test.dart lo comprueba con un barrido de esos juegos).
class GateChallenge {
  GateChallenge._(this.a, this.b);

  factory GateChallenge.random([Random? random]) {
    final Random r = random ?? Random();
    while (true) {
      final int a = factores[r.nextInt(factores.length)];
      final int b = factores[r.nextInt(factores.length)];
      if (valido(a, b)) {
        return GateChallenge._(a, b);
      }
    }
  }

  /// Factores posibles: de 13 a 39, sin múltiplos de 5.
  static final List<int> factores = <int>[for (int v = 13; v <= 39; v++) if (v % 5 != 0) v];

  /// Si la app entrena esa multiplicación: un factor de una cifra, 10, 11 o
  /// 12 (tablas de la carrera y cantidades de la tienda) o múltiplo de 5
  /// (precios redondos de la tienda, contados en centenas).
  static bool entrenado(int a, int b) => a <= 12 || b <= 12 || a % 5 == 0 || b % 5 == 0;

  /// La operación [a] × [b], si es válida para la puerta (para recuperar la
  /// pendiente); null si no.
  static GateChallenge? de(List<int>? ab) => ab != null && ab.length == 2 && valido(ab[0], ab[1]) ? GateChallenge._(ab[0], ab[1]) : null;

  /// Si [a] × [b] puede salir en la puerta.
  static bool valido(int a, int b) => factores.contains(a) && factores.contains(b) && (a * b) % 10 != 0 && !entrenado(a, b);

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
  late GateChallenge _challenge;
  final TextEditingController _ctrl = TextEditingController();
  bool _error = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // La operación pendiente se reutiliza: cerrar y volver a abrir la puerta
    // no da otra (eso solo lo hace «Otra operación», que cuenta como intento).
    final GateChallenge? pendiente = GateChallenge.de(widget.settings.gatePendiente);
    _challenge = pendiente ?? GateChallenge.random();
    if (pendiente == null) {
      unawaited(widget.settings.setGatePendiente(<int>[_challenge.a, _challenge.b]));
    }
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

  /// Mientras se guarda un intento, los toques de más no hacen nada (un
  /// segundo «Entrar» haría dos `pop` y cerraría también la pantalla de
  /// abajo).
  bool _enviando = false;

  /// Una operación nueva y distinta de la actual.
  GateChallenge _nueva() {
    GateChallenge c;
    do {
      c = GateChallenge.random();
    } while (c.a == _challenge.a && c.b == _challenge.b);
    return c;
  }

  /// Otra operación: cuenta como un intento fallido (con las mismas esperas),
  /// para que no se puedan pedir operaciones hasta que salga una fácil.
  Future<void> _otra() async {
    if (_remaining > Duration.zero || _enviando) {
      return;
    }
    _enviando = true;
    try {
      await _fallo(error: false);
    } finally {
      _enviando = false;
    }
  }

  Future<void> _submit() async {
    if (_remaining > Duration.zero || _enviando) {
      return;
    }
    _enviando = true;
    try {
      if (_challenge.check(_ctrl.text)) {
        await widget.settings.setGateState(fails: 0);
        await widget.settings.setGatePendiente(null);
        if (mounted) {
          Navigator.of(context).pop(true);
        }
        return;
      }
      await _fallo(error: true);
    } finally {
      _enviando = false;
    }
  }

  /// Suma un intento fallido, aplica la espera que toque y cambia la operación.
  Future<void> _fallo({required bool error}) async {
    final DateTime now = clock.now();
    final int fails = GateLock.vigentes(widget.settings.gateFails, widget.settings.gateLastFail, now) + 1;
    final Duration wait = GateLock.waitAfter(fails);
    await widget.settings.setGateState(fails: fails, lockedUntil: wait == Duration.zero ? null : now.add(wait), lastFail: now);
    final GateChallenge nueva = _nueva();
    await widget.settings.setGatePendiente(<int>[nueva.a, nueva.b]);
    if (!mounted) {
      return;
    }
    setState(() {
      _error = error;
      _challenge = nueva;
      _ctrl.clear();
    });
    _scheduleUnlock();
  }

  @override
  Widget build(BuildContext context) {
    final PilasPalette pal = PilasPalette.of(context);
    final Duration remaining = _remaining;
    final bool locked = remaining > Duration.zero;
    // Todo (también «Entrar») va dentro de la parte que se desplaza: con el
    // teclado numérico abierto, que en iPhone no tiene tecla de enviar, y
    // con la letra al doble en un teléfono acostado, «Entrar» sigue a mano.
    // A la derecha, como las acciones de los demás diálogos.
    final Widget botones = Align(
      alignment: Alignment.centerRight,
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 4,
        children: <Widget>[
          TextButton(key: const ValueKey<String>('puerta-cancelar'), onPressed: () => Navigator.of(context).pop(false), child: const Text(S.cancelar)),
          FilledButton(key: const ValueKey<String>('puerta-entrar'), onPressed: locked ? null : _submit, child: const Text(S.entrar)),
        ],
      ),
    );
    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      title: const Text(S.paraAdultos),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (widget.reason != null) ...<Widget>[
            Text(widget.reason!, style: TextStyle(fontSize: 16, color: pal.tintaSuave)),
            const SizedBox(height: 12),
          ],
          const Text(S.resuelveParaEntrar, style: TextStyle(fontSize: 16)),
          const SizedBox(height: 12),
          Text(_challenge.question, key: const ValueKey<String>('puerta-pregunta'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(S.puertaCalculadora, style: TextStyle(fontSize: 15, color: pal.tintaSuave)),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey<String>('puerta-respuesta'),
            controller: _ctrl,
            autofocus: true,
            enabled: !locked,
            keyboardType: TextInputType.number,
            // En Android el teclado numérico tiene «Listo»: también envía.
            textInputAction: TextInputAction.done,
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
          const SizedBox(height: 12),
          botones,
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
                label: const Text(S.otraOperacionCuenta),
              ),
            ),
        ],
      ),
    );
  }
}
