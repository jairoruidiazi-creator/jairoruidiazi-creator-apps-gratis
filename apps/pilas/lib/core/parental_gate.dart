import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'strings.dart';
import 'theme.dart';

/// Pregunta de la puerta parental: una multiplicación de dos cifras por una,
/// que un niño pequeño no resuelve y un adulto sí.
class GateChallenge {
  GateChallenge._(this.a, this.b);

  factory GateChallenge.random([Random? random]) {
    final Random r = random ?? Random();
    final int a = 12 + r.nextInt(78); // 12..89
    final int b = 3 + r.nextInt(7); // 3..9
    return GateChallenge._(a, b);
  }

  final int a;
  final int b;

  int get answer => a * b;

  String get question => '¿Cuánto es $a × $b?';

  bool check(String text) {
    final int? n = int.tryParse(text.trim().replaceAll('.', '').replaceAll(',', ''));
    return n == answer;
  }
}

/// Muestra la puerta parental y devuelve true si el adulto la pasó.
Future<bool> showParentalGate(BuildContext context, {String? reason}) async {
  final bool? ok = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext context) => _GateDialog(reason: reason),
  );
  return ok == true;
}

class _GateDialog extends StatefulWidget {
  const _GateDialog({this.reason});

  final String? reason;

  @override
  State<_GateDialog> createState() => _GateDialogState();
}

class _GateDialogState extends State<_GateDialog> {
  GateChallenge _challenge = GateChallenge.random();
  final TextEditingController _ctrl = TextEditingController();
  bool _error = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_challenge.check(_ctrl.text)) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _error = true;
      _challenge = GateChallenge.random();
      _ctrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(S.paraAdultos),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (widget.reason != null) ...<Widget>[
            Text(widget.reason!, style: const TextStyle(fontSize: 16, color: PilasColors.tintaSuave)),
            const SizedBox(height: 12),
          ],
          const Text(S.resuelveParaEntrar, style: TextStyle(fontSize: 16)),
          const SizedBox(height: 12),
          Text(_challenge.question, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontSize: 24),
            decoration: InputDecoration(
              labelText: S.respuesta,
              errorText: _error ? S.respuestaIncorrecta : null,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text(S.cancelar)),
        FilledButton(onPressed: _submit, child: const Text(S.entrar)),
      ],
    );
  }
}
